import 'dart:convert';

import 'package:flutter/foundation.dart';

enum ScoreRendererMessageType { ready, layout, gestureEnd, error }

class ScoreMeasureRect {
  final int ordinal;
  final double left;
  final double top;
  final double width;
  final double height;

  const ScoreMeasureRect({
    required this.ordinal,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  bool contains(double x, double y) =>
      x >= left && x <= left + width && y >= top && y <= top + height;

  @override
  bool operator ==(Object other) =>
      other is ScoreMeasureRect &&
      ordinal == other.ordinal &&
      left == other.left &&
      top == other.top &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(ordinal, left, top, width, height);
}

class ScoreRendererMessage {
  final ScoreRendererMessageType type;
  final double? tapX;
  final double? tapY;
  final double gestureTravel;
  final int gestureDurationMs;
  final int gesturePointerCount;
  final List<ScoreMeasureRect> measureRects;
  final String? errorMessage;
  final bool layoutComplete;

  const ScoreRendererMessage._(
    this.type, {
    this.tapX,
    this.tapY,
    this.gestureTravel = 0,
    this.gestureDurationMs = 0,
    this.gesturePointerCount = 0,
    this.measureRects = const [],
    this.errorMessage,
    this.layoutComplete = false,
  });

  const ScoreRendererMessage.gestureEnd({
    required double x,
    required double y,
    required double travel,
    required int durationMs,
    required int pointerCount,
  }) : this._(
         ScoreRendererMessageType.gestureEnd,
         tapX: x,
         tapY: y,
         gestureTravel: travel,
         gestureDurationMs: durationMs,
         gesturePointerCount: pointerCount,
       );

  const ScoreRendererMessage.ready() : this._(ScoreRendererMessageType.ready);

  const ScoreRendererMessage.layout({
    required bool complete,
    required List<ScoreMeasureRect> measureRects,
  }) : this._(
         ScoreRendererMessageType.layout,
         layoutComplete: complete,
         measureRects: measureRects,
       );

  const ScoreRendererMessage.error(String message)
    : this._(ScoreRendererMessageType.error, errorMessage: message);

  static ScoreRendererMessage parse(String raw) {
    if (utf8.encode(raw).length > 2 * 1024 * 1024) {
      throw const FormatException('Renderer message too large');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Renderer message must be an object');
    }
    final json = Map<String, Object?>.from(decoded);
    return switch (json['type']) {
      'ready' => const ScoreRendererMessage.ready(),
      'layout' => _parseLayout(json),
      'gestureEnd' => _parseGestureEnd(json),
      'error' => _parseError(json['message']),
      _ => throw const FormatException('Unknown renderer message'),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ScoreRendererMessage &&
      type == other.type &&
      tapX == other.tapX &&
      tapY == other.tapY &&
      gestureTravel == other.gestureTravel &&
      gestureDurationMs == other.gestureDurationMs &&
      gesturePointerCount == other.gesturePointerCount &&
      listEquals(measureRects, other.measureRects) &&
      errorMessage == other.errorMessage &&
      layoutComplete == other.layoutComplete;

  @override
  int get hashCode => Object.hash(
    type,
    tapX,
    tapY,
    gestureTravel,
    gestureDurationMs,
    gesturePointerCount,
    Object.hashAll(measureRects),
    errorMessage,
    layoutComplete,
  );
}

ScoreRendererMessage _parseGestureEnd(Map<String, Object?> json) {
  final x = _boundedDouble(json['x'], minimum: 0, maximum: 10000000);
  final y = _boundedDouble(json['y'], minimum: 0, maximum: 10000000);
  final travel = _boundedDouble(json['travel'], minimum: 0, maximum: 10000000);
  final durationMs = _boundedInt(
    json['durationMs'],
    minimum: 0,
    maximum: 60000,
  );
  final pointerCount = _boundedInt(
    json['pointerCount'],
    minimum: 1,
    maximum: 10,
  );
  return ScoreRendererMessage.gestureEnd(
    x: x,
    y: y,
    travel: travel,
    durationMs: durationMs,
    pointerCount: pointerCount,
  );
}

ScoreRendererMessage _parseLayout(Map<String, Object?> json) {
  final complete = json['complete'];
  final measures = json['measures'];
  if (complete is! bool || measures is! List || measures.length > 10000) {
    throw const FormatException('Invalid renderer layout');
  }

  final ordinals = <int>{};
  final measureRects = <ScoreMeasureRect>[];
  for (final measure in measures) {
    if (measure is! Map) {
      throw const FormatException('Invalid measure rectangle');
    }
    final rectJson = Map<String, Object?>.from(measure);
    final ordinal = _boundedInt(
      rectJson['ordinal'],
      minimum: 1,
      maximum: 100000,
    );
    if (!ordinals.add(ordinal)) {
      throw const FormatException('Duplicate measure ordinal');
    }
    measureRects.add(
      ScoreMeasureRect(
        ordinal: ordinal,
        left: _boundedDouble(rectJson['left'], minimum: 0, maximum: 10000000),
        top: _boundedDouble(rectJson['top'], minimum: 0, maximum: 10000000),
        width: _boundedDouble(
          rectJson['width'],
          minimum: 0,
          maximum: 10000000,
          minimumExclusive: true,
        ),
        height: _boundedDouble(
          rectJson['height'],
          minimum: 0,
          maximum: 10000000,
          minimumExclusive: true,
        ),
      ),
    );
  }

  return ScoreRendererMessage.layout(
    complete: complete,
    measureRects: List<ScoreMeasureRect>.unmodifiable(measureRects),
  );
}

ScoreRendererMessage _parseError(Object? value) {
  if (value is! String || value.isEmpty || value.length > 500) {
    throw const FormatException('Invalid renderer error');
  }
  return ScoreRendererMessage.error(value);
}

int _boundedInt(Object? value, {required int minimum, required int maximum}) {
  if (value is! int || value < minimum || value > maximum) {
    throw const FormatException('Invalid renderer integer');
  }
  return value;
}

double _boundedDouble(
  Object? value, {
  required double minimum,
  required double maximum,
  bool minimumExclusive = false,
}) {
  if (value is! num) {
    throw const FormatException('Invalid renderer number');
  }
  final number = value.toDouble();
  final belowMinimum = minimumExclusive ? number <= minimum : number < minimum;
  if (!number.isFinite || belowMinimum || number > maximum) {
    throw const FormatException('Invalid renderer number');
  }
  return number;
}
