import 'dart:async';

import 'package:core_midi_input/core_midi_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k478_practice/src/core/follow_mode_controller.dart';
import 'package:k478_practice/src/core/k478_adaptive_follow_session.dart';
import 'package:k478_practice/src/core/k478_player.dart';
import 'package:k478_practice/src/core/midi_engine.dart';
import 'package:k478_practice/src/models/midi_track.dart';

class _ReadyEngine implements MidiPlaybackEngine {
  final List<int> noteOns = [];
  bool disposed = false;

  @override
  bool get isReady => true;

  @override
  Future<void> allNotesOff() async {}

  @override
  Future<void> controlChange({
    required int channel,
    required int controller,
    required int value,
  }) async {}

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<void> loadSoundfontsFromAssets(
    Map<int, String> assetPathsByProgram,
  ) async {}

  @override
  Future<void> noteOff({required int channel, required int note}) async {}

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
  }) async {}
}

class _ConnectedInput implements MidiInput {
  final _messages = StreamController<MidiInputMessage>.broadcast();
  final _states = StreamController<MidiInputState>.broadcast();
  bool disposed = false;

  @override
  Stream<MidiInputMessage> get messages => _messages.stream;

  @override
  Stream<MidiInputState> get states => _states.stream;

  @override
  MidiInputState get state => const MidiInputState(
    devices: [MidiInputDevice(id: 'usb-1', name: 'Digital Piano')],
  );

  @override
  Future<void> start() async {}

  void addNote(int note) {
    _messages.add(
      MidiInputMessage(
        status: 0x90,
        data1: note,
        data2: 100,
        timestamp: DateTime.now(),
      ),
    );
  }

  void disconnect() {
    _states.add(const MidiInputState());
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _messages.close();
    await _states.close();
  }
}

MidiSongData _song() => MidiSongData(
  fileName: 'k478_test.mid',
  format: 1,
  ticksPerBeat: 480,
  tracks: [
    MidiTrackInfo(
      index: 4,
      notes: [
        MidiNote(
          noteNumber: 60,
          velocity: 100,
          channel: 0,
          startTick: 0,
          endTick: 240,
          startTime: 0,
          endTime: 0.5,
        ),
        MidiNote(
          noteNumber: 62,
          velocity: 100,
          channel: 0,
          startTick: 480,
          endTick: 720,
          startTime: 0.5,
          endTime: 1,
        ),
        MidiNote(
          noteNumber: 64,
          velocity: 100,
          channel: 0,
          startTick: 960,
          endTick: 1200,
          startTime: 1,
          endTime: 1.5,
        ),
      ],
    ),
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
  totalTicks: 1920,
  totalDuration: 2,
);

List<MidiTrackInfo> _performerTracks() => [
  MidiTrackInfo(
    index: 4,
    notes: [
      MidiNote(
        noteNumber: 60,
        velocity: 100,
        channel: 0,
        startTick: 0,
        endTick: 240,
        startTime: 0,
        endTime: 0.5,
      ),
      MidiNote(
        noteNumber: 62,
        velocity: 100,
        channel: 0,
        startTick: 480,
        endTick: 720,
        startTime: 0.5,
        endTime: 1,
      ),
      MidiNote(
        noteNumber: 64,
        velocity: 100,
        channel: 0,
        startTick: 960,
        endTick: 1200,
        startTime: 1,
        endTime: 1.5,
      ),
    ],
  ),
];

Future<void> _settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  Future<K478PlayerController> createPlayer(_ReadyEngine engine) async {
    final player = K478PlayerController(engine: engine);
    await player.loadSong(_song());
    await player.prepareSoundfont();
    return player;
  }

  test('两次正确起拍后启动伴奏并进入跟随', () async {
    final engine = _ReadyEngine();
    final player = await createPlayer(engine);
    final input = _ConnectedInput();
    var now = 0.0;
    final session = K478AdaptiveFollowSession(
      player: player,
      performerTracks: _performerTracks(),
      input: input,
      timeProvider: () => now,
    );
    addTearDown(() async {
      await session.dispose();
      player.dispose();
    });

    await session.start();
    expect(session.isActive, isTrue);
    expect(session.state, FollowModeState.following);

    input.addNote(60);
    await _settle();
    expect(player.isPlaying, isFalse);

    now = 0.5;
    input.addNote(62);
    await _settle();
    expect(player.isPlaying, isTrue);
    expect(player.playbackSpeed, closeTo(1, 0.2));
    expect(session.speedFactor, closeTo(1, 0.2));
    // 锁定在第二个 onset 时，应从上一个 onset（0 s）起播，而不是 0.5 s。
    expect(player.currentTime, lessThan(0.2));

    now = 1;
    input.addNote(64);
    await _settle();
    expect(player.isPlaying, isTrue);
  });

  test('拔掉 MIDI 输入会终止会话并暂停伴奏', () async {
    final engine = _ReadyEngine();
    final player = await createPlayer(engine);
    final input = _ConnectedInput();
    var now = 0.0;
    final session = K478AdaptiveFollowSession(
      player: player,
      performerTracks: _performerTracks(),
      input: input,
      timeProvider: () => now,
    );
    addTearDown(() async {
      await session.dispose();
      player.dispose();
    });

    await session.start();
    input.addNote(60);
    await _settle();
    now = 0.5;
    input.addNote(62);
    await _settle();
    expect(player.isPlaying, isTrue);

    final terminated = Completer<Object>();
    session.onTerminated = (_, error) => terminated.complete(error);
    input.disconnect();

    final error = await terminated.future.timeout(const Duration(seconds: 2));
    expect(error, isA<StateError>());
    expect(session.isActive, isFalse);
    expect(player.isPlaying, isFalse);
    expect(input.disposed, isTrue);
  });

  test('停止跟随后恢复开始前的用户速度', () async {
    final engine = _ReadyEngine();
    final player = await createPlayer(engine);
    player.setSpeed(0.75);
    final input = _ConnectedInput();
    var now = 0.0;
    final session = K478AdaptiveFollowSession(
      player: player,
      performerTracks: _performerTracks(),
      input: input,
      timeProvider: () => now,
    );

    await session.start();
    input.addNote(60);
    await _settle();
    now = 0.5;
    input.addNote(62);
    await _settle();
    expect(player.playbackSpeed, closeTo(1, 0.2));

    await session.dispose();
    expect(player.playbackSpeed, 0.75);
    expect(input.disposed, isTrue);
    player.dispose();
  });

  test('重复 start 不会建立第二个会话', () async {
    final engine = _ReadyEngine();
    final player = await createPlayer(engine);
    final input = _ConnectedInput();
    final session = K478AdaptiveFollowSession(
      player: player,
      performerTracks: _performerTracks(),
      input: input,
    );
    addTearDown(() async {
      await session.dispose();
      player.dispose();
    });

    await Future.wait([session.start(), session.start()]);
    expect(session.isActive, isTrue);
    expect(session.state, FollowModeState.following);
  });
}
