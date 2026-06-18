import 'dart:async';

class PlaybackTimerBenchmarkConfig {
  final Duration interval;
  final int samples;
  final Duration busyWorkPerTick;

  const PlaybackTimerBenchmarkConfig({
    this.interval = const Duration(milliseconds: 5),
    this.samples = 200,
    this.busyWorkPerTick = Duration.zero,
  });
}

class PlaybackTimerBenchmarkResult {
  final Duration targetInterval;
  final int sampleCount;
  final double averageIntervalMicros;
  final int maxIntervalMicros;
  final double averageErrorMicros;
  final int maxErrorMicros;
  final Duration busyWorkPerTick;

  const PlaybackTimerBenchmarkResult({
    required this.targetInterval,
    required this.sampleCount,
    required this.averageIntervalMicros,
    required this.maxIntervalMicros,
    required this.averageErrorMicros,
    required this.maxErrorMicros,
    required this.busyWorkPerTick,
  });

  @override
  String toString() {
    return 'samples=$sampleCount, '
        'target=${targetInterval.inMicroseconds}us, '
        'busy=${busyWorkPerTick.inMicroseconds}us, '
        'avgInterval=${averageIntervalMicros.toStringAsFixed(1)}us, '
        'maxInterval=${maxIntervalMicros}us, '
        'avgError=${averageErrorMicros.toStringAsFixed(1)}us, '
        'maxError=${maxErrorMicros}us';
  }
}

Future<PlaybackTimerBenchmarkResult> runPlaybackTimerBenchmark(
  PlaybackTimerBenchmarkConfig config,
) {
  final completer = Completer<PlaybackTimerBenchmarkResult>();
  final stopwatch = Stopwatch()..start();
  final intervals = <int>[];
  final errors = <int>[];
  final targetMicros = config.interval.inMicroseconds;
  var lastTickMicros = stopwatch.elapsedMicroseconds;

  late final Timer timer;
  timer = Timer.periodic(config.interval, (_) {
    final nowMicros = stopwatch.elapsedMicroseconds;
    final actualInterval = nowMicros - lastTickMicros;
    lastTickMicros = nowMicros;
    intervals.add(actualInterval);
    errors.add((actualInterval - targetMicros).abs());

    _runBusyWork(config.busyWorkPerTick);

    if (intervals.length >= config.samples) {
      timer.cancel();
      stopwatch.stop();
      completer.complete(
        PlaybackTimerBenchmarkResult(
          targetInterval: config.interval,
          sampleCount: intervals.length,
          averageIntervalMicros: _average(intervals),
          maxIntervalMicros: _max(intervals),
          averageErrorMicros: _average(errors),
          maxErrorMicros: _max(errors),
          busyWorkPerTick: config.busyWorkPerTick,
        ),
      );
    }
  });

  return completer.future;
}

void _runBusyWork(Duration duration) {
  if (duration <= Duration.zero) return;
  final stopwatch = Stopwatch()..start();
  var value = 0;
  while (stopwatch.elapsedMicroseconds < duration.inMicroseconds) {
    value = (value + 1) & 0x7fffffff;
  }
  if (value == -1) {
    throw StateError('unreachable');
  }
}

double _average(List<int> values) {
  if (values.isEmpty) return 0.0;
  var sum = 0;
  for (final value in values) {
    sum += value;
  }
  return sum / values.length;
}

int _max(List<int> values) {
  if (values.isEmpty) return 0;
  var maxValue = values.first;
  for (final value in values.skip(1)) {
    if (value > maxValue) {
      maxValue = value;
    }
  }
  return maxValue;
}
