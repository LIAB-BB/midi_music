/// 把跟随器的速度估计与播放器的实际谱面相位结合，做一个小幅度的
/// 比例修正。
///
/// 约定：`phaseErrorSeconds = 播放器当前谱面时间 - 跟随器估计的谱面时间`。
/// 正数表示伴奏已经跑到演奏者前面，需要稍微减速；负数则加速。
///
/// 这不是完整的 PLL，只是一个有死区、限幅、最大 ±4% 的软修正；大偏差仍由
/// 会话的 seek 保护处理。这样普通音不会因为输入抖动而频繁 seek。
double correctFollowSpeed(
  double baseSpeed,
  double phaseErrorSeconds, {
  double deadbandSeconds = 0.05,
  double gain = 0.12,
  double maxCorrection = 0.04,
  double minSpeed = 0.25,
  double maxSpeed = 2.0,
}) {
  final base = baseSpeed.clamp(minSpeed, maxSpeed).toDouble();
  final error = phaseErrorSeconds.abs() <= deadbandSeconds
      ? 0.0
      : phaseErrorSeconds;
  final correction = (-error * gain)
      .clamp(-maxCorrection, maxCorrection)
      .toDouble();
  return (base * (1 + correction)).clamp(minSpeed, maxSpeed).toDouble();
}
