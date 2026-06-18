import 'performance_timeline.dart';
import 'score_position.dart';
import 'score_source.dart';

enum PitchStep { c, d, e, f, g, a, b }

class NotatedPitch {
  final PitchStep step;
  final int alter;
  final int octave;
  final int midiPitch;

  const NotatedPitch({
    required this.step,
    this.alter = 0,
    required this.octave,
    required this.midiPitch,
  });
}

abstract class ScoreEvent {
  final String id;
  final ScorePosition position;
  final double durationBeats;
  final SourceReference? source;

  const ScoreEvent({
    required this.id,
    required this.position,
    required this.durationBeats,
    this.source,
  });
}

class ScoreNote extends ScoreEvent {
  final NotatedPitch pitch;
  final int voice;
  final bool tieStart;
  final bool tieStop;
  final bool isGrace;

  const ScoreNote({
    required super.id,
    required super.position,
    required super.durationBeats,
    required this.pitch,
    this.voice = 1,
    this.tieStart = false,
    this.tieStop = false,
    this.isGrace = false,
    super.source,
  });
}

class ScoreRest extends ScoreEvent {
  const ScoreRest({
    required super.id,
    required super.position,
    required super.durationBeats,
    super.source,
  });
}

class ScoreVoice {
  final String id;
  final List<ScoreEvent> events;

  ScoreVoice({required this.id, required Iterable<ScoreEvent> events})
    : events = List.unmodifiable(
        List<ScoreEvent>.of(events)..sort(_compareEvents),
      );

  List<ScoreEvent> eventsAtAbsoluteBeat(double absoluteBeat) {
    return [
      for (final event in events)
        if (event.position.isAtAbsoluteBeat(absoluteBeat)) event,
    ];
  }
}

class ScoreMeasure {
  final int number;
  final double startBeat;
  final double durationBeats;
  final List<ScoreVoice> voices;

  ScoreMeasure({
    required this.number,
    required this.startBeat,
    required this.durationBeats,
    required Iterable<ScoreVoice> voices,
  }) : voices = List.unmodifiable(voices);

  List<ScoreEvent> eventsAtAbsoluteBeat(double absoluteBeat) {
    return [
      for (final voice in voices) ...voice.eventsAtAbsoluteBeat(absoluteBeat),
    ];
  }
}

class ScorePart {
  final String id;
  final String name;
  final List<ScoreMeasure> measures;

  ScorePart({
    required this.id,
    required this.name,
    required Iterable<ScoreMeasure> measures,
  }) : measures = List.unmodifiable(measures);

  ScoreMeasure? measureByNumber(int measureNumber) {
    for (final measure in measures) {
      if (measure.number == measureNumber) {
        return measure;
      }
    }
    return null;
  }
}

class ScoreDocument {
  final String id;
  final String title;
  final List<ScorePart> parts;
  final SourceReference? source;

  ScoreDocument({
    required this.id,
    required this.title,
    required Iterable<ScorePart> parts,
    this.source,
  }) : parts = List.unmodifiable(parts);

  ScorePart? partById(String partId) {
    for (final part in parts) {
      if (part.id == partId) {
        return part;
      }
    }
    return null;
  }

  List<ScoreMeasure> measuresForPart(String partId) {
    return partById(partId)?.measures ?? const [];
  }

  ScoreMeasure? measureByNumber(String partId, int measureNumber) {
    return partById(partId)?.measureByNumber(measureNumber);
  }

  List<ScoreEvent> eventsAtAbsoluteBeat(double absoluteBeat) {
    return [
      for (final part in parts)
        for (final measure in part.measures)
          ...measure.eventsAtAbsoluteBeat(absoluteBeat),
    ];
  }

  PerformanceTimeline toPerformanceTimeline({
    double secondsPerBeat = 0.5,
    int defaultVelocity = 80,
  }) {
    final performanceEvents = <PerformanceEvent>[];
    for (final part in parts) {
      for (final measure in part.measures) {
        for (final voice in measure.voices) {
          for (final event in voice.events) {
            switch (event) {
              case ScoreNote note:
                performanceEvents.add(
                  PerformanceEvent(
                    id: '${note.id}:on',
                    scoreEventId: note.id,
                    partId: part.id,
                    voiceId: voice.id,
                    type: PerformanceEventType.noteOn,
                    position: note.position,
                    timeSeconds: note.position.absoluteBeat * secondsPerBeat,
                    midiPitch: note.pitch.midiPitch,
                    velocity: defaultVelocity,
                    source: note.source,
                  ),
                );
                final endPosition = note.position.shift(note.durationBeats);
                performanceEvents.add(
                  PerformanceEvent(
                    id: '${note.id}:off',
                    scoreEventId: note.id,
                    partId: part.id,
                    voiceId: voice.id,
                    type: PerformanceEventType.noteOff,
                    position: endPosition,
                    timeSeconds: endPosition.absoluteBeat * secondsPerBeat,
                    midiPitch: note.pitch.midiPitch,
                    velocity: 0,
                    source: note.source,
                  ),
                );
              case ScoreRest rest:
                performanceEvents.add(
                  PerformanceEvent(
                    id: '${rest.id}:rest',
                    scoreEventId: rest.id,
                    partId: part.id,
                    voiceId: voice.id,
                    type: PerformanceEventType.rest,
                    position: rest.position,
                    timeSeconds: rest.position.absoluteBeat * secondsPerBeat,
                    source: rest.source,
                  ),
                );
            }
          }
        }
      }
    }
    return PerformanceTimeline(performanceEvents);
  }
}

int _compareEvents(ScoreEvent a, ScoreEvent b) {
  final positionCompare = a.position.compareTo(b.position);
  if (positionCompare != 0) return positionCompare;
  return a.id.compareTo(b.id);
}
