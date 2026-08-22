import 'package:flutter_test/flutter_test.dart';
import 'package:k478_practice/src/core/k478_player.dart';
import 'package:k478_practice/src/core/midi_engine.dart';
import 'package:k478_practice/src/models/midi_track.dart';

class _FakeEngine implements MidiPlaybackEngine {
  final List<int> programs = [];
  final List<int> noteOns = [];
  final List<int> noteOffs = [];
  int allNotesOffCalls = 0;
  Map<int, String>? loadedAssetsByProgram;

  @override
  bool get isReady => true;

  @override
  Future<void> allNotesOff() async {
    allNotesOffCalls++;
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> loadSoundfontsFromAssets(
    Map<int, String> assetPathsByProgram,
  ) async {
    loadedAssetsByProgram = Map<int, String>.of(assetPathsByProgram);
  }

  @override
  Future<void> noteOff({required int channel, required int note}) async {
    noteOffs.add(note);
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
    programs.add(program);
  }
}

void main() {
  test('准备阶段只加载 Violin 40 与 Cello 42 两个内置音色', () async {
    final engine = _FakeEngine();
    final player = K478PlayerController(engine: engine);

    await player.prepareSoundfont();

    expect(engine.loadedAssetsByProgram, k478SoundfontAssetsByProgram);
    expect(engine.loadedAssetsByProgram, isNot(contains(0)));
    player.dispose();
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

    player.loadSong(song);
    player.play();
    await Future<void>.delayed(const Duration(milliseconds: 25));
    player.pause();

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

    player.loadSong(song);
    player.setSpeed(0.5);
    player.play();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    player.pause();
    final pausedAt = player.currentTime;

    expect(player.state, PlaybackState.paused);
    expect(pausedAt, greaterThan(0));
    expect(pausedAt, lessThan(0.1));

    player.seekTo(5);
    expect(player.currentTime, 5);
    expect(player.state, PlaybackState.paused);

    player.stop();
    expect(player.state, PlaybackState.stopped);
    expect(player.currentTime, 0);
    expect(engine.allNotesOffCalls, greaterThanOrEqualTo(3));
    player.dispose();
  });
}
