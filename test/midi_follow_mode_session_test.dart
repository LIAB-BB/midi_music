import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/follow/midi_follow_mode_session.dart';
import 'package:midi_music/core/midi/midi_engine.dart';
import 'package:midi_music/core/midi/midi_player.dart';
import 'package:midi_music/core/midi_input/midi_input.dart';
import 'package:midi_music/models/midi_track.dart';

void main() {
  test('USB MIDI 跟随启动时静音钢琴轨，退出后恢复', () async {
    final melody = _melodyTrack();
    final player = _playerWith(melody);
    final midiInput = _FakeMidiInput(connected: true);
    final session = MidiFollowModeSession(
      player: player,
      performerTracks: [melody],
      midiInput: midiInput,
    );

    await session.start();

    expect(melody.isMuted, isTrue);
    expect(player.isPlaying, isTrue);
    expect(session.isActive, isTrue);

    midiInput.emit(status: 0x90, note: 60, velocity: 100, micros: 1000000);
    midiInput.emit(status: 0x90, note: 62, velocity: 100, micros: 1800000);
    await pumpEventQueue();

    expect(session.speedFactor, closeTo(1.075, 0.0001));

    await session.dispose();
    expect(melody.isMuted, isFalse);
    expect(player.playbackSpeed, 1.0);
    player.dispose();
  });

  test('保留用户原本的钢琴轨静音状态', () async {
    final melody = _melodyTrack()..isMuted = true;
    final player = _playerWith(melody);
    final session = MidiFollowModeSession(
      player: player,
      performerTracks: [melody],
      midiInput: _FakeMidiInput(connected: true),
    );

    await session.start();
    await session.dispose();

    expect(melody.isMuted, isTrue);
    player.dispose();
  });

  test('没有 USB MIDI 设备时拒绝启动且不静音钢琴轨', () async {
    final melody = _melodyTrack();
    final player = _playerWith(melody);
    final session = MidiFollowModeSession(
      player: player,
      performerTracks: [melody],
      midiInput: _FakeMidiInput(connected: false),
    );

    await expectLater(session.start(), throwsStateError);

    expect(melody.isMuted, isFalse);
    expect(player.isPlaying, isFalse);
    player.dispose();
  });

  test('多个钢琴轨会合并跟随、一起静音并分别恢复', () async {
    final upper = _melodyTrack();
    final lower = MidiTrackInfo(
      index: 1,
      name: 'Piano lower',
      notes: [
        MidiNote(
          noteNumber: 48,
          velocity: 90,
          channel: 1,
          startTick: 0,
          endTick: 240,
          startTime: 0,
          endTime: 0.5,
        ),
      ],
    )..isMuted = true;
    final player = _playerWith(upper, extraTracks: [lower]);
    final midiInput = _FakeMidiInput(connected: true);
    final session = MidiFollowModeSession(
      player: player,
      performerTracks: [upper, lower],
      midiInput: midiInput,
    );

    await session.start();
    expect(upper.isMuted, isTrue);
    expect(lower.isMuted, isTrue);

    midiInput.emit(status: 0x90, note: 48, velocity: 100, micros: 1000000);
    midiInput.emit(status: 0x90, note: 62, velocity: 100, micros: 1800000);
    await pumpEventQueue();
    expect(session.speedFactor, closeTo(1.075, 0.0001));

    await session.dispose();
    expect(upper.isMuted, isFalse);
    expect(lower.isMuted, isTrue);
    player.dispose();
  });
}

MidiPlayerController _playerWith(
  MidiTrackInfo melody, {
  List<MidiTrackInfo> extraTracks = const [],
}) {
  final player = MidiPlayerController(engine: _ReadyMidiEngine());
  player.loadSong(
    MidiSongData(
      fileName: 'piano-quartet.mid',
      format: 1,
      ticksPerBeat: 480,
      tracks: [melody, ...extraTracks, MidiTrackInfo(index: 9)],
      timeline: const [],
      tempoChanges: [TempoChange(tick: 0, microsecondsPerBeat: 500000)],
      timeSignatureChanges: const [],
      totalTicks: 1440,
      totalDuration: 3,
    ),
  );
  return player;
}

MidiTrackInfo _melodyTrack() {
  return MidiTrackInfo(
    index: 0,
    name: 'Piano',
    notes: [
      MidiNote(
        noteNumber: 60,
        velocity: 90,
        channel: 0,
        startTick: 0,
        endTick: 240,
        startTime: 0,
        endTime: 0.5,
      ),
      MidiNote(
        noteNumber: 62,
        velocity: 90,
        channel: 0,
        startTick: 480,
        endTick: 720,
        startTime: 1,
        endTime: 1.5,
      ),
    ],
  );
}

class _FakeMidiInput implements MidiInput {
  final controller = StreamController<MidiInputMessage>.broadcast();
  @override
  final MidiInputState state;

  _FakeMidiInput({required bool connected})
    : state = MidiInputState(
        devices: connected
            ? const [MidiInputDevice(id: '1', name: 'Digital Piano')]
            : const [],
      );

  @override
  Stream<MidiInputMessage> get messages => controller.stream;

  @override
  Stream<MidiInputState> get states => const Stream.empty();

  void emit({
    required int status,
    required int note,
    required int velocity,
    required int micros,
  }) {
    controller.add(
      MidiInputMessage(
        status: status,
        data1: note,
        data2: velocity,
        timestamp: DateTime.fromMicrosecondsSinceEpoch(micros),
      ),
    );
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() => controller.close();
}

class _ReadyMidiEngine implements MidiPlaybackEngine {
  @override
  bool get isReady => true;

  @override
  Future<void> allNotesOff() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> loadSoundfontFromAsset(String assetPath) async {}

  @override
  Future<void> loadSoundfontFromFile(String filePath) async {}

  @override
  Future<void> noteOff({required int channel, required int note}) async {}

  @override
  Future<void> noteOn({
    required int channel,
    required int note,
    required int velocity,
  }) async {}

  @override
  Future<void> setInstrument({
    required int channel,
    required int program,
    int bank = 0,
  }) async {}

  @override
  Future<void> waitForPendingOperations() async {}
}
