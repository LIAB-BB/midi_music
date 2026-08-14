import '../../models/midi_score_part.dart';
import '../../models/midi_track.dart';

class MidiPartAnalyzer {
  MidiScoreCatalog analyze(MidiSongData song, {required String fingerprint}) {
    final sources = <_AnalyzedSource>[];
    final sortedTracks = song.tracks.where((track) => track.hasNotes).toList()
      ..sort((left, right) => left.index.compareTo(right.index));
    if (sortedTracks.length > _maximumNoteTrackCount) {
      throw ArgumentError.value(
        sortedTracks.length,
        'noteTrackCount',
        '最多支持 $_maximumNoteTrackCount 个有音符轨道。',
      );
    }
    final totalNoteCount = sortedTracks.fold<int>(
      0,
      (total, track) => total + track.notes.length,
    );
    if (totalNoteCount > _maximumNoteCount) {
      throw ArgumentError.value(
        totalNoteCount,
        'noteCount',
        '最多支持 $_maximumNoteCount 个音符。',
      );
    }

    for (final track in sortedTracks) {
      final channels = track.notes.map((note) => note.channel).toSet().toList()
        ..sort();
      for (final channel in channels) {
        final sourceNotes = track.notes
            .where((note) => note.channel == channel)
            .toList(growable: false);
        sources.add(
          _AnalyzedSource(
            track: track,
            channel: channel,
            noteCount: sourceNotes.length,
            kind: _classify(track, channel, channels.length, sourceNotes),
            program: _effectiveProgram(track, channel, sourceNotes),
          ),
        );
      }
    }

    final pianoSources = sources
        .where((source) => source.kind == MidiPartKind.piano)
        .toList(growable: false);
    final parts = <MidiScorePart>[];
    if (pianoSources.isNotEmpty) {
      parts.add(_pianoPart(pianoSources));
    }
    for (final source in sources) {
      if (source.kind == MidiPartKind.piano) continue;
      parts.add(_sourcePart(source));
    }

    final labelledParts = _deduplicateLabels(parts);
    final piano = labelledParts.where(
      (part) => part.kind == MidiPartKind.piano,
    );
    final nonPercussion = labelledParts.where(
      (part) => part.kind != MidiPartKind.percussion,
    );
    final recommendedParts = piano.isNotEmpty
        ? piano.toList(growable: false)
        : (nonPercussion.isNotEmpty
              ? nonPercussion.toList(growable: false)
              : labelledParts);
    final origin = piano.isNotEmpty
        ? MidiSelectionOrigin.automaticPiano
        : (nonPercussion.isNotEmpty
              ? MidiSelectionOrigin.automaticEnsemble
              : MidiSelectionOrigin.percussionFallback);

    return MidiScoreCatalog(
      fingerprint: fingerprint,
      parts: labelledParts,
      recommendedPartIds: recommendedParts.map((part) => part.id).toSet(),
      recommendedOrigin: origin,
    );
  }

  MidiPartKind _classify(
    MidiTrackInfo track,
    int channel,
    int noteChannelCount,
    List<MidiNote> notes,
  ) {
    if (channel == 9) return MidiPartKind.percussion;
    if (noteChannelCount == 1) {
      final namedKind = _kindForTrackName(track.name);
      if (namedKind != null) return namedKind;
    }
    return _kindForProgram(_effectiveProgram(track, channel, notes));
  }

  int? _effectiveProgram(
    MidiTrackInfo track,
    int channel,
    List<MidiNote> notes,
  ) {
    final firstOnset = notes
        .map((note) => note.startTick)
        .reduce((left, right) => left < right ? left : right);
    final changes =
        track.events
            .where(
              (event) =>
                  event.type == MidiEventType.programChange &&
                  event.channel == channel &&
                  event.tick <= firstOnset,
            )
            .toList()
          ..sort((left, right) => left.tick.compareTo(right.tick));
    return changes.isNotEmpty
        ? changes.last.data1
        : track.programByChannel[channel];
  }

  MidiScorePart _pianoPart(List<_AnalyzedSource> sources) {
    final keys = sources.map((source) => source.key).join(',');
    return MidiScorePart(
      id: 'piano:$keys',
      label: '钢琴',
      kind: MidiPartKind.piano,
      sources: sources
          .map((source) => source.partSource)
          .toList(growable: false),
      noteCount: sources.fold(0, (total, source) => total + source.noteCount),
      staffMode: MidiStaffMode.grandStaff,
    );
  }

  MidiScorePart _sourcePart(_AnalyzedSource source) => MidiScorePart(
    id: 'source:${source.track.index}:${source.channel}',
    label: _labelForSource(source),
    kind: source.kind,
    sources: [source.partSource],
    noteCount: source.noteCount,
    staffMode: source.kind == MidiPartKind.percussion
        ? MidiStaffMode.percussionStaff
        : MidiStaffMode.singleStaff,
  );

  List<MidiScorePart> _deduplicateLabels(List<MidiScorePart> parts) {
    final seenCounts = <String, int>{};
    return parts
        .map((part) {
          final count = (seenCounts[part.label] ?? 0) + 1;
          seenCounts[part.label] = count;
          if (count == 1) return part;
          return MidiScorePart(
            id: part.id,
            label: '${part.label}（$count）',
            kind: part.kind,
            sources: part.sources,
            noteCount: part.noteCount,
            staffMode: part.staffMode,
          );
        })
        .toList(growable: false);
  }
}

class _AnalyzedSource {
  final MidiTrackInfo track;
  final int channel;
  final int noteCount;
  final MidiPartKind kind;
  final int? program;

  const _AnalyzedSource({
    required this.track,
    required this.channel,
    required this.noteCount,
    required this.kind,
    required this.program,
  });

  String get key => '${track.index}:$channel';

  MidiPartSource get partSource =>
      MidiPartSource(trackIndex: track.index, channels: {channel});
}

MidiPartKind? _kindForTrackName(String name) {
  final normalized = name.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final entry in _nameKinds.entries) {
    if (entry.key.any(normalized.contains)) return entry.value;
  }
  return null;
}

MidiPartKind _kindForProgram(int? program) {
  if (program == null || program < 0 || program > 127) {
    return MidiPartKind.other;
  }
  if (program <= 7) return MidiPartKind.piano;
  if (program >= 24 && program <= 31) return MidiPartKind.guitar;
  if (program >= 32 && program <= 39) return MidiPartKind.bass;
  if (program >= 40 && program <= 51) return MidiPartKind.strings;
  if (program >= 52 && program <= 54) return MidiPartKind.voice;
  if (program >= 56 && program <= 63) return MidiPartKind.brass;
  if (program >= 64 && program <= 79) return MidiPartKind.woodwind;
  if (program >= 80 && program <= 103) return MidiPartKind.synth;
  return MidiPartKind.other;
}

const Map<List<String>, MidiPartKind> _nameKinds = {
  [
    'piano',
    'keyboard',
    'upper',
    'lower',
    'right hand',
    'left hand',
    '钢琴',
    '右手',
    '左手',
  ]: MidiPartKind.piano,
  ['violin', 'viola', 'cello', 'string', '小提琴', '中提琴', '大提琴', '弦乐']:
      MidiPartKind.strings,
  [
    'flute',
    'oboe',
    'clarinet',
    'bassoon',
    'sax',
    '长笛',
    '双簧管',
    '单簧管',
    '巴松',
    '萨克斯',
  ]: MidiPartKind.woodwind,
  ['trumpet', 'trombone', 'horn', 'tuba', '小号', '长号', '圆号', '大号']:
      MidiPartKind.brass,
  ['guitar', '吉他']: MidiPartKind.guitar,
  ['bass', '贝斯']: MidiPartKind.bass,
  ['drum', 'percussion', '鼓', '打击']: MidiPartKind.percussion,
  ['voice', 'vocal', 'choir', '人声', '合唱']: MidiPartKind.voice,
  ['synth', 'pad', 'lead', '合成']: MidiPartKind.synth,
};

const _maximumNoteTrackCount = 64;
const _maximumNoteCount = 500000;

String _labelForSource(_AnalyzedSource source) {
  final name = source.track.name.trim();
  if (name.isNotEmpty && _kindForTrackName(name) == source.kind) return name;
  if (source.kind == MidiPartKind.percussion) return _labelForKind(source.kind);
  final programLabel = _labelForProgram(source.program);
  return programLabel ?? _labelForKind(source.kind);
}

String? _labelForProgram(int? program) {
  if (program == null || program < 0 || program >= _gmProgramNames.length) {
    return null;
  }
  return _gmProgramNames[program];
}

const _gmProgramNames = [
  '大钢琴',
  '明亮钢琴',
  '电钢琴',
  '酒吧钢琴',
  '电钢琴1',
  '电钢琴2',
  '大键琴',
  '击弦古钢琴',
  '钢片琴',
  '钟琴',
  '音乐盒',
  '颤音琴',
  '马林巴琴',
  '木琴',
  '管钟',
  '扬琴',
  '音栓风琴',
  '打击风琴',
  '摇滚风琴',
  '教堂风琴',
  '簧风琴',
  '手风琴',
  '口琴',
  '探戈手风琴',
  '尼龙弦吉他',
  '钢弦吉他',
  '爵士电吉他',
  '清音电吉他',
  '闷音电吉他',
  '过载电吉他',
  '失真电吉他',
  '吉他泛音',
  '原声贝斯',
  '指弹贝斯',
  '拨片贝斯',
  '无品贝斯',
  '击弦贝斯1',
  '击弦贝斯2',
  '合成贝斯1',
  '合成贝斯2',
  '小提琴',
  '中提琴',
  '大提琴',
  '低音提琴',
  '颤弓弦乐',
  '拨弦弦乐',
  '竖琴',
  '定音鼓',
  '弦乐合奏1',
  '弦乐合奏2',
  '合成弦乐1',
  '合成弦乐2',
  '人声啊',
  '人声哦',
  '合成人声',
  '乐队重击',
  '小号',
  '长号',
  '大号',
  '弱音小号',
  '圆号',
  '铜管组',
  '合成铜管1',
  '合成铜管2',
  '高音萨克斯',
  '中音萨克斯',
  '次中音萨克斯',
  '上低音萨克斯',
  '双簧管',
  '英国管',
  '巴松',
  '单簧管',
  '短笛',
  '长笛',
  '竖笛',
  '排箫',
  '吹瓶声',
  '尺八',
  '口哨',
  '陶笛',
  '合成主音1',
  '合成主音2',
  '合成主音3',
  '合成主音4',
  '合成主音5',
  '合成主音6',
  '合成主音7',
  '合成主音8',
  '合成铺底1',
  '合成铺底2',
  '合成铺底3',
  '合成铺底4',
  '合成铺底5',
  '合成铺底6',
  '合成铺底7',
  '合成铺底8',
  '合成特效1',
  '合成特效2',
  '合成特效3',
  '合成特效4',
  '合成特效5',
  '合成特效6',
  '合成特效7',
  '合成特效8',
  '西塔琴',
  '班卓琴',
  '三味线',
  '筝',
  '卡林巴琴',
  '风笛',
  '提琴',
  '唢呐',
  '钟铃',
  '阿哥哥鼓',
  '钢鼓',
  '木鱼',
  '太鼓',
  '旋律通鼓',
  '合成鼓',
  '铜钹',
  '吉他杂音',
  '呼吸声',
  '海浪',
  '鸟鸣',
  '电话铃声',
  '直升机',
  '掌声',
  '枪声',
];

String _labelForKind(MidiPartKind kind) => switch (kind) {
  MidiPartKind.piano => '钢琴',
  MidiPartKind.strings => '弦乐',
  MidiPartKind.woodwind => '长笛',
  MidiPartKind.brass => '铜管',
  MidiPartKind.guitar => '吉他',
  MidiPartKind.bass => '贝斯',
  MidiPartKind.percussion => '打击乐',
  MidiPartKind.voice => '人声',
  MidiPartKind.synth => '合成器',
  MidiPartKind.other => '其他',
};
