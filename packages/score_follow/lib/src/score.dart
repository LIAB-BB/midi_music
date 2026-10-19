import 'dart:math' as math;

/// 一个已按参考速度换算成秒的谱面音符。
///
/// [start] / [end] 是参考演奏（通常为 MIDI 原速）下的秒数，不是当前实际
/// 演奏时间。实时位置由 [AdaptiveScoreFollower] 估计。
class ScoreNote {
  const ScoreNote({
    required this.pitch,
    required this.start,
    required this.end,
    this.velocity = 100,
    this.startTick,
    this.endTick,
  }) : assert(pitch >= 0 && pitch <= 127, 'pitch 必须在 0..127'),
       assert(start >= 0, 'start 不能为负'),
       assert(end >= start, 'end 不能早于 start');

  final int pitch;
  final double start;
  final double end;
  final int velocity;

  /// MIDI tick 仅用于调试/回溯；算法只使用秒。
  final int? startTick;
  final int? endTick;
}

/// 同一时刻起拍的音符集合（单音或和弦）。
///
/// 跟随器以 onset 为最小匹配单位：和弦的多个 Note On 共享一个 onset，
/// 尾音不会重复推进位置。
class ScoreOnset {
  ScoreOnset._({
    required this.index,
    required this.time,
    required List<ScoreNote> notes,
  }) : notes = List<ScoreNote>.unmodifiable(notes),
       pitches = Set<int>.unmodifiable(notes.map((note) => note.pitch)),
       endTime = notes.fold<double>(0, (end, note) => math.max(end, note.end));

  final int index;
  final double time;
  final List<ScoreNote> notes;
  final Set<int> pitches;
  final double endTime;

  bool containsPitch(int pitch) => pitches.contains(pitch);

  @override
  String toString() =>
      'ScoreOnset(#$index, t=${time.toStringAsFixed(3)}s, '
      'pitches=$pitches)';
}

/// 只包含跟随所需信息的参考谱面。
class Score {
  Score._({
    required this.title,
    required List<ScoreOnset> onsets,
    required this.duration,
  }) : onsets = List<ScoreOnset>.unmodifiable(onsets);

  /// 从任意音符列表构建 onset 序列。
  ///
  /// 同一 tick / 同一秒起拍的音符会合并；时间容差取 1 微秒，避免浮点
  /// 误差把同一和弦拆成两个 onset。
  factory Score.fromNotes(Iterable<ScoreNote> notes, {String title = ''}) {
    final sorted = notes.toList(growable: false)
      ..sort((a, b) {
        final timeCompare = a.start.compareTo(b.start);
        if (timeCompare != 0) return timeCompare;
        return a.pitch.compareTo(b.pitch);
      });

    final groups = <List<ScoreNote>>[];
    for (final note in sorted) {
      if (groups.isEmpty) {
        groups.add(<ScoreNote>[note]);
        continue;
      }
      final groupStart = groups.last.first.start;
      if ((note.start - groupStart).abs() <= 0.000001) {
        groups.last.add(note);
      } else {
        groups.add(<ScoreNote>[note]);
      }
    }

    final onsets = <ScoreOnset>[];
    for (var index = 0; index < groups.length; index++) {
      onsets.add(
        ScoreOnset._(
          index: index,
          time: groups[index].first.start,
          notes: groups[index],
        ),
      );
    }

    final duration = sorted.isEmpty
        ? 0.0
        : sorted.fold<double>(0, (end, note) => math.max(end, note.end));
    return Score._(title: title, onsets: onsets, duration: duration);
  }

  final String title;
  final List<ScoreOnset> onsets;

  /// 参考速度下最后一个音符的结束时间（秒）。
  final double duration;

  int get length => onsets.length;

  bool get isEmpty => onsets.isEmpty;

  ScoreOnset? onsetAt(int index) {
    if (index < 0 || index >= onsets.length) return null;
    return onsets[index];
  }

  /// [index] 之后到下一个 onset 的参考间隔；用于自适应时间门限。
  double intervalAfter(int index) {
    if (index < 0 || index + 1 >= onsets.length) return 0.5;
    return onsets[index + 1].time - onsets[index].time;
  }

  /// [index] 附近（前 2 个到后 2 个）的典型起拍间隔。
  ///
  /// 快速跑动时时间门限必须收紧，否则相邻音会互相竞争；慢速乐句则要
  /// 放宽以容纳 rubato。用局部中位数比全局常数稳定。
  double localInterval(int index) {
    final values = <double>[];
    for (var offset = -2; offset <= 1; offset++) {
      final candidate = index + offset;
      if (candidate < 0 || candidate + 1 >= onsets.length) continue;
      final interval = onsets[candidate + 1].time - onsets[candidate].time;
      if (interval > 0) values.add(interval);
    }
    if (values.isEmpty) return 0.5;
    values.sort();
    return values[values.length ~/ 2];
  }

  @override
  String toString() =>
      'Score("$title", onsets:$length, '
      'duration:${duration.toStringAsFixed(2)}s)';
}
