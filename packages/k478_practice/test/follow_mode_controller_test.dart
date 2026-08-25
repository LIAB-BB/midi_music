import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:k478_practice/src/core/follow_mode_controller.dart';
import 'package:k478_practice/src/core/onset_event.dart';
import 'package:k478_practice/src/models/midi_track.dart';

MidiNote _note(int midi, int tick, double start, double end) => MidiNote(
  noteNumber: midi,
  velocity: 100,
  channel: 0,
  startTick: tick,
  endTick: tick + 60,
  startTime: start,
  endTime: end,
);

OnsetEvent _onset(int midi, DateTime timestamp) => OnsetEvent(
  midiNote: midi,
  frequency: 440,
  volume: 0.8,
  timestamp: timestamp,
);

void main() {
  test('首个错音、后续起拍音与连续错音都不会启动匹配', () async {
    final input = StreamController<OnsetEvent>.broadcast();
    final controller = FollowModeController.fromOnsetStream(
      onsetStream: input.stream,
    );
    final matches = <FollowMatch>[];
    final speeds = <double>[];
    final realignments = <FollowRealignmentRequest>[];
    controller.onMatch = matches.add;
    controller.onSpeedChanged = speeds.add;
    controller.onRealignmentRequested = realignments.add;
    controller.loadScore([
      _note(60, 0, 0, 0.2),
      _note(62, 120, 0.4, 0.6),
      _note(64, 240, 0.8, 1),
    ]);
    controller.start();

    final at = DateTime(2026, 8, 23, 12);
    input.add(_onset(62, at));
    input.add(_onset(64, at.add(const Duration(milliseconds: 100))));
    input.add(_onset(72, at.add(const Duration(milliseconds: 200))));
    await Future<void>.delayed(Duration.zero);

    expect(matches, isEmpty);
    expect(controller.expectedOnsetIndex, 0);
    expect(controller.speedFactor, 1);
    expect(speeds, isEmpty);
    expect(realignments, isEmpty);
    controller.dispose();
    await input.close();
  });

  test('首个正确单音或和弦只产生一次初始匹配', () async {
    final input = StreamController<OnsetEvent>.broadcast();
    final controller = FollowModeController.fromOnsetStream(
      onsetStream: input.stream,
    );
    final matches = <FollowMatch>[];
    controller.onMatch = matches.add;
    controller.loadScore([
      _note(60, 0, 0, 0.2),
      _note(64, 0, 0, 0.2),
      _note(67, 120, 0.4, 0.6),
    ]);
    controller.start();

    final at = DateTime(2026, 8, 23, 12);
    input.add(_onset(60, at));
    input.add(_onset(64, at.add(const Duration(milliseconds: 30))));
    await Future<void>.delayed(Duration.zero);

    expect(matches, hasLength(1));
    expect(matches.single.isInitialMatch, isTrue);
    expect(controller.expectedOnsetIndex, 1);
    controller.dispose();
    await input.close();
  });

  test('首个正确单音只产生一次初始匹配', () async {
    final input = StreamController<OnsetEvent>.broadcast();
    final controller = FollowModeController.fromOnsetStream(
      onsetStream: input.stream,
    );
    final matches = <FollowMatch>[];
    controller.onMatch = matches.add;
    controller.loadScore([_note(60, 0, 0, 0.2), _note(62, 120, 0.4, 0.6)]);
    controller.start();

    input.add(_onset(60, DateTime(2026, 8, 23, 12)));
    await Future<void>.delayed(Duration.zero);

    expect(matches, hasLength(1));
    expect(matches.single.isInitialMatch, isTrue);
    controller.dispose();
    await input.close();
  });

  test('快速同音重复会推进到下一个 onset，而和弦第二音仍不会重复匹配', () async {
    final input = StreamController<OnsetEvent>.broadcast();
    final controller = FollowModeController.fromOnsetStream(
      onsetStream: input.stream,
    );
    final matches = <FollowMatch>[];
    controller.onMatch = matches.add;
    controller.loadScore([
      _note(60, 0, 0, 0.1),
      _note(60, 120, 0.2, 0.3),
      _note(62, 240, 0.4, 0.5),
    ]);
    controller.start();

    final at = DateTime(2026, 8, 23, 12);
    input.add(_onset(60, at));
    input.add(_onset(60, at.add(const Duration(milliseconds: 20))));
    await Future<void>.delayed(Duration.zero);

    expect(matches, hasLength(2));
    expect(controller.expectedOnsetIndex, 2);
    controller.dispose();
    await input.close();
  });

  test('错音后首个正确起拍仍只启动一次', () async {
    final input = StreamController<OnsetEvent>.broadcast();
    final controller = FollowModeController.fromOnsetStream(
      onsetStream: input.stream,
    );
    final matches = <FollowMatch>[];
    controller.onMatch = matches.add;
    controller.loadScore([_note(60, 0, 0, 0.2), _note(62, 120, 0.4, 0.6)]);
    controller.start();

    final at = DateTime(2026, 8, 23, 12);
    input.add(_onset(72, at));
    input.add(_onset(60, at.add(const Duration(milliseconds: 100))));
    await Future<void>.delayed(Duration.zero);

    expect(matches, hasLength(1));
    expect(matches.single.isInitialMatch, isTrue);
    controller.dispose();
    await input.close();
  });

  test('长休止到达边界后才等待，提前重入会被忽略', () async {
    final input = StreamController<OnsetEvent>.broadcast();
    final controller = FollowModeController.fromOnsetStream(
      onsetStream: input.stream,
      config: const FollowModeConfig(
        restThresholdSeconds: 1,
        approvedWaitReentryTicks: {120},
      ),
    );
    final matches = <FollowMatch>[];
    final speeds = <double>[];
    final realignments = <FollowRealignmentRequest>[];
    controller.onMatch = matches.add;
    controller.onSpeedChanged = speeds.add;
    controller.onRealignmentRequested = realignments.add;
    controller.loadScore([_note(60, 0, 0, 0.5), _note(62, 120, 2, 2.5)]);
    controller.start();

    final at = DateTime(2026, 8, 23, 12);
    input.add(_onset(60, at));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, FollowModeState.following);
    final rest = matches.single.followingRest!;
    expect(rest.restStartScoreTime, 0.5);
    expect(rest.resumeScoreTime, 2);

    input.add(_onset(62, at.add(const Duration(milliseconds: 200))));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, FollowModeState.following);
    expect(matches, hasLength(1));

    controller.markRestBoundaryReached(rest);
    expect(controller.state, FollowModeState.waitingForOnset);

    for (var index = 0; index < 3; index++) {
      input.add(
        _onset(72, at.add(Duration(seconds: 2, milliseconds: index * 100))),
      );
    }
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, FollowModeState.waitingForOnset);
    expect(matches, hasLength(1));
    expect(controller.speedFactor, 1);
    expect(speeds, isEmpty);
    expect(realignments, isEmpty);

    input.add(_onset(62, at.add(const Duration(seconds: 3))));
    await Future<void>.delayed(Duration.zero);
    expect(matches, hasLength(2));
    expect(matches.last.resumesFromRest, isTrue);
    expect(matches.last.scoreTime, 2);
    expect(controller.state, FollowModeState.following);
    controller.dispose();
    await input.close();
  });

  test('未批准的钢琴休止不能自动暂停其他声部', () async {
    final input = StreamController<OnsetEvent>.broadcast();
    final controller = FollowModeController.fromOnsetStream(
      onsetStream: input.stream,
      config: const FollowModeConfig(restThresholdSeconds: 1),
    );
    final matches = <FollowMatch>[];
    controller.onMatch = matches.add;
    controller.loadScore([_note(60, 0, 0, 0.5), _note(62, 120, 2, 2.5)]);
    controller.start();

    final at = DateTime(2026, 8, 24, 12);
    input.add(_onset(60, at));
    await Future<void>.delayed(Duration.zero);

    expect(matches.single.followingRest, isNull);
    expect(controller.pendingRest, isNull);
    expect(controller.state, FollowModeState.following);

    input.add(_onset(62, at.add(const Duration(seconds: 2))));
    await Future<void>.delayed(Duration.zero);
    expect(matches, hasLength(2));
    expect(controller.state, FollowModeState.following);
    controller.dispose();
    await input.close();
  });

  test('批准等待点的重入不把休止时长计入速度', () async {
    final input = StreamController<OnsetEvent>.broadcast();
    final controller = FollowModeController.fromOnsetStream(
      onsetStream: input.stream,
      config: const FollowModeConfig(
        restThresholdSeconds: 1,
        approvedWaitReentryTicks: {120},
      ),
    );
    final matches = <FollowMatch>[];
    final speeds = <double>[];
    controller.onMatch = matches.add;
    controller.onSpeedChanged = speeds.add;
    controller.loadScore([
      _note(60, 0, 0, 0.5),
      _note(62, 120, 2, 2.2),
      _note(64, 240, 2.5, 2.7),
    ]);
    controller.start();

    final at = DateTime(2026, 8, 24, 12);
    input.add(_onset(60, at));
    await Future<void>.delayed(Duration.zero);
    controller.markRestBoundaryReached(matches.single.followingRest!);

    // 谱面间隔为 2 秒、实际间隔为 1.5 秒；旧逻辑会把速度推到 1.1。
    input.add(_onset(62, at.add(const Duration(milliseconds: 1500))));
    await Future<void>.delayed(Duration.zero);
    expect(matches.last.resumesFromRest, isTrue);
    expect(controller.speedFactor, 1);
    expect(speeds, isEmpty);

    input.add(_onset(64, at.add(const Duration(seconds: 2))));
    await Future<void>.delayed(Duration.zero);
    expect(controller.speedFactor, 1);
    expect(speeds, [1]);
    controller.dispose();
    await input.close();
  });

  test('连续错音请求与当前期待起拍一致的重新对齐', () async {
    final input = StreamController<OnsetEvent>.broadcast();
    final controller = FollowModeController.fromOnsetStream(
      onsetStream: input.stream,
      config: const FollowModeConfig(unmatchedThreshold: 3),
    );
    final requests = <FollowRealignmentRequest>[];
    controller.onRealignmentRequested = requests.add;
    controller.loadScore([_note(60, 0, 1.25, 1.5), _note(62, 120, 2, 2.25)]);
    controller.start();
    final at = DateTime(2026, 8, 23, 12);
    input.add(_onset(60, at));
    for (var index = 0; index < 3; index++) {
      input.add(_onset(72, at.add(Duration(milliseconds: 100 + index * 100))));
    }
    await Future<void>.delayed(Duration.zero);
    expect(requests, hasLength(1));
    expect(requests.single.expectedOnsetIndex, 1);
    expect(requests.single.scoreTime, 2);
    controller.dispose();
    await input.close();
  });

  test('首次正确匹配后的连续错音不会改变速度', () async {
    final input = StreamController<OnsetEvent>.broadcast();
    final controller = FollowModeController.fromOnsetStream(
      onsetStream: input.stream,
      config: const FollowModeConfig(unmatchedThreshold: 3),
    );
    final speeds = <double>[];
    final requests = <FollowRealignmentRequest>[];
    controller.onSpeedChanged = speeds.add;
    controller.onRealignmentRequested = requests.add;
    controller.loadScore([_note(60, 0, 0, 0.2), _note(62, 120, 0.4, 0.6)]);
    controller.start();

    final at = DateTime(2026, 8, 23, 12);
    input.add(_onset(60, at));
    for (var index = 0; index < 3; index++) {
      input.add(_onset(72, at.add(Duration(milliseconds: 100 + index * 100))));
    }
    await Future<void>.delayed(Duration.zero);

    expect(controller.speedFactor, 1);
    expect(speeds, isEmpty);
    expect(requests, hasLength(1));
    controller.dispose();
    await input.close();
  });
}
