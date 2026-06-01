import 'dart:async';

import '../../models/midi_track.dart';
import '../midi/midi_player.dart';
import 'follow_mode_controller.dart';
import 'follow_playback_target.dart';
import 'microphone_input.dart';
import 'onset_detector.dart';
import 'pitch_input.dart';

class FollowModeSessionConfig {
  final int sampleRate;
  final int bufferSize;
  final double minPrecision;

  const FollowModeSessionConfig({
    this.sampleRate = 44100,
    this.bufferSize = 4096,
    this.minPrecision = 0.6,
  });
}

class FollowModeSession {
  final FollowPlaybackTarget _playbackTarget;
  final MidiTrackInfo _melodyTrack;
  final PitchInput _pitchInput;
  final OnsetDetector _onsetDetector;
  final FollowModeController _followController;
  final FollowModeSessionConfig _config;

  bool _disposed = false;
  bool _started = false;
  FollowModeState _state = FollowModeState.idle;
  double _speedFactor = 1.0;

  SpeedChangeCallback? onSpeedChanged;
  StateChangeCallback? onStateChanged;

  FollowModeState get state => _state;
  double get speedFactor => _speedFactor;
  bool get isActive => _started && _state != FollowModeState.idle;

  factory FollowModeSession({
    required FollowPlaybackTarget playbackTarget,
    required MidiTrackInfo melodyTrack,
    PitchInput? pitchInput,
    OnsetDetector? onsetDetector,
    FollowModeController? followController,
    FollowModeSessionConfig config = const FollowModeSessionConfig(),
  }) {
    final resolvedOnsetDetector = onsetDetector ?? OnsetDetector();
    return FollowModeSession._(
      playbackTarget: playbackTarget,
      melodyTrack: melodyTrack,
      pitchInput: pitchInput ?? MicrophoneInput(),
      onsetDetector: resolvedOnsetDetector,
      followController:
          followController ??
          FollowModeController(onsetDetector: resolvedOnsetDetector),
      config: config,
    );
  }

  factory FollowModeSession.forMidi({
    required MidiPlayerController player,
    required MidiTrackInfo melodyTrack,
    PitchInput? pitchInput,
    OnsetDetector? onsetDetector,
    FollowModeController? followController,
    FollowModeSessionConfig config = const FollowModeSessionConfig(),
  }) {
    return FollowModeSession(
      playbackTarget: MidiFollowPlaybackTarget(player),
      melodyTrack: melodyTrack,
      pitchInput: pitchInput,
      onsetDetector: onsetDetector,
      followController: followController,
      config: config,
    );
  }

  FollowModeSession._({
    required FollowPlaybackTarget playbackTarget,
    required MidiTrackInfo melodyTrack,
    required PitchInput pitchInput,
    required OnsetDetector onsetDetector,
    required FollowModeController followController,
    required FollowModeSessionConfig config,
  }) : _playbackTarget = playbackTarget,
       _melodyTrack = melodyTrack,
       _pitchInput = pitchInput,
       _onsetDetector = onsetDetector,
       _followController = followController,
       _config = config;

  static MidiTrackInfo? findMelodyTrack(MidiSongData song, int trackIndex) {
    for (final track in song.tracks) {
      if (track.index == trackIndex) {
        return track;
      }
    }
    return null;
  }

  Future<void> start() async {
    if (_disposed) {
      throw StateError('跟随模式会话已经释放');
    }
    if (_started) return;
    if (_melodyTrack.notes.isEmpty) {
      throw StateError('主旋律轨道没有可跟随的音符');
    }

    _followController.onSpeedChanged = _handleSpeedChanged;
    _followController.onStateChanged = _handleStateChanged;
    _followController.loadScore(_melodyTrack.notes);
    _onsetDetector.attachPitchStream(_pitchInput.pitchStream);

    try {
      await _pitchInput.start(
        sampleRate: _config.sampleRate,
        bufferSize: _config.bufferSize,
        minPrecision: _config.minPrecision,
      );

      if (!_playbackTarget.isPlaying) {
        await _playbackTarget.play();
      }

      _followController.start();
      if (!_followController.isActive) {
        throw StateError('跟随模式启动失败');
      }
      _started = true;
    } catch (_) {
      await dispose(resetPlayerSpeed: false);
      rethrow;
    }
  }

  Future<void> dispose({bool resetPlayerSpeed = true}) async {
    if (_disposed) return;
    _disposed = true;
    _started = false;

    _followController.stop(notifyCallbacks: false);
    _onsetDetector.detach();
    await _pitchInput.dispose();
    _followController.dispose();
    _onsetDetector.dispose();

    _state = FollowModeState.idle;
    _speedFactor = 1.0;
    if (resetPlayerSpeed) {
      await _playbackTarget.setSpeed(1.0);
    }
  }

  void _handleSpeedChanged(double speedFactor) {
    _speedFactor = speedFactor;
    unawaited(_playbackTarget.setSpeed(speedFactor));
    onSpeedChanged?.call(speedFactor);
  }

  void _handleStateChanged(FollowModeState state) {
    _state = state;
    switch (state) {
      case FollowModeState.idle:
        _started = false;
        _speedFactor = 1.0;
        unawaited(_playbackTarget.setSpeed(1.0));
      case FollowModeState.following:
        if (!_playbackTarget.isPlaying) {
          unawaited(_playbackTarget.play());
        }
      case FollowModeState.waitingForOnset:
        if (_playbackTarget.isPlaying) {
          unawaited(_playbackTarget.pause());
        }
    }
    onStateChanged?.call(state);
  }
}
