import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/score/score_renderer_protocol.dart';
import 'package:midi_music/ui/widgets/interactive_score_view.dart';

import 'helpers/score_renderer_test_fakes.dart';

void main() {
  testWidgets('没有 MusicXML 时不创建 WebView', (tester) async {
    var importCount = 0;

    await tester.pumpWidget(
      CupertinoApp(
        home: InteractiveScoreView(
          musicXml: null,
          onMessage: (_) {},
          onImportMusicXml: () => importCount += 1,
        ),
      ),
    );

    expect(find.byKey(const Key('interactive-score-webview')), findsNothing);
    expect(find.text('仅伴奏'), findsOneWidget);
    expect(find.text('导入对应 MusicXML 以显示可交互乐谱'), findsOneWidget);

    await tester.tap(find.text('导入 MusicXML'));
    expect(importCount, 1);
  });

  testWidgets('加载中和就绪状态有稳定语义', (tester) async {
    final port = RecordingRendererPort();
    final received = <ScoreRendererMessage>[];
    late ValueChanged<ScoreRendererMessage> emit;

    await tester.pumpWidget(
      CupertinoApp(
        home: InteractiveScoreView(
          musicXml: '<score-partwise/>',
          onMessage: received.add,
          surfaceFactory: (onMessage) {
            emit = onMessage;
            return ScoreSurface(
              port: port,
              child: const SizedBox(key: Key('fake-score-surface')),
            );
          },
        ),
      ),
    );

    expect(find.byKey(const Key('fake-score-surface')), findsOneWidget);
    expect(find.text('正在排版乐谱'), findsOneWidget);

    emit(const ScoreRendererMessage.ready());
    await tester.pump();

    expect(find.text('正在排版乐谱'), findsNothing);
    expect(received, [const ScoreRendererMessage.ready()]);
  });

  testWidgets('错误消息经统一验收后显示原因和重新导入', (tester) async {
    final port = RecordingRendererPort();
    final received = <ScoreRendererMessage>[];
    late ValueChanged<ScoreRendererMessage> emit;
    var importCount = 0;

    await tester.pumpWidget(
      CupertinoApp(
        home: InteractiveScoreView(
          musicXml: '<score-partwise/>',
          onMessage: received.add,
          onImportMusicXml: () => importCount += 1,
          surfaceFactory: (onMessage) {
            emit = onMessage;
            return ScoreSurface(
              port: port,
              child: const SizedBox(key: Key('fake-score-surface')),
            );
          },
        ),
      ),
    );

    emit(const ScoreRendererMessage.error('谱面解析失败'));
    await tester.pump();

    expect(find.text('谱面解析失败'), findsOneWidget);
    expect(find.text('重新导入'), findsOneWidget);
    expect(received, [const ScoreRendererMessage.error('谱面解析失败')]);

    await tester.tap(find.text('重新导入'));
    expect(importCount, 1);
  });

  testWidgets('工厂端口交付后初始加载一次且仅在 XML 变化时重载', (tester) async {
    final port = RecordingRendererPort();
    final readyPorts = <Object>[];

    Widget build(String xml) => CupertinoApp(
      home: InteractiveScoreView(
        musicXml: xml,
        onMessage: (_) {},
        onPortReady: readyPorts.add,
        surfaceFactory: (_) => ScoreSurface(
          port: port,
          child: const SizedBox(key: Key('fake-score-surface')),
        ),
      ),
    );

    await tester.pumpWidget(build('<score-partwise id="one"/>'));
    await tester.pump();
    expect(readyPorts, [same(port)]);
    expect(port.loadedXml, ['<score-partwise id="one"/>']);

    await tester.pumpWidget(build('<score-partwise id="one"/>'));
    await tester.pump();
    expect(port.loadedXml, hasLength(1));

    await tester.pumpWidget(build('<score-partwise id="two"/>'));
    await tester.pump();
    expect(port.loadedXml, [
      '<score-partwise id="one"/>',
      '<score-partwise id="two"/>',
    ]);
  });
}
