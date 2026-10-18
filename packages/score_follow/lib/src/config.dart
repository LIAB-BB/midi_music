/// 跟随器的可调参数。
class FollowConfig {
  const FollowConfig({
    this.maxHypotheses = 10,
    this.lookahead = 2,
    this.minSpeed = 0.25,
    this.maxSpeed = 4.0,
    this.initialSpeed = 1.0,
    this.timingToleranceSeconds = 0.15,
    this.maxMatchCost = 6.0,
    this.maxMisses = 4,
    this.skipPenalty = 0.35,
    this.backwardPenalty = 0.6,
    this.tempoSmoothing = 0.3,
    this.preferredStartIndex = 0,
    this.startWindow = 24,
    this.startBias = 0.002,
    this.reacquireCost = 4.0,
    this.recoveryWindow = 32,
    this.recoveryConfidence = 0.08,
    this.forkConfidenceCap = 0.35,
    this.confidenceTargetMatches = 4,
  }) : assert(maxHypotheses > 0),
       assert(lookahead > 0),
       assert(minSpeed > 0 && minSpeed < 1),
       assert(maxSpeed > 1),
       assert(initialSpeed >= minSpeed && initialSpeed <= maxSpeed),
       assert(timingToleranceSeconds > 0),
       assert(maxMatchCost > 0),
       assert(maxMisses > 0),
       assert(skipPenalty >= 0),
       assert(backwardPenalty >= 0),
       assert(tempoSmoothing > 0 && tempoSmoothing <= 1),
       assert(preferredStartIndex >= 0),
       assert(startWindow > 0),
       assert(startBias >= 0),
       assert(reacquireCost > 0),
       assert(recoveryWindow > 0),
       assert(recoveryConfidence > 0 && recoveryConfidence < 0.5),
       assert(forkConfidenceCap > 0 && forkConfidenceCap < 1),
       assert(confidenceTargetMatches > 0);

  /// 同时保留的假设数。越大越能容忍歧义，但计算量线性增加。
  final int maxHypotheses;

  /// 正常跟踪时允许向后回看 1 个 onset（和弦尾音），向前最多 2 个。
  /// 更大的跳段交给重新捕获，不在单次匹配里猜。
  final int lookahead;

  /// 输出速度范围（倍速）。
  final double minSpeed;
  final double maxSpeed;
  final double initialSpeed;

  /// 时间门限下限（秒）。快速跑动时会按局部起拍间隔收紧。
  final double timingToleranceSeconds;

  /// 单次匹配允许的最大代价；超过则记为一次 miss。
  final double maxMatchCost;

  /// 连续多少次输入没有匹配后丢弃假设并重新捕获。
  final int maxMisses;

  /// 允许小跳（1–2 个 onset）时的额外代价。
  final double skipPenalty;

  /// 回看一个 onset 处理和弦尾音的代价。
  final double backwardPenalty;

  /// 速度估计 EMA 系数。
  final double tempoSmoothing;

  /// 初始捕获时偏向的 onset。默认 0 表示从曲首附近开始。
  final int preferredStartIndex;

  /// 初始捕获只在这个 onset 窗口内找候选，避免曲中反复音型把开头
  /// 误锁到几十个 onset 之后。窗口内没有任何音高匹配时才回退全曲搜索。
  final int startWindow;

  /// 初始捕获时对偏离 prefer 位置的惩罚（每 onset）。
  final double startBias;

  /// 长时间停顿后，输入正好命中期待 onset 时允许重锚的代价。
  final double reacquireCost;

  /// 漏音/跳音时向前搜索的 onset 窗口；在此范围内开低置信度分支。
  final int recoveryWindow;

  /// 分支的初始置信度。
  final double recoveryConfidence;

  /// 只要还有主假设存活，分支置信度不得超过此值，避免并行重复段落
  /// 抢走主假设的位置。主假设全部淘汰后分支才可升为最佳。
  final double forkConfidenceCap;

  /// 达到满置信度所需的连续匹配数。
  final int confidenceTargetMatches;
}
