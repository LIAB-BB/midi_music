import 'dart:async';

import 'score_playback_port.dart';
import 'score_renderer_port.dart';
import 'score_renderer_protocol.dart';

enum ScoreMessageHandlingResult { handled, ignored, unmappableMeasure }

/// 在播放位置与谱面渲染器之间同步高亮和跳转。
///
/// 此协调器只依赖两个端口，因此可在不引入 UI、WebView 或具体播放器的前提下
/// 单独测试和逐步接线。
class ScorePlaybackCoordinator {
  final ScorePlaybackPort player;
  final ScoreRendererPort port;
  int? _lastHighlightedOrdinal;
  bool _hasSynchronizedRenderer = false;
  bool _syncPending = false;
  int? _pendingOrdinal;
  bool _pendingScrollIntoView = false;
  bool _resyncAfterPending = false;
  bool _forceAfterPending = false;
  bool _autoFollow = true;
  List<ScoreMeasureRect> _measureRects = const [];

  ScorePlaybackCoordinator({required this.player, required this.port});

  ScoreMessageHandlingResult handleMessage(ScoreRendererMessage message) {
    switch (message.type) {
      case ScoreRendererMessageType.layout:
        _measureRects = message.measureRects;
        return ScoreMessageHandlingResult.handled;
      case ScoreRendererMessageType.gestureEnd:
        final isTap =
            message.gesturePointerCount == 1 &&
            message.gestureTravel <= 10 &&
            message.gestureDurationMs <= 350;
        if (!isTap) {
          _autoFollow = false;
          return ScoreMessageHandlingResult.handled;
        }
        ScoreMeasureRect? hit;
        for (final rect in _measureRects) {
          if (rect.contains(message.tapX!, message.tapY!)) {
            hit = rect;
            break;
          }
        }
        if (hit == null) {
          return ScoreMessageHandlingResult.ignored;
        }
        final ordinal = hit.ordinal;
        final session = player.scoreSession;
        if (session != null &&
            session.isMeasureInteractive(ordinal) &&
            player.seekToMeasure(ordinal)) {
          syncFromPlayer(force: true);
          return ScoreMessageHandlingResult.handled;
        }
        return ScoreMessageHandlingResult.unmappableMeasure;
      case ScoreRendererMessageType.ready:
      case ScoreRendererMessageType.error:
        return ScoreMessageHandlingResult.handled;
    }
  }

  void resumeAutoFollow() => _autoFollow = true;

  void syncFromPlayer({bool force = false}) {
    final ordinal = player.currentMeasureOrdinal;
    if (_syncPending) {
      final matchesPending =
          ordinal == _pendingOrdinal &&
          (ordinal == null || _pendingScrollIntoView == _autoFollow);
      if (!matchesPending || force) {
        _resyncAfterPending = true;
        _forceAfterPending = _forceAfterPending || force;
      }
      return;
    }
    if (!force &&
        _hasSynchronizedRenderer &&
        ordinal == _lastHighlightedOrdinal) {
      return;
    }
    _syncPending = true;
    _pendingOrdinal = ordinal;
    _pendingScrollIntoView = _autoFollow;
    unawaited(
      _sendRendererSync(ordinal, scrollIntoView: _pendingScrollIntoView),
    );
  }

  Future<void> _sendRendererSync(
    int? ordinal, {
    required bool scrollIntoView,
  }) async {
    var succeeded = false;
    try {
      if (ordinal == null) {
        await port.clearHighlight();
      } else {
        await port.highlightMeasure(ordinal, scrollIntoView: scrollIntoView);
      }
      succeeded = true;
    } catch (_) {
      // 渲染器可能暂时不可用；下一次播放器同步会重试。
    } finally {
      if (succeeded) {
        _hasSynchronizedRenderer = true;
        _lastHighlightedOrdinal = ordinal;
      }
      _syncPending = false;
      _pendingOrdinal = null;
      final resync = _resyncAfterPending;
      final force = _forceAfterPending;
      _resyncAfterPending = false;
      _forceAfterPending = false;
      if (resync) {
        syncFromPlayer(force: force);
      }
    }
  }
}
