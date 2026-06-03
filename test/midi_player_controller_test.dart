import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_engine.dart';
import 'package:midi_music/core/midi/midi_player.dart';
import 'package:midi_music/models/midi_track.dart';

void main() {
  test('重复准备音色时等待同一个下载任务', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'midi-player-sf2-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final soundfontFile = File('${tempDir.path}/test.sf2');
    final engine = _FakeMidiPlaybackEngine(ready: false);
    final downloadStarted = Completer<void>();
    final downloadGate = Completer<void>();
    var fileProviderCalls = 0;
    var downloadCalls = 0;
    final player = MidiPlayerController(
      engine: engine,
      soundfontFileProvider: () async {
        fileProviderCalls++;
        return soundfontFile;
      },
      soundfontDownloader: (targetFile) async {
        downloadCalls++;
        if (!downloadStarted.isCompleted) {
          downloadStarted.complete();
        }
        await downloadGate.future;
        await targetFile.writeAsBytes([1]);
      },
    );

    final firstSetup = player.ensureSoundfontReady();
    await downloadStarted.future;
    final secondSetup = player.ensureSoundfontReady();
    await pumpEventQueue();

    expect(fileProviderCalls, 1);
    expect(downloadCalls, 1);

    downloadGate.complete();
    await Future.wait([firstSetup, secondSetup]);

    expect(player.soundfontState, SoundfontSetupState.ready);
    expect(engine.calls.where((call) => call.type == 'loadFile'), [
      _EngineCall.loadFile(soundfontFile.path),
    ]);

    player.dispose();
  });

  test('可以读取 SoundFont 缓存诊断信息', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'midi-player-sf2-cache-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final soundfontFile = File('${tempDir.path}/test.sf2');
    await soundfontFile.writeAsBytes([1, 2, 3, 4]);
    final player = MidiPlayerController(
      engine: _FakeMidiPlaybackEngine(),
      soundfontFileProvider: () async => soundfontFile,
    );

    final cacheInfo = await player.inspectSoundfontCache();

    expect(cacheInfo.path, soundfontFile.path);
    expect(cacheInfo.exists, isTrue);
    expect(cacheInfo.sizeBytes, 4);
    expect(cacheInfo.errorMessage, isNull);

    player.dispose();
  });

  test('释放后完成的音色加载不会通知监听器', () async {
    final engine = _FakeMidiPlaybackEngine(ready: false);
    final loadGate = Completer<void>();
    engine.loadAssetGate = loadGate;
    final player = MidiPlayerController(engine: engine);
    var notifyCount = 0;
    player.addListener(() => notifyCount++);

    final loadFuture = player.loadSoundfont('test.sf2');
    await pumpEventQueue();
    player.dispose();
    loadGate.complete();

    await loadFuture;

    expect(notifyCount, 0);
  });

  test('加载歌曲时发送每个轨道的初始乐器设置', () {
    final engine = _FakeMidiPlaybackEngine();
    final player = MidiPlayerController(engine: engine);

    player.loadSong(
      _song(
        tracks: [
          MidiTrackInfo(index: 0, programByChannel: {0: 40}),
          MidiTrackInfo(index: 1, programByChannel: {3: 12}),
        ],
      ),
    );

    expect(engine.calls.where((call) => call.type == 'setInstrument'), [
      const _EngineCall.setInstrument(channel: 0, program: 40),
      const _EngineCall.setInstrument(channel: 3, program: 12),
    ]);

    player.dispose();
  });

  test('加载歌曲时不会提前应用未来的 Program Change', () {
    final engine = _FakeMidiPlaybackEngine();
    final player = MidiPlayerController(engine: engine);

    player.loadSong(
      _song(
        tracks: [
          MidiTrackInfo(index: 0, programByChannel: {0: 40}),
        ],
        timeline: [
          _programChange(trackIndex: 0, channel: 0, program: 40, time: 1),
        ],
      ),
    );

    expect(engine.calls.where((call) => call.type == 'setInstrument'), [
      const _EngineCall.setInstrument(channel: 0, program: 0),
    ]);

    player.dispose();
  });

  test('seek 后恢复当前位置已经生效的 Program Change', () {
    final engine = _FakeMidiPlaybackEngine();
    final player = MidiPlayerController(engine: engine);
    player.loadSong(
      _song(
        tracks: [
          MidiTrackInfo(index: 0, programByChannel: {0: 12}),
        ],
        timeline: [
          _programChange(trackIndex: 0, channel: 0, program: 40, time: 0.1),
          _programChange(trackIndex: 0, channel: 0, program: 12, time: 0.8),
        ],
      ),
    );
    engine.clear();

    player.seekTo(0.2);

    expect(engine.calls.where((call) => call.type == 'setInstrument'), [
      const _EngineCall.setInstrument(channel: 0, program: 40),
    ]);

    player.dispose();
  });

  test('seek 回 Program Change 之前时恢复默认乐器', () {
    final engine = _FakeMidiPlaybackEngine();
    final player = MidiPlayerController(engine: engine);
    player.loadSong(
      _song(
        tracks: [
          _track(index: 0, channels: {0}),
        ],
        timeline: [
          _programChange(trackIndex: 0, channel: 0, program: 40, time: 0.1),
        ],
      ),
    );
    player.seekTo(0.2);
    engine.clear();

    player.seekTo(0);

    expect(engine.calls.where((call) => call.type == 'setInstrument'), [
      const _EngineCall.setInstrument(channel: 0, program: 0),
    ]);

    player.dispose();
  });

  test('seek 回开头时恢复所有发生过 Program Change 的 channel', () {
    final engine = _FakeMidiPlaybackEngine();
    final player = MidiPlayerController(engine: engine);
    player.loadSong(
      _song(
        tracks: [
          _track(index: 0, channels: {0, 1}),
        ],
        timeline: [
          _programChange(trackIndex: 0, channel: 0, program: 40, time: 0.1),
          _programChange(trackIndex: 0, channel: 1, program: 12, time: 0.8),
        ],
      ),
    );
    player.seekTo(1);
    engine.clear();

    player.seekTo(0);

    expect(engine.calls.where((call) => call.type == 'setInstrument'), [
      const _EngineCall.setInstrument(channel: 0, program: 0),
      const _EngineCall.setInstrument(channel: 1, program: 0),
    ]);

    player.dispose();
  });

  test('负数轨道控制不会抛出越界异常', () {
    final engine = _FakeMidiPlaybackEngine();
    final player = MidiPlayerController(engine: engine);
    player.loadSong(_song(tracks: [_track(index: 0)]));

    expect(() => player.setTrackVolume(-1, 0.5), returnsNormally);
    expect(() => player.toggleTrackMute(-1), returnsNormally);

    player.dispose();
  });

  testWidgets('播放时按轨道音量折算 NoteOn 力度', (tester) async {
    final engine = _FakeMidiPlaybackEngine();
    final player = MidiPlayerController(engine: engine);
    player.loadSong(
      _song(
        tracks: [_track(index: 0)],
        timeline: [
          _noteOn(trackIndex: 0, channel: 0, note: 60, velocity: 100, time: 0),
        ],
      ),
    );
    player.setTrackVolume(0, 0.5);
    engine.clear();

    player.play();
    await tester.pump(const Duration(milliseconds: 6));

    expect(engine.calls.where((call) => call.type == 'noteOn'), [
      const _EngineCall.noteOn(channel: 0, note: 60, velocity: 50),
    ]);

    player.dispose();
  });

  testWidgets('轨道音量按 track.index 而不是列表位置查找', (tester) async {
    final engine = _FakeMidiPlaybackEngine();
    final player = MidiPlayerController(engine: engine);
    player.loadSong(
      _song(
        tracks: [_track(index: 4), _track(index: 9)],
        timeline: [
          _noteOn(trackIndex: 9, channel: 0, note: 60, velocity: 100, time: 0),
        ],
      ),
    );
    player.setTrackVolume(9, 0.25);
    engine.clear();

    player.play();
    await tester.pump(const Duration(milliseconds: 6));

    expect(engine.calls.where((call) => call.type == 'noteOn'), [
      const _EngineCall.noteOn(channel: 0, note: 60, velocity: 25),
    ]);

    player.dispose();
  });

  testWidgets('零音量轨道不会在共享 channel 时发送 NoteOn 或 NoteOff', (tester) async {
    final engine = _FakeMidiPlaybackEngine();
    final player = MidiPlayerController(engine: engine);
    player.loadSong(
      _song(
        tracks: [
          _track(index: 0, channels: {0}),
          _track(index: 1, channels: {0}),
        ],
        timeline: [
          _noteOn(trackIndex: 0, channel: 0, note: 60, velocity: 100, time: 0),
          _noteOn(trackIndex: 1, channel: 0, note: 60, velocity: 100, time: 0),
          _noteOff(trackIndex: 0, channel: 0, note: 60, time: 0.1),
        ],
      ),
    );
    player.setTrackVolume(0, 0);
    engine.clear();

    player.play();
    await tester.pump(const Duration(milliseconds: 120));

    expect(engine.calls.where((call) => call.type == 'noteOn'), [
      const _EngineCall.noteOn(channel: 0, note: 60, velocity: 100),
    ]);
    expect(engine.calls.where((call) => call.type == 'noteOff'), isEmpty);

    player.dispose();
  });

  testWidgets('播放中把轨道音量设为 0 会停止该轨道活动音', (tester) async {
    final engine = _FakeMidiPlaybackEngine();
    final player = MidiPlayerController(engine: engine);
    player.loadSong(
      _song(
        tracks: [
          _track(index: 0, channels: {0}),
          _track(index: 1, channels: {0}),
        ],
        timeline: [
          _noteOn(trackIndex: 0, channel: 0, note: 60, velocity: 100, time: 0),
          _noteOn(trackIndex: 1, channel: 0, note: 64, velocity: 100, time: 0),
        ],
      ),
    );
    player.play();
    await tester.pump(const Duration(milliseconds: 6));
    engine.clear();

    player.setTrackVolume(0, 0);

    expect(engine.calls.where((call) => call.type == 'noteOff'), [
      const _EngineCall.noteOff(channel: 0, note: 60),
    ]);

    player.dispose();
  });

  testWidgets('同步播放异常会带具体事件上下文上报', (tester) async {
    final engine = _FakeMidiPlaybackEngine()..throwSynchronouslyOnNoteOn = true;
    final player = MidiPlayerController(engine: engine);
    final errors = <String>[];
    player.onPlaybackError = (error, context) {
      errors.add('$context: $error');
    };
    player.loadSong(
      _song(
        tracks: [_track(index: 0)],
        timeline: [
          _noteOn(trackIndex: 0, channel: 0, note: 60, velocity: 100, time: 0),
        ],
      ),
    );

    player.play();
    await tester.pump(const Duration(milliseconds: 6));

    expect(errors, ['NoteOn ch:0 note:60: Bad state: sync noteOn failure']);

    player.dispose();
  });

  testWidgets('同步 NoteOn 失败不会把音符记录为活动音', (tester) async {
    final engine = _FakeMidiPlaybackEngine()..throwSynchronouslyOnNoteOn = true;
    final player = MidiPlayerController(engine: engine);
    player.loadSong(
      _song(
        tracks: [_track(index: 0)],
        timeline: [
          _noteOn(trackIndex: 0, channel: 0, note: 60, velocity: 100, time: 0),
          _noteOff(trackIndex: 0, channel: 0, note: 60, time: 0.01),
        ],
      ),
    );

    player.play();
    await tester.pump(const Duration(milliseconds: 20));

    expect(engine.calls.where((call) => call.type == 'noteOff'), isEmpty);

    player.dispose();
  });

  testWidgets('异步 NoteOn 失败会清理已记录的活动音', (tester) async {
    final engine = _FakeMidiPlaybackEngine()..failAsynchronouslyOnNoteOn = true;
    final player = MidiPlayerController(engine: engine);
    final errors = <String>[];
    player.onPlaybackError = (error, context) {
      errors.add('$context: $error');
    };
    player.loadSong(
      _song(
        tracks: [_track(index: 0)],
        timeline: [
          _noteOn(trackIndex: 0, channel: 0, note: 60, velocity: 100, time: 0),
          _noteOff(trackIndex: 0, channel: 0, note: 60, time: 0.02),
        ],
      ),
    );

    player.play();
    await tester.pump(const Duration(milliseconds: 10));
    engine.clear();
    await tester.pump(const Duration(milliseconds: 30));

    expect(errors, ['NoteOn ch:0 note:60: Bad state: async noteOn failure']);
    expect(engine.calls.where((call) => call.type == 'noteOff'), isEmpty);

    player.dispose();
  });

  testWidgets('静音轨道不会分发 NoteOn', (tester) async {
    final engine = _FakeMidiPlaybackEngine();
    final player = MidiPlayerController(engine: engine);
    player.loadSong(
      _song(
        tracks: [
          _track(index: 0, channels: {0}),
        ],
        timeline: [
          _noteOn(trackIndex: 0, channel: 0, note: 60, velocity: 100, time: 0),
        ],
      ),
    );
    player.toggleTrackMute(0);
    engine.clear();

    player.play();
    await tester.pump(const Duration(milliseconds: 6));

    expect(engine.calls.where((call) => call.type == 'noteOn'), isEmpty);

    player.dispose();
  });

  testWidgets('轨道静音按 track.index 而不是列表位置查找', (tester) async {
    final engine = _FakeMidiPlaybackEngine();
    final player = MidiPlayerController(engine: engine);
    player.loadSong(
      _song(
        tracks: [_track(index: 4), _track(index: 9)],
        timeline: [
          _noteOn(trackIndex: 9, channel: 0, note: 60, velocity: 100, time: 0),
        ],
      ),
    );
    player.toggleTrackMute(9);
    engine.clear();

    player.play();
    await tester.pump(const Duration(milliseconds: 6));

    expect(engine.calls.where((call) => call.type == 'noteOn'), isEmpty);

    player.dispose();
  });

  testWidgets('静音期间仍会应用 Program Change', (tester) async {
    final engine = _FakeMidiPlaybackEngine();
    final player = MidiPlayerController(engine: engine);
    player.loadSong(
      _song(
        tracks: [
          _track(index: 0, channels: {0}),
        ],
        timeline: [
          _programChange(trackIndex: 0, channel: 0, program: 40, time: 0),
          _noteOn(trackIndex: 0, channel: 0, note: 60, velocity: 100, time: 0),
        ],
      ),
    );
    player.toggleTrackMute(0);
    engine.clear();

    player.play();
    await tester.pump(const Duration(milliseconds: 6));

    expect(engine.calls.where((call) => call.type == 'setInstrument'), [
      const _EngineCall.setInstrument(channel: 0, program: 40),
    ]);
    expect(engine.calls.where((call) => call.type == 'noteOn'), isEmpty);

    player.dispose();
  });

  testWidgets('静音轨道未发出的 NoteOn 不会在共享 channel 时发送 NoteOff', (tester) async {
    final engine = _FakeMidiPlaybackEngine();
    final player = MidiPlayerController(engine: engine);
    player.loadSong(
      _song(
        tracks: [
          _track(index: 0, channels: {0}),
          _track(index: 1, channels: {0}),
        ],
        timeline: [
          _noteOn(trackIndex: 0, channel: 0, note: 60, velocity: 100, time: 0),
          _noteOn(trackIndex: 1, channel: 0, note: 60, velocity: 100, time: 0),
          _noteOff(trackIndex: 0, channel: 0, note: 60, time: 0.1),
        ],
      ),
    );
    player.toggleTrackMute(0);
    engine.clear();

    player.play();
    await tester.pump(const Duration(milliseconds: 120));

    expect(engine.calls.where((call) => call.type == 'noteOn'), [
      const _EngineCall.noteOn(channel: 0, note: 60, velocity: 100),
    ]);
    expect(engine.calls.where((call) => call.type == 'noteOff'), isEmpty);

    player.dispose();
  });

  testWidgets('静音共享 channel 的轨道只停止该轨道活动音符', (tester) async {
    final engine = _FakeMidiPlaybackEngine();
    final player = MidiPlayerController(engine: engine);
    player.loadSong(
      _song(
        tracks: [
          _track(index: 0, channels: {0}),
          _track(index: 1, channels: {0}),
        ],
        timeline: [
          _noteOn(trackIndex: 0, channel: 0, note: 60, velocity: 100, time: 0),
          _noteOn(trackIndex: 1, channel: 0, note: 64, velocity: 100, time: 0),
        ],
      ),
    );
    player.play();
    await tester.pump(const Duration(milliseconds: 6));
    engine.clear();

    player.toggleTrackMute(0);

    expect(engine.calls.where((call) => call.type == 'noteOff'), [
      const _EngineCall.noteOff(channel: 0, note: 60),
    ]);

    player.dispose();
  });

  testWidgets('静音重叠的同音符时按活动次数发送 NoteOff', (tester) async {
    final engine = _FakeMidiPlaybackEngine();
    final player = MidiPlayerController(engine: engine);
    player.loadSong(
      _song(
        tracks: [
          _track(index: 0, channels: {0}),
        ],
        timeline: [
          _noteOn(trackIndex: 0, channel: 0, note: 60, velocity: 100, time: 0),
          _noteOn(trackIndex: 0, channel: 0, note: 60, velocity: 100, time: 0),
        ],
      ),
    );
    player.play();
    await tester.pump(const Duration(milliseconds: 6));
    engine.clear();

    player.toggleTrackMute(0);

    expect(engine.calls.where((call) => call.type == 'noteOff'), [
      const _EngineCall.noteOff(channel: 0, note: 60),
      const _EngineCall.noteOff(channel: 0, note: 60),
    ]);

    player.dispose();
  });

  testWidgets('已经收到 NoteOff 的音符不会在静音时重复停止', (tester) async {
    final engine = _FakeMidiPlaybackEngine();
    final player = MidiPlayerController(engine: engine);
    player.loadSong(
      _song(
        tracks: [
          _track(index: 0, channels: {0}),
        ],
        timeline: [
          _noteOn(trackIndex: 0, channel: 0, note: 60, velocity: 100, time: 0),
          _noteOff(trackIndex: 0, channel: 0, note: 60, time: 0),
        ],
      ),
    );
    player.play();
    await tester.pump(const Duration(milliseconds: 6));
    engine.clear();

    player.toggleTrackMute(0);

    expect(engine.calls.where((call) => call.type == 'noteOff'), isEmpty);

    player.dispose();
  });

  testWidgets('seek 到事件之后再播放不会重放旧事件', (tester) async {
    final engine = _FakeMidiPlaybackEngine();
    final player = MidiPlayerController(engine: engine);
    player.loadSong(
      _song(
        tracks: [_track(index: 0)],
        timeline: [
          _noteOn(
            trackIndex: 0,
            channel: 0,
            note: 60,
            velocity: 100,
            time: 0.1,
          ),
        ],
      ),
    );
    player.seekTo(0.2);
    engine.clear();

    player.play();
    await tester.pump(const Duration(milliseconds: 6));

    expect(engine.calls.where((call) => call.type == 'noteOn'), isEmpty);

    player.dispose();
  });
}

MidiSongData _song({
  List<MidiTrackInfo>? tracks,
  List<TimelineEvent>? timeline,
}) {
  return MidiSongData(
    fileName: 'controller-test.mid',
    format: 1,
    ticksPerBeat: 480,
    tracks: tracks ?? [_track(index: 0)],
    timeline: timeline ?? const [],
    tempoChanges: [TempoChange(tick: 0, microsecondsPerBeat: 500000)],
    timeSignatureChanges: const [],
    totalTicks: 960,
    totalDuration: 2,
  );
}

MidiTrackInfo _track({required int index, Set<int>? channels}) {
  return MidiTrackInfo(index: index, channels: channels ?? {0});
}

TimelineEvent _noteOn({
  required int trackIndex,
  required int channel,
  required int note,
  required int velocity,
  required double time,
}) {
  return TimelineEvent(
    type: MidiEventType.noteOn,
    tick: (time * 960).round(),
    time: time,
    channel: channel,
    trackIndex: trackIndex,
    data1: note,
    data2: velocity,
  );
}

TimelineEvent _noteOff({
  required int trackIndex,
  required int channel,
  required int note,
  required double time,
}) {
  return TimelineEvent(
    type: MidiEventType.noteOff,
    tick: (time * 960).round(),
    time: time,
    channel: channel,
    trackIndex: trackIndex,
    data1: note,
    data2: 0,
  );
}

TimelineEvent _programChange({
  required int trackIndex,
  required int channel,
  required int program,
  required double time,
}) {
  return TimelineEvent(
    type: MidiEventType.programChange,
    tick: (time * 960).round(),
    time: time,
    channel: channel,
    trackIndex: trackIndex,
    data1: program,
  );
}

class _FakeMidiPlaybackEngine implements MidiPlaybackEngine {
  final calls = <_EngineCall>[];
  bool ready;
  Completer<void>? loadAssetGate;
  bool throwSynchronouslyOnNoteOn = false;
  bool failAsynchronouslyOnNoteOn = false;

  _FakeMidiPlaybackEngine({this.ready = true});

  @override
  bool get isReady => ready;

  void clear() => calls.clear();

  @override
  Future<void> loadSoundfontFromAsset(String assetPath) async {
    await loadAssetGate?.future;
    ready = true;
    calls.add(_EngineCall.loadAsset(assetPath));
  }

  @override
  Future<void> loadSoundfontFromFile(String filePath) async {
    ready = true;
    calls.add(_EngineCall.loadFile(filePath));
  }

  @override
  Future<void> setInstrument({
    required int channel,
    required int program,
    int bank = 0,
  }) async {
    calls.add(_EngineCall.setInstrument(channel: channel, program: program));
  }

  @override
  Future<void> noteOn({
    required int channel,
    required int note,
    required int velocity,
  }) {
    if (throwSynchronouslyOnNoteOn) {
      throw StateError('sync noteOn failure');
    }
    calls.add(
      _EngineCall.noteOn(channel: channel, note: note, velocity: velocity),
    );
    if (failAsynchronouslyOnNoteOn) {
      return Future<void>.delayed(
        const Duration(milliseconds: 1),
        () => throw StateError('async noteOn failure'),
      );
    }
    return Future<void>.value();
  }

  @override
  Future<void> noteOff({required int channel, required int note}) async {
    calls.add(_EngineCall.noteOff(channel: channel, note: note));
  }

  @override
  Future<void> allNotesOff() async {
    calls.add(const _EngineCall(type: 'allNotesOff'));
  }

  @override
  Future<void> waitForPendingOperations() async {}

  @override
  Future<void> dispose() async {
    ready = false;
    calls.add(const _EngineCall(type: 'dispose'));
  }
}

class _EngineCall {
  final String type;
  final int? channel;
  final int? program;
  final int? note;
  final int? velocity;
  final String? path;

  const _EngineCall({
    required this.type,
    this.channel,
    this.program,
    this.note,
    this.velocity,
    this.path,
  });

  const _EngineCall.loadAsset(String assetPath)
    : this(type: 'loadAsset', path: assetPath);

  const _EngineCall.loadFile(String filePath)
    : this(type: 'loadFile', path: filePath);

  const _EngineCall.setInstrument({required int channel, required int program})
    : this(type: 'setInstrument', channel: channel, program: program);

  const _EngineCall.noteOn({
    required int channel,
    required int note,
    required int velocity,
  }) : this(type: 'noteOn', channel: channel, note: note, velocity: velocity);

  const _EngineCall.noteOff({required int channel, required int note})
    : this(type: 'noteOff', channel: channel, note: note);

  @override
  bool operator ==(Object other) {
    return other is _EngineCall &&
        other.type == type &&
        other.channel == channel &&
        other.program == program &&
        other.note == note &&
        other.velocity == velocity &&
        other.path == path;
  }

  @override
  int get hashCode => Object.hash(type, channel, program, note, velocity, path);

  @override
  String toString() {
    return '_EngineCall($type, channel:$channel, program:$program, '
        'note:$note, velocity:$velocity, path:$path)';
  }
}
