import '../models/midi_track.dart';

/// 一段“所有声部都沉默”的休止区间（秒，参考速度）。
class ScoreRest {
  const ScoreRest({required this.start, required this.end});

  final double start;
  final double end;

  double get duration => end - start;

  @override
  String toString() =>
      'ScoreRest(${start.toStringAsFixed(3)}–${end.toStringAsFixed(3)}s)';
}

/// 全局休止计划。
///
/// 只有**所有轨道**都没有音符的区间才算休止；钢琴单独休止、弦乐仍在
/// 进行时不会暂停伴奏。这避免了旧实现“每个钢琴休止都切断弦乐”的问题。
class RestPlan {
  RestPlan._(this.rests);

  final List<ScoreRest> rests;

  factory RestPlan.fromSong(
    MidiSongData song, {
    double minSilenceSeconds = 1.0,
  }) {
    if (minSilenceSeconds <= 0) {
      throw ArgumentError.value(
        minSilenceSeconds,
        'minSilenceSeconds',
        'must be greater than zero',
      );
    }

    final intervals = <_Interval>[];
    for (final track in song.tracks) {
      for (final note in track.notes) {
        if (note.endTime < note.startTime) continue;
        intervals.add(_Interval(note.startTime, note.endTime));
      }
    }
    if (intervals.isEmpty) return RestPlan._(const []);

    intervals.sort((a, b) => a.start.compareTo(b.start));
    final rests = <ScoreRest>[];
    var coveredUntil = intervals.first.end;
    for (var index = 1; index < intervals.length; index++) {
      final interval = intervals[index];
      if (interval.start - coveredUntil >= minSilenceSeconds) {
        rests.add(ScoreRest(start: coveredUntil, end: interval.start));
      }
      if (interval.end > coveredUntil) coveredUntil = interval.end;
    }
    return RestPlan._(List<ScoreRest>.unmodifiable(rests));
  }

  /// 返回起点严格晚于 [scoreTime] 的下一段全局休止。
  ScoreRest? nextAfter(double scoreTime) {
    for (final rest in rests) {
      if (rest.start > scoreTime + 0.05) return rest;
    }
    return null;
  }
}

class _Interval {
  const _Interval(this.start, this.end);

  final double start;
  final double end;
}
