import 'dart:async';
import 'dart:math' as math;

import '../../models/midi_track.dart';
import '../midi/midi_player.dart';
import '../midi_input/midi_input.dart';
import 'follow_mode_controller.dart';
import 'follow_playback_target.dart';
import 'onset_detector.dart';

class MidiFollowModeSession {
  final MidiPlayerController _player;
  final List<MidiTrackInfo> _performerTracks;
  final MidiInput _midiInput;
  final FollowPlaybackTarget _playbackTarget;
  final FollowModeController _followController;

  bool _disposed = false;
  bool _started = false;
  final Map<int, bool> _previousMuteStates = {};
  FollowModeState _state = FollowModeState.idle;
  double _speedFactor = 1.0;

  SpeedChangeCallback? onSpeedChanged;
  StateChangeCallback? onStateChanged;
  FollowRuntimeErrorCallback? onRuntimeError;

  FollowModeState get state => _state;
  double get speedFactor => _speedFactor;
  bool get isActive => _started && _state != FollowModeState.idle;

  MidiFollowModeSession({
    required MidiPlayerController player,
    required List<MidiTrackInfo> performerTracks,
    required MidiInput midiInput,
    FollowModeController? followController,
    FollowModeConfig? config,
  }) : _player = player,
       _performerTracks = List.unmodifiable(performerTracks),
       _midiInput = midiInput,
       _playbackTarget = MidiFollowPlaybackTarget(player),
       _followController =
           followController ??
           FollowModeController.fromOnsetStream(
             onsetStream: midiInput.messages
                 .where((message) => message.isNoteOn)
                 .map(_toOnset),
             config: config,
           );

  static OnsetEvent _toOnset(MidiInputMessage message) {
    return OnsetEvent(
      midiNote: message.noteNumber,
      frequency: (440 * math.pow(2, (message.noteNumber - 69) / 12)).toDouble(),
      volume: message.velocity / 127,
      timestamp: message.timestamp,
    );
  }

  Future<void> start() async {
    if (_disposed) throw StateError('跟随模式会话已经释放');
    if (_started) return;
    if (_performerTracks.isEmpty ||
        _performerTracks.every((track) => track.notes.isEmpty)) {
      throw StateError('电子琴声部没有可跟随的音符');
    }

    await _midiInput.start();
    if (!_midiInput.state.isConnected) {
      throw StateError('未检测到 USB MIDI 电子琴');
    }

    _followController.onSpeedChanged = _handleSpeedChanged;
    _followController.onStateChanged = _handleStateChanged;
    _followController.onRealignmentRequested = _handleRealignmentRequested;
    _followController.onRuntimeError = _handleRuntimeError;
    _followController.loadScore(
      _performerTracks.expand((track) => track.notes).toList(),
    );

    for (final track in _performerTracks) {
      _previousMuteStates[track.index] = track.isMuted;
      _player.setTrackMute(track.index, isMuted: true);
    }

    try {
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

  void resumeFromTime(double currentTimeSeconds) {
    if (_disposed || !_started) return;
    _followController.resumeFromTime(currentTimeSeconds);
  }

  Future<void> dispose({bool resetPlayerSpeed = true}) async {
    if (_disposed) return;
    _disposed = true;
    _started = false;
    _followController.stop(notifyCallbacks: false);
    _followController.onSpeedChanged = null;
    _followController.onStateChanged = null;
    _followController.onRealignmentRequested = null;
    _followController.onRuntimeError = null;
    _followController.dispose();

    for (final entry in _previousMuteStates.entries) {
      _player.setTrackMute(entry.key, isMuted: entry.value);
    }
    _state = FollowModeState.idle;
    _speedFactor = 1.0;
    if (resetPlayerSpeed) {
      await _playbackTarget.setSpeed(1.0);
    }
  }

  void _handleSpeedChanged(double speedFactor) {
    if (_disposed) return;
    _speedFactor = speedFactor;
    unawaited(_playbackTarget.setSpeed(speedFactor));
    onSpeedChanged?.call(speedFactor);
  }

  void _handleStateChanged(FollowModeState state) {
    if (_disposed) return;
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

  void _handleRealignmentRequested() {
    if (_disposed || !_started) return;
    _followController.resumeFromTime(_playbackTarget.currentTime);
  }

  void _handleRuntimeError(Object error, StackTrace? stackTrace) {
    if (_disposed) return;
    onRuntimeError?.call(error, stackTrace);
    unawaited(dispose().catchError((Object _) {}));
  }
}
