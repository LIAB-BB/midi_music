import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/follow/follow_replay_case.dart';
import 'package:midi_music/core/follow/tracking_state.dart';
import 'package:midi_music/core/input/performance_input.dart';
import 'package:midi_music/core/score/score.dart';

void main() {
  test('FollowReplayCase 保存目标 timeline、输入事件和恢复期望', () {
    final start = DateTime(2026);
    final timeline = PerformanceTimeline([
      const PerformanceEvent(
        id: 'n1:on',
        scoreEventId: 'n1',
        partId: 'solo',
        voiceId: 'v1',
        type: PerformanceEventType.noteOn,
        position: ScorePosition.absolute(0),
        timeSeconds: 0,
        midiPitch: 60,
      ),
    ]);

    final replayCase = FollowReplayCase(
      name: 'normal-start',
      targetTimeline: timeline,
      inputEvents: [
        PerformanceInputEvent.noteOn(
          midiNote: 62,
          velocity: 90,
          timestamp: start.add(const Duration(milliseconds: 500)),
        ),
        PerformanceInputEvent.noteOn(
          midiNote: 60,
          velocity: 90,
          timestamp: start,
        ),
      ],
      expectation: const FollowReplayExpectation(
        expectedPosition: ScorePositionRange(
          start: ScorePosition.absolute(0),
          end: ScorePosition.absolute(1),
        ),
        expectedRecoveryTime: Duration(milliseconds: 300),
      ),
    );

    expect(replayCase.inputEvents.first.midiNote, 60);
    expect(
      replayCase.expectation.expectedPosition.contains(
        const ScorePosition.absolute(0.5),
      ),
      isTrue,
    );
  });

  test('ScoreTrackingState 预留位置、速度、置信度和可靠匹配状态', () {
    final lastMatch = DateTime(2026);
    final state = ScoreTrackingState(
      scorePosition: const ScorePosition.absolute(4),
      tempo: 92,
      confidence: 0.75,
      status: TrackingStatus.tracking,
      lastReliableMatch: lastMatch,
    );

    final updated = state.copyWith(
      confidence: 0.3,
      status: TrackingStatus.lowConfidence,
    );

    expect(updated.scorePosition.absoluteBeat, 4);
    expect(updated.tempo, 92);
    expect(updated.confidence, 0.3);
    expect(updated.status, TrackingStatus.lowConfidence);
    expect(updated.lastReliableMatch, lastMatch);
  });
}
