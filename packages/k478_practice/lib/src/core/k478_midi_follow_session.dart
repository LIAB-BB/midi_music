import 'dart:async';
import 'dart:math' as math;

import 'package:core_midi_input/core_midi_input.dart';

import '../models/midi_track.dart';
import 'follow_mode_controller.dart';
import 'k478_player.dart';
import 'onset_event.dart';

/// 用 USB MIDI 演奏的钢琴两轨控制 K.478 弦乐伴奏速度。
class K478MidiFollowSession {
  final K478PlayerController _player;
  final List<MidiTrackInfo> _performerTracks;
  final MidiInput _input;
  final FollowModeController _followController;

  StreamSubscription<MidiInputMessage>? _firstInputSubscription;
  bool _started = false;
  bool _disposed = false;
  bool _waitingForFirstInput = true;
  FollowModeState _state = FollowModeState.idle;
  double _speedFactor = 1;
  double _speedBeforeStart = 1;

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
  bool get isActive => _started;

  Future<void> start() async {
    if (_disposed) throw StateError('USB MIDI 跟随会话已经释放');
    if (_started) return;
    if (_performerTracks.isEmpty ||
        _performerTracks.every((track) => track.notes.isEmpty)) {
      throw StateError('K.478 钢琴声部没有可跟随的音符');
    }

    _speedBeforeStart = _player.playbackSpeed;
    await _input.start();
    if (!_input.state.isConnected) {
      throw StateError('没有检测到可用的 CoreMIDI 输入；请检查 USB 连接。');
    }

    _followController.onSpeedChanged = _handleSpeedChanged;
    _followController.onStateChanged = _handleStateChanged;
    _followController.onRuntimeError = _handleRuntimeError;
    _followController.loadScore(
      _performerTracks.expand((track) => track.notes).toList(growable: false),
    );
    _waitingForFirstInput = true;
    _firstInputSubscription = _input.messages
        .where((message) => message.isNoteOn)
        .listen((_) {
          if (_waitingForFirstInput) {
            _waitingForFirstInput = false;
            _player.play();
          }
        });
    _followController.start();
    _started = _followController.isActive;
    if (!_started) {
      await dispose();
      throw StateError('USB MIDI 跟随模式启动失败');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _started = false;
    await _firstInputSubscription?.cancel();
    _firstInputSubscription = null;
    _followController.stop(notifyCallbacks: false);
    _followController.onSpeedChanged = null;
    _followController.onStateChanged = null;
    _followController.onRuntimeError = null;
    _followController.dispose();
    _player.setSpeed(_speedBeforeStart);
    _player.pause();
    await _input.dispose();
    _state = FollowModeState.idle;
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
    _state = state;
    switch (state) {
      case FollowModeState.idle:
        _speedFactor = 1;
        _player.setSpeed(_speedBeforeStart);
        break;
      case FollowModeState.waitingForOnset:
        _player.pause();
        break;
      case FollowModeState.following:
        if (!_waitingForFirstInput) _player.play();
        break;
    }
  }

  void _handleRuntimeError(Object error, StackTrace? stackTrace) {
    unawaited(dispose());
  }
}
