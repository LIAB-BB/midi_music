import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_parser.dart';
import 'package:midi_music/core/notation/piece_score_alignment.dart';
import 'package:midi_music/core/score/piece_manifest.dart';
import 'package:midi_music/ui/widgets/k478_measure_rail.dart';

void main() {
  late PieceScoreAlignment alignment;

  setUpAll(() {
    final bytes = File(
      'assets/midi/mozart_k478_piano_quartet.mid',
    ).readAsBytesSync();
    final manifest = PieceManifest.parse(
      File('assets/pieces/k478.json').readAsStringSync(),
    );
    alignment = PieceScoreAlignment.compile(
      MidiFileParser().parseBytes(
        bytes,
        fileName: 'mozart_k478_piano_quartet.mid',
      ),
      manifest,
    );
  });

  testWidgets('点小节会请求跳到该小节', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: K478MeasureRail(
            alignment: alignment,
            currentOrdinal: 1,
            onMeasureSelected: selected.add,
          ),
        ),
      ),
    );

    expect(find.text('第 1 小节'), findsOneWidget);
    await tester.tap(find.byKey(const Key('k478-measure-2')));
    await tester.pump();

    expect(selected, [2]);
  });

  testWidgets('跟随进行中不接受小节点选', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: K478MeasureRail(alignment: alignment, currentOrdinal: 3),
        ),
      ),
    );

    expect(find.text('第 3 小节'), findsOneWidget);
    expect(find.textContaining('跟随进行中'), findsOneWidget);
    final button = tester.widget<CupertinoButton>(
      find.byKey(const Key('k478-measure-3')),
    );
    expect(button.onPressed, isNull);
  });
}
