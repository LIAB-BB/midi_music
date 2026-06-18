import '../input/performance_input.dart';
import '../score/performance_timeline.dart';
import '../score/score_position.dart';

class ScorePositionRange {
  final ScorePosition start;
  final ScorePosition end;

  const ScorePositionRange({required this.start, required this.end});

  bool contains(ScorePosition position) {
    return position.absoluteBeat >= start.absoluteBeat &&
        position.absoluteBeat <= end.absoluteBeat;
  }
}

class FollowReplayExpectation {
  final ScorePositionRange expectedPosition;
  final Duration expectedRecoveryTime;

  const FollowReplayExpectation({
    required this.expectedPosition,
    required this.expectedRecoveryTime,
  });
}

class FollowReplayCase {
  final String name;
  final PerformanceTimeline targetTimeline;
  final List<PerformanceInputEvent> inputEvents;
  final FollowReplayExpectation expectation;

  FollowReplayCase({
    required this.name,
    required this.targetTimeline,
    required Iterable<PerformanceInputEvent> inputEvents,
    required this.expectation,
  }) : inputEvents = List.unmodifiable(
         List<PerformanceInputEvent>.of(inputEvents)
           ..sort((a, b) => a.timestamp.compareTo(b.timestamp)),
       );
}
