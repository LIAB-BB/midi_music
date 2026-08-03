import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:midi_music/ui/widgets/pdf_score_viewer.dart';

void main() {
  testWidgets('PDF 分谱阅读器可以翻页', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: CupertinoPageScaffold(
          child: Center(
            child: SizedBox(
              width: 360,
              height: 520,
              child: PdfScoreViewer(
                pageAssetPrefix: 'assets/scores/mozart_k478_piano_part/page',
                pageCount: 21,
                label: '公版 PDF 钢琴分谱',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('1 / 21'), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('2 / 21'), findsOneWidget);
  });
}
