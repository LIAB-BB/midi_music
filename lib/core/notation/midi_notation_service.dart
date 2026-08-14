import 'dart:isolate';

import '../../models/midi_score_part.dart';
import '../../models/midi_track.dart';
import '../../models/score_session.dart';
import 'midi_part_analyzer.dart';
import 'midi_score_selection.dart';
import 'midi_to_musicxml_converter.dart';

class MidiNotationPreparation {
  final MidiScoreCatalog catalog;
  final MidiScoreSelection selection;
  final ScoreSession session;

  factory MidiNotationPreparation({
    required MidiScoreCatalog catalog,
    required MidiScoreSelection selection,
    required ScoreSession session,
  }) => MidiNotationPreparation._(
    catalog: catalog,
    selection: selection,
    session: session,
  );

  const MidiNotationPreparation._({
    required this.catalog,
    required this.selection,
    required this.session,
  });
}

abstract interface class MidiNotationBuilder {
  Future<MidiNotationPreparation> prepare(
    MidiSongData song, {
    required String fingerprint,
    required Set<MidiPartKind> globalDefaultKinds,
    Set<String>? songDefaultPartIds,
  });

  Future<ScoreSession> rebuild(
    MidiSongData song, {
    required MidiScoreCatalog catalog,
    required Set<String> selectedPartIds,
  });
}

class MidiNotationService implements MidiNotationBuilder {
  @override
  Future<MidiNotationPreparation> prepare(
    MidiSongData song, {
    required String fingerprint,
    required Set<MidiPartKind> globalDefaultKinds,
    Set<String>? songDefaultPartIds,
  }) async {
    final copiedGlobalDefaultKinds = Set<MidiPartKind>.of(globalDefaultKinds);
    final copiedSongDefaultPartIds = songDefaultPartIds == null
        ? null
        : Set<String>.of(songDefaultPartIds);
    final prepared = await Isolate.run(
      () => _prepareNotation(
        song,
        fingerprint: fingerprint,
        globalDefaultKinds: copiedGlobalDefaultKinds,
        songDefaultPartIds: copiedSongDefaultPartIds,
      ),
      debugName: 'MIDI notation preparation',
    );
    return MidiNotationPreparation(
      catalog: prepared.catalog,
      selection: prepared.selection,
      session: _asMidiNotation(
        song,
        prepared.notation,
        fingerprint: prepared.catalog.fingerprint,
      ),
    );
  }

  @override
  Future<ScoreSession> rebuild(
    MidiSongData song, {
    required MidiScoreCatalog catalog,
    required Set<String> selectedPartIds,
  }) async {
    final copiedSelectedPartIds = Set<String>.of(selectedPartIds);
    final notation = await Isolate.run(
      () => MidiToMusicXmlConverter().convertSync(
        song,
        catalog: catalog,
        selectedPartIds: copiedSelectedPartIds,
      ),
      debugName: 'MIDI notation rebuild',
    );
    return _asMidiNotation(song, notation, fingerprint: catalog.fingerprint);
  }
}

_PreparedNotation _prepareNotation(
  MidiSongData song, {
  required String fingerprint,
  required Set<MidiPartKind> globalDefaultKinds,
  Set<String>? songDefaultPartIds,
}) {
  final catalog = MidiPartAnalyzer().analyze(song, fingerprint: fingerprint);
  final selection = MidiScoreSelectionResolver().resolve(
    catalog,
    globalDefaultKinds: globalDefaultKinds,
    songDefaultPartIds: songDefaultPartIds,
  );
  final notation = MidiToMusicXmlConverter().convertSync(
    song,
    catalog: catalog,
    selectedPartIds: selection.partIds,
  );
  return _PreparedNotation(
    catalog: catalog,
    selection: selection,
    notation: notation,
  );
}

ScoreSession _asMidiNotation(
  MidiSongData song,
  MidiNotationResult result, {
  required String fingerprint,
}) => ScoreSession(
  songData: song,
  musicXml: result.musicXml,
  sourceType: ScoreSourceType.midiNotation,
  measures: result.measures,
  mappingStatus: ScoreMappingStatus.complete,
  sourceFingerprint: fingerprint,
  selectedPartIds: result.selectedPartIds,
  notationWarnings: result.warnings,
);

class _PreparedNotation {
  final MidiScoreCatalog catalog;
  final MidiScoreSelection selection;
  final MidiNotationResult notation;

  const _PreparedNotation({
    required this.catalog,
    required this.selection,
    required this.notation,
  });
}
