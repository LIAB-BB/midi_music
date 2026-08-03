import 'dart:async';

import '../../models/midi_track.dart';
import 'onset_detector.dart';

// ============================================================
// 状态定义
// ============================================================

/// 跟随模式状态
enum FollowModeState {
  /// 空闲，未启动跟随
  idle,

  /// 正在跟随演奏者
  following,

  /// 等待演奏者在休止符后重新开始
  waitingForOnset,
}

// ============================================================
// 配置
// ============================================================

/// 跟随模式配置
class FollowModeConfig {
  /// EMA 平滑系数 (0.0-1.0)，越大越灵敏
  final double emaSmoothingAlpha;

  /// speedFactor 允许范围下限
  final double minSpeedFactor;

  /// speedFactor 允许范围上限
  final double maxSpeedFactor;

  /// 音符匹配容差（半音数），允许偏差范围
  final int noteMatchTolerance;

  /// 是否容忍常见八度误检，使用音级匹配同一类音名
  final bool allowOctaveError;

  /// 由匹配 onset 间隔测得的可信速度下限，超出范围则忽略
  final double minMeasuredSpeedFactor;

  /// 由匹配 onset 间隔测得的可信速度上限，超出范围则忽略
  final double maxMeasuredSpeedFactor;

  /// 休止符检测阈值（秒），期望音符间隔超过此值视为休止符
  final double restThresholdSeconds;

  /// 连续未匹配 onset 达到此数量后降低 speedFactor
  final int unmatchedThreshold;

  /// 同一和弦的 MIDI Note On 可能分批抵达，在此窗口内视为同一次起拍。
  final int chordInputWindowMs;

  const FollowModeConfig({
    this.emaSmoothingAlpha = 0.3,
    this.minSpeedFactor = 0.25,
    this.maxSpeedFactor = 4.0,
    this.noteMatchTolerance = 0,
    this.allowOctaveError = false,
    this.minMeasuredSpeedFactor = 0.6,
    this.maxMeasuredSpeedFactor = 1.6,
    this.restThresholdSeconds = 1.0,
    this.unmatchedThreshold = 3,
    this.chordInputWindowMs = 80,
  });
}

// ============================================================
// 速度变化回调类型
// ============================================================

/// 速度变化回调
typedef SpeedChangeCallback = void Function(double speedFactor);

/// 状态变化回调
typedef StateChangeCallback = void Function(FollowModeState state);

/// 请求外部按播放位置重新对齐
typedef RealignmentRequestCallback = void Function();

/// 运行时错误回调，例如麦克风采集中断或 pitch 流异常。
typedef FollowRuntimeErrorCallback =
    void Function(Object error, StackTrace? stackTrace);

// ============================================================
// FollowModeController
// ============================================================

/// 跟随模式控制器
///
/// 状态机：Idle → Following → WaitingForOnset → Following
/// 职责：订阅 OnsetDetector 的 onset 流，与乐谱期望音符匹配，
/// 计算 EMA 平滑的 speedFactor，通过回调通知播放器调速。
class FollowModeController {
  final Stream<OnsetEvent> _onsetStream;
  FollowModeConfig _config;

  /// 当前状态
  FollowModeState _state = FollowModeState.idle;

  /// 当前平滑后的 speedFactor
  double _speedFactor = 1.0;

  /// 乐谱中的期望起拍序列；同一 tick 的复音音符合并为一个起拍。
  List<_ScoreOnset> _scoreOnsets = [];

  /// 当前期望起拍索引
  int _expectedOnsetIndex = 0;

  /// 上一次成功匹配的谱面起拍索引
  int? _lastMatchedOnsetIndex;

  /// 上一次 onset 的时间戳
  DateTime? _lastOnsetTimestamp;

  /// 连续未匹配计数
  int _unmatchedCount = 0;

  /// onset 流订阅
  StreamSubscription<OnsetEvent>? _onsetSubscription;

  /// 回调
  SpeedChangeCallback? onSpeedChanged;
  StateChangeCallback? onStateChanged;
  RealignmentRequestCallback? onRealignmentRequested;
  FollowRuntimeErrorCallback? onRuntimeError;

  // Getters
  FollowModeState get state => _state;
  double get speedFactor => _speedFactor;
  FollowModeConfig get config => _config;
  bool get isActive => _state != FollowModeState.idle;

  FollowModeController({
    required OnsetDetector onsetDetector,
    FollowModeConfig? config,
  }) : _onsetStream = onsetDetector.onsetStream,
       _config = config ?? const FollowModeConfig();

  FollowModeController.fromOnsetStream({
    required Stream<OnsetEvent> onsetStream,
    FollowModeConfig? config,
  }) : _onsetStream = onsetStream,
       _config = config ?? const FollowModeConfig();

  /// 更新配置
  void updateConfig(FollowModeConfig config) {
    _config = config;
  }

  /// 加载乐谱音符序列，并把同一 tick 的和弦音合并为一个起拍。
  void loadScore(List<MidiNote> notes) {
    final sortedNotes = List.of(notes)
      ..sort((a, b) {
        final tickCompare = a.startTick.compareTo(b.startTick);
        if (tickCompare != 0) return tickCompare;
        return a.noteNumber.compareTo(b.noteNumber);
      });
    final onsets = <_ScoreOnset>[];
    for (final note in sortedNotes) {
      if (onsets.isEmpty || onsets.last.startTick != note.startTick) {
        onsets.add(_ScoreOnset(note));
      } else {
        onsets.last.add(note);
      }
    }
    _scoreOnsets = onsets;
  }

  /// 启动跟随模式
  void start() {
    if (_scoreOnsets.isEmpty) return;

    _resetFollowPosition(0);

    unawaited(_onsetSubscription?.cancel());
    _onsetSubscription = _onsetStream.listen(
      _handleOnset,
      onError: _handleOnsetError,
    );

    _setState(FollowModeState.following);
  }

  /// 停止跟随模式
  void stop({bool notifyCallbacks = true}) {
    _onsetSubscription?.cancel();
    _onsetSubscription = null;
    _speedFactor = 1.0;
    _lastMatchedOnsetIndex = null;
    if (notifyCallbacks) {
      _setState(FollowModeState.idle);
      onSpeedChanged?.call(1.0);
    } else {
      _state = FollowModeState.idle;
    }
  }

  /// 从指定音符索引恢复（用于 seek 后重新对齐）
  void resumeFromIndex(int noteIndex) {
    if (noteIndex < 0 || noteIndex >= _scoreOnsets.length) return;
    if (_state == FollowModeState.idle) {
      start();
    }
    _resetFollowPosition(noteIndex);
    _setState(FollowModeState.following);
  }

  /// 从播放时间恢复（用于播放器 seek/currentTime 后重新对齐）
  void resumeFromTime(double currentTimeSeconds) {
    if (_scoreOnsets.isEmpty) return;
    final onsetIndex = _findOnsetIndexAtOrAfter(currentTimeSeconds);
    if (onsetIndex == null) {
      stop();
      return;
    }
    resumeFromIndex(onsetIndex);
    if (_isTimeInsideLongRestBefore(onsetIndex, currentTimeSeconds)) {
      _setState(FollowModeState.waitingForOnset);
    }
  }

  // ============================================================
  // 核心逻辑：onset 处理
  // ============================================================

  /// 处理 onset 事件
  void _handleOnset(OnsetEvent onset) {
    if (_state == FollowModeState.idle) return;
    if (_isTrailingChordNote(onset)) return;
    if (_expectedOnsetIndex >= _scoreOnsets.length) {
      stop();
      return;
    }

    final expectedOnset = _scoreOnsets[_expectedOnsetIndex];
    final isMatch = expectedOnset.notes.any(
      (note) => _matchesExpectedNote(onset.midiNote, note),
    );

    if (isMatch) {
      _onNoteMatched(onset, expectedOnset);
    } else {
      _onNoteUnmatched(onset);
    }
  }

  void _handleOnsetError(Object error, StackTrace stackTrace) {
    if (_state == FollowModeState.idle) return;
    onRuntimeError?.call(error, stackTrace);
    stop();
  }

  /// 音符匹配成功
  void _onNoteMatched(OnsetEvent onset, _ScoreOnset expectedOnset) {
    final matchedOnsetIndex = _expectedOnsetIndex;
    _unmatchedCount = 0;

    // 如果是从 WaitingForOnset 恢复，切回 Following
    if (_state == FollowModeState.waitingForOnset) {
      _setState(FollowModeState.following);
    }

    // 计算 speedFactor
    if (_lastOnsetTimestamp != null) {
      final actualInterval =
          onset.timestamp.difference(_lastOnsetTimestamp!).inMilliseconds /
          1000.0;

      // 期望间隔 = 当前音符 startTime - 上一个匹配音符 startTime
      final prevIndex = _lastMatchedOnsetIndex;
      if (prevIndex != null && actualInterval > 0.01) {
        final expectedInterval =
            expectedOnset.startTime - _scoreOnsets[prevIndex].startTime;

        if (expectedInterval > 0.01) {
          final rawFactor = expectedInterval / actualInterval;
          _applyMeasuredSpeed(rawFactor);
        }
      }
    }

    _lastOnsetTimestamp = onset.timestamp;
    _lastMatchedOnsetIndex = matchedOnsetIndex;
    _expectedOnsetIndex++;

    // 检查下一个音符是否为休止符（间隔大）
    _checkForRest();
  }

  /// 音符未匹配
  void _onNoteUnmatched(OnsetEvent onset) {
    _unmatchedCount++;

    // 尝试向前搜索：演奏者可能跳过了一些音符
    final lookAhead = _findMatchInRange(
      onset.midiNote,
      _expectedOnsetIndex + 1,
      _expectedOnsetIndex + 4, // 最多向前看 3 个起拍
    );

    if (lookAhead >= 0) {
      // 找到匹配，跳过中间起拍
      _expectedOnsetIndex = lookAhead;
      _onNoteMatched(onset, _scoreOnsets[lookAhead]);
      return;
    }

    // 连续未匹配过多，逐渐降速
    if (_unmatchedCount >= _config.unmatchedThreshold) {
      _applyEmaSpeed(_speedFactor * 0.9);
    }
    if (_unmatchedCount == _config.unmatchedThreshold) {
      onRealignmentRequested?.call();
    }
  }

  // ============================================================
  // 辅助方法
  // ============================================================

  /// 检查下一个期望音符前是否有休止符
  void _checkForRest() {
    if (_expectedOnsetIndex >= _scoreOnsets.length) return;
    if (_expectedOnsetIndex == 0) return;

    final previousOnset = _scoreOnsets[_expectedOnsetIndex - 1];
    final nextOnset = _scoreOnsets[_expectedOnsetIndex];
    final gap = nextOnset.startTime - previousOnset.endTime;

    if (gap >= _config.restThresholdSeconds) {
      _setState(FollowModeState.waitingForOnset);
    }
  }

  /// 判断 onset 音符是否匹配期望音符（允许容差）
  bool _matchesExpectedNote(int onsetMidi, MidiNote expected) {
    final diff = (onsetMidi - expected.noteNumber).abs();
    if (diff <= _config.noteMatchTolerance) {
      return true;
    }

    if (!_config.allowOctaveError) {
      return false;
    }

    return _pitchClassDistance(onsetMidi, expected.noteNumber) <=
        _config.noteMatchTolerance;
  }

  int _pitchClassDistance(int a, int b) {
    final diff = ((a % 12) - (b % 12)).abs();
    return diff > 6 ? 12 - diff : diff;
  }

  /// 在指定范围内查找匹配音符，返回索引，未找到返回 -1
  int _findMatchInRange(int onsetMidi, int fromIndex, int toIndex) {
    final end = toIndex.clamp(0, _scoreOnsets.length);
    final start = fromIndex.clamp(0, end);
    for (int i = start; i < end; i++) {
      if (_scoreOnsets[i].notes.any(
        (note) => _matchesExpectedNote(onsetMidi, note),
      )) {
        return i;
      }
    }
    return -1;
  }

  int? _findOnsetIndexAtOrAfter(double currentTimeSeconds) {
    for (var i = 0; i < _scoreOnsets.length; i++) {
      final onset = _scoreOnsets[i];
      if (onset.endTime >= currentTimeSeconds) {
        return i;
      }
    }
    return null;
  }

  void _resetFollowPosition(int noteIndex) {
    _expectedOnsetIndex = noteIndex;
    _unmatchedCount = 0;
    _lastOnsetTimestamp = null;
    _lastMatchedOnsetIndex = null;
  }

  bool _isTimeInsideLongRestBefore(int noteIndex, double currentTimeSeconds) {
    final nextOnset = _scoreOnsets[noteIndex];
    if (currentTimeSeconds >= nextOnset.startTime) {
      return false;
    }

    final restStart = noteIndex == 0
        ? 0.0
        : _scoreOnsets[noteIndex - 1].endTime;
    final gap = nextOnset.startTime - restStart;
    return currentTimeSeconds >= restStart &&
        gap >= _config.restThresholdSeconds;
  }

  bool _isTrailingChordNote(OnsetEvent onset) {
    final lastTimestamp = _lastOnsetTimestamp;
    final lastIndex = _lastMatchedOnsetIndex;
    if (lastTimestamp == null || lastIndex == null) return false;
    final elapsedMs = onset.timestamp.difference(lastTimestamp).inMilliseconds;
    if (elapsedMs < 0 || elapsedMs > _config.chordInputWindowMs) return false;
    return _scoreOnsets[lastIndex].notes.any(
      (note) => _matchesExpectedNote(onset.midiNote, note),
    );
  }

  /// EMA 平滑更新 speedFactor 并通知回调
  void _applyEmaSpeed(double rawFactor) {
    final clamped = rawFactor.clamp(
      _config.minSpeedFactor,
      _config.maxSpeedFactor,
    );
    final alpha = _config.emaSmoothingAlpha;
    _speedFactor = alpha * clamped + (1 - alpha) * _speedFactor;
    onSpeedChanged?.call(_speedFactor);
  }

  /// 只采纳可信范围内的演奏间隔速度，避免单次误检强行拉动速度。
  void _applyMeasuredSpeed(double rawFactor) {
    if (rawFactor < _config.minMeasuredSpeedFactor ||
        rawFactor > _config.maxMeasuredSpeedFactor) {
      return;
    }
    _applyEmaSpeed(rawFactor);
  }

  /// 切换状态并通知回调
  void _setState(FollowModeState newState) {
    if (_state == newState) return;
    _state = newState;
    onStateChanged?.call(newState);
  }

  /// 释放资源
  void dispose() {
    stop(notifyCallbacks: false);
  }
}

class _ScoreOnset {
  final int startTick;
  final double startTime;
  final List<MidiNote> notes;
  double endTime;

  _ScoreOnset(MidiNote note)
    : startTick = note.startTick,
      startTime = note.startTime,
      notes = [note],
      endTime = note.endTime;

  void add(MidiNote note) {
    notes.add(note);
    if (note.endTime > endTime) endTime = note.endTime;
  }
}
