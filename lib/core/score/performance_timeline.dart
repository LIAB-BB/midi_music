import 'score_position.dart';
import 'score_source.dart';

enum PerformanceEventType { noteOn, noteOff, rest }

class PerformanceEvent implements Comparable<PerformanceEvent> {
  final String id;
  final String scoreEventId;
  final String partId;
  final String voiceId;
  final PerformanceEventType type;
  final ScorePosition position;
  final double timeSeconds;
  final int? midiPitch;
  final int velocity;
  final SourceReference? source;

  const PerformanceEvent({
    required this.id,
    required this.scoreEventId,
    required this.partId,
    required this.voiceId,
    required this.type,
    required this.position,
    required this.timeSeconds,
    this.midiPitch,
    this.velocity = 80,
    this.source,
  });

  @override
  int compareTo(PerformanceEvent other) {
    final timeCompare = timeSeconds.compareTo(other.timeSeconds);
    if (timeCompare != 0) return timeCompare;
    final positionCompare = position.compareTo(other.position);
    if (positionCompare != 0) return positionCompare;
    if (scoreEventId == other.scoreEventId) {
      final sameEventCompare = _sameEventPriority(
        type,
      ).compareTo(_sameEventPriority(other.type));
      if (sameEventCompare != 0) return sameEventCompare;
    }
    final priorityCompare = _eventPriority(
      type,
    ).compareTo(_eventPriority(other.type));
    if (priorityCompare != 0) return priorityCompare;
    return id.compareTo(other.id);
  }
}

class PerformanceTimeline {
  final List<PerformanceEvent> events;

  PerformanceTimeline(Iterable<PerformanceEvent> events)
    : events = List.unmodifiable(List.of(events)..sort());

  List<PerformanceEvent> eventsAtBeat(
    double absoluteBeat, {
    double tolerance = 0.000001,
  }) {
    return [
      for (final event in events)
        if (event.position.isAtAbsoluteBeat(absoluteBeat, tolerance: tolerance))
          event,
    ];
  }

  List<PerformanceEvent> eventsInBeatRange(double startBeat, double endBeat) {
    return [
      for (final event in events)
        if (event.position.absoluteBeat >= startBeat &&
            event.position.absoluteBeat <= endBeat)
          event,
    ];
  }
}

int _eventPriority(PerformanceEventType type) {
  return switch (type) {
    PerformanceEventType.noteOff => 0,
    PerformanceEventType.rest => 1,
    PerformanceEventType.noteOn => 2,
  };
}

int _sameEventPriority(PerformanceEventType type) {
  return switch (type) {
    PerformanceEventType.noteOn => 0,
    PerformanceEventType.rest => 1,
    PerformanceEventType.noteOff => 2,
  };
}
