import 'dart:async';

import 'package:core_midi_input/core_midi_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k478_practice/src/core/follow_mode_controller.dart';
import 'package:k478_practice/src/core/k478_midi_follow_session.dart';
import 'package:k478_practice/src/core/k478_player.dart';
import 'package:k478_practice/src/core/midi_engine.dart';
import 'package:k478_practice/src/models/midi_track.dart';

class _ReadyEngine implements MidiPlaybackEngine {
  Completer<void>? allNotesOffGate;
  Completer<void>? allNotesOffStarted;
  final List<int> noteOns = [];

  @override
  bool get isReady => true;

  @override
  Future<void> allNotesOff() async {
    allNotesOffStarted?.complete();
    await allNotesOffGate?.future;
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> loadSoundfontsFromAssets(
    Map<int, String> assetPathsByProgram,
  ) async {}

  @override
  Future<void> noteOff({required int channel, required int note}) async {}

  @override
  Future<void> controlChange({
    required int channel,
    required int controller,
    required int value,
  }) async {}

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
  Completer<void>? startGate;
  Completer<void>? startStarted;
  bool keepStreamsOpenOnDispose = false;

  @override
  Stream<MidiInputMessage> get messages => _messages.stream;

  @override
  Stream<MidiInputState> get states => _states.stream;

  @override
  MidiInputState get state => const MidiInputState(
    devices: [MidiInputDevice(id: 'usb-1', name: 'Digital Piano')],
  );

  @override
  Future<void> start() async {
    startStarted?.complete();
    await startGate?.future;
  }

  void addNote(int note, DateTime timestamp) {
    _messages.add(
      MidiInputMessage(
        status: 0x90,
        data1: note,
        data2: 100,
        timestamp: timestamp,
      ),
    );
  }

  void addError(Object error) {
    _messages.addError(error);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    if (!keepStreamsOpenOnDispose) {
      await _messages.close();
      await _states.close();
    }
  }
}

void main() {
  test('停止跟随后恢复开始前的用户速度', () async {
    final player = K478PlayerController(engine: _ReadyEngine());
    player.setSpeed(0.75);
    final input = _ConnectedInput();
    final performerTracks = [
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
            startTime: 1,
            endTime: 1.5,
          ),
        ],
      ),
    ];
    final session = K478MidiFollowSession(
      player: player,
      performerTracks: performerTracks,
      input: input,
    );

    await session.start();
    final firstAt = DateTime(2026, 8, 20, 12);
    input.addNote(60, firstAt);
    input.addNote(62, firstAt.add(const Duration(milliseconds: 800)));
    await Future<void>.delayed(Duration.zero);

    expect(player.playbackSpeed, greaterThan(1));
    await session.dispose();

    expect(player.playbackSpeed, 0.75);
    expect(input.disposed, isTrue);
    player.dispose();
  });

  test('输入流错误会终止会话并通知页面层重新开始', () async {
    final player = K478PlayerController(engine: _ReadyEngine());
    final input = _ConnectedInput();
    final session = K478MidiFollowSession(
      player: player,
      performerTracks: [
        MidiTrackInfo(
          index: 4,
          notes: [
            MidiNote(
              noteNumber: 60,
              velocity: 100,
              channel: 0,
              startTick: 0,
              endTick: 120,
              startTime: 0,
              endTime: 0.25,
            ),
          ],
        ),
      ],
      input: input,
    );
    final terminated = Completer<Object>();
    session.onTerminated = (_, error) => terminated.complete(error);

    await session.start();
    input.addError(StateError('device disconnected'));

    expect(await terminated.future, isA<StateError>());
    expect(session.isActive, isFalse);
    expect(session.state, FollowModeState.idle);
    expect(input.disposed, isTrue);
    player.dispose();
  });

  test('首次正确匹配后的连续错音不会改变播放器速度', () async {
    final player = K478PlayerController(engine: _ReadyEngine());
    final input = _ConnectedInput();
    final session = K478MidiFollowSession(
      player: player,
      performerTracks: [
        MidiTrackInfo(
          index: 4,
          notes: [
            MidiNote(
              noteNumber: 60,
              velocity: 100,
              channel: 0,
              startTick: 0,
              endTick: 120,
              startTime: 0,
              endTime: 0.25,
            ),
            MidiNote(
              noteNumber: 62,
              velocity: 100,
              channel: 0,
              startTick: 240,
              endTick: 360,
              startTime: 0.5,
              endTime: 0.75,
            ),
          ],
        ),
      ],
      input: input,
    );

    await session.start();
    final at = DateTime(2026, 8, 23, 12);
    input.addNote(60, at);
    for (var index = 0; index < 3; index++) {
      input.addNote(72, at.add(Duration(milliseconds: 100 + index * 100)));
    }
    await Future<void>.delayed(Duration.zero);

    expect(session.speedFactor, 1);
    expect(player.playbackSpeed, 1);
    await session.dispose();
    player.dispose();
  });

  test('start 与 dispose 并发时不重新绑定跟随或播放', () async {
    final player = K478PlayerController(engine: _ReadyEngine());
    final input = _ConnectedInput()
      ..startGate = Completer<void>()
      ..startStarted = Completer<void>()
      ..keepStreamsOpenOnDispose = true;
    final session = K478MidiFollowSession(
      player: player,
      performerTracks: [
        MidiTrackInfo(
          index: 4,
          notes: [
            MidiNote(
              noteNumber: 60,
              velocity: 100,
              channel: 0,
              startTick: 0,
              endTick: 120,
              startTime: 0,
              endTime: 0.25,
            ),
          ],
        ),
      ],
      input: input,
    );

    final starting = session.start();
    await input.startStarted!.future;
    final disposing = session.dispose();
    expect(input.disposed, isFalse);

    input.startGate!.complete();
    await starting;
    await disposing;
    input.addNote(60, DateTime(2026, 8, 23, 12));
    await Future<void>.delayed(Duration.zero);

    expect(session.isActive, isFalse);
    expect(session.state, FollowModeState.idle);
    expect(input.disposed, isTrue);
    expect(player.state, PlaybackState.stopped);
    await input._messages.close();
    await input._states.close();
    player.dispose();
  });

  test('长休止在边界暂停，错误重入不恢复，正确重入 seek 后播放', () async {
    final engine = _ReadyEngine();
    final player = K478PlayerController(engine: engine);
    await player.loadSong(
      MidiSongData(
        fileName: 'k478.mid',
        format: 1,
        ticksPerBeat: 480,
        tracks: const [],
        timeline: [
          TimelineEvent(
            type: MidiEventType.noteOn,
            tick: 240,
            time: 0.2,
            channel: 0,
            trackIndex: 1,
            data1: 67,
            data2: 100,
          ),
        ],
        tempoChanges: [TempoChange(tick: 0, microsecondsPerBeat: 500000)],
        timeSignatureChanges: const [],
        totalTicks: 480,
        totalDuration: 0.4,
      ),
    );
    final input = _ConnectedInput();
    final session = K478MidiFollowSession(
      player: player,
      performerTracks: [
        MidiTrackInfo(
          index: 4,
          notes: [
            MidiNote(
              noteNumber: 60,
              velocity: 100,
              channel: 0,
              startTick: 0,
              endTick: 96,
              startTime: 0,
              endTime: 0.08,
            ),
            MidiNote(
              noteNumber: 62,
              velocity: 100,
              channel: 0,
              startTick: 240,
              endTick: 300,
              startTime: 0.2,
              endTime: 0.25,
            ),
          ],
        ),
      ],
      input: input,
      config: const FollowModeConfig(
        restThresholdSeconds: 0.05,
        approvedWaitReentryTicks: {240},
      ),
    );
    await session.start();
    final at = DateTime(2026, 8, 23, 12);
    input.addNote(60, at);
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(session.state, FollowModeState.following);
    expect(player.state, PlaybackState.playing);
    expect(player.currentTime, lessThan(0.08));

    await Future<void>.delayed(const Duration(milliseconds: 90));

    expect(session.state, FollowModeState.waitingForOnset);
    expect(player.state, PlaybackState.paused);
    expect(player.currentTime, closeTo(0.08, 0.01));

    input.addNote(72, at.add(const Duration(milliseconds: 300)));
    await Future<void>.delayed(Duration.zero);
    expect(player.state, PlaybackState.paused);
    expect(player.currentTime, closeTo(0.08, 0.01));

    input.addNote(62, at.add(const Duration(milliseconds: 600)));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(session.state, FollowModeState.following);
    expect(player.state, PlaybackState.playing);
    expect(player.currentTime, greaterThanOrEqualTo(0.2));
    expect(engine.noteOns, contains(67));
    await session.dispose();
    player.dispose();
  });

  test('会话退出后，延迟的长休止回调不能重新播放', () async {
    final engine = _ReadyEngine();
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
        totalDuration: 0.3,
      ),
    );
    final input = _ConnectedInput();
    final session = K478MidiFollowSession(
      player: player,
      performerTracks: [
        MidiTrackInfo(
          index: 4,
          notes: [
            MidiNote(
              noteNumber: 60,
              velocity: 100,
              channel: 0,
              startTick: 0,
              endTick: 12,
              startTime: 0,
              endTime: 0.01,
            ),
            MidiNote(
              noteNumber: 62,
              velocity: 100,
              channel: 0,
              startTick: 120,
              endTick: 180,
              startTime: 0.1,
              endTime: 0.15,
            ),
          ],
        ),
      ],
      input: input,
      config: const FollowModeConfig(
        restThresholdSeconds: 0.05,
        approvedWaitReentryTicks: {120},
      ),
    );
    await session.start();
    engine.allNotesOffGate = Completer<void>();
    engine.allNotesOffStarted = Completer<void>();
    input.addNote(60, DateTime(2026, 8, 23, 12));
    await engine.allNotesOffStarted!.future;

    final dispose = session.dispose();
    expect(session.isActive, isFalse);
    engine.allNotesOffGate!.complete();
    await dispose;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(player.state, PlaybackState.stopped);
    expect(player.currentTime, 0);
    player.dispose();
  });
}
