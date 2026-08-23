import 'dart:async';

import '../models/midi_track.dart';
import 'onset_event.dart';

/// 跟随模式状态。
enum FollowModeState {
  /// 空闲，未启动跟随。
  idle,

  /// 正在跟随演奏者。
  following,

  /// 已识别到长休止，等待正确的下一起拍。
  waitingForOnset,
}

/// 跟随模式配置。
class FollowModeConfig {
  final double emaSmoothingAlpha;
  final double minSpeedFactor;
  final double maxSpeedFactor;
  final int noteMatchTolerance;
  final bool allowOctaveError;
  final double minMeasuredSpeedFactor;
  final double maxMeasuredSpeedFactor;
  final double restThresholdSeconds;
  final int unmatchedThreshold;
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

/// 一段长休止的播放边界与正确重入位置。
class FollowRestBoundary {
  final double restStartScoreTime;
  final double resumeScoreTime;
  final int reentryOnsetIndex;

  const FollowRestBoundary({
    required this.restStartScoreTime,
    required this.resumeScoreTime,
    required this.reentryOnsetIndex,
  });
}

/// 一次正确谱面起拍匹配。
class FollowMatch {
  final int onsetIndex;
  final double scoreTime;
  final bool isInitialMatch;
  final bool resumesFromRest;
  final FollowRestBoundary? followingRest;

  const FollowMatch({
    required this.onsetIndex,
    required this.scoreTime,
    required this.isInitialMatch,
    required this.resumesFromRest,
    this.followingRest,
  });
}

/// 连续错音后的重新对齐请求。
class FollowRealignmentRequest {
  final int expectedOnsetIndex;
  final double scoreTime;

  const FollowRealignmentRequest({
    required this.expectedOnsetIndex,
    required this.scoreTime,
  });
}

typedef SpeedChangeCallback = void Function(double speedFactor);
typedef StateChangeCallback = void Function(FollowModeState state);
typedef FollowMatchCallback = void Function(FollowMatch match);
typedef RealignmentRequestCallback =
    void Function(FollowRealignmentRequest request);
typedef FollowRuntimeErrorCallback =
    void Function(Object error, StackTrace? stackTrace);

/// 将演奏者输入与钢琴谱面起拍匹配的状态机。
///
/// 第一个正确起拍前不做 look-ahead；这样演奏者误按后面音符时，绝不会
/// 意外启动伴奏。长休止由 [FollowRestBoundary] 明确描述，播放器据此在
/// 休止起点暂停，并在正确重入时回到下一起拍的谱面时间。
class FollowModeController {
  final Stream<OnsetEvent> _onsetStream;
  FollowModeConfig _config;

  FollowModeState _state = FollowModeState.idle;
  double _speedFactor = 1.0;
  List<_ScoreOnset> _scoreOnsets = [];
  int _expectedOnsetIndex = 0;
  int? _lastMatchedOnsetIndex;
  DateTime? _lastOnsetTimestamp;
  final Set<int> _receivedChordPitches = <int>{};
  int _unmatchedCount = 0;
  FollowRestBoundary? _pendingRest;
  StreamSubscription<OnsetEvent>? _onsetSubscription;

  SpeedChangeCallback? onSpeedChanged;
  StateChangeCallback? onStateChanged;
  FollowMatchCallback? onMatch;
  RealignmentRequestCallback? onRealignmentRequested;
  FollowRuntimeErrorCallback? onRuntimeError;

  FollowModeState get state => _state;
  double get speedFactor => _speedFactor;
  FollowModeConfig get config => _config;
  bool get isActive => _state != FollowModeState.idle;
  int get expectedOnsetIndex => _expectedOnsetIndex;
  FollowRestBoundary? get pendingRest => _pendingRest;

  FollowModeController.fromOnsetStream({
    required Stream<OnsetEvent> onsetStream,
    FollowModeConfig? config,
  }) : _onsetStream = onsetStream,
       _config = config ?? const FollowModeConfig();

  void updateConfig(FollowModeConfig config) {
    _config = config;
  }

  /// 加载乐谱音符序列，并将同一 tick 的和弦合并为一个起拍。
  void loadScore(List<MidiNote> notes) {
    final sortedNotes = List.of(notes)
      ..sort((a, b) {
        final tickCompare = a.startTick.compareTo(b.startTick);
        return tickCompare != 0
            ? tickCompare
            : a.noteNumber.compareTo(b.noteNumber);
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

  void stop({bool notifyCallbacks = true}) {
    unawaited(_onsetSubscription?.cancel());
    _onsetSubscription = null;
    _speedFactor = 1.0;
    _lastMatchedOnsetIndex = null;
    _receivedChordPitches.clear();
    _pendingRest = null;
    if (notifyCallbacks) {
      _setState(FollowModeState.idle);
      onSpeedChanged?.call(1.0);
    } else {
      _state = FollowModeState.idle;
    }
  }

  void resumeFromIndex(int noteIndex) {
    if (noteIndex < 0 || noteIndex >= _scoreOnsets.length) return;
    if (_state == FollowModeState.idle) start();
    _resetFollowPosition(noteIndex);
    _setState(FollowModeState.following);
  }

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

  void _handleOnset(OnsetEvent onset) {
    if (_state == FollowModeState.idle ||
        _expectedOnsetIndex >= _scoreOnsets.length) {
      if (_expectedOnsetIndex >= _scoreOnsets.length) stop();
      return;
    }
    // 已匹配长休止前一拍、但播放器尚未到达休止边界时，任何输入都不能
    // 被解释为重入，避免提前按下一音导致伴奏跳到休止之后。
    if (_pendingRest != null) return;
    if (_state == FollowModeState.following && _isTrailingChordNote(onset)) {
      return;
    }

    final expectedOnset = _scoreOnsets[_expectedOnsetIndex];
    if (expectedOnset.notes.any(
      (note) => _matchesExpectedNote(onset.midiNote, note),
    )) {
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

  void _onNoteMatched(OnsetEvent onset, _ScoreOnset expectedOnset) {
    final matchedIndex = _expectedOnsetIndex;
    final isInitialMatch = _lastMatchedOnsetIndex == null;
    final resumesFromRest = _state == FollowModeState.waitingForOnset;
    _unmatchedCount = 0;

    if (_lastOnsetTimestamp != null && _lastMatchedOnsetIndex != null) {
      final actualInterval =
          onset.timestamp.difference(_lastOnsetTimestamp!).inMilliseconds /
          1000.0;
      if (actualInterval > 0.01) {
        final expectedInterval =
            expectedOnset.startTime -
            _scoreOnsets[_lastMatchedOnsetIndex!].startTime;
        if (expectedInterval > 0.01) {
          _applyMeasuredSpeed(expectedInterval / actualInterval);
        }
      }
    }

    _lastOnsetTimestamp = onset.timestamp;
    _lastMatchedOnsetIndex = matchedIndex;
    _receivedChordPitches
      ..clear()
      ..addAll(
        expectedOnset.notes
            .where((note) => _matchesExpectedNote(onset.midiNote, note))
            .map((note) => note.noteNumber),
      );
    _expectedOnsetIndex++;
    final followingRest = _restBefore(_expectedOnsetIndex);
    onMatch?.call(
      FollowMatch(
        onsetIndex: matchedIndex,
        scoreTime: expectedOnset.startTime,
        isInitialMatch: isInitialMatch,
        resumesFromRest: resumesFromRest,
        followingRest: followingRest,
      ),
    );

    if (followingRest != null) {
      _pendingRest = followingRest;
    } else if (resumesFromRest) {
      _setState(FollowModeState.following);
    }
  }

  /// 由播放器在实际到达长休止边界、完成清音后调用。
  ///
  /// [rest] 必须仍是当前等待中的同一段休止；过期的异步回调会被忽略。
  void markRestBoundaryReached(FollowRestBoundary rest) {
    final pending = _pendingRest;
    if (_state == FollowModeState.idle ||
        pending == null ||
        pending.reentryOnsetIndex != rest.reentryOnsetIndex ||
        pending.restStartScoreTime != rest.restStartScoreTime) {
      return;
    }
    _pendingRest = null;
    _setState(FollowModeState.waitingForOnset);
  }

  void _onNoteUnmatched(OnsetEvent onset) {
    // 尚未开始和长休止等待都只是“继续等待正确起拍”；不能因为错音改变
    // 下次启动的速度，也不能悄悄改变谱面位置。
    if (_lastMatchedOnsetIndex == null ||
        _state != FollowModeState.following ||
        _pendingRest != null) {
      return;
    }
    _unmatchedCount++;

    if (_unmatchedCount == _config.unmatchedThreshold) {
      onRealignmentRequested?.call(
        FollowRealignmentRequest(
          expectedOnsetIndex: _expectedOnsetIndex,
          scoreTime: _scoreOnsets[_expectedOnsetIndex].startTime,
        ),
      );
    }
  }

  FollowRestBoundary? _restBefore(int reentryIndex) {
    if (reentryIndex <= 0 || reentryIndex >= _scoreOnsets.length) return null;
    final previous = _scoreOnsets[reentryIndex - 1];
    final next = _scoreOnsets[reentryIndex];
    if (next.startTime - previous.endTime < _config.restThresholdSeconds) {
      return null;
    }
    return FollowRestBoundary(
      restStartScoreTime: previous.endTime,
      resumeScoreTime: next.startTime,
      reentryOnsetIndex: reentryIndex,
    );
  }

  bool _matchesExpectedNote(int onsetMidi, MidiNote expected) {
    final diff = (onsetMidi - expected.noteNumber).abs();
    if (diff <= _config.noteMatchTolerance) return true;
    if (!_config.allowOctaveError) return false;
    return _pitchClassDistance(onsetMidi, expected.noteNumber) <=
        _config.noteMatchTolerance;
  }

  int _pitchClassDistance(int a, int b) {
    final diff = ((a % 12) - (b % 12)).abs();
    return diff > 6 ? 12 - diff : diff;
  }

  int? _findOnsetIndexAtOrAfter(double currentTimeSeconds) {
    for (var index = 0; index < _scoreOnsets.length; index++) {
      if (_scoreOnsets[index].endTime >= currentTimeSeconds) return index;
    }
    return null;
  }

  void _resetFollowPosition(int noteIndex) {
    _expectedOnsetIndex = noteIndex;
    _unmatchedCount = 0;
    _lastOnsetTimestamp = null;
    _lastMatchedOnsetIndex = null;
    _receivedChordPitches.clear();
    _pendingRest = null;
  }

  bool _isTimeInsideLongRestBefore(int noteIndex, double currentTimeSeconds) {
    final next = _scoreOnsets[noteIndex];
    if (currentTimeSeconds >= next.startTime) return false;
    final restStart = noteIndex == 0
        ? 0.0
        : _scoreOnsets[noteIndex - 1].endTime;
    return currentTimeSeconds >= restStart &&
        next.startTime - restStart >= _config.restThresholdSeconds;
  }

  bool _isTrailingChordNote(OnsetEvent onset) {
    final lastTimestamp = _lastOnsetTimestamp;
    final lastIndex = _lastMatchedOnsetIndex;
    if (lastTimestamp == null || lastIndex == null) return false;
    final elapsedMs = onset.timestamp.difference(lastTimestamp).inMilliseconds;
    if (elapsedMs < 0 || elapsedMs > _config.chordInputWindowMs) return false;
    final remainingChordPitches = _scoreOnsets[lastIndex].notes.where(
      (note) => !_receivedChordPitches.contains(note.noteNumber),
    );
    final matchedRemaining = remainingChordPitches
        .where((note) => _matchesExpectedNote(onset.midiNote, note))
        .toList(growable: false);
    if (matchedRemaining.isEmpty) return false;
    _receivedChordPitches.addAll(
      matchedRemaining.map((note) => note.noteNumber),
    );
    return true;
  }

  void _applyEmaSpeed(double rawFactor) {
    final clamped = rawFactor.clamp(
      _config.minSpeedFactor,
      _config.maxSpeedFactor,
    );
    _speedFactor =
        _config.emaSmoothingAlpha * clamped +
        (1 - _config.emaSmoothingAlpha) * _speedFactor;
    onSpeedChanged?.call(_speedFactor);
  }

  void _applyMeasuredSpeed(double rawFactor) {
    if (rawFactor < _config.minMeasuredSpeedFactor ||
        rawFactor > _config.maxMeasuredSpeedFactor) {
      return;
    }
    _applyEmaSpeed(rawFactor);
  }

  void _setState(FollowModeState newState) {
    if (_state == newState) return;
    _state = newState;
    onStateChanged?.call(newState);
  }

  void dispose() => stop(notifyCallbacks: false);
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
