import 'dart:async';

import 'package:core_midi_input/core_midi_input.dart';
import 'package:score_follow/score_follow.dart';

import '../models/midi_track.dart';
import 'follow_mode_controller.dart';
import 'follow_phase.dart';
import 'follow_rest_plan.dart';
import 'k478_player.dart';

typedef AdaptiveFollowStateCallback = void Function(FollowModeState state);
typedef AdaptiveFollowTerminatedCallback =
    void Function(K478AdaptiveFollowSession session, Object error);

/// 用 score_follow 的多假设内核驱动 K.478 候选播放器。
///
/// 与旧 [K478MidiFollowSession] 的区别：
/// - 输入时间来自会话自己的单调时钟（或测试注入），不使用 CoreMIDI 的
///   host timestamp；
/// - 只有置信度达到 0.5 才启动伴奏；
/// - 普通匹配只调速；重新捕获或大漂移才 seek；
/// - 拔掉 USB 设备时暂停并上报，而不是让伴奏继续空转。
///
/// 本类保留与旧会话相同的公开生命周期（start/dispose/state/callbacks），
/// 便于候选页面切换和回退。
class K478AdaptiveFollowSession {
  K478AdaptiveFollowSession({
    required K478PlayerController player,
    required List<MidiTrackInfo> performerTracks,
    required MidiInput input,
    FollowConfig config = const FollowConfig(minSpeed: 0.25, maxSpeed: 2),
    double Function()? timeProvider,
    double restMinSilenceSeconds = 1,
    bool enableGlobalRestWait = true,
  }) : _player = player,
       _performerTracks = List<MidiTrackInfo>.unmodifiable(performerTracks),
       _input = input,
       _config = config,
       _timeProvider = timeProvider,
       _restMinSilenceSeconds = restMinSilenceSeconds,
       _enableGlobalRestWait = enableGlobalRestWait;

  final K478PlayerController _player;
  final List<MidiTrackInfo> _performerTracks;
  final MidiInput _input;
  final FollowConfig _config;

  /// 测试可注入；生产环境使用 [_clock]。
  final double Function()? _timeProvider;
  final Stopwatch _clock = Stopwatch();
  final double _restMinSilenceSeconds;
  final bool _enableGlobalRestWait;

  AdaptiveScoreFollower? _follower;
  Score? _score;
  RestPlan? _restPlan;
  double? _scheduledRestStart;
  StreamSubscription<MidiInputMessage>? _messageSubscription;
  StreamSubscription<MidiInputState>? _stateSubscription;
  Future<void>? _startFuture;
  Future<void>? _disposeFuture;
  Future<void> _commandTail = Future<void>.value();
  int _commandGeneration = 0;
  bool _started = false;
  bool _disposed = false;
  bool _terminating = false;
  bool _locked = false;
  FollowModeState _state = FollowModeState.idle;
  double _speedFactor = 1;
  double _speedBeforeStart = 1;

  AdaptiveFollowStateCallback? onStateChanged;
  AdaptiveFollowTerminatedCallback? onTerminated;

  MidiInputState get inputState => _input.state;
  FollowModeState get state => _state;
  double get speedFactor => _speedFactor;
  bool get isActive => _started && !_disposed && !_terminating;

  Future<void> start() {
    if (_disposed) {
      return Future<void>.error(StateError('自适应跟随会话已经释放'));
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
    final notes = <MidiNote>[
      for (final track in _performerTracks) ...track.notes,
    ];
    if (notes.isEmpty) {
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
    if (!_player.isSoundfontReady) {
      throw StateError('弦乐音色尚未就绪');
    }

    final score = _buildScore(notes);
    _score = score;
    _follower = AdaptiveScoreFollower(score: score, config: _config);
    final song = _player.song;
    if (_enableGlobalRestWait && song != null) {
      _restPlan = RestPlan.fromSong(
        song,
        minSilenceSeconds: _restMinSilenceSeconds,
      );
    }
    _clock.start();
    _messageSubscription = _input.messages
        .where((message) => message.isNoteOn)
        .listen(_handleMessage, onError: _handleInputError);
    _stateSubscription = _input.states.listen(_handleInputState);
    _started = true;
    _setState(FollowModeState.following);
  }

  bool get _shouldAbortStart => _disposed || _terminating;

  void _clearStartFuture(Future<void> future) {
    if (identical(_startFuture, future)) _startFuture = null;
  }

  double _now() {
    final provider = _timeProvider;
    if (provider != null) return provider();
    return _clock.elapsedMicroseconds / 1000000;
  }

  void _handleMessage(MidiInputMessage message) {
    if (_disposed || !_started || _terminating) return;
    final follower = _follower;
    if (follower == null) return;

    final update = follower.onNoteOn(message.noteNumber, _now());
    _speedFactor = update.speed;

    if (!_locked) {
      if (!update.matched || update.confidence < 0.5) return;
      _locked = true;
      // 从上一个 onset 起播，避免“等置信度够”把第一个弦乐起拍切掉。
      final score = _score;
      final previousIndex = update.positionOnsetIndex - 1;
      final target = score != null && previousIndex >= 0
          ? score.onsets[previousIndex].time
          : update.scoreTime;
      _enqueuePlayerCommand((generation) async {
        _player.setSpeed(update.speed);
        await _player.seekTo(target, includeEventsAtTarget: true);
        if (_isCancelled(generation)) return;
        await _player.play();
        if (_isCancelled(generation)) return;
        _scheduleNextRest(target);
      });
      return;
    }

    if (update.reacquired) {
      _enqueuePlayerCommand((generation) async {
        _player.setSpeed(update.speed);
        await _player.seekTo(update.scoreTime, includeEventsAtTarget: true);
        if (_isCancelled(generation)) return;
        if (!_player.isPlaying) await _player.play();
        if (_isCancelled(generation)) return;
        _scheduledRestStart = null;
        _scheduleNextRest(update.scoreTime);
      });
      return;
    }

    if (!update.matched) return;

    // 普通匹配只做小幅相位修正；大偏差留给下面的 seek 保护。
    final phaseError = _player.currentTime - update.scoreTime;
    _player.setSpeed(correctFollowSpeed(update.speed, phaseError));

    if (update.confidence >= 0.6 && phaseError.abs() > 0.8) {
      _enqueuePlayerCommand((generation) async {
        await _player.seekTo(update.scoreTime, includeEventsAtTarget: true);
        if (_isCancelled(generation)) return;
        _scheduledRestStart = null;
        _scheduleNextRest(update.scoreTime);
      });
    }
  }

  /// [pauseAt] 在到达全局休止边界时清音并暂停；重入时由 reacquired 路径恢复。
  void _scheduleNextRest(double fromScoreTime) {
    final plan = _restPlan;
    if (plan == null || _disposed || _terminating) return;
    final rest = plan.nextAfter(fromScoreTime);
    if (rest == null) return;
    if (_scheduledRestStart == rest.start) return;
    _scheduledRestStart = rest.start;
    unawaited(
      _player.pauseAt(rest.start, isCancelled: () => _disposed || _terminating),
    );
  }

  void _handleInputState(MidiInputState state) {
    if (_disposed || !_started || _terminating) return;
    if (state.devices.isEmpty) {
      _handleRuntimeError(StateError('MIDI 输入已断开'));
    }
  }

  void _handleInputError(Object error, [StackTrace? stackTrace]) {
    _handleRuntimeError(error);
  }

  void _handleRuntimeError(Object error) {
    if (_disposed || _terminating) return;
    _terminating = true;
    _commandGeneration++;
    _started = false;
    unawaited(_terminateAfterError(error));
  }

  Future<void> _terminateAfterError(Object error) async {
    await dispose();
    onTerminated?.call(this, error);
  }

  void _enqueuePlayerCommand(Future<void> Function(int generation) operation) {
    final generation = _commandGeneration;
    final next = _commandTail.catchError((Object _) {}).then<void>((_) async {
      if (_isCancelled(generation)) return;
      await operation(generation);
    });
    unawaited(
      next.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (!_isCancelled(generation)) _handleRuntimeError(error);
        },
      ),
    );
    _commandTail = next.catchError((Object _) {});
  }

  bool _isCancelled(int generation) =>
      _disposed || _terminating || generation != _commandGeneration;

  Future<void> dispose() {
    final disposing = _disposeFuture;
    if (disposing != null) return disposing;
    if (_disposed) return Future<void>.value();
    _disposed = true;
    _commandGeneration++;
    _started = false;
    final future = _disposeInternal();
    _disposeFuture = future;
    return future;
  }

  Future<void> _disposeInternal() async {
    final starting = _startFuture;
    if (starting != null) {
      await starting.catchError((Object _) {});
    }
    await _messageSubscription?.cancel();
    await _stateSubscription?.cancel();
    _messageSubscription = null;
    _stateSubscription = null;
    _clock.stop();
    await _player.stop();
    await _commandTail.catchError((Object _) {});
    _player.setSpeed(_speedBeforeStart);
    await _input.dispose();
    _setState(FollowModeState.idle);
    _speedFactor = 1;
  }

  Score _buildScore(List<MidiNote> notes) {
    return Score.fromNotes([
      for (final note in notes)
        ScoreNote(
          pitch: note.noteNumber,
          start: note.startTime,
          end: note.endTime,
          velocity: note.velocity,
          startTick: note.startTick,
          endTick: note.endTick,
        ),
    ], title: 'K.478 performer');
  }

  void _setState(FollowModeState state) {
    if (_state == state) return;
    _state = state;
    onStateChanged?.call(state);
  }
}
