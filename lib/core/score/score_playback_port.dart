import '../../models/score_session.dart';

/// 面向谱面交互的最小播放端口。
///
/// 由未来的播放器适配器实现，避免记谱层直接依赖当前的
/// [MidiPlayerController]，也避免在本次选择性移植中改变播放控制器。
abstract interface class ScorePlaybackPort {
  ScoreSession? get scoreSession;

  int? get currentMeasureOrdinal;

  bool seekToMeasure(int ordinal);
}
