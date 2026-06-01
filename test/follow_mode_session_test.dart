import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/follow/follow_mode_controller.dart';
import 'package:midi_music/core/follow/follow_mode_session.dart';
import 'package:midi_music/core/follow/follow_playback_target.dart';
import 'package:midi_music/core/follow/onset_detector.dart';
import 'package:midi_music/core/follow/pitch_input.dart';
import 'package:midi_music/models/midi_track.dart';

void main() {
  test('按 track.index 查找主旋律轨道', () {
    final song = MidiSongData(
      fileName: 'test.mid',
      format: 1,
      ticksPerBeat: 480,
      tracks: [MidiTrackInfo(index: 4), MidiTrackInfo(index: 9)],
      timeline: const [],
      tempoChanges: const [],
      timeSignatureChanges: const [],
      totalTicks: 0,
      totalDuration: 0,
    );

    expect(FollowModeSession.findMelodyTrack(song, 9)?.index, 9);
    expect(FollowModeSession.findMelodyTrack(song, 1), isNull);
  });

  test('启动后根据 pitch 输入更新跟随速度', () async {
    final pitchInput = _FakePitchInput();
    final playbackTarget = _FakePlaybackTarget();
    final session = FollowModeSession(
      playbackTarget: playbackTarget,
      melodyTrack: MidiTrackInfo(
        index: 0,
        notes: [
          MidiNote(
            noteNumber: 60,
            velocity: 80,
            channel: 0,
            startTick: 0,
            endTick: 240,
            startTime: 0,
            endTime: 0.5,
          ),
          MidiNote(
            noteNumber: 62,
            velocity: 80,
            channel: 0,
            startTick: 480,
            endTick: 720,
            startTime: 1,
            endTime: 1.5,
          ),
        ],
      ),
      pitchInput: pitchInput,
    );
    final states = <FollowModeState>[];
    final speeds = <double>[];
    session.onStateChanged = states.add;
    session.onSpeedChanged = speeds.add;

    await session.start();

    expect(pitchInput.started, isTrue);
    expect(playbackTarget.isPlaying, isTrue);
    expect(session.isActive, isTrue);
    expect(states, contains(FollowModeState.following));

    final start = DateTime(2026);
    pitchInput.emit(_pitchData(midiNote: 60, timestamp: start));
    await pumpEventQueue();
    pitchInput.emit(
      _pitchData(
        midiNote: 62,
        timestamp: start.add(const Duration(milliseconds: 500)),
      ),
    );
    await pumpEventQueue();

    expect(speeds.last, closeTo(1.3, 0.0001));
    expect(playbackTarget.speed, closeTo(1.3, 0.0001));

    await session.dispose();

    expect(pitchInput.disposed, isTrue);
    expect(session.state, FollowModeState.idle);
    expect(playbackTarget.speed, 1.0);
  });

  test('遇到长休止时暂停播放，下一次 onset 后恢复', () async {
    final pitchInput = _FakePitchInput();
    final playbackTarget = _FakePlaybackTarget();
    final session = FollowModeSession(
      playbackTarget: playbackTarget,
      melodyTrack: MidiTrackInfo(
        index: 0,
        notes: [
          MidiNote(
            noteNumber: 60,
            velocity: 80,
            channel: 0,
            startTick: 0,
            endTick: 240,
            startTime: 0,
            endTime: 0.5,
          ),
          MidiNote(
            noteNumber: 62,
            velocity: 80,
            channel: 0,
            startTick: 960,
            endTick: 1200,
            startTime: 2,
            endTime: 2.5,
          ),
        ],
      ),
      pitchInput: pitchInput,
    );

    await session.start();

    final start = DateTime(2026);
    pitchInput.emit(_pitchData(midiNote: 60, timestamp: start));
    await pumpEventQueue();

    expect(session.state, FollowModeState.waitingForOnset);
    expect(playbackTarget.isPlaying, isFalse);
    expect(playbackTarget.pauseCount, 1);

    pitchInput.emit(
      _pitchData(
        midiNote: 62,
        timestamp: start.add(const Duration(milliseconds: 1200)),
      ),
    );
    await pumpEventQueue();

    expect(session.state, FollowModeState.following);
    expect(playbackTarget.isPlaying, isTrue);
    expect(playbackTarget.playCount, greaterThanOrEqualTo(2));

    await session.dispose();
  });
}

PitchData _pitchData({required int midiNote, required DateTime timestamp}) {
  return PitchData(
    frequency: 440,
    midiNote: midiNote,
    noteName: '',
    octave: 4,
    volume: 0.1,
    volumeDbFS: -20,
    precision: 1,
    timestamp: timestamp,
  );
}

class _FakePitchInput implements PitchInput {
  final _controller = StreamController<PitchData>.broadcast();
  bool started = false;
  bool disposed = false;

  @override
  Stream<PitchData> get pitchStream => _controller.stream;

  @override
  Future<void> start({
    int sampleRate = 44100,
    int bufferSize = 8192,
    double minPrecision = 0.7,
  }) async {
    started = true;
  }

  void emit(PitchData data) {
    _controller.add(data);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _controller.close();
  }
}

class _FakePlaybackTarget implements FollowPlaybackTarget {
  @override
  bool isPlaying = false;

  @override
  double speed = 1.0;

  int playCount = 0;
  int pauseCount = 0;

  @override
  Future<void> play() async {
    playCount++;
    isPlaying = true;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    isPlaying = false;
  }

  @override
  Future<void> setSpeed(double speed) async {
    this.speed = speed;
  }
}
