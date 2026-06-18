import '../score/score_position.dart';

enum TrackingStatus { idle, tracking, lowConfidence, recovering, lost }

class ScoreTrackingState {
  final ScorePosition scorePosition;
  final double tempo;
  final double confidence;
  final TrackingStatus status;
  final DateTime? lastReliableMatch;

  const ScoreTrackingState({
    required this.scorePosition,
    required this.tempo,
    required this.confidence,
    required this.status,
    this.lastReliableMatch,
  });

  ScoreTrackingState copyWith({
    ScorePosition? scorePosition,
    double? tempo,
    double? confidence,
    TrackingStatus? status,
    DateTime? lastReliableMatch,
  }) {
    return ScoreTrackingState(
      scorePosition: scorePosition ?? this.scorePosition,
      tempo: tempo ?? this.tempo,
      confidence: confidence ?? this.confidence,
      status: status ?? this.status,
      lastReliableMatch: lastReliableMatch ?? this.lastReliableMatch,
    );
  }
}
