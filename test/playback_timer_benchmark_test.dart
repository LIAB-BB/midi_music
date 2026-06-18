import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/playback_timer_benchmark.dart';

void main() {
  test('Timer benchmark 生成 interval 误差基线数据', () async {
    final result = await runPlaybackTimerBenchmark(
      const PlaybackTimerBenchmarkConfig(
        interval: Duration(milliseconds: 1),
        samples: 3,
      ),
    );

    expect(result.sampleCount, 3);
    expect(result.averageIntervalMicros, greaterThan(0));
    expect(result.maxIntervalMicros, greaterThan(0));
    expect(result.averageErrorMicros, greaterThanOrEqualTo(0));
  });
}
