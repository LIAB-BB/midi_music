import '../../models/midi_track.dart';

/// Tempo Map：负责 tick 到实际时间（秒）的映射
///
/// MIDI 文件中时间以 tick 为单位，需要结合 PPQ（ticksPerBeat）
/// 和 tempo（microsecondsPerBeat）来转换为实际秒数。
/// tempo 可能在曲中变化，所以需要分段计算。
class TempoMap {
  final int ticksPerBeat;
  final List<TempoChange> _tempoChanges;

  /// 预计算的每个 tempo 段的起始时间（秒）
  final List<double> _segmentStartTimes = [];

  TempoMap({
    required this.ticksPerBeat,
    required List<TempoChange> tempoChanges,
  }) : _tempoChanges = _normalizeTempoChanges(tempoChanges) {
    if (ticksPerBeat <= 0) {
      throw ArgumentError.value(
        ticksPerBeat,
        'ticksPerBeat',
        'must be greater than zero',
      );
    }

    // MIDI 在第一个 Set Tempo 之前使用默认 120 BPM。
    if (_tempoChanges.isEmpty || _tempoChanges.first.tick > 0) {
      _tempoChanges.add(
        TempoChange(
          tick: 0,
          microsecondsPerBeat: 500000, // 120 BPM
        ),
      );
      _tempoChanges.sort((a, b) => a.tick.compareTo(b.tick));
    }
    _buildSegmentTimes();
  }

  static List<TempoChange> _normalizeTempoChanges(
    List<TempoChange> tempoChanges,
  ) {
    final byTick = <int, TempoChange>{};
    for (final change in tempoChanges) {
      if (change.tick < 0) {
        throw ArgumentError.value(change.tick, 'tempo tick', 'must be >= 0');
      }
      if (change.microsecondsPerBeat <= 0) {
        throw ArgumentError.value(
          change.microsecondsPerBeat,
          'microsecondsPerBeat',
          'must be greater than zero',
        );
      }
      // 同一 tick 出现多个 tempo 时，采用文件中最后出现的值。
      byTick[change.tick] = TempoChange(
        tick: change.tick,
        microsecondsPerBeat: change.microsecondsPerBeat,
      );
    }

    return byTick.values.toList()..sort((a, b) => a.tick.compareTo(b.tick));
  }

  /// 预计算每个 tempo 段的起始时间
  void _buildSegmentTimes() {
    _segmentStartTimes.clear();
    double currentTime = 0.0;

    for (int i = 0; i < _tempoChanges.length; i++) {
      if (i == 0) {
        _segmentStartTimes.add(0.0);
        _tempoChanges[i].time = 0.0;
        continue;
      }

      final prevTempo = _tempoChanges[i - 1];
      final tickDelta = _tempoChanges[i].tick - prevTempo.tick;
      final secondsPerTick =
          prevTempo.microsecondsPerBeat / (ticksPerBeat * 1000000.0);
      currentTime += tickDelta * secondsPerTick;

      _segmentStartTimes.add(currentTime);
      _tempoChanges[i].time = currentTime;
    }
  }

  /// 将 tick 转换为秒
  double tickToSeconds(int tick) {
    // 二分查找所在的 tempo 段
    int segIndex = _findSegmentIndex(tick);
    final tempo = _tempoChanges[segIndex];
    final segStartTime = _segmentStartTimes[segIndex];
    final tickDelta = tick - tempo.tick;
    final secondsPerTick =
        tempo.microsecondsPerBeat / (ticksPerBeat * 1000000.0);
    return segStartTime + tickDelta * secondsPerTick;
  }

  /// 将秒转换为 tick
  int secondsToTick(double seconds) {
    // 找到对应的 tempo 段
    int segIndex = 0;
    for (int i = _segmentStartTimes.length - 1; i >= 0; i--) {
      if (seconds >= _segmentStartTimes[i]) {
        segIndex = i;
        break;
      }
    }
    final tempo = _tempoChanges[segIndex];
    final segStartTime = _segmentStartTimes[segIndex];
    final secondsPerTick =
        tempo.microsecondsPerBeat / (ticksPerBeat * 1000000.0);
    final tickDelta = ((seconds - segStartTime) / secondsPerTick).round();
    return tempo.tick + tickDelta;
  }

  /// 获取指定 tick 处的 BPM
  double getBpmAtTick(int tick) {
    final segIndex = _findSegmentIndex(tick);
    return _tempoChanges[segIndex].bpm;
  }

  /// 获取指定 tick 处的 microsecondsPerBeat
  int getMicrosecondsPerBeatAtTick(int tick) {
    final segIndex = _findSegmentIndex(tick);
    return _tempoChanges[segIndex].microsecondsPerBeat;
  }

  /// 所有 tempo 变化点
  List<TempoChange> get tempoChanges => List.unmodifiable(_tempoChanges);

  /// 二分查找 tick 所在的 tempo 段索引
  int _findSegmentIndex(int tick) {
    int low = 0;
    int high = _tempoChanges.length - 1;

    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_tempoChanges[mid].tick <= tick) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  /// 批量将 tick 转换为秒（性能优化：顺序遍历避免重复二分查找）
  void applyTimesToEvents(List<TimelineEvent> events) {
    int segIndex = 0;
    for (final event in events) {
      // 向前推进 tempo 段
      while (segIndex < _tempoChanges.length - 1 &&
          _tempoChanges[segIndex + 1].tick <= event.tick) {
        segIndex++;
      }
      final tempo = _tempoChanges[segIndex];
      final segStartTime = _segmentStartTimes[segIndex];
      final tickDelta = event.tick - tempo.tick;
      final secondsPerTick =
          tempo.microsecondsPerBeat / (ticksPerBeat * 1000000.0);
      event.time = segStartTime + tickDelta * secondsPerTick;
    }
  }

  /// 批量为音符设置绝对时间
  void applyTimesToNotes(List<MidiNote> notes) {
    int segIndex = 0;
    for (final note in notes) {
      // startTime
      while (segIndex < _tempoChanges.length - 1 &&
          _tempoChanges[segIndex + 1].tick <= note.startTick) {
        segIndex++;
      }
      note.startTime = _tickToSecondsAtSegment(note.startTick, segIndex);
      // endTime（可能跨 tempo 段）
      note.endTime = tickToSeconds(note.endTick);
    }
  }

  double _tickToSecondsAtSegment(int tick, int segIndex) {
    final tempo = _tempoChanges[segIndex];
    final segStartTime = _segmentStartTimes[segIndex];
    final tickDelta = tick - tempo.tick;
    final secondsPerTick =
        tempo.microsecondsPerBeat / (ticksPerBeat * 1000000.0);
    return segStartTime + tickDelta * secondsPerTick;
  }
}
