class ScorePosition implements Comparable<ScorePosition> {
  final int measureNumber;
  final double beat;
  final double absoluteBeat;

  const ScorePosition({
    required this.measureNumber,
    required this.beat,
    required this.absoluteBeat,
  });

  const ScorePosition.absolute(this.beat)
    : measureNumber = 0,
      absoluteBeat = beat;

  ScorePosition shift(double beatDelta) {
    return ScorePosition.absolute(absoluteBeat + beatDelta);
  }

  bool isAtAbsoluteBeat(double value, {double tolerance = 0.000001}) {
    return (absoluteBeat - value).abs() <= tolerance;
  }

  @override
  int compareTo(ScorePosition other) {
    return absoluteBeat.compareTo(other.absoluteBeat);
  }
}
