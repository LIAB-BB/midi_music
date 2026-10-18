import 'dart:math' as math;

import 'config.dart';
import 'score.dart';

/// 一次 Note On 之后的跟随结果。
///
/// [scoreTime] 是当前对齐到的谱面秒数；上层播放器应把伴奏定位到这里，
/// 并按 [speed] 调整速度。[confidence] 低于 0.5 时不要据此启动伴奏。
class FollowUpdate {
  const FollowUpdate({
    required this.inputPitch,
    required this.inputTime,
    required this.matched,
    required this.positionOnsetIndex,
    required this.nextOnsetIndex,
    required this.scoreTime,
    required this.nextScoreTime,
    required this.speed,
    required this.confidence,
    required this.timingError,
    required this.reacquired,
    required this.hypothesisCount,
  });

  final int inputPitch;
  final double inputTime;

  /// 本次输入是否被最佳假设解释为一次谱面起拍（含和弦尾音）。
  final bool matched;

  /// 当前最佳假设最后匹配到的 onset；未锁定前可能只是初始猜测。
  final int positionOnsetIndex;

  /// 下一期待 onset；等于 [Score.length] 表示已到曲末。
  final int nextOnsetIndex;

  /// 当前对齐的谱面时间（秒）。
  final double scoreTime;

  /// 下一期待 onset 的谱面时间（秒）。
  final double nextScoreTime;

  /// 建议播放速度（倍速），已限制在配置范围内。
  final double speed;

  /// 0..1。连续正确匹配越多、时间误差越小，置信度越高。
  final double confidence;

  /// 本次输入相对预测时间的误差（秒，正数表示晚于预测）。
  final double timingError;

  /// 是否通过初始捕获或停顿后重锚恢复位置。
  final bool reacquired;

  final int hypothesisCount;

  @override
  String toString() =>
      'FollowUpdate(${matched ? 'match' : 'miss'} '
      'pos:$positionOnsetIndex next:$nextOnsetIndex '
      't:${scoreTime.toStringAsFixed(3)}s '
      'speed:${speed.toStringAsFixed(3)} '
      'conf:${confidence.toStringAsFixed(2)} '
      'err:${timingError.toStringAsFixed(3)}s '
      'hyp:$hypothesisCount)';
}

/// 在线多假设乐谱跟随器。
///
/// 与旧实现的区别：
/// - 不要求输入严格等于“当前期待的那一个 onset”；在局部窗口内做代价匹配，
///   允许漏音、跳音、错音与和弦尾音；
/// - 每个假设独立维护位置和速度，错误输入只消耗 miss，不会把位置推走；
/// - 连续 miss 后按当前输入重新捕获；
/// - 速度由相邻正确匹配的墙钟/谱面时间比估计，并对跳音降权。
class AdaptiveScoreFollower {
  AdaptiveScoreFollower({
    required this.score,
    this.config = const FollowConfig(),
  }) : assert(!score.isEmpty, '谱面不能为空'),
       _outputSpeed = config.initialSpeed;

  final Score score;
  final FollowConfig config;

  final List<_Hypothesis> _hypotheses = [];
  bool _started = false;
  int _lastKnownIndex = -1;
  double _lastInputTime = -1;
  double? _lastMatchWallTime;
  double? _lastMatchScoreTime;
  double _outputSpeed;
  FollowUpdate? _lastUpdate;

  FollowUpdate? get lastUpdate => _lastUpdate;

  int get hypothesisCount => _hypotheses.length;

  /// 当前是否已有足够证据启动伴奏。
  bool get isLocked =>
      _hypotheses.isNotEmpty && _bestHypothesis().confidence >= 0.5;

  /// 丢弃全部假设，回到未开始状态。谱面不变。
  void reset() {
    _hypotheses.clear();
    _started = false;
    _lastKnownIndex = -1;
    _lastInputTime = -1;
    _lastMatchWallTime = null;
    _lastMatchScoreTime = null;
    _outputSpeed = config.initialSpeed;
    _lastUpdate = null;
  }

  /// 消费一次 MIDI Note On。
  ///
  /// [time] 必须是单调递增的演奏时钟（秒），建议使用 `Stopwatch` 而非
  /// `DateTime.now()`，避免系统时间调整导致抖动。
  FollowUpdate onNoteOn(int pitch, double time) {
    final observedTime = time < _lastInputTime ? _lastInputTime : time;
    _lastInputTime = observedTime;

    if (_hypotheses.isEmpty) {
      final seeded = _seed(pitch, observedTime, reacquire: _started);
      if (seeded != null) return seeded;
      return _neutralUpdate(pitch, observedTime);
    }

    var matchedAny = false;
    var reanchored = false;

    // 先快照：_apply 会修改假设，避免边遍历边改。
    final snapshot = List<_Hypothesis>.of(_hypotheses);
    for (final hypothesis in snapshot) {
      hypothesis.matchedThisInput = false;
      final candidate = _bestCandidate(hypothesis, pitch, observedTime);
      if (candidate == null) {
        _recordMiss(hypothesis);
        _maybeFork(hypothesis, pitch, observedTime);
        continue;
      }
      _apply(hypothesis, candidate, observedTime);
      matchedAny = true;
      if (candidate.reanchor) reanchored = true;
    }

    _hypotheses.removeWhere(
      (hypothesis) => hypothesis.misses > config.maxMisses,
    );

    if (!matchedAny) {
      if (_hypotheses.isEmpty) {
        final seeded = _seed(pitch, observedTime, reacquire: true);
        if (seeded != null) return seeded;
      } else {
        _prune();
      }
      return _buildUpdate(pitch, observedTime, reacquired: false);
    }

    _prune();
    final best = _bestHypothesis();
    _lastKnownIndex = best.lastIndex;
    return _buildUpdate(pitch, observedTime, reacquired: reanchored);
  }

  _Candidate? _bestCandidate(_Hypothesis hypothesis, int pitch, double time) {
    if (hypothesis.nextIndex >= score.length) return null;

    final firstIndex = math.max(0, hypothesis.nextIndex - 1);
    final lastIndex = math.min(
      score.length - 1,
      hypothesis.nextIndex + config.lookahead,
    );

    _Candidate? best;
    for (var index = firstIndex; index <= lastIndex; index++) {
      final onset = score.onsets[index];
      if (!onset.containsPitch(pitch)) continue;

      final forward = index - hypothesis.nextIndex;
      // 向后只允许一个 onset（和弦尾音）；更大的反复交给重新捕获。
      if (forward > 2) continue;
      if (forward < 0 && time - hypothesis.lastWallTime > 0.25) continue;

      final predicted =
          hypothesis.anchorWall +
          (onset.time - hypothesis.anchorScore) / hypothesis.speed;
      final error = time - predicted;
      final gate = _gateFor(hypothesis, index);
      final normalized = error / gate;

      // 长时间停顿后，输入正好命中期待 onset：允许重锚，避免把停顿
      // 误当成极慢速度，也避免连续 miss 丢掉整段。
      final longGap = time - hypothesis.lastWallTime > 0.6;
      if (forward == 0 && longGap && error.abs() > gate) {
        final candidate = _Candidate(
          index: index,
          cost: config.reacquireCost,
          error: error,
          gate: gate,
          reanchor: true,
        );
        if (best == null || candidate.cost < best.cost) best = candidate;
        continue;
      }

      if (forward > 0 && error.abs() > gate * 0.55) continue;

      var cost = normalized * normalized;
      if (forward > 0) {
        cost += 0.35 + config.skipPenalty * forward;
      } else if (forward < 0) {
        cost += config.backwardPenalty;
      }
      if (cost > config.maxMatchCost) continue;

      final candidate = _Candidate(
        index: index,
        cost: cost,
        error: error,
        gate: gate,
        reanchor: false,
      );
      if (best == null || candidate.cost < best.cost) best = candidate;
    }
    return best;
  }

  void _apply(_Hypothesis hypothesis, _Candidate candidate, double time) {
    final index = candidate.index;
    final onset = score.onsets[index];
    final forward = index - hypothesis.lastIndex;
    // 同一 onset 的后续 Note On（和弦尾音/重复触发）只确认位置，不推进
    // 锚点；否则和弦越宽，下一次速度估计就越偏快。
    final chordTrailing = forward <= 0 && !candidate.reanchor;

    if (forward > 0 && !candidate.reanchor) {
      // 用上一个和弦的第一个音作为锚点，而不是最后一个尾音；否则和弦
      // 越宽，下一次速度估计就越偏快。
      final scoreDelta = onset.time - hypothesis.anchorScore;
      final wallDelta = time - hypothesis.anchorWall;
      if (scoreDelta > 0.02 && wallDelta > 0.005) {
        final rawSpeed = (scoreDelta / wallDelta)
            .clamp(config.minSpeed, config.maxSpeed)
            .toDouble();
        // 前两次匹配允许较大的速度范围，之后收紧，避免一次长停顿
        // 把整条时间映射拉坏。
        final minRatio = hypothesis.matches <= 2 ? 0.15 : 0.5;
        final maxRatio = hypothesis.matches <= 2 ? 6.0 : 2.0;
        final plausible =
            rawSpeed >= hypothesis.speed * minRatio &&
            rawSpeed <= hypothesis.speed * maxRatio;
        if (plausible) {
          final alpha = forward == 1
              ? config.tempoSmoothing
              : config.tempoSmoothing * 0.5;
          hypothesis.speed = hypothesis.speed * (1 - alpha) + rawSpeed * alpha;
        }
      }
    }

    hypothesis
      ..matchedThisInput = true
      ..lastError = candidate.error
      ..lastWallTime = time
      ..misses = 0;

    if (chordTrailing) {
      // 和弦尾音只确认当前位置：不动锚点、不推进位置、不增加匹配数。
      hypothesis.confidence = math.min(1.0, hypothesis.confidence * 1.02);
      return;
    }

    hypothesis
      ..anchorScore = onset.time
      ..anchorWall = time
      ..lastIndex = index
      ..nextIndex = index + 1
      ..matches += 1
      ..errorEma = hypothesis.errorEma * 0.7 + candidate.error.abs() * 0.3;

    if (candidate.reanchor) {
      hypothesis.confidence = math.max(0.2, hypothesis.confidence * 0.5);
    } else {
      final matchConfidence =
          (hypothesis.matches / config.confidenceTargetMatches)
              .clamp(0.0, 1.0)
              .toDouble();
      final errorConfidence = math.exp(
        -hypothesis.errorEma / math.max(0.05, candidate.gate),
      );
      hypothesis.confidence = (matchConfidence * errorConfidence)
          .clamp(0.05, 1.0)
          .toDouble();
    }
  }

  void _recordMiss(_Hypothesis hypothesis) {
    hypothesis
      ..matchedThisInput = false
      ..misses += 1
      ..confidence = hypothesis.confidence * 0.7;
  }

  /// 当前假设漏掉一个音时，向前开一个低置信度分支。
  ///
  /// 这比“连续 miss 后整段重新捕获”快：跳音/长休止后只要后续音能接上，
  /// 分支会在 2–3 个音内超过旧假设，不需要等旧假设完全死掉。
  void _maybeFork(_Hypothesis source, int pitch, double time) {
    if (source.isFork) return;
    final start = source.nextIndex + 1;
    final end = math.min(
      score.length - 1,
      source.nextIndex + config.recoveryWindow,
    );
    if (start > end) return;

    final existing = <int>{
      for (final hypothesis in _hypotheses) hypothesis.lastIndex,
    };
    final options = <int>[];
    for (var index = start; index <= end; index++) {
      if (!score.onsets[index].containsPitch(pitch)) continue;
      if (existing.contains(index)) continue;
      options.add(index);
    }
    options.sort((a, b) {
      final priorCompare = _seedPrior(
        b,
        reacquire: true,
        time: time,
      ).compareTo(_seedPrior(a, reacquire: true, time: time));
      return priorCompare != 0 ? priorCompare : a.compareTo(b);
    });

    for (final index in options.take(6)) {
      existing.add(index);
      _hypotheses.add(
        _Hypothesis(
          nextIndex: index + 1,
          lastIndex: index,
          anchorScore: score.onsets[index].time,
          anchorWall: time,
          speed: source.speed,
          matches: 1,
          confidence: config.recoveryConfidence,
          lastWallTime: time,
          matchedThisInput: true,
          prior: _seedPrior(index, reacquire: true, time: time),
          isFork: true,
        ),
      );
    }
  }

  double _gateFor(_Hypothesis hypothesis, int index) {
    if (hypothesis.matches <= 1) return 0.6;
    final interval = score.localInterval(index);
    final adaptive = (0.5 * interval + 0.05).clamp(0.06, 0.32).toDouble();
    return math.max(config.timingToleranceSeconds, adaptive);
  }

  FollowUpdate? _seed(int pitch, double time, {required bool reacquire}) {
    if (reacquire && _lastKnownIndex >= score.length - 1) return null;

    List<int> collect({required bool restrict}) {
      final start = restrict ? config.preferredStartIndex : 0;
      final end = restrict
          ? math.min(score.length, start + config.startWindow)
          : score.length;
      final result = <int>[];
      for (var index = start; index < end; index++) {
        if (score.onsets[index].containsPitch(pitch)) result.add(index);
      }
      return result;
    }

    var candidates = collect(restrict: !reacquire);
    if (candidates.isEmpty && !reacquire) {
      // 曲首窗口内没有这个音高：可能是从中间起奏，回退全曲搜索。
      candidates = collect(restrict: false);
    }
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final priorCompare = _seedPrior(
        b,
        reacquire: reacquire,
        time: time,
      ).compareTo(_seedPrior(a, reacquire: reacquire, time: time));
      return priorCompare != 0 ? priorCompare : a.compareTo(b);
    });

    _hypotheses.clear();
    final seedSpeed = reacquire ? _outputSpeed : config.initialSpeed;
    for (final index in candidates.take(config.maxHypotheses)) {
      final onset = score.onsets[index];
      _hypotheses.add(
        _Hypothesis(
          nextIndex: index + 1,
          lastIndex: index,
          anchorScore: onset.time,
          anchorWall: time,
          speed: seedSpeed,
          matches: 1,
          confidence: 0.15,
          lastWallTime: time,
          matchedThisInput: true,
          prior: _seedPrior(index, reacquire: reacquire, time: time),
          isFork: false,
        ),
      );
    }
    _started = true;
    _lastKnownIndex = candidates.first;

    return _buildUpdate(pitch, time, reacquired: true);
  }

  double _seedPrior(
    int index, {
    required bool reacquire,
    required double time,
  }) {
    if (!reacquire) {
      return -config.startBias * (index - config.preferredStartIndex).abs();
    }

    final lastWall = _lastMatchWallTime;
    final lastScore = _lastMatchScoreTime;
    if (lastWall == null || lastScore == null) {
      final anchor = math.max(0, _lastKnownIndex + 1);
      return -0.12 * (index - anchor).abs();
    }

    // 让墙钟推进按当前速度折算成谱面时间，再按时间距离排序。这样
    // 跳音/长休止后，几百毫秒到几十秒的间隔都会落到正确的段落附近，
    // 而不是只按 onset 序号“就近”猜。
    final predictedScore = lastScore + (time - lastWall) * _outputSpeed;
    final timeError = score.onsets[index].time - predictedScore;
    var prior = -0.6 * timeError.abs();
    if (index < _lastKnownIndex) prior -= 0.1;
    return prior;
  }

  void _prune() {
    final hasPrimary = _hypotheses.any((hypothesis) => !hypothesis.isFork);
    if (hasPrimary) {
      for (final hypothesis in _hypotheses) {
        if (!hypothesis.isFork) continue;
        hypothesis.confidence = math.min(
          hypothesis.confidence,
          config.forkConfidenceCap,
        );
      }
    }

    _hypotheses.sort((a, b) {
      final confidenceCompare = b.confidence.compareTo(a.confidence);
      if (confidenceCompare != 0) return confidenceCompare;
      final matchCompare = b.matches.compareTo(a.matches);
      if (matchCompare != 0) return matchCompare;
      final priorCompare = b.prior.compareTo(a.prior);
      if (priorCompare != 0) return priorCompare;
      // 完全同分时优先更早的位置：默认从曲首开始，反复音型不应把
      // 位置带到后面的同一段落。
      return a.lastIndex.compareTo(b.lastIndex);
    });

    final seen = <String>{};
    final deduped = <_Hypothesis>[];
    for (final hypothesis in _hypotheses) {
      final key = '${hypothesis.nextIndex}:${(hypothesis.speed * 20).round()}';
      if (!seen.add(key)) continue;
      deduped.add(hypothesis);
      if (deduped.length >= config.maxHypotheses) break;
    }
    _hypotheses
      ..clear()
      ..addAll(deduped);
  }

  _Hypothesis _bestHypothesis() {
    var best = _hypotheses.first;
    for (final hypothesis in _hypotheses.skip(1)) {
      if (hypothesis.confidence > best.confidence) {
        best = hypothesis;
      } else if (hypothesis.confidence == best.confidence) {
        if (hypothesis.matches > best.matches) {
          best = hypothesis;
        } else if (hypothesis.matches == best.matches &&
            hypothesis.prior > best.prior) {
          best = hypothesis;
        }
      }
    }
    return best;
  }

  FollowUpdate _buildUpdate(
    int pitch,
    double time, {
    required bool reacquired,
  }) {
    if (_hypotheses.isEmpty) return _neutralUpdate(pitch, time);

    final best = _bestHypothesis();
    final rawSpeed = best.speed
        .clamp(config.minSpeed, config.maxSpeed)
        .toDouble();

    // 速度已经在假设内做过 EMA，这里直接输出；播放侧如需限速，可在
    // setSpeed 前做 slew-rate。
    _outputSpeed = rawSpeed;

    if (best.matchedThisInput) {
      _lastMatchWallTime = best.anchorWall;
      _lastMatchScoreTime = best.anchorScore;
    }

    final positionIndex = best.lastIndex;
    final scoreTime = score.onsets[positionIndex].time;
    final nextIndex = best.nextIndex;
    final nextScoreTime = nextIndex < score.length
        ? score.onsets[nextIndex].time
        : score.duration;

    final update = FollowUpdate(
      inputPitch: pitch,
      inputTime: time,
      matched: best.matchedThisInput,
      positionOnsetIndex: positionIndex,
      nextOnsetIndex: nextIndex,
      scoreTime: scoreTime,
      nextScoreTime: nextScoreTime,
      speed: _outputSpeed,
      confidence: best.confidence,
      timingError: best.matchedThisInput ? best.lastError : 0,
      reacquired: reacquired,
      hypothesisCount: _hypotheses.length,
    );
    _lastUpdate = update;
    return update;
  }

  FollowUpdate _neutralUpdate(int pitch, double time) {
    final last = _lastUpdate;
    final update = FollowUpdate(
      inputPitch: pitch,
      inputTime: time,
      matched: false,
      positionOnsetIndex: last?.positionOnsetIndex ?? 0,
      nextOnsetIndex: last?.nextOnsetIndex ?? 0,
      scoreTime: last?.scoreTime ?? 0,
      nextScoreTime: last?.nextScoreTime ?? 0,
      speed: last?.speed ?? _outputSpeed,
      confidence: 0,
      timingError: 0,
      reacquired: false,
      hypothesisCount: _hypotheses.length,
    );
    _lastUpdate = update;
    return update;
  }
}

class _Hypothesis {
  _Hypothesis({
    required this.nextIndex,
    required this.lastIndex,
    required this.anchorScore,
    required this.anchorWall,
    required this.speed,
    required this.matches,
    required this.confidence,
    required this.lastWallTime,
    required this.matchedThisInput,
    required this.prior,
    required this.isFork,
  });

  int nextIndex;
  int lastIndex;
  double anchorScore;
  double anchorWall;
  double speed;
  int matches;
  int misses = 0;
  double confidence;
  double errorEma = 0;
  double lastWallTime;
  bool matchedThisInput;
  double lastError = 0;

  /// 初始捕获时的先验（越大越可信）。只在置信度与匹配数相同时用于
  /// 破除歧义，避免反复音型把位置带到后面的同一段落。
  final double prior;

  /// 由漏音分支创建的假设；分支不再继续分支，避免指数增长。
  final bool isFork;
}

class _Candidate {
  const _Candidate({
    required this.index,
    required this.cost,
    required this.error,
    required this.gate,
    required this.reanchor,
  });

  final int index;
  final double cost;
  final double error;
  final double gate;
  final bool reanchor;
}
