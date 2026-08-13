import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/score/score_renderer_protocol.dart';
import 'package:midi_music/ui/widgets/interactive_score_view.dart';
// The app-facing package intentionally hides the platform delegates required by
// this production-path timing fake.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'helpers/score_renderer_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('桥接重载只允许当前代际更新谱面', () async {
    final script = await rootBundle.loadString(
      'assets/score_renderer/score_bridge.js',
    );

    expect(script, contains('let generation = 0'));
    expect(
      script,
      contains('const isCurrent = () => renderGeneration === generation'),
    );
    expect(script, contains('score.replaceChildren()'));
    expect(script, contains('layer.replaceChildren()'));
    expect(
      script,
      contains(
        'const renderGeneration = ++generation;\n'
        '      resetRenderSurface();',
      ),
    );
    expect(script, contains('if (!isCurrent()) return'));
    expect(script, contains('if (renderGeneration !== generation) return'));
  });

  test('桥接把 UTF-8 原文解析为 XML Document 后交给 OSMD', () async {
    final script = await rootBundle.loadString(
      'assets/score_renderer/score_bridge.js',
    );

    expect(
      script,
      contains("new DOMParser().parseFromString(xml, 'application/xml')"),
    );
    expect(script, contains("document.querySelector('parsererror')"));
    expect(script, contains('await renderer.load(document)'));
    expect(script, isNot(contains('await osmd.load(xml)')));
  });

  test('桥接跟踪活动指针且取消手势不会被视为点击', () async {
    final script = await rootBundle.loadString(
      'assets/score_renderer/score_bridge.js',
    );

    expect(script, contains('const activePointers = new Set()'));
    expect(script, contains("document.addEventListener('pointercancel'"));
    expect(script, contains('Math.max(maxTravel, 11)'));
    expect(script, contains('event.pointerId !== primaryPointerId'));
    expect(script, contains('if (!event.isPrimary || down) return'));
    expect(script, contains('activePointers.clear()'));
    expect(script, contains('cancelGesture(event)'));
  });

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

  testWidgets('测试工厂端口构造即就绪且仅在 XML 变化时重载', (tester) async {
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

  testWidgets('生产端口只在本地页完成后宣布且加载一次', (tester) async {
    final platform = _TestWebViewPlatform();
    WebViewPlatform.instance = platform;
    final readyPorts = <Object>[];

    await tester.pumpWidget(
      CupertinoApp(
        home: InteractiveScoreView(
          musicXml: '<score-partwise/>',
          onMessage: (_) {},
          onPortReady: readyPorts.add,
        ),
      ),
    );

    expect(readyPorts, isEmpty);
    expect(platform.controller.scripts, isEmpty);

    platform.navigationDelegate.onPageFinished!('about:blank');
    await tester.pump();
    expect(readyPorts, isEmpty);
    expect(platform.controller.scripts, isEmpty);

    platform.navigationDelegate.onPageFinished!(
      'file:///flutter_assets/assets/score_renderer/index.html',
    );
    await tester.pump();
    expect(readyPorts, hasLength(1));
    expect(platform.controller.scripts, hasLength(1));

    platform.navigationDelegate.onPageFinished!(
      'file:///flutter_assets/assets/score_renderer/index.html',
    );
    await tester.pump();
    expect(readyPorts, hasLength(1));
    expect(platform.controller.scripts, hasLength(1));
  });
}

class _TestWebViewPlatform extends WebViewPlatform {
  late final _TestPlatformWebViewController controller;
  late final _TestPlatformNavigationDelegate navigationDelegate;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return controller = _TestPlatformWebViewController(params);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return navigationDelegate = _TestPlatformNavigationDelegate(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return _TestPlatformWebViewWidget(params);
  }
}

class _TestPlatformWebViewController extends PlatformWebViewController {
  _TestPlatformWebViewController(super.params) : super.implementation();

  final scripts = <String>[];

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> loadFlutterAsset(String key) async {}

  @override
  Future<void> runJavaScript(String javaScript) async {
    scripts.add(javaScript);
  }
}

class _TestPlatformNavigationDelegate extends PlatformNavigationDelegate {
  _TestPlatformNavigationDelegate(super.params) : super.implementation();

  PageEventCallback? onPageFinished;

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    onPageFinished = callback;
  }

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {}
}

class _TestPlatformWebViewWidget extends PlatformWebViewWidget {
  _TestPlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
