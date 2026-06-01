// MIDI 轨道和音符数据模型
// 针对播放引擎优化：支持按时间线快速遍历事件

/// MIDI 事件类型枚举
enum MidiEventType {
  noteOn,
  noteOff,
  controlChange,
  programChange,
  pitchBend,
  tempo,
  timeSignature,
  keySignature,
  endOfTrack,
  other,
}

/// 单个 MIDI 音符（已解析为绝对时间）
class MidiNote {
  /// MIDI 音符编号 (0-127)
  final int noteNumber;

  /// 力度 (0-127)
  final int velocity;

  /// MIDI 通道 (0-15)
  final int channel;

  /// 音符开始时间（tick）
  final int startTick;

  /// 音符结束时间（tick）
  final int endTick;

  /// 音符开始时间（秒）
  double startTime;

  /// 音符结束时间（秒）
  double endTime;

  MidiNote({
    required this.noteNumber,
    required this.velocity,
    required this.channel,
    required this.startTick,
    required this.endTick,
    this.startTime = 0.0,
    this.endTime = 0.0,
  });

  /// 音符时长（tick）
  int get durationTick => endTick - startTick;

  /// 音符时长（秒）
  double get duration => endTime - startTime;

  /// 音符名称（如 C4, D#5）
  String get noteName {
    const names = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    final octave = (noteNumber ~/ 12) - 1;
    final name = names[noteNumber % 12];
    return '$name$octave';
  }

  @override
  String toString() =>
      'MidiNote($noteName, ch:$channel, vel:$velocity, '
      'tick:$startTick-$endTick, time:${startTime.toStringAsFixed(3)}s)';
}

/// 时间线上的单个事件（绝对时间，用于播放引擎遍历）
class TimelineEvent implements Comparable<TimelineEvent> {
  final MidiEventType type;

  /// 绝对 tick 位置
  final int tick;

  /// 绝对时间（秒），由 TempoMap 计算
  double time;

  /// MIDI 通道 (0-15)，meta 事件为 -1
  final int channel;

  /// 事件数据（根据 type 不同含义不同）
  /// noteOn/noteOff: data1=noteNumber, data2=velocity
  /// controlChange: data1=controller, data2=value
  /// programChange: data1=program
  /// tempo: data1=microsecondsPerBeat
  final int data1;
  final int data2;

  /// 所属轨道索引（用于多轨道共享 channel 时区分控制）
  final int trackIndex;

  TimelineEvent({
    required this.type,
    required this.tick,
    this.time = 0.0,
    this.channel = -1,
    this.trackIndex = -1,
    this.data1 = 0,
    this.data2 = 0,
  });

  @override
  int compareTo(TimelineEvent other) {
    final tickCompare = tick.compareTo(other.tick);
    if (tickCompare != 0) return tickCompare;

    final priorityCompare = _eventPriority(
      type,
    ).compareTo(_eventPriority(other.type));
    if (priorityCompare != 0) return priorityCompare;

    final trackCompare = trackIndex.compareTo(other.trackIndex);
    if (trackCompare != 0) return trackCompare;

    final channelCompare = channel.compareTo(other.channel);
    if (channelCompare != 0) return channelCompare;

    final data1Compare = data1.compareTo(other.data1);
    if (data1Compare != 0) return data1Compare;

    return data2.compareTo(other.data2);
  }

  @override
  String toString() =>
      'TimelineEvent($type, tick:$tick, time:${time.toStringAsFixed(3)}s, '
      'ch:$channel, d1:$data1, d2:$data2)';
}

int _eventPriority(MidiEventType type) {
  return switch (type) {
    MidiEventType.noteOff => 0,
    MidiEventType.controlChange => 1,
    MidiEventType.programChange => 1,
    MidiEventType.pitchBend => 1,
    MidiEventType.noteOn => 2,
    MidiEventType.tempo => 3,
    MidiEventType.timeSignature => 3,
    MidiEventType.keySignature => 3,
    MidiEventType.endOfTrack => 4,
    MidiEventType.other => 5,
  };
}

/// 单个 MIDI 轨道的信息
class MidiTrackInfo {
  /// 轨道索引
  final int index;

  /// 轨道名称（来自 TrackName meta event）
  final String name;

  /// 轨道使用的 MIDI 通道（可能多个）
  final Set<int> channels;

  /// 乐器编号（Program Change 值）
  final Map<int, int> programByChannel;

  /// 该轨道的所有音符（按 startTick 排序）
  final List<MidiNote> notes;

  /// 该轨道的所有时间线事件（按 tick 排序）
  final List<TimelineEvent> events;

  /// 是否静音
  bool isMuted;

  /// 音量 (0.0 - 1.0)
  double volume;

  MidiTrackInfo({
    required this.index,
    this.name = '',
    Set<int>? channels,
    Map<int, int>? programByChannel,
    List<MidiNote>? notes,
    List<TimelineEvent>? events,
    this.isMuted = false,
    this.volume = 1.0,
  }) : channels = channels ?? {},
       programByChannel = programByChannel ?? {},
       notes = notes ?? [],
       events = events ?? [];

  /// 轨道是否包含音符
  bool get hasNotes => notes.isNotEmpty;

  /// 音符数量
  int get noteCount => notes.length;

  /// 轨道总时长（tick）
  int get durationTick {
    if (notes.isEmpty) return 0;
    return notes.last.endTick;
  }

  /// 轨道总时长（秒）
  double get duration {
    if (notes.isEmpty) return 0.0;
    return notes.last.endTime;
  }

  @override
  String toString() =>
      'MidiTrackInfo(#$index "$name", '
      'ch:$channels, notes:${notes.length})';
}

/// 解析后的完整 MIDI 歌曲数据
class MidiSongData {
  /// 文件名
  final String fileName;

  /// MIDI 格式 (0, 1, 2)
  final int format;

  /// 每拍的 tick 数（PPQ / ticksPerBeat）
  final int ticksPerBeat;

  /// 所有轨道信息
  final List<MidiTrackInfo> tracks;

  /// 全局时间线事件（所有轨道合并，按 tick 排序）
  final List<TimelineEvent> timeline;

  /// Tempo 变化列表（tick -> microsecondsPerBeat）
  final List<TempoChange> tempoChanges;

  /// 拍号变化列表
  final List<TimeSignatureChange> timeSignatureChanges;

  /// 歌曲总时长（tick）
  final int totalTicks;

  /// 歌曲总时长（秒）
  final double totalDuration;

  MidiSongData({
    required this.fileName,
    required this.format,
    required this.ticksPerBeat,
    required this.tracks,
    required this.timeline,
    required this.tempoChanges,
    required this.timeSignatureChanges,
    required this.totalTicks,
    required this.totalDuration,
  });

  /// 包含音符的轨道
  List<MidiTrackInfo> get noteTracks =>
      tracks.where((t) => t.hasNotes).toList();

  /// 轨道数量
  int get trackCount => tracks.length;

  /// 初始 BPM
  double get initialBpm {
    if (tempoChanges.isEmpty) return 120.0;
    return 60000000.0 / tempoChanges.first.microsecondsPerBeat;
  }

  @override
  String toString() =>
      'MidiSongData("$fileName", format:$format, '
      'ppq:$ticksPerBeat, tracks:${tracks.length}, '
      'duration:${totalDuration.toStringAsFixed(1)}s)';
}

/// Tempo 变化点
class TempoChange {
  /// 发生位置（tick）
  final int tick;

  /// 发生时间（秒）
  double time;

  /// 每拍微秒数
  final int microsecondsPerBeat;

  TempoChange({
    required this.tick,
    this.time = 0.0,
    required this.microsecondsPerBeat,
  });

  /// BPM 值
  double get bpm => 60000000.0 / microsecondsPerBeat;

  @override
  String toString() => 'TempoChange(tick:$tick, ${bpm.toStringAsFixed(1)} BPM)';
}

/// 拍号变化点
class TimeSignatureChange {
  /// 发生位置（tick）
  final int tick;

  /// 发生时间（秒）
  double time;

  /// 分子（每小节拍数）
  final int numerator;

  /// 分母（拍的音符类型，4=四分音符）
  final int denominator;

  TimeSignatureChange({
    required this.tick,
    this.time = 0.0,
    required this.numerator,
    required this.denominator,
  });

  @override
  String toString() => 'TimeSignature(tick:$tick, $numerator/$denominator)';
}
