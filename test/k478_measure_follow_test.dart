import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_parser.dart';
import 'package:midi_music/core/notation/k478_score_alignment.dart';
import 'package:midi_music/core/score/k478_measure_follow.dart';

void main() {
  late K478ScoreAlignment alignment;

  setUpAll(() {
    final bytes = File(
      'assets/midi/mozart_k478_piano_quartet.mid',
    ).readAsBytesSync();
    final song = MidiFileParser().parseBytes(
      bytes,
      fileName: 'mozart_k478_piano_quartet.mid',
    );
    alignment = K478ScoreAlignment.compile(song);
  });

  test('播放时间落在对应小节，曲尾停在最后一小节', () {
    final seeks = <double>[];
    final follow = K478MeasureFollow(
      alignment: alignment,
      seekToTime: (seconds) {
        seeks.add(seconds);
        return true;
      },
    );

    expect(follow.currentMeasureOrdinal, 1);
    expect(follow.ordinalAt(follow.timeForMeasure(2)), 2);
    expect(follow.ordinalAt(follow.timeForMeasure(2) - 0.01), 1);
    expect(follow.ordinalAt(99999), alignment.measures.length);

    expect(follow.seekToMeasure(0), isFalse);
    expect(seeks, isEmpty);
    expect(follow.currentMeasureOrdinal, 1);

    expect(follow.seekToMeasure(10), isTrue);
    expect(seeks.single, closeTo(follow.timeForMeasure(10), 0.0001));
    expect(follow.currentMeasureOrdinal, 10);
  });

  test('跳转被播放器拒绝时不改变当前小节', () {
    final follow = K478MeasureFollow(
      alignment: alignment,
      seekToTime: (_) => false,
    );

    expect(follow.seekToMeasure(4), isFalse);
    expect(follow.currentMeasureOrdinal, 1);
  });
}
