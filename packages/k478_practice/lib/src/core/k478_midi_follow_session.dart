import 'dart:async';
import 'dart:math' as math;

import 'package:core_midi_input/core_midi_input.dart';

import '../models/midi_track.dart';
import 'follow_mode_controller.dart';
import 'k478_player.dart';
import 'onset_event.dart';

typedef FollowSessionStateCallback = void Function(FollowModeState state);
typedef FollowSessionTerminatedCallback =
    void Function(K478MidiFollowSession session, Object error);

/// 用 USB MIDI 演奏的钢琴两轨控制 K.478 弦乐伴奏速度。
class K478MidiFollowSession {
  final K478PlayerController _player;
  final List<MidiTrackInfo> _performerTracks;
  final MidiInput _input;
  final FollowModeController _followController;

  bool _started = false;
  bool _disposed = false;
  bool _terminating = false;
  Future<void>? _startFuture;
  Future<void>? _disposeFuture;
  FollowModeState _state = FollowModeState.idle;
  double _speedFactor = 1;
  double _speedBeforeStart = 1;

  FollowSessionStateCallback? onStateChanged;
  FollowSessionTerminatedCallback? onTerminated;

  K478MidiFollowSession({
    required K478PlayerController player,
    required List<MidiTrackInfo> performerTracks,
    required MidiInput input,
    FollowModeConfig? config,
  }) : _player = player,
       _performerTracks = List.unmodifiable(performerTracks),
       _input = input,
       _followController = FollowModeController.fromOnsetStream(
         onsetStream: input.messages
             .where((message) => message.isNoteOn)
             .map(_toOnset),
         config: config,
       );

  MidiInputState get inputState => _input.state;
  FollowModeState get state => _state;
  double get speedFactor => _speedFactor;
  bool get isActive => _started && !_disposed && !_terminating;

  Future<void> start() {
    if (_disposed) {
      return Future<void>.error(StateError('USB MIDI 跟随会话已经释放'));
    }
    if (_started) return Future<void>.value();
    final starting = _startFuture;
    if (starting != null) return starting;
    final future = _startInternal();
    _startFuture = future;
    unawaited(
      future.then<void>(
        (_) => _clearStartFuture(future),
        onError: (Object error, StackTrace stackTrace) =>
            _clearStartFuture(future),
      ),
    );
    return future;
  }

  Future<void> _startInternal() async {
    if (_performerTracks.isEmpty ||
        _performerTracks.every((track) => track.notes.isEmpty)) {
      throw StateError('K.478 钢琴声部没有可跟随的音符');
    }

    _speedBeforeStart = _player.playbackSpeed;
    await _player.stop();
    if (_shouldAbortStart) return;
    await _input.start();
    if (_shouldAbortStart) return;
    if (!_input.state.isConnected) {
      throw StateError('没有检测到可用的 CoreMIDI 输入；请检查 USB 连接。');
    }

    _followController.onSpeedChanged = _handleSpeedChanged;
    _followController.onStateChanged = _handleStateChanged;
    _followController.onMatch = _handleMatch;
    _followController.onRealignmentRequested = _handleRealignmentRequested;
    _followController.onRuntimeError = _handleRuntimeError;
    _followController.loadScore(
      _performerTracks.expand((track) => track.notes).toList(growable: false),
    );
    _followController.start();
    _started = _followController.isActive;
    if (!_started) {
      _followController.stop(notifyCallbacks: false);
      await _player.stop();
      await _input.dispose();
      throw StateError('USB MIDI 跟随模式启动失败');
    }
  }

  bool get _shouldAbortStart => _disposed || _terminating;

  void _clearStartFuture(Future<void> future) {
    if (identical(_startFuture, future)) _startFuture = null;
  }

  Future<void> dispose() {
    final disposing = _disposeFuture;
    if (disposing != null) return disposing;
    if (_disposed) return Future<void>.value();
    _disposed = true;
    _started = false;
    _followController.stop(notifyCallbacks: false);
    _followController.onSpeedChanged = null;
    _followController.onStateChanged = null;
    _followController.onMatch = null;
    _followController.onRealignmentRequested = null;
    _followController.onRuntimeError = null;
    _followController.dispose();
    final future = _disposeInternal();
    _disposeFuture = future;
    return future;
  }

  Future<void> _disposeInternal() async {
    final starting = _startFuture;
    if (starting != null) {
      await starting.catchError((Object _) {});
    }
    _player.setSpeed(_speedBeforeStart);
    await _player.stop();
    await _input.dispose();
    _setState(FollowModeState.idle);
    _speedFactor = 1;
  }

  static OnsetEvent _toOnset(MidiInputMessage message) {
    return OnsetEvent(
      midiNote: message.noteNumber,
      frequency: (440 * math.pow(2, (message.noteNumber - 69) / 12)).toDouble(),
      volume: message.velocity / 127,
      timestamp: message.timestamp,
    );
  }

  void _handleSpeedChanged(double speedFactor) {
    if (_disposed) return;
    _speedFactor = speedFactor;
    _player.setSpeed(speedFactor);
  }

  void _handleStateChanged(FollowModeState state) {
    if (_disposed) return;
    _setState(state);
    if (state == FollowModeState.idle) {
      _speedFactor = 1;
      _player.setSpeed(_speedBeforeStart);
    }
  }

  void _handleMatch(FollowMatch match) {
    if (_disposed || _terminating) return;
    unawaited(_applyMatch(match));
  }

  Future<void> _applyMatch(FollowMatch match) async {
    if (_disposed || _terminating) return;
    if (match.resumesFromRest) {
      await _player.seekTo(match.scoreTime);
      if (_disposed || _terminating) return;
      await _player.play();
      if (_disposed || _terminating) return;
    } else if (match.isInitialMatch) {
      await _player.play();
      if (_disposed || _terminating) return;
    }
    final rest = match.followingRest;
    if (rest != null) {
      await _player.pauseAt(rest.restStartScoreTime);
      if (_disposed || _terminating) return;
      _followController.markRestBoundaryReached(rest);
    }
  }

  void _handleRealignmentRequested(FollowRealignmentRequest request) {
    if (_disposed || _terminating) return;
    // 保持 controller 的期望 onset 和播放器的谱面时间一致；seek 会在原有
    // 播放状态下恢复，等待长休止时不会被此路径触发。
    unawaited(_player.seekTo(request.scoreTime));
  }

  void _handleRuntimeError(Object error, StackTrace? stackTrace) {
    if (_disposed || _terminating) return;
    _terminating = true;
    _started = false;
    unawaited(_terminateAfterInputError(error));
  }

  Future<void> _terminateAfterInputError(Object error) async {
    await dispose();
    onTerminated?.call(this, error);
  }

  void _setState(FollowModeState state) {
    if (_state == state) return;
    _state = state;
    onStateChanged?.call(state);
  }
}
