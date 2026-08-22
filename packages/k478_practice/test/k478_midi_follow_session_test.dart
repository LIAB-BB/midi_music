import 'dart:async';

import 'package:core_midi_input/core_midi_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k478_practice/src/core/k478_midi_follow_session.dart';
import 'package:k478_practice/src/core/k478_player.dart';
import 'package:k478_practice/src/core/midi_engine.dart';
import 'package:k478_practice/src/models/midi_track.dart';

class _ReadyEngine implements MidiPlaybackEngine {
  @override
  bool get isReady => true;

  @override
  Future<void> allNotesOff() async {}

  @override
  Future<void> dispose() async {}

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
  }) async {}

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

  @override
  Future<void> dispose() async {
    disposed = true;
    await _messages.close();
    await _states.close();
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
}
