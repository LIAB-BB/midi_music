import '../../models/midi_score_part.dart';
import '../../models/midi_track.dart';

class MidiPartAnalyzer {
  MidiScoreCatalog analyze(MidiSongData song, {required String fingerprint}) {
    final sources = <_AnalyzedSource>[];
    final sortedTracks = song.tracks.where((track) => track.hasNotes).toList()
      ..sort((left, right) => left.index.compareTo(right.index));

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
    label: _labelForKind(source.kind),
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

  const _AnalyzedSource({
    required this.track,
    required this.channel,
    required this.noteCount,
    required this.kind,
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
  ['piano', 'keyboard', '钢琴']: MidiPartKind.piano,
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
