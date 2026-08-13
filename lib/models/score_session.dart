import 'midi_track.dart';

enum ScoreSourceType { midiOnly, musicXml, pdfOmr }

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

  const ScoreSession({
    required this.songData,
    required this.sourceType,
    this.musicXml,
    this.measures = const [],
    required this.mappingStatus,
    this.warnings = const {},
  });

  factory ScoreSession.midiOnly(MidiSongData songData) => ScoreSession(
    songData: songData,
    sourceType: ScoreSourceType.midiOnly,
    mappingStatus: ScoreMappingStatus.unavailable,
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
