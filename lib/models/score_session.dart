import 'midi_score_part.dart';
import 'midi_track.dart';

enum ScoreSourceType { midiOnly, midiNotation, musicXml, pdfOmr }

enum ScoreMappingStatus { unavailable, complete, partial }

enum ScoreWarning { complexRepetition, inconsistentPartMeasures }

class ScoreMeasureBoundary {
  final int ordinal;
  final String label;
  final int startTick;
  final int endTick;
  final bool isInteractive;

  const ScoreMeasureBoundary({
    required this.ordinal,
    required this.label,
    required this.startTick,
    required this.endTick,
    this.isInteractive = true,
  });

  @override
  bool operator ==(Object other) =>
      other is ScoreMeasureBoundary &&
      ordinal == other.ordinal &&
      label == other.label &&
      startTick == other.startTick &&
      endTick == other.endTick &&
      isInteractive == other.isInteractive;

  @override
  int get hashCode =>
      Object.hash(ordinal, label, startTick, endTick, isInteractive);
}

class ScoreSession {
  final MidiSongData songData;
  final String? musicXml;
  final ScoreSourceType sourceType;
  final List<ScoreMeasureBoundary> measures;
  final ScoreMappingStatus mappingStatus;
  final Set<ScoreWarning> warnings;
  final String? sourceFingerprint;
  final Set<String> selectedPartIds;
  final Set<MidiNotationWarning> notationWarnings;

  factory ScoreSession({
    required MidiSongData songData,
    required ScoreSourceType sourceType,
    String? musicXml,
    List<ScoreMeasureBoundary> measures = const [],
    required ScoreMappingStatus mappingStatus,
    Set<ScoreWarning> warnings = const {},
    String? sourceFingerprint,
    Set<String> selectedPartIds = const {},
    Set<MidiNotationWarning> notationWarnings = const {},
  }) => ScoreSession._(
    songData: songData,
    musicXml: musicXml,
    sourceType: sourceType,
    measures: List<ScoreMeasureBoundary>.unmodifiable(
      List<ScoreMeasureBoundary>.of(measures),
    ),
    mappingStatus: mappingStatus,
    warnings: Set<ScoreWarning>.unmodifiable(Set<ScoreWarning>.of(warnings)),
    sourceFingerprint: sourceFingerprint,
    selectedPartIds: Set<String>.unmodifiable(Set<String>.of(selectedPartIds)),
    notationWarnings: Set<MidiNotationWarning>.unmodifiable(
      Set<MidiNotationWarning>.of(notationWarnings),
    ),
  );

  const ScoreSession._({
    required this.songData,
    required this.musicXml,
    required this.sourceType,
    required this.measures,
    required this.mappingStatus,
    required this.warnings,
    required this.sourceFingerprint,
    required this.selectedPartIds,
    required this.notationWarnings,
  });

  factory ScoreSession.midiOnly(
    MidiSongData songData, {
    String? sourceFingerprint,
  }) => ScoreSession(
    songData: songData,
    sourceType: ScoreSourceType.midiOnly,
    mappingStatus: ScoreMappingStatus.unavailable,
    sourceFingerprint: sourceFingerprint,
  );

  bool get hasInteractiveScore =>
      musicXml != null &&
      musicXml!.trim().isNotEmpty &&
      mappingStatus != ScoreMappingStatus.unavailable &&
      measures.any((measure) => measure.isInteractive);

  bool isMeasureInteractive(int ordinal) => measures.any(
    (measure) => measure.ordinal == ordinal && measure.isInteractive,
  );
}
