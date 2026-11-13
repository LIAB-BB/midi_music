import '../../models/score_session.dart';
import '../midi/tempo_map.dart';
import '../notation/piece_score_alignment.dart';
import 'score_playback_port.dart';

/// 把曲目包的小节对齐接到播放时间。
///
/// 不依赖具体播放器：调用方用 [seekToTime] 执行跳转，用 [ordinalAt] 读取当前位置。
class PieceMeasureFollow implements ScorePlaybackPort {
  final PieceScoreAlignment alignment;
  final bool Function(double seconds) seekToTime;
  final TempoMap _tempoMap;
  final ScoreSession _session;
  double _currentTime;

  PieceMeasureFollow({
    required this.alignment,
    required this.seekToTime,
    double currentTime = 0,
  }) : _tempoMap = TempoMap(
         ticksPerBeat: alignment.song.ticksPerBeat,
         tempoChanges: alignment.song.tempoChanges,
       ),
       _session = alignment.toSession(),
       _currentTime = currentTime;

  @override
  ScoreSession? get scoreSession => _session;

  @override
  int? get currentMeasureOrdinal => ordinalAt(_currentTime);

  void syncTime(double seconds) {
    _currentTime = seconds;
  }

  /// 把播放时间换成小节序号。超过曲尾时停在最后一小节。
  int ordinalAt(double seconds) {
    final measures = alignment.measures;
    if (measures.isEmpty) {
      throw StateError('曲目包对齐结果没有小节');
    }
    final duration = alignment.song.totalDuration;
    final safeSeconds = seconds.isFinite ? seconds.clamp(0.0, duration) : 0.0;
    var tick = _tempoMap.secondsToTick(safeSeconds);
    if (tick < 0) tick = 0;
    if (tick > measures.last.endTick) tick = measures.last.endTick;
    return alignment.measureOrdinalAtTick(tick);
  }

  double timeForMeasure(int ordinal) =>
      _tempoMap.tickToSeconds(alignment.measureStartTick(ordinal));

  @override
  bool seekToMeasure(int ordinal) {
    if (!_session.isMeasureInteractive(ordinal)) return false;
    final seconds = timeForMeasure(ordinal);
    if (!seekToTime(seconds)) return false;
    _currentTime = seconds;
    return true;
  }
}
