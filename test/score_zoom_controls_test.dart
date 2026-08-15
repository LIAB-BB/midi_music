import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/ui/widgets/score_zoom_controls.dart';

void main() {
  testWidgets('显示整数百分比并提供可访问的缩放按钮', (tester) async {
    var zoomOutCount = 0;
    var zoomInCount = 0;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: ScoreZoomControls(
            zoom: 0.7,
            onZoomOut: () => zoomOutCount += 1,
            onZoomIn: () => zoomInCount += 1,
          ),
        ),
      ),
    );

    expect(find.text('70%'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const Key('score-zoom-out'))),
      matchesSemantics(
        label: '缩小乐谱',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('score-zoom-in'))),
      matchesSemantics(
        label: '放大乐谱',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSize(find.byKey(const Key('score-zoom-out'))),
      const Size(44, 44),
    );
    expect(
      tester.getSize(find.byKey(const Key('score-zoom-in'))),
      const Size(44, 44),
    );

    await tester.tap(find.byKey(const Key('score-zoom-out')));
    await tester.tap(find.byKey(const Key('score-zoom-in')));
    expect(zoomOutCount, 1);
    expect(zoomInCount, 1);
    semantics.dispose();
  });

  testWidgets('最小和最大比例禁用对应方向且布局不跳动', (tester) async {
    var zoom = ScoreZoomControls.minZoom;

    Widget build() => CupertinoApp(
      home: Center(
        child: ScoreZoomControls(zoom: zoom, onZoomOut: () {}, onZoomIn: () {}),
      ),
    );

    await tester.pumpWidget(build());
    final minSize = tester.getSize(find.byType(ScoreZoomControls));
    expect(find.text('50%'), findsOneWidget);
    expect(
      tester
          .widget<CupertinoButton>(
            find.descendant(
              of: find.byKey(const Key('score-zoom-out')),
              matching: find.byType(CupertinoButton),
            ),
          )
          .onPressed,
      isNull,
    );

    zoom = ScoreZoomControls.maxZoom;
    await tester.pumpWidget(build());
    expect(find.text('140%'), findsOneWidget);
    expect(tester.getSize(find.byType(ScoreZoomControls)), minSize);
    expect(
      tester
          .widget<CupertinoButton>(
            find.descendant(
              of: find.byKey(const Key('score-zoom-in')),
              matching: find.byType(CupertinoButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });
}
