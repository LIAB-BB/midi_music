import 'package:score_follow/score_follow.dart';
import 'package:test/test.dart';

Score scoreOf(List<List<int>> onsets, {double spacing = 0.5}) {
  final notes = <ScoreNote>[];
  for (var index = 0; index < onsets.length; index++) {
    final start = index * spacing;
    for (final pitch in onsets[index]) {
      notes.add(
        ScoreNote(
          pitch: pitch,
          start: start,
          end: start + spacing * 0.9,
          startTick: index * 480,
          endTick: index * 480 + 432,
        ),
      );
    }
  }
  return Score.fromNotes(notes, title: 'test');
}

List<FollowUpdate> play(
  AdaptiveScoreFollower follower,
  Score score, {
  double speed = 1,
  Set<int> skip = const {},
  Duration chordGap = const Duration(milliseconds: 15),
}) {
  final updates = <FollowUpdate>[];
  for (final onset in score.onsets) {
    if (skip.contains(onset.index)) continue;
    final time = onset.time / speed;
    for (var noteIndex = 0; noteIndex < onset.notes.length; noteIndex++) {
      updates.add(
        follower.onNoteOn(
          onset.notes[noteIndex].pitch,
          time + chordGap.inMicroseconds / 1000000 * noteIndex,
        ),
      );
    }
  }
  return updates;
}

void main() {
  group('Score', () {
    test('同一时刻的音符合并为一个 onset，并按时间排序', () {
      final score = Score.fromNotes([
        const ScoreNote(pitch: 67, start: 0.5, end: 1.0),
        const ScoreNote(pitch: 60, start: 0, end: 0.4),
        const ScoreNote(pitch: 64, start: 0, end: 0.4),
      ]);

      expect(score.length, 2);
      expect(score.onsets[0].pitches, {60, 64});
      expect(score.onsets[0].time, 0);
      expect(score.onsets[0].endTime, 0.4);
      expect(score.onsets[1].pitches, {67});
      expect(score.duration, 1.0);
    });

    test('局部起拍间隔取中位数，快速跑动收紧门限', () {
      final score = scoreOf([
        [60],
        [62],
        [64],
        [65],
      ], spacing: 0.1);
      expect(score.localInterval(1), closeTo(0.1, 1e-9));
      expect(score.intervalAfter(0), closeTo(0.1, 1e-9));
    });

    test('空谱面被拒绝', () {
      expect(
        () => AdaptiveScoreFollower(score: Score.fromNotes(const [])),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('AdaptiveScoreFollower', () {
    test('匀速 1.0 演奏：位置逐 onset 前进，速度收敛到 1', () {
      final score = scoreOf([
        for (var index = 0; index < 16; index++) [60 + index % 5],
      ]);
      final follower = AdaptiveScoreFollower(score: score);

      final updates = play(follower, score);
      final matched = updates.where((update) => update.matched).toList();

      expect(matched, hasLength(score.length));
      expect(updates.last.positionOnsetIndex, score.length - 1);
      expect(updates.last.nextOnsetIndex, score.length);
      expect(updates.last.speed, closeTo(1.0, 0.02));
      expect(updates.last.confidence, greaterThan(0.9));
      expect(follower.isLocked, isTrue);
    });

    test('慢速 0.7 与快速 1.4 演奏都能收敛到真实速度', () {
      final score = scoreOf([
        for (var index = 0; index < 20; index++) [60 + index],
      ]);

      final slow = AdaptiveScoreFollower(score: score);
      final slowUpdates = play(slow, score, speed: 0.7);
      expect(slowUpdates.last.positionOnsetIndex, score.length - 1);
      expect(slowUpdates.last.speed, closeTo(0.7, 0.06));

      final fast = AdaptiveScoreFollower(score: score);
      final fastUpdates = play(fast, score, speed: 1.4);
      expect(fastUpdates.last.positionOnsetIndex, score.length - 1);
      expect(fastUpdates.last.speed, closeTo(1.4, 0.1));
    });

    test('错音只消耗 miss，不改变位置，后续正确起拍继续前进', () {
      final score = scoreOf([
        for (var index = 0; index < 18; index++) [60 + index % 7],
      ]);
      final follower = AdaptiveScoreFollower(score: score);
      var time = 0.0;
      var maxPosition = -1;

      for (final onset in score.onsets) {
        time = onset.time;
        // 每个正确起拍之后插入一个谱面中不存在的音。
        follower.onNoteOn(onset.notes.first.pitch, time);
        follower.onNoteOn(126, time + 0.2);
        maxPosition = maxPosition > onset.index ? maxPosition : onset.index;
      }

      final update = follower.onNoteOn(score.onsets.last.pitches.first, 9.0);
      expect(update.positionOnsetIndex, greaterThanOrEqualTo(maxPosition));
      expect(update.confidence, greaterThan(0.3));
      expect(update.speed, closeTo(1.0, 0.1));
    });

    test('漏掉一个 onset 后可向前跳一个位置继续', () {
      final score = scoreOf([
        for (var index = 0; index < 12; index++) [60 + index],
      ]);
      final follower = AdaptiveScoreFollower(score: score);

      final updates = play(follower, score, skip: {4});
      final atFive = updates.firstWhere(
        (update) => update.positionOnsetIndex == 5,
      );

      expect(atFive.matched, isTrue);
      expect(updates.last.positionOnsetIndex, score.length - 1);
      expect(updates.last.speed, closeTo(1.0, 0.05));
    });

    test('和弦尾音不重复推进位置', () {
      final score = scoreOf([
        [60, 64, 67],
        [62],
        [65],
      ]);
      final follower = AdaptiveScoreFollower(score: score);

      final first = follower.onNoteOn(60, 0);
      final second = follower.onNoteOn(64, 0.015);
      final third = follower.onNoteOn(67, 0.03);
      final next = follower.onNoteOn(62, 0.5);

      expect(first.positionOnsetIndex, 0);
      expect(second.positionOnsetIndex, 0);
      expect(second.nextOnsetIndex, 1);
      expect(third.positionOnsetIndex, 0);
      expect(third.nextOnsetIndex, 1);
      expect(next.positionOnsetIndex, 1);
      expect(next.matched, isTrue);
    });

    test('长休止后命中期待起拍会重锚，速度不被停顿拉坏', () {
      final score = scoreOf([
        for (var index = 0; index < 10; index++) [60 + index],
      ]);
      final follower = AdaptiveScoreFollower(score: score);

      play(follower, score, skip: {4, 5, 6, 7, 8, 9});
      final beforeRest = follower.lastUpdate!;
      expect(beforeRest.positionOnsetIndex, 3);

      final resumed = follower.onNoteOn(64, 3.5);
      expect(resumed.matched, isTrue);
      expect(resumed.positionOnsetIndex, 4);
      expect(resumed.reacquired, isTrue);
      expect(resumed.speed, closeTo(1.0, 0.05));

      final continued = follower.onNoteOn(65, 4.0);
      expect(continued.positionOnsetIndex, 5);
      expect(continued.matched, isTrue);
    });

    test('首个音不在谱面时保持未锁定，随后从正确起拍开始', () {
      final score = scoreOf([
        [60],
        [62],
        [64],
        [65],
      ]);
      final follower = AdaptiveScoreFollower(score: score);

      final wrong = follower.onNoteOn(72, 0);
      expect(wrong.matched, isFalse);
      expect(wrong.confidence, 0);
      expect(follower.hypothesisCount, 0);

      final first = follower.onNoteOn(60, 0.5);
      expect(first.matched, isTrue);
      expect(first.reacquired, isTrue);

      final second = follower.onNoteOn(62, 1.0);
      expect(second.positionOnsetIndex, 1);
      final third = follower.onNoteOn(64, 1.5);
      expect(third.positionOnsetIndex, 2);
      follower.onNoteOn(65, 2.0);
      expect(follower.lastUpdate!.confidence, greaterThan(0.5));
    });

    test('反复音型不会把假设带到后面的同一音型', () {
      final score = scoreOf([
        for (var index = 0; index < 12; index++) [index.isEven ? 60 : 62],
      ]);
      final follower = AdaptiveScoreFollower(score: score);

      final updates = play(follower, score);
      expect(updates.last.positionOnsetIndex, score.length - 1);
      for (var index = 0; index < score.length; index++) {
        final update = updates[index];
        expect(update.positionOnsetIndex, index);
      }
    });

    test('自由速度（连续 rubato）下位置仍正确，速度跟随变化', () {
      final score = scoreOf([
        for (var index = 0; index < 24; index++) [60 + index % 9],
      ]);
      final follower = AdaptiveScoreFollower(score: score);
      var performanceTime = 0.0;

      for (final onset in score.onsets) {
        final targetSpeed = 1 + 0.18 * (onset.index.isEven ? 1 : -1);
        if (onset.index > 0) {
          performanceTime +=
              (onset.time - score.onsets[onset.index - 1].time) / targetSpeed;
        }
        final update = follower.onNoteOn(onset.pitches.first, performanceTime);
        expect(
          update.positionOnsetIndex,
          onset.index,
          reason: 'onset ${onset.index}',
        );
        expect(update.speed, inInclusiveRange(0.7, 1.3));
      }

      expect(follower.lastUpdate!.confidence, greaterThan(0.5));
    });

    test('跳段后能恢复位置', () {
      final score = scoreOf([
        for (var index = 0; index < 14; index++) [60 + index],
      ]);
      final follower = AdaptiveScoreFollower(
        score: score,
        config: const FollowConfig(maxMisses: 3),
      );

      // 正常演奏到 onset 3，然后跳到 onset 9。
      for (var index = 0; index <= 3; index++) {
        follower.onNoteOn(60 + index, index * 0.5);
      }
      for (var index = 9; index < 14; index++) {
        follower.onNoteOn(60 + index, index * 0.5);
      }

      final update = follower.lastUpdate!;
      expect(update.positionOnsetIndex, 13);
      expect(update.matched, isTrue);
      expect(update.confidence, greaterThan(0.5));
    });

    test('reset 后可以当作新演奏重新开始', () {
      final score = scoreOf([
        [60],
        [62],
        [64],
      ]);
      final follower = AdaptiveScoreFollower(score: score);
      play(follower, score);
      expect(follower.lastUpdate!.positionOnsetIndex, 2);

      follower.reset();
      expect(follower.hypothesisCount, 0);
      expect(follower.lastUpdate, isNull);

      final restart = follower.onNoteOn(60, 10);
      expect(restart.positionOnsetIndex, 0);
      expect(restart.reacquired, isTrue);
    });
  });
}
