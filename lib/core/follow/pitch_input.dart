import 'onset_detector.dart';

abstract class PitchInput {
  Stream<PitchData> get pitchStream;

  Future<void> start({
    int sampleRate = 44100,
    int bufferSize = 8192,
    double minPrecision = 0.7,
  });

  Future<void> dispose();
}
