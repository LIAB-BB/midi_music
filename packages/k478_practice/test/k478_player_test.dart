import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:k478_practice/src/core/midi_parser.dart';
import 'package:k478_practice/src/core/k478_player.dart';
import 'package:k478_practice/src/core/midi_engine.dart';
import 'package:k478_practice/src/models/midi_track.dart';

class _FakeEngine implements MidiPlaybackEngine {
  final List<int> programs = [];
  final List<int> noteOns = [];
  final List<int> noteOffs = [];
  final List<(int controller, int value)> controlChanges = [];
  int allNotesOffCalls = 0;
  Completer<void>? allNotesOffGate;
  Completer<void>? allNotesOffStarted;
  Completer<void>? loadSoundfontsGate;
  Completer<void>? loadSoundfontsStarted;
  Completer<void>? setInstrumentGate;
  Completer<void>? setInstrumentStarted;
  Completer<void>? disposedCompleted;
  Map<int, String>? loadedAssetsByProgram;
  Object? nextLoadSoundfontsError;
  bool disposed = false;

  @override
  bool get isReady => true;

  @override
  Future<void> allNotesOff() async {
    allNotesOffCalls++;
    allNotesOffStarted?.complete();
    await allNotesOffGate?.future;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    disposedCompleted?.complete();
  }

  @override
  Future<void> loadSoundfontsFromAssets(
    Map<int, String> assetPathsByProgram,
  ) async {
    loadSoundfontsStarted?.complete();
    await loadSoundfontsGate?.future;
    final error = nextLoadSoundfontsError;
    nextLoadSoundfontsError = null;
    if (error != null) throw error;
    loadedAssetsByProgram = Map<int, String>.of(assetPathsByProgram);
  }

  @override
  Future<void> noteOff({required int channel, required int note}) async {
    noteOffs.add(note);
  }

  @override
  Future<void> controlChange({
    required int channel,
    required int controller,
    required int value,
  }) async {
    controlChanges.add((controller, value));
  }

  @override
  Future<void> noteOn({
    required int channel,
    required int note,
    required int velocity,
  }) async {
    noteOns.add(note);
  }

  @override
  Future<void> setInstrument({
    required int channel,
    required int program,
    int bank = 0,
  }) async {
    setInstrumentStarted?.complete();
    await setInstrumentGate?.future;
    programs.add(program);
  }
}

MidiSongData _songWithAccompanimentProgram() => MidiSongData(
  fileName: 'k478.mid',
  format: 1,
  ticksPerBeat: 480,
  tracks: [
    MidiTrackInfo(index: 1, programByChannel: {0: 40}),
  ],
  timeline: [
    TimelineEvent(
      type: MidiEventType.programChange,
      tick: 0,
      time: 0,
      channel: 0,
      trackIndex: 1,
      data1: 40,
    ),
  ],
  tempoChanges: [TempoChange(tick: 0, microsecondsPerBeat: 500000)],
  timeSignatureChanges: const [],
  totalTicks: 480,
  totalDuration: 1,
);

void main() {
  Future<void> disposeDuringBlockedOperation({
    required K478PlayerController player,
    required _FakeEngine engine,
    required Future<void> operation,
    required Completer<void> started,
    required Completer<void> gate,
  }) async {
    await started.future;
    player.dispose();
    expect(engine.disposed, isFalse);
    gate.complete();
    await operation;
    await engine.disposedCompleted!.future;
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(player.state, PlaybackState.stopped);
    expect(player.isPlaying, isFalse);
  }

  test('准备阶段只加载 Violin 40 与 Cello 42 两个内置音色', () async {
    final engine = _FakeEngine();
    final player = K478PlayerController(engine: engine);

    await player.prepareSoundfont();

    expect(engine.loadedAssetsByProgram, k478SoundfontAssetsByProgram);
    expect(engine.loadedAssetsByProgram, isNot(contains(0)));
    player.dispose();
  });

  test('dispose 等待进行中的 SoundFont 加载完成后才释放音源', () async {
    final engine = _FakeEngine()
      ..loadSoundfontsGate = Completer<void>()
      ..loadSoundfontsStarted = Completer<void>()
      ..disposedCompleted = Completer<void>();
    final player = K478PlayerController(engine: engine);

    final loading = player.prepareSoundfont();
    await engine.loadSoundfontsStarted!.future;
    player.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(engine.disposed, isFalse);

    engine.loadSoundfontsGate!.complete();
    await loading;
    await engine.disposedCompleted!.future;
    expect(engine.disposed, isTrue);
  });

  test('SoundFont 加载失败后队列仍允许下一次准备', () async {
    final engine = _FakeEngine()
      ..nextLoadSoundfontsError = StateError('first load failed');
    final player = K478PlayerController(engine: engine);

    await player.prepareSoundfont();
    expect(player.soundfontState, SoundfontState.failed);

    await player.prepareSoundfont();
    expect(player.soundfontState, SoundfontState.ready);
    expect(engine.loadedAssetsByProgram, k478SoundfontAssetsByProgram);
    player.dispose();
  });

  test('dispose 在 loadSong 清音期间不会继续载入或恢复播放器', () async {
    final engine = _FakeEngine()
      ..allNotesOffGate = Completer<void>()
      ..allNotesOffStarted = Completer<void>()
      ..disposedCompleted = Completer<void>();
    final player = K478PlayerController(engine: engine);

    await disposeDuringBlockedOperation(
      player: player,
      engine: engine,
      operation: player.loadSong(_songWithAccompanimentProgram()),
      started: engine.allNotesOffStarted!,
      gate: engine.allNotesOffGate!,
    );
    expect(engine.programs, isEmpty);
  });

  test('dispose 在 play 配置音色期间不会重启 Timer', () async {
    final engine = _FakeEngine();
    final player = K478PlayerController(engine: engine);
    await player.loadSong(_songWithAccompanimentProgram());
    engine
      ..setInstrumentGate = Completer<void>()
      ..setInstrumentStarted = Completer<void>()
      ..disposedCompleted = Completer<void>();

    await disposeDuringBlockedOperation(
      player: player,
      engine: engine,
      operation: player.play(),
      started: engine.setInstrumentStarted!,
      gate: engine.setInstrumentGate!,
    );
  });

  test('dispose 在 pause 清音期间不会发送后续通知或恢复播放', () async {
    final engine = _FakeEngine();
    final player = K478PlayerController(engine: engine);
    await player.loadSong(_songWithAccompanimentProgram());
    await player.play();
    engine
      ..allNotesOffGate = Completer<void>()
      ..allNotesOffStarted = Completer<void>()
      ..disposedCompleted = Completer<void>();

    await disposeDuringBlockedOperation(
      player: player,
      engine: engine,
      operation: player.pause(),
      started: engine.allNotesOffStarted!,
      gate: engine.allNotesOffGate!,
    );
  });

  test('dispose 在 seek 清音期间不会重启 Timer', () async {
    final engine = _FakeEngine();
    final player = K478PlayerController(engine: engine);
    await player.loadSong(_songWithAccompanimentProgram());
    await player.play();
    engine
      ..allNotesOffGate = Completer<void>()
      ..allNotesOffStarted = Completer<void>()
      ..disposedCompleted = Completer<void>();

    await disposeDuringBlockedOperation(
      player: player,
      engine: engine,
      operation: player.seekTo(0.5),
      started: engine.allNotesOffStarted!,
      gate: engine.allNotesOffGate!,
    );
  });

  test('只把弦乐轨送进音频引擎，钢琴 Program 0 与音符被过滤', () async {
    final engine = _FakeEngine();
    final player = K478PlayerController(engine: engine);
    final song = MidiSongData(
      fileName: 'k478.mid',
      format: 1,
      ticksPerBeat: 480,
      tracks: [
        MidiTrackInfo(index: 1, programByChannel: {0: 40}),
        MidiTrackInfo(index: 4, programByChannel: {3: 0}),
      ],
      timeline: [
        TimelineEvent(
          type: MidiEventType.programChange,
          tick: 0,
          time: 0,
          channel: 0,
          trackIndex: 1,
          data1: 40,
        ),
        TimelineEvent(
          type: MidiEventType.programChange,
          tick: 0,
          time: 0,
          channel: 3,
          trackIndex: 4,
          data1: 0,
        ),
        TimelineEvent(
          type: MidiEventType.noteOn,
          tick: 0,
          time: 0,
          channel: 0,
          trackIndex: 1,
          data1: 64,
          data2: 100,
        ),
        TimelineEvent(
          type: MidiEventType.noteOn,
          tick: 0,
          time: 0,
          channel: 3,
          trackIndex: 4,
          data1: 60,
          data2: 100,
        ),
        TimelineEvent(
          type: MidiEventType.noteOff,
          tick: 48,
          time: 0.01,
          channel: 0,
          trackIndex: 1,
          data1: 64,
        ),
        TimelineEvent(
          type: MidiEventType.noteOff,
          tick: 48,
          time: 0.01,
          channel: 3,
          trackIndex: 4,
          data1: 60,
        ),
      ],
      tempoChanges: [TempoChange(tick: 0, microsecondsPerBeat: 500000)],
      timeSignatureChanges: [],
      totalTicks: 480,
      totalDuration: 0.1,
    );

    await player.loadSong(song);
    await player.play();
    await Future<void>.delayed(const Duration(milliseconds: 25));
    await player.pause();

    expect(engine.programs, everyElement(isNot(0)));
    expect(engine.programs, contains(40));
    expect(engine.noteOns, [64]);
    expect(engine.noteOffs, [64]);
    player.dispose();
  });

  test('播放、暂停、seek、速度和停止保持一致的会话状态', () async {
    final engine = _FakeEngine();
    final player = K478PlayerController(engine: engine);
    final song = MidiSongData(
      fileName: 'k478.mid',
      format: 1,
      ticksPerBeat: 480,
      tracks: const [],
      timeline: const [],
      tempoChanges: [TempoChange(tick: 0, microsecondsPerBeat: 500000)],
      timeSignatureChanges: const [],
      totalTicks: 9600,
      totalDuration: 10,
    );

    await player.loadSong(song);
    player.setSpeed(0.5);
    await player.play();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await player.pause();
    final pausedAt = player.currentTime;

    expect(player.state, PlaybackState.paused);
    expect(pausedAt, greaterThan(0));
    expect(pausedAt, lessThan(0.1));

    await player.seekTo(5);
    expect(player.currentTime, 5);
    expect(player.state, PlaybackState.paused);

    await player.stop();
    expect(player.state, PlaybackState.stopped);
    expect(player.currentTime, 0);
    expect(engine.allNotesOffCalls, greaterThanOrEqualTo(3));
    player.dispose();
  });

  test('CC7 会被分发，并在 seek 后恢复目标位置前的最近音量', () async {
    final engine = _FakeEngine();
    final player = K478PlayerController(engine: engine);
    final song = MidiSongData(
      fileName: 'k478.mid',
      format: 1,
      ticksPerBeat: 480,
      tracks: [
        MidiTrackInfo(index: 1, programByChannel: {0: 40}),
      ],
      timeline: [
        TimelineEvent(
          type: MidiEventType.programChange,
          tick: 0,
          time: 0,
          channel: 0,
          trackIndex: 1,
          data1: 40,
        ),
        TimelineEvent(
          type: MidiEventType.controlChange,
          tick: 24,
          time: 0.02,
          channel: 0,
          trackIndex: 1,
          data1: 7,
          data2: 45,
        ),
      ],
      tempoChanges: [TempoChange(tick: 0, microsecondsPerBeat: 500000)],
      timeSignatureChanges: [],
      totalTicks: 480,
      totalDuration: 1,
    );

    await player.loadSong(song);
    await player.play();
    await Future<void>.delayed(const Duration(milliseconds: 35));
    await player.pause();
    await player.seekTo(0.5);

    expect(engine.controlChanges, contains((7, 45)));
    player.dispose();
  });

  Future<void> expectReplayAfterDelayedAllNotesOff(
    Future<void> Function(K478PlayerController player) clear,
  ) async {
    final engine = _FakeEngine();
    final player = K478PlayerController(engine: engine);
    final song = MidiSongData(
      fileName: 'k478.mid',
      format: 1,
      ticksPerBeat: 480,
      tracks: [
        MidiTrackInfo(index: 1, programByChannel: {0: 40}),
      ],
      timeline: [
        TimelineEvent(
          type: MidiEventType.programChange,
          tick: 0,
          time: 0,
          channel: 0,
          trackIndex: 1,
          data1: 40,
        ),
        TimelineEvent(
          type: MidiEventType.noteOn,
          tick: 60,
          time: 0.05,
          channel: 0,
          trackIndex: 1,
          data1: 64,
          data2: 100,
        ),
      ],
      tempoChanges: [TempoChange(tick: 0, microsecondsPerBeat: 500000)],
      timeSignatureChanges: [],
      totalTicks: 480,
      totalDuration: 1,
    );
    await player.loadSong(song);
    await player.play();

    engine.allNotesOffGate = Completer<void>();
    final clearing = clear(player);
    final replay = player.play();
    await Future<void>.delayed(Duration.zero);
    expect(player.isPlaying, isFalse);
    engine.allNotesOffGate!.complete();
    await clearing;
    await replay;
    expect(player.isPlaying, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(engine.noteOns, contains(64));
    player.dispose();
  }

  test('pause 后立即 play 不会越过未完成的 allNotesOff', () async {
    await expectReplayAfterDelayedAllNotesOff((player) => player.pause());
  });

  test('seek 后立即 play 不会越过未完成的 allNotesOff', () async {
    await expectReplayAfterDelayedAllNotesOff((player) => player.seekTo(0));
  });

  test('stop 后立即 play 不会越过未完成的 allNotesOff', () async {
    await expectReplayAfterDelayedAllNotesOff((player) => player.stop());
  });

  test('stop 会取消仍在等待清音的 pauseAt Future', () async {
    final engine = _FakeEngine();
    final player = K478PlayerController(engine: engine);
    await player.loadSong(
      MidiSongData(
        fileName: 'k478.mid',
        format: 1,
        ticksPerBeat: 480,
        tracks: const [],
        timeline: const [],
        tempoChanges: [TempoChange(tick: 0, microsecondsPerBeat: 500000)],
        timeSignatureChanges: const [],
        totalTicks: 480,
        totalDuration: 0.2,
      ),
    );
    await player.play();
    engine.allNotesOffGate = Completer<void>();
    engine.allNotesOffStarted = Completer<void>();
    final boundary = player.pauseAt(0.01);
    await engine.allNotesOffStarted!.future;

    final stop = player.stop();
    await expectLater(boundary, completes);
    engine.allNotesOffGate!.complete();
    await stop;
    player.dispose();
  });

  test('内置 K.478 弦乐轨只含候选支持的 CC7，不含 pitch bend 或 sustain', () {
    final bytes = File(
      'assets/midi/mozart_k478_piano_quartet.mid',
    ).readAsBytesSync();
    final song = MidiFileParser().parseBytes(bytes, fileName: 'k478.mid');
    final accompaniment = song.timeline.where(
      (event) => k478AccompanimentTrackIndexes.contains(event.trackIndex),
    );
    final controls = accompaniment
        .where((event) => event.type == MidiEventType.controlChange)
        .toList(growable: false);

    expect(controls, isNotEmpty);
    expect(controls.every((event) => event.data1 == 7), isTrue);
    expect(
      accompaniment.where((event) => event.type == MidiEventType.pitchBend),
      isEmpty,
    );
    expect(controls.where((event) => event.data1 == 64), isEmpty);
  });
}
