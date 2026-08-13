import 'dart:async';

import '../midi/midi_player.dart';
import 'score_renderer_protocol.dart';

abstract class ScoreRendererPort {
  Future<void> loadMusicXml(String musicXml);

  Future<void> highlightMeasure(int ordinal, {required bool scrollIntoView});

  Future<void> clearHighlight();
}

enum ScoreMessageHandlingResult { handled, ignored, unmappableMeasure }

class ScorePlaybackCoordinator {
  final MidiPlayerController player;
  final ScoreRendererPort port;
  int? _lastHighlightedOrdinal;
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
    if (ordinal == null) {
      unawaited(port.clearHighlight());
      return;
    }
    if (!force && ordinal == _lastHighlightedOrdinal) {
      return;
    }
    _lastHighlightedOrdinal = ordinal;
    unawaited(port.highlightMeasure(ordinal, scrollIntoView: _autoFollow));
  }
}
