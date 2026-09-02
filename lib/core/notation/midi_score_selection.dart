import '../../models/midi_score_part.dart';

class MidiScoreSelection {
  final Set<String> partIds;
  final MidiSelectionOrigin origin;

  factory MidiScoreSelection({
    required Set<String> partIds,
    required MidiSelectionOrigin origin,
  }) => MidiScoreSelection._(
    partIds: Set<String>.unmodifiable(Set<String>.of(partIds)),
    origin: origin,
  );

  const MidiScoreSelection._({required this.partIds, required this.origin});
}

class MidiScoreSelectionResolver {
  MidiScoreSelection resolve(
    MidiScoreCatalog catalog, {
    Set<String>? songDefaultPartIds,
    required Set<MidiPartKind> globalDefaultKinds,
  }) {
    final available = {
      for (final part in catalog.parts)
        if (part.noteCount > 0) part.id: part,
    };
    if (available.isEmpty) {
      throw StateError('MIDI 中没有可记谱音符');
    }

    final songDefaults = _validPartIds(songDefaultPartIds, available);
    if (songDefaults.isNotEmpty) {
      return MidiScoreSelection(
        partIds: songDefaults,
        origin: MidiSelectionOrigin.songDefault,
      );
    }

    final globalDefaults = {
      for (final entry in available.entries)
        if (globalDefaultKinds.contains(entry.value.kind)) entry.key,
    };
    if (globalDefaults.isNotEmpty) {
      return MidiScoreSelection(
        partIds: globalDefaults,
        origin: MidiSelectionOrigin.globalDefault,
      );
    }

    final recommended = _validPartIds(catalog.recommendedPartIds, available);
    if (recommended.isNotEmpty) {
      return MidiScoreSelection(
        partIds: recommended,
        origin: catalog.recommendedOrigin,
      );
    }

    final piano = _partIdsForKind(available, MidiPartKind.piano);
    if (piano.isNotEmpty) {
      return MidiScoreSelection(
        partIds: piano,
        origin: MidiSelectionOrigin.automaticPiano,
      );
    }
    final ensemble = {
      for (final entry in available.entries)
        if (entry.value.kind != MidiPartKind.percussion) entry.key,
    };
    if (ensemble.isNotEmpty) {
      return MidiScoreSelection(
        partIds: ensemble,
        origin: MidiSelectionOrigin.automaticEnsemble,
      );
    }
    return MidiScoreSelection(
      partIds: available.keys.toSet(),
      origin: MidiSelectionOrigin.percussionFallback,
    );
  }

  Set<String> _validPartIds(
    Set<String>? candidates,
    Map<String, MidiScorePart> available,
  ) => {
    if (candidates != null)
      for (final id in candidates)
        if (available.containsKey(id)) id,
  };

  Set<String> _partIdsForKind(
    Map<String, MidiScorePart> available,
    MidiPartKind kind,
  ) => {
    for (final entry in available.entries)
      if (entry.value.kind == kind) entry.key,
  };
}
