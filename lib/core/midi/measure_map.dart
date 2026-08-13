import '../../models/midi_track.dart';
import '../../models/score_session.dart';
import 'tempo_map.dart';

/// 小节信息，按 MIDI tick 派生而来。
class MeasureInfo {
  final int number;
  final String label;
  final int startTick;
  final int endTick;
  final double startTime;
  final double endTime;
  final int numerator;
  final int denominator;
  final bool isInteractive;

  const MeasureInfo({
    required this.number,
    required this.label,
    required this.startTick,
    required this.endTick,
    required this.startTime,
    required this.endTime,
    required this.numerator,
    required this.denominator,
    this.isInteractive = true,
  });

  int get lengthTick => endTick - startTick;

  int beatLengthTick(int ticksPerBeat) =>
      (ticksPerBeat * 4 / denominator).round().clamp(1, 1 << 30);
}

/// 当前播放位置对应的小节/拍。
class MeasurePosition {
  final int measureNumber;
  final int beatNumber;
  final int tick;
  final double time;

  const MeasurePosition({
    required this.measureNumber,
    required this.beatNumber,
    required this.tick,
    required this.time,
  });
}

/// 从 MIDI 的 tempo / 拍号信息派生小节导航能力。
class MeasureMap {
  final MidiSongData song;
  final TempoMap tempoMap;
  final List<ScoreMeasureBoundary> scoreMeasures;
  late final List<MeasureInfo> _measures = _buildMeasures();

  MeasureMap({
    required this.song,
    required this.tempoMap,
    this.scoreMeasures = const [],
  });

  List<MeasureInfo> get measures => List.unmodifiable(_measures);

  MeasurePosition timeToMeasureBeat(double seconds) {
    final safeSeconds = seconds.clamp(0.0, song.totalDuration);
    final tick = tempoMap.secondsToTick(safeSeconds).clamp(0, song.totalTicks);
    final measure = _measureAtTick(tick);
    final beatLength = measure.beatLengthTick(song.ticksPerBeat);
    final beatOffset = ((tick - measure.startTick) / beatLength).floor();
    final beatNumber = (beatOffset + 1).clamp(1, measure.numerator);
    return MeasurePosition(
      measureNumber: measure.number,
      beatNumber: beatNumber,
      tick: tick,
      time: safeSeconds,
    );
  }

  double measureToTime(int measureNumber) {
    final measure = _measureByNumber(measureNumber);
    return measure.startTime;
  }

  double? tryMeasureToTime(int ordinal) {
    for (final measure in _measures) {
      if (measure.number == ordinal && measure.isInteractive) {
        return measure.startTime;
      }
    }
    return null;
  }

  int? previousInteractiveOrdinal(int ordinal) {
    for (var index = _measures.length - 1; index >= 0; index--) {
      final measure = _measures[index];
      if (measure.number < ordinal && measure.isInteractive) {
        return measure.number;
      }
    }
    return null;
  }

  int? nextInteractiveOrdinal(int ordinal) {
    for (final measure in _measures) {
      if (measure.number > ordinal && measure.isInteractive) {
        return measure.number;
      }
    }
    return null;
  }

  int measureToTick(int measureNumber) {
    final measure = _measureByNumber(measureNumber);
    return measure.startTick;
  }

  double nearestMeasureStart(double seconds) {
    final tick = tempoMap.secondsToTick(seconds).clamp(0, song.totalTicks);
    final measure = _measureAtTick(tick);
    final previousDistance = (tick - measure.startTick).abs();
    final next = measure.number < _measures.length
        ? _measures[measure.number]
        : null;
    if (next == null) return measure.startTime;
    final nextDistance = (next.startTick - tick).abs();
    return nextDistance < previousDistance ? next.startTime : measure.startTime;
  }

  double previousMeasureStart(double seconds) {
    final tick = tempoMap.secondsToTick(seconds).clamp(0, song.totalTicks);
    final measure = _measureAtTick(tick);
    final index = (measure.number - 2).clamp(0, _measures.length - 1);
    return _measures[index].startTime;
  }

  double nextMeasureStart(double seconds) {
    final tick = tempoMap.secondsToTick(seconds).clamp(0, song.totalTicks);
    final measure = _measureAtTick(tick);
    final index = measure.number.clamp(0, _measures.length - 1);
    return _measures[index].startTime;
  }

  MeasureInfo _measureByNumber(int measureNumber) {
    final index = (measureNumber - 1).clamp(0, _measures.length - 1);
    return _measures[index];
  }

  MeasureInfo _measureAtTick(int tick) {
    var low = 0;
    var high = _measures.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_measures[mid].startTick <= tick) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return _measures[low];
  }

  List<MeasureInfo> _buildMeasures() {
    if (scoreMeasures.isNotEmpty) {
      return scoreMeasures
          .map((boundary) {
            final signature = _signatureAt(boundary.startTick);
            return MeasureInfo(
              number: boundary.ordinal,
              label: boundary.label,
              startTick: boundary.startTick,
              endTick: boundary.endTick,
              startTime: tempoMap.tickToSeconds(boundary.startTick),
              endTime: tempoMap.tickToSeconds(boundary.endTick),
              numerator: signature.numerator,
              denominator: signature.denominator,
              isInteractive: boundary.isInteractive,
            );
          })
          .toList(growable: false);
    }

    final signatures = _normalizedTimeSignatures();
    final measures = <MeasureInfo>[];
    var signatureIndex = 0;
    var currentTick = 0;
    var measureNumber = 1;
    final totalTicks = song.totalTicks <= 0
        ? song.ticksPerBeat * 4
        : song.totalTicks;

    while (currentTick < totalTicks || measures.isEmpty) {
      while (signatureIndex < signatures.length - 1 &&
          signatures[signatureIndex + 1].tick <= currentTick) {
        signatureIndex++;
      }

      final signature = signatures[signatureIndex];
      final naturalLength = _measureLengthTicks(
        numerator: signature.numerator,
        denominator: signature.denominator,
      );
      final nextSignatureTick = signatureIndex < signatures.length - 1
          ? signatures[signatureIndex + 1].tick
          : totalTicks;
      final endTick = (currentTick + naturalLength).clamp(
        currentTick + 1,
        nextSignatureTick > currentTick ? nextSignatureTick : totalTicks,
      );

      measures.add(
        MeasureInfo(
          number: measureNumber,
          label: '$measureNumber',
          startTick: currentTick,
          endTick: endTick,
          startTime: tempoMap.tickToSeconds(currentTick),
          endTime: tempoMap.tickToSeconds(endTick),
          numerator: signature.numerator,
          denominator: signature.denominator,
        ),
      );
      currentTick = endTick;
      measureNumber++;
    }
    return measures;
  }

  List<TimeSignatureChange> _normalizedTimeSignatures() {
    final sorted = List<TimeSignatureChange>.from(song.timeSignatureChanges)
      ..sort((a, b) => a.tick.compareTo(b.tick));
    if (sorted.isEmpty || sorted.first.tick > 0) {
      sorted.insert(
        0,
        TimeSignatureChange(tick: 0, numerator: 4, denominator: 4),
      );
    }
    return sorted;
  }

  TimeSignatureChange _signatureAt(int tick) {
    final signatures = _normalizedTimeSignatures();
    var signature = signatures.first;
    for (final candidate in signatures.skip(1)) {
      if (candidate.tick > tick) break;
      signature = candidate;
    }
    return signature;
  }

  int _measureLengthTicks({required int numerator, required int denominator}) {
    final safeNumerator = numerator <= 0 ? 4 : numerator;
    final safeDenominator = denominator <= 0 ? 4 : denominator;
    return (song.ticksPerBeat * safeNumerator * 4 / safeDenominator)
        .round()
        .clamp(1, 1 << 30);
  }
}
