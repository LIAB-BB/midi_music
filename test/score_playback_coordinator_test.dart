import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_player.dart';
import 'package:midi_music/core/score/score_playback_coordinator.dart';
import 'package:midi_music/core/score/score_renderer_protocol.dart';

import 'helpers/score_renderer_test_fakes.dart';
import 'helpers/score_test_fixtures.dart';

void main() {
  test('Flutter 用上报矩形命中点击并调用统一播放器跳转', () {
    final port = RecordingRendererPort();
    final player = readyPlayer()..loadScore(interactiveSession());
    addTearDown(player.dispose);
    final coordinator = ScorePlaybackCoordinator(player: player, port: port);

    coordinator.handleMessage(
      const ScoreRendererMessage.layout(
        complete: true,
        measureRects: [
          ScoreMeasureRect(
            ordinal: 2,
            left: 0,
            top: 100,
            width: 200,
            height: 80,
          ),
        ],
      ),
    );
    expect(
      coordinator.handleMessage(
        const ScoreRendererMessage.gestureEnd(
          x: 50,
          y: 120,
          travel: 4,
          durationMs: 120,
          pointerCount: 1,
        ),
      ),
      ScoreMessageHandlingResult.handled,
    );

    expect(player.currentMeasureOrdinal, 2);
  });

  test('不可映射的小节点击向页面返回失败且不改变播放器', () {
    final port = RecordingRendererPort();
    final player = readyPlayer()..loadScore(partialSession());
    addTearDown(player.dispose);
    final coordinator = ScorePlaybackCoordinator(player: player, port: port);

    coordinator.handleMessage(
      const ScoreRendererMessage.layout(
        complete: true,
        measureRects: [
          ScoreMeasureRect(
            ordinal: 2,
            left: 0,
            top: 100,
            width: 200,
            height: 80,
          ),
        ],
      ),
    );
    final before = player.currentTime;

    expect(
      coordinator.handleMessage(
        const ScoreRendererMessage.gestureEnd(
          x: 50,
          y: 120,
          travel: 4,
          durationMs: 120,
          pointerCount: 1,
        ),
      ),
      ScoreMessageHandlingResult.unmappableMeasure,
    );
    expect(player.currentMeasureOrdinal, 1);
    expect(player.currentTime, before);
  });

  test('点击只能命中渲染器上报的矩形', () {
    final port = RecordingRendererPort();
    final player = readyPlayer()..loadScore(interactiveSession());
    addTearDown(player.dispose);
    final coordinator = ScorePlaybackCoordinator(player: player, port: port);

    coordinator.handleMessage(
      const ScoreRendererMessage.layout(
        complete: true,
        measureRects: [
          ScoreMeasureRect(
            ordinal: 2,
            left: 0,
            top: 100,
            width: 200,
            height: 80,
          ),
        ],
      ),
    );

    expect(
      coordinator.handleMessage(
        const ScoreRendererMessage.gestureEnd(
          x: 250,
          y: 120,
          travel: 4,
          durationMs: 120,
          pointerCount: 1,
        ),
      ),
      ScoreMessageHandlingResult.ignored,
    );
    expect(player.currentMeasureOrdinal, 1);
  });

  test('相同小节不会重复发送高亮', () async {
    final port = RecordingRendererPort();
    final player = readyPlayer()..loadScore(interactiveSession());
    addTearDown(player.dispose);
    final coordinator = ScorePlaybackCoordinator(player: player, port: port);

    coordinator.syncFromPlayer();
    coordinator.syncFromPlayer();

    expect(port.highlighted, [1]);
    await _drainAsyncCommands();
    coordinator.syncFromPlayer();
    expect(port.highlighted, [1]);
  });

  test('手动浏览暂停自动滚动，恢复跟随后重新滚动', () async {
    final port = RecordingRendererPort();
    final player = readyPlayer()..loadScore(interactiveSession());
    addTearDown(player.dispose);
    final coordinator = ScorePlaybackCoordinator(player: player, port: port);

    coordinator.handleMessage(
      const ScoreRendererMessage.gestureEnd(
        x: 50,
        y: 120,
        travel: 40,
        durationMs: 300,
        pointerCount: 1,
      ),
    );
    player.seekToMeasure(2);
    coordinator.syncFromPlayer();
    expect(port.scrollFlags.last, isFalse);
    await _drainAsyncCommands();

    coordinator.resumeAutoFollow();
    coordinator.syncFromPlayer(force: true);
    expect(port.scrollFlags.last, isTrue);
  });

  test('多指手势只关闭自动跟随且不跳转', () {
    final port = RecordingRendererPort();
    final player = readyPlayer()..loadScore(interactiveSession());
    addTearDown(player.dispose);
    final coordinator = ScorePlaybackCoordinator(player: player, port: port);

    coordinator.handleMessage(
      const ScoreRendererMessage.layout(
        complete: true,
        measureRects: [
          ScoreMeasureRect(
            ordinal: 2,
            left: 0,
            top: 100,
            width: 200,
            height: 80,
          ),
        ],
      ),
    );

    expect(
      coordinator.handleMessage(
        const ScoreRendererMessage.gestureEnd(
          x: 50,
          y: 120,
          travel: 0,
          durationMs: 100,
          pointerCount: 2,
        ),
      ),
      ScoreMessageHandlingResult.handled,
    );
    expect(player.currentMeasureOrdinal, 1);

    player.seekToMeasure(2);
    coordinator.syncFromPlayer();
    expect(port.scrollFlags.single, isFalse);
  });

  test('长按只关闭自动跟随且不跳转', () {
    final port = RecordingRendererPort();
    final player = readyPlayer()..loadScore(interactiveSession());
    addTearDown(player.dispose);
    final coordinator = ScorePlaybackCoordinator(player: player, port: port);

    coordinator.handleMessage(
      const ScoreRendererMessage.layout(
        complete: true,
        measureRects: [
          ScoreMeasureRect(
            ordinal: 2,
            left: 0,
            top: 100,
            width: 200,
            height: 80,
          ),
        ],
      ),
    );

    expect(
      coordinator.handleMessage(
        const ScoreRendererMessage.gestureEnd(
          x: 50,
          y: 120,
          travel: 0,
          durationMs: 351,
          pointerCount: 1,
        ),
      ),
      ScoreMessageHandlingResult.handled,
    );
    expect(player.currentMeasureOrdinal, 1);

    player.seekToMeasure(2);
    coordinator.syncFromPlayer();
    expect(port.scrollFlags.single, isFalse);
  });

  test('高亮失败被消费且可重试，成功后才去重', () async {
    final port = ControllableRendererPort();
    final player = readyPlayer()..loadScore(interactiveSession());
    addTearDown(player.dispose);
    final coordinator = ScorePlaybackCoordinator(player: player, port: port);
    final uncaughtErrors = <Object>[];

    final zoneDone = Completer<void>();
    unawaited(
      runZonedGuarded(
        () async {
          coordinator.syncFromPlayer();
          coordinator.syncFromPlayer();
          expect(port.highlighted, [1]);

          port.highlightCompleters.single.completeError(StateError('failed'));
          await _drainAsyncCommands();
          coordinator.syncFromPlayer();
          expect(port.highlighted, [1, 1]);

          port.highlightCompleters.last.complete();
          await _drainAsyncCommands();
          coordinator.syncFromPlayer();
          expect(port.highlighted, [1, 1]);
          zoneDone.complete();
        },
        (error, stackTrace) {
          uncaughtErrors.add(error);
          if (!zoneDone.isCompleted) {
            zoneDone.complete();
          }
        },
      ),
    );

    await zoneDone.future;
    expect(uncaughtErrors, isEmpty);
  });

  test('空状态清除高亮去重，失败后可重试', () async {
    final port = ControllableRendererPort();
    final player = _MutableMeasurePlayer();
    final coordinator = ScorePlaybackCoordinator(player: player, port: port);
    final uncaughtErrors = <Object>[];

    final zoneDone = Completer<void>();
    unawaited(
      runZonedGuarded(
        () async {
          player.measureOrdinal = 1;
          coordinator.syncFromPlayer();
          port.highlightCompleters.single.complete();
          await _drainAsyncCommands();

          player.measureOrdinal = null;
          coordinator.syncFromPlayer();
          coordinator.syncFromPlayer();
          expect(port.clearCount, 1);

          port.clearCompleters.single.completeError(StateError('failed'));
          await _drainAsyncCommands();
          coordinator.syncFromPlayer();
          expect(port.clearCount, 2);

          port.clearCompleters.last.complete();
          await _drainAsyncCommands();
          coordinator.syncFromPlayer();
          expect(port.clearCount, 2);
          zoneDone.complete();
        },
        (error, stackTrace) {
          uncaughtErrors.add(error);
          if (!zoneDone.isCompleted) {
            zoneDone.complete();
          }
        },
      ),
    );

    await zoneDone.future;
    expect(uncaughtErrors, isEmpty);
  });

  test('首次空状态只清除一次高亮', () async {
    final port = RecordingRendererPort();
    final player = readyPlayer();
    addTearDown(player.dispose);
    final coordinator = ScorePlaybackCoordinator(player: player, port: port);

    coordinator.syncFromPlayer();
    coordinator.syncFromPlayer();
    await _drainAsyncCommands();
    coordinator.syncFromPlayer();

    expect(port.clearCount, 1);
    expect(port.highlighted, isEmpty);
  });
}

Future<void> _drainAsyncCommands() async {
  await Future<void>.value();
  await Future<void>.value();
}

class _MutableMeasurePlayer extends MidiPlayerController {
  int? measureOrdinal;

  @override
  int? get currentMeasureOrdinal => measureOrdinal;
}
