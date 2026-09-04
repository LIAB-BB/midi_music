import '../../models/score_session.dart';

/// 面向谱面交互的最小播放端口。
///
/// 由播放器适配器实现，使协调器不依赖完整的 MIDI 播放控制器接口。
abstract interface class ScorePlaybackPort {
  ScoreSession? get scoreSession;

  int? get currentMeasureOrdinal;

  bool seekToMeasure(int ordinal);
}
