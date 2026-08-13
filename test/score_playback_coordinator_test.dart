import 'package:flutter_test/flutter_test.dart';
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

  test('相同小节不会重复发送高亮', () {
    final port = RecordingRendererPort();
    final player = readyPlayer()..loadScore(interactiveSession());
    addTearDown(player.dispose);
    final coordinator = ScorePlaybackCoordinator(player: player, port: port);

    coordinator.syncFromPlayer();
    coordinator.syncFromPlayer();

    expect(port.highlighted, [1]);
  });

  test('手动浏览暂停自动滚动，恢复跟随后重新滚动', () {
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

    coordinator.resumeAutoFollow();
    coordinator.syncFromPlayer(force: true);
    expect(port.scrollFlags.last, isTrue);
  });

  test('多指或长按只关闭自动跟随且不跳转', () {
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

  test('无当前小节时清除高亮', () {
    final port = RecordingRendererPort();
    final player = readyPlayer();
    addTearDown(player.dispose);
    final coordinator = ScorePlaybackCoordinator(player: player, port: port);

    coordinator.syncFromPlayer();

    expect(port.clearCount, 1);
    expect(port.highlighted, isEmpty);
  });
}
