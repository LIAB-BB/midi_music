import 'dart:io';

import 'package:midi_music/core/midi/playback_timer_benchmark.dart';

Future<void> main(List<String> args) async {
  final samples = _readIntArg(args, 'samples') ?? 200;
  final normal = await runPlaybackTimerBenchmark(
    PlaybackTimerBenchmarkConfig(samples: samples),
  );
  final highLoad = await runPlaybackTimerBenchmark(
    PlaybackTimerBenchmarkConfig(
      samples: samples,
      busyWorkPerTick: const Duration(milliseconds: 8),
    ),
  );

  stdout.writeln('Timer.periodic(5ms) benchmark');
  stdout.writeln('normal: $normal');
  stdout.writeln('high-load: $highLoad');
}

int? _readIntArg(List<String> args, String name) {
  final prefix = '--$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) {
      return int.tryParse(arg.substring(prefix.length));
    }
  }
  return null;
}
