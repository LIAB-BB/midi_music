import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/follow/follow_mode_controller.dart';
import 'package:midi_music/core/follow/onset_detector.dart';
import 'package:midi_music/models/midi_track.dart';

void main() {
  test('允许常见八度误检匹配同一音级', () async {
    final pitchInput = StreamController<PitchData>.broadcast();
    final onsetDetector = OnsetDetector();
    final controller = FollowModeController(
      onsetDetector: onsetDetector,
      config: const FollowModeConfig(
        noteMatchTolerance: 0,
        allowOctaveError: true,
      ),
    );
    final speeds = <double>[];
    controller.onSpeedChanged = speeds.add;
    onsetDetector.attachPitchStream(pitchInput.stream);
    controller.loadScore([
      _note(60, start: 0, end: 0.2),
      _note(64, start: 1, end: 1.2),
    ]);
    controller.start();

    final start = DateTime(2026);
    pitchInput.add(_pitch(72, start));
    await pumpEventQueue();
    pitchInput.add(_pitch(64, start.add(const Duration(seconds: 1))));
    await pumpEventQueue();

    expect(speeds, isNotEmpty);
    expect(speeds.last, 1.0);

    await pitchInput.close();
    onsetDetector.dispose();
    controller.dispose();
  });

  test('关闭八度误差容忍时不会匹配同一音级', () async {
    final pitchInput = StreamController<PitchData>.broadcast();
    final onsetDetector = OnsetDetector();
    final controller = FollowModeController(
      onsetDetector: onsetDetector,
      config: const FollowModeConfig(
        noteMatchTolerance: 0,
        allowOctaveError: false,
      ),
    );
    final speeds = <double>[];
    controller.onSpeedChanged = speeds.add;
    onsetDetector.attachPitchStream(pitchInput.stream);
    controller.loadScore([
      _note(60, start: 0, end: 0.2),
      _note(64, start: 1, end: 1.2),
    ]);
    controller.start();

    final start = DateTime(2026);
    pitchInput.add(_pitch(72, start));
    await pumpEventQueue();
    pitchInput.add(_pitch(64, start.add(const Duration(seconds: 1))));
    await pumpEventQueue();

    expect(speeds, isEmpty);

    await pitchInput.close();
    onsetDetector.dispose();
    controller.dispose();
  });

  test('过滤匹配间隔产生的极端速度异常值', () async {
    final pitchInput = StreamController<PitchData>.broadcast();
    final onsetDetector = OnsetDetector();
    final controller = FollowModeController(
      onsetDetector: onsetDetector,
      config: const FollowModeConfig(
        minMeasuredSpeedFactor: 0.6,
        maxMeasuredSpeedFactor: 1.6,
      ),
    );
    final speeds = <double>[];
    controller.onSpeedChanged = speeds.add;
    onsetDetector.attachPitchStream(pitchInput.stream);
    controller.loadScore([
      _note(60, start: 0, end: 0.2),
      _note(62, start: 1, end: 1.2),
    ]);
    controller.start();

    final start = DateTime(2026);
    pitchInput.add(_pitch(60, start));
    await pumpEventQueue();
    pitchInput.add(_pitch(62, start.add(const Duration(milliseconds: 100))));
    await pumpEventQueue();

    expect(speeds, isEmpty);
    expect(controller.speedFactor, 1.0);

    await pitchInput.close();
    onsetDetector.dispose();
    controller.dispose();
  });

  test('匹配间隔在可信范围内时正常更新速度', () async {
    final pitchInput = StreamController<PitchData>.broadcast();
    final onsetDetector = OnsetDetector();
    final controller = FollowModeController(
      onsetDetector: onsetDetector,
      config: const FollowModeConfig(maxMeasuredSpeedFactor: 2.5),
    );
    final speeds = <double>[];
    controller.onSpeedChanged = speeds.add;
    onsetDetector.attachPitchStream(pitchInput.stream);
    controller.loadScore([
      _note(60, start: 0, end: 0.2),
      _note(62, start: 1, end: 1.2),
    ]);
    controller.start();

    final start = DateTime(2026);
    pitchInput.add(_pitch(60, start));
    await pumpEventQueue();
    pitchInput.add(_pitch(62, start.add(const Duration(milliseconds: 500))));
    await pumpEventQueue();

    expect(speeds, hasLength(1));
    expect(speeds.last, closeTo(1.3, 0.0001));
    expect(controller.speedFactor, closeTo(1.3, 0.0001));

    await pitchInput.close();
    onsetDetector.dispose();
    controller.dispose();
  });

  test('同一 tick 的钢琴和弦按一个起拍处理', () async {
    final pitchInput = StreamController<PitchData>.broadcast();
    final onsetDetector = OnsetDetector();
    final controller = FollowModeController(
      onsetDetector: onsetDetector,
      config: const FollowModeConfig(maxMeasuredSpeedFactor: 2.5),
    );
    final speeds = <double>[];
    controller.onSpeedChanged = speeds.add;
    onsetDetector.attachPitchStream(pitchInput.stream);
    controller.loadScore([
      _note(60, start: 0, end: 0.3),
      _note(64, start: 0, end: 0.5),
      _note(67, start: 0, end: 0.4),
      _note(62, start: 1, end: 1.2),
    ]);
    controller.start();

    final start = DateTime(2026);
    pitchInput.add(_pitch(67, start));
    await pumpEventQueue();
    pitchInput.add(_pitch(60, start.add(const Duration(milliseconds: 15))));
    await pumpEventQueue();
    pitchInput.add(_pitch(64, start.add(const Duration(milliseconds: 30))));
    await pumpEventQueue();
    pitchInput.add(_pitch(62, start.add(const Duration(milliseconds: 800))));
    await pumpEventQueue();

    expect(speeds, hasLength(1));
    expect(speeds.single, closeTo(1.075, 0.0001));

    await pitchInput.close();
    onsetDetector.dispose();
    controller.dispose();
  });

  test('跳过中间音符后按上一次成功匹配音符计算速度', () async {
    final pitchInput = StreamController<PitchData>.broadcast();
    final onsetDetector = OnsetDetector();
    final controller = FollowModeController(
      onsetDetector: onsetDetector,
      config: const FollowModeConfig(noteMatchTolerance: 0),
    );
    final speeds = <double>[];
    controller.onSpeedChanged = speeds.add;
    onsetDetector.attachPitchStream(pitchInput.stream);
    controller.loadScore([
      _note(60, start: 0, end: 0.2),
      _note(62, start: 1, end: 1.2),
      _note(64, start: 2, end: 2.2),
    ]);
    controller.start();

    final start = DateTime(2026);
    pitchInput.add(_pitch(60, start));
    await pumpEventQueue();
    pitchInput.add(_pitch(64, start.add(const Duration(seconds: 2))));
    await pumpEventQueue();

    expect(speeds, hasLength(1));
    expect(speeds.last, 1.0);
    expect(controller.speedFactor, 1.0);

    await pitchInput.close();
    onsetDetector.dispose();
    controller.dispose();
  });

  test('按播放时间恢复后从对应音符继续跟随', () async {
    final pitchInput = StreamController<PitchData>.broadcast();
    final onsetDetector = OnsetDetector();
    final controller = FollowModeController(
      onsetDetector: onsetDetector,
      config: const FollowModeConfig(
        noteMatchTolerance: 0,
        allowOctaveError: false,
      ),
    );
    onsetDetector.attachPitchStream(pitchInput.stream);
    controller.loadScore([
      _note(60, start: 0, end: 0.2),
      _note(61, start: 1, end: 1.2),
      _note(62, start: 2, end: 2.2),
      _note(63, start: 3, end: 3.2),
      _note(64, start: 4, end: 4.2),
      _note(65, start: 5, end: 5.2),
    ]);
    controller.start();
    controller.resumeFromTime(5);

    final start = DateTime(2026);
    pitchInput.add(_pitch(65, start));
    await pumpEventQueue();
    pitchInput.add(_pitch(66, start.add(const Duration(milliseconds: 120))));
    await pumpEventQueue();

    expect(controller.state, FollowModeState.idle);

    await pitchInput.close();
    onsetDetector.dispose();
    controller.dispose();
  });

  test('idle 时按播放时间恢复不会被 start 重置到开头', () async {
    final pitchInput = StreamController<PitchData>.broadcast();
    final onsetDetector = OnsetDetector();
    final controller = FollowModeController(
      onsetDetector: onsetDetector,
      config: const FollowModeConfig(
        noteMatchTolerance: 0,
        allowOctaveError: false,
      ),
    );
    onsetDetector.attachPitchStream(pitchInput.stream);
    controller.loadScore([
      _note(60, start: 0, end: 0.2),
      _note(61, start: 1, end: 1.2),
      _note(62, start: 2, end: 2.2),
      _note(63, start: 3, end: 3.2),
      _note(64, start: 4, end: 4.2),
      _note(65, start: 5, end: 5.2),
    ]);

    controller.resumeFromTime(5);

    final start = DateTime(2026);
    pitchInput.add(_pitch(65, start));
    await pumpEventQueue();
    pitchInput.add(_pitch(66, start.add(const Duration(milliseconds: 120))));
    await pumpEventQueue();

    expect(controller.state, FollowModeState.idle);

    await pitchInput.close();
    onsetDetector.dispose();
    controller.dispose();
  });

  test('按超过曲尾的播放时间恢复会停止跟随', () async {
    final pitchInput = StreamController<PitchData>.broadcast();
    final onsetDetector = OnsetDetector();
    final controller = FollowModeController(onsetDetector: onsetDetector);
    onsetDetector.attachPitchStream(pitchInput.stream);
    controller.loadScore([_note(60, start: 0, end: 0.2)]);
    controller.start();

    controller.resumeFromTime(10);

    expect(controller.state, FollowModeState.idle);

    await pitchInput.close();
    onsetDetector.dispose();
    controller.dispose();
  });

  test('按播放时间恢复到长休止中间时等待下一个 onset', () async {
    final pitchInput = StreamController<PitchData>.broadcast();
    final onsetDetector = OnsetDetector();
    final controller = FollowModeController(onsetDetector: onsetDetector);
    onsetDetector.attachPitchStream(pitchInput.stream);
    controller.loadScore([
      _note(60, start: 0, end: 0.2),
      _note(62, start: 2, end: 2.2),
    ]);
    controller.start();

    controller.resumeFromTime(1);

    expect(controller.state, FollowModeState.waitingForOnset);

    await pitchInput.close();
    onsetDetector.dispose();
    controller.dispose();
  });

  test('连续未匹配达到阈值时请求外部重对齐', () async {
    final pitchInput = StreamController<PitchData>.broadcast();
    final onsetDetector = OnsetDetector();
    final controller = FollowModeController(
      onsetDetector: onsetDetector,
      config: const FollowModeConfig(
        noteMatchTolerance: 0,
        allowOctaveError: false,
        unmatchedThreshold: 2,
      ),
    );
    var realignmentRequests = 0;
    controller.onRealignmentRequested = () => realignmentRequests++;
    onsetDetector.attachPitchStream(pitchInput.stream);
    controller.loadScore([
      _note(60, start: 0, end: 0.2),
      _note(62, start: 1, end: 1.2),
    ]);
    controller.start();

    final start = DateTime(2026);
    pitchInput.add(_pitch(72, start));
    await pumpEventQueue();
    pitchInput.add(_pitch(74, start.add(const Duration(milliseconds: 120))));
    await pumpEventQueue();
    pitchInput.add(_pitch(76, start.add(const Duration(milliseconds: 240))));
    await pumpEventQueue();

    expect(realignmentRequests, 1);

    await pitchInput.close();
    onsetDetector.dispose();
    controller.dispose();
  });

  test('pitch stream 运行时错误会停止跟随并上报', () async {
    final pitchInput = StreamController<PitchData>.broadcast();
    final onsetDetector = OnsetDetector();
    final controller = FollowModeController(onsetDetector: onsetDetector);
    final errors = <Object>[];
    final stackTraces = <StackTrace?>[];
    controller.onRuntimeError = (error, stackTrace) {
      errors.add(error);
      stackTraces.add(stackTrace);
    };
    onsetDetector.attachPitchStream(pitchInput.stream);
    controller.loadScore([_note(60, start: 0, end: 0.2)]);
    controller.start();

    final error = StateError('audio route changed');
    final stackTrace = StackTrace.current;
    pitchInput.addError(error, stackTrace);
    await pumpEventQueue();

    expect(errors, contains(error));
    expect(stackTraces, contains(stackTrace));
    expect(controller.state, FollowModeState.idle);
    expect(controller.isActive, isFalse);

    await pitchInput.close();
    onsetDetector.dispose();
    controller.dispose();
  });
}

MidiNote _note(int noteNumber, {required double start, required double end}) {
  return MidiNote(
    noteNumber: noteNumber,
    velocity: 80,
    channel: 0,
    startTick: (start * 480).round(),
    endTick: (end * 480).round(),
    startTime: start,
    endTime: end,
  );
}

PitchData _pitch(int midiNote, DateTime timestamp) {
  return PitchData(
    frequency: 440,
    midiNote: midiNote,
    noteName: '',
    octave: 4,
    volume: 0.1,
    volumeDbFS: -20,
    precision: 1,
    timestamp: timestamp,
  );
}
