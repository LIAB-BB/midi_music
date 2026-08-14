enum MidiPartKind {
  piano,
  strings,
  woodwind,
  brass,
  guitar,
  bass,
  percussion,
  voice,
  synth,
  other,
}

enum MidiStaffMode { grandStaff, singleStaff, percussionStaff }

enum MidiSelectionOrigin {
  songDefault,
  globalDefault,
  automaticPiano,
  automaticEnsemble,
  percussionFallback,
}

enum MidiNotationWarning {
  rhythmQuantized,
  unknownInstrument,
  irregularTimeSignature,
  densePassage,
}

class MidiPartSource {
  final int trackIndex;
  final Set<int> channels;

  factory MidiPartSource({
    required int trackIndex,
    required Set<int> channels,
  }) => MidiPartSource._(
    trackIndex: trackIndex,
    channels: Set<int>.unmodifiable(Set<int>.of(channels)),
  );

  const MidiPartSource._({required this.trackIndex, required this.channels});

  bool contains(int candidateTrackIndex, int channel) =>
      candidateTrackIndex == trackIndex && channels.contains(channel);
}

class MidiScorePart {
  final String id;
  final String label;
  final MidiPartKind kind;
  final List<MidiPartSource> sources;
  final int noteCount;
  final MidiStaffMode staffMode;

  factory MidiScorePart({
    required String id,
    required String label,
    required MidiPartKind kind,
    required List<MidiPartSource> sources,
    required int noteCount,
    required MidiStaffMode staffMode,
  }) => MidiScorePart._(
    id: id,
    label: label,
    kind: kind,
    sources: List<MidiPartSource>.unmodifiable(
      List<MidiPartSource>.of(sources),
    ),
    noteCount: noteCount,
    staffMode: staffMode,
  );

  const MidiScorePart._({
    required this.id,
    required this.label,
    required this.kind,
    required this.sources,
    required this.noteCount,
    required this.staffMode,
  });
}

class MidiScoreCatalog {
  final String fingerprint;
  final List<MidiScorePart> parts;
  final Set<String> recommendedPartIds;
  final MidiSelectionOrigin recommendedOrigin;

  factory MidiScoreCatalog({
    required String fingerprint,
    required List<MidiScorePart> parts,
    required Set<String> recommendedPartIds,
    required MidiSelectionOrigin recommendedOrigin,
  }) => MidiScoreCatalog._(
    fingerprint: fingerprint,
    parts: List<MidiScorePart>.unmodifiable(List<MidiScorePart>.of(parts)),
    recommendedPartIds: Set<String>.unmodifiable(
      Set<String>.of(recommendedPartIds),
    ),
    recommendedOrigin: recommendedOrigin,
  );

  const MidiScoreCatalog._({
    required this.fingerprint,
    required this.parts,
    required this.recommendedPartIds,
    required this.recommendedOrigin,
  });
}
