import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
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

  test('桥接隐藏重复且可能被裁切的 OSMD 文档标题', () async {
    final script = await rootBundle.loadString(
      'assets/score_renderer/score_bridge.js',
    );

    expect(script, contains('drawTitle: false'));
    expect(script, isNot(contains('drawTitle: true')));
  });

  test('桥接使用 OSMD 原生 Zoom 重排并重建可点击小节', () async {
    final script = await rootBundle.loadString(
      'assets/score_renderer/score_bridge.js',
    );

    expect(script, contains('let currentZoom = 0.7'));
    expect(script, contains('renderer.Zoom = currentZoom'));
    expect(
      script,
      contains('setZoom(value, requestGeneration = zoomRequestGeneration + 1)'),
    );
    expect(script, contains('let zoomRequestGeneration = 0'));
    expect(script, contains('if (request < zoomRequestGeneration) return'));
    expect(script, contains('renderer.renderAndScrollBack()'));
    expect(script, contains('rebuildLayer(renderer, true'));
    expect(script, contains('applyHighlight(activeOrdinal, true)'));
    expect(script, isNot(contains('style.transform')));
  });

  test('桥接按 SVG viewBox 和实际 client rect 归一化小节联合边界', () async {
    final script = await rootBundle.loadString(
      'assets/score_renderer/score_bridge.js',
    );

    expect(script, contains('const createDocumentMapper'));
    expect(script, contains('svg.viewBox.baseVal'));
    expect(script, contains('svg.getBoundingClientRect()'));
    expect(script, contains('layer.getBoundingClientRect()'));
    expect(
      script,
      contains('renderer.GraphicSheet.MusicPages[0]?.PositionAndShape'),
    );
    expect(script, isNot(contains('EngravingRules.unit')));
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
          onImportScore: () => importCount += 1,
        ),
      ),
    );

    expect(find.byKey(const Key('interactive-score-webview')), findsNothing);
    expect(find.text('暂无可显示乐谱'), findsOneWidget);
    expect(find.text('导入 MIDI 或 MusicXML'), findsOneWidget);

    await tester.tap(find.text('导入文件'));
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

  testWidgets('初始缩放先于 MusicXML 且后续缩放不重载谱面', (tester) async {
    final port = RecordingRendererPort();

    Widget build(double zoom) => CupertinoApp(
      home: InteractiveScoreView(
        musicXml: '<score-partwise/>',
        zoom: zoom,
        onMessage: (_) {},
        surfaceFactory: (_) => ScoreSurface(
          port: port,
          child: const SizedBox(key: Key('fake-score-surface')),
        ),
      ),
    );

    await tester.pumpWidget(build(0.7));
    await tester.pump();

    expect(port.zoomLevels, [0.7]);
    expect(port.operations, ['zoom:0.7', 'load']);
    expect(port.loadedXml, ['<score-partwise/>']);

    await tester.pumpWidget(build(0.6));
    await tester.pump();

    expect(port.zoomLevels, [0.7, 0.6]);
    expect(port.loadedXml, hasLength(1));

    await tester.pumpWidget(build(0.6));
    await tester.pump();
    expect(port.zoomLevels, [0.7, 0.6]);
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
          onImportScore: () => importCount += 1,
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

  testWidgets('测试工厂等待谱面 ready 后只宣布端口一次', (tester) async {
    final port = RecordingRendererPort();
    final readyPorts = <Object>[];
    late ValueChanged<ScoreRendererMessage> emit;

    Widget build(String xml) => CupertinoApp(
      home: InteractiveScoreView(
        musicXml: xml,
        onMessage: (_) {},
        onPortReady: readyPorts.add,
        surfaceFactory: (onMessage) {
          emit = onMessage;
          return ScoreSurface(
            port: port,
            child: const SizedBox(key: Key('fake-score-surface')),
          );
        },
      ),
    );

    await tester.pumpWidget(build('<score-partwise id="one"/>'));
    await tester.pump();
    expect(readyPorts, isEmpty);
    expect(port.loadedXml, ['<score-partwise id="one"/>']);

    emit(const ScoreRendererMessage.ready());
    await tester.pump();
    expect(readyPorts, [same(port)]);

    emit(const ScoreRendererMessage.ready());
    await tester.pump();
    expect(readyPorts, hasLength(1));

    await tester.pumpWidget(build('<score-partwise id="one"/>'));
    await tester.pump();
    expect(port.loadedXml, hasLength(1));
    emit(const ScoreRendererMessage.ready());
    await tester.pump();
    expect(readyPorts, hasLength(1));

    await tester.pumpWidget(build('<score-partwise id="two"/>'));
    await tester.pump();
    expect(port.loadedXml, [
      '<score-partwise id="one"/>',
      '<score-partwise id="two"/>',
    ]);
    emit(const ScoreRendererMessage.ready());
    await tester.pump();
    expect(readyPorts, hasLength(1));
  });

  testWidgets('过期 surface 消息不得污染新 surface', (tester) async {
    final ports = [RecordingRendererPort(), RecordingRendererPort()];
    final emitters = <ValueChanged<ScoreRendererMessage>>[];
    final received = <ScoreRendererMessage>[];
    final readyPorts = <Object>[];
    var surfaceCount = 0;

    Widget build(String? xml) => CupertinoApp(
      home: InteractiveScoreView(
        musicXml: xml,
        onMessage: received.add,
        onPortReady: readyPorts.add,
        surfaceFactory: (onMessage) {
          emitters.add(onMessage);
          final index = surfaceCount++;
          return ScoreSurface(
            port: ports[index],
            child: SizedBox(key: Key('fake-score-surface-$index')),
          );
        },
      ),
    );

    await tester.pumpWidget(build('<score-partwise id="a"/>'));
    await tester.pumpWidget(build(null));
    await tester.pumpWidget(build('<score-partwise id="b"/>'));
    await tester.pump();

    expect(find.byKey(const Key('fake-score-surface-1')), findsOneWidget);
    expect(find.text('正在排版乐谱'), findsOneWidget);

    final emitA = emitters[0];
    emitA(const ScoreRendererMessage.ready());
    emitA(const ScoreRendererMessage.error('过期错误'));
    emitA(
      const ScoreRendererMessage.layout(
        complete: true,
        measureRects: [
          ScoreMeasureRect(ordinal: 1, left: 0, top: 0, width: 10, height: 10),
        ],
      ),
    );
    emitA(
      const ScoreRendererMessage.gestureEnd(
        x: 5,
        y: 5,
        travel: 0,
        durationMs: 100,
        pointerCount: 1,
      ),
    );
    await tester.pump();

    expect(find.text('正在排版乐谱'), findsOneWidget);
    expect(find.text('过期错误'), findsNothing);
    expect(received, isEmpty);
    expect(readyPorts, isEmpty);

    emitters[1](const ScoreRendererMessage.ready());
    await tester.pump();

    expect(find.text('正在排版乐谱'), findsNothing);
    expect(received, [const ScoreRendererMessage.ready()]);
    expect(readyPorts, [same(ports[1])]);
  });

  testWidgets('生产端口在初始加载后等待桥接 ready 再开放', (tester) async {
    final platform = _TestWebViewPlatform();
    WebViewPlatform.instance = platform;
    final readyPorts = <Object>[];

    await tester.pumpWidget(
      CupertinoApp(
        home: InteractiveScoreView(
          musicXml: '<score-partwise/>',
          onMessage: (_) {},
          musicXmlEncoder: (_) => SynchronousFuture<String>('encoded'),
          onPortReady: (port) {
            readyPorts.add(port);
            port.highlightMeasure(2, scrollIntoView: true);
          },
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
    expect(readyPorts, isEmpty);
    expect(platform.controller.scripts, hasLength(1));
    expect(platform.controller.scripts.single, contains('loadMusicXmlBase64'));

    platform.controller.emitBridgeMessage('{"type":"ready"}');
    await tester.pump();
    expect(readyPorts, hasLength(1));
    expect(platform.controller.scripts, hasLength(2));
    expect(platform.controller.scripts[0], contains('loadMusicXmlBase64'));
    expect(
      platform.controller.scripts[1],
      contains('highlightMeasure(2, true)'),
    );

    platform.controller.emitBridgeMessage('{"type":"ready"}');
    await tester.pump();
    expect(readyPorts, hasLength(1));
    expect(platform.controller.scripts, hasLength(2));

    platform.navigationDelegate.onPageFinished!(
      'file:///flutter_assets/assets/score_renderer/index.html',
    );
    await tester.pump();
    expect(readyPorts, hasLength(1));
    expect(platform.controller.scripts, hasLength(2));
  });

  testWidgets('后台编码使用 last-request-wins 不让旧大谱覆盖新谱', (tester) async {
    final platform = _TestWebViewPlatform();
    WebViewPlatform.instance = platform;
    final encoder = _ControlledMusicXmlEncoder();

    Widget build(String xml) => CupertinoApp(
      home: InteractiveScoreView(
        musicXml: xml,
        onMessage: (_) {},
        musicXmlEncoder: encoder.encode,
      ),
    );

    await tester.pumpWidget(build('<score-partwise id="old-large"/>'));
    platform.navigationDelegate.onPageFinished!(
      'file:///flutter_assets/assets/score_renderer/index.html',
    );
    await tester.pump();
    expect(encoder.requests, ['<score-partwise id="old-large"/>']);

    await tester.pumpWidget(build('<score-partwise id="new"/>'));
    await tester.pump();
    expect(encoder.requests, [
      '<score-partwise id="old-large"/>',
      '<score-partwise id="new"/>',
    ]);

    encoder.completers[1].complete('encoded-new');
    await tester.pump();
    expect(platform.controller.scripts, hasLength(1));
    expect(platform.controller.scripts.single, contains('encoded-new'));

    encoder.completers[0].complete('encoded-stale');
    await tester.pump();
    expect(platform.controller.scripts, hasLength(1));
    expect(
      platform.controller.scripts.single,
      isNot(contains('encoded-stale')),
    );
  });

  testWidgets('musicXml 置空并替换 surface 后旧端口不得执行脚本', (tester) async {
    final platform = _TestWebViewPlatform();
    WebViewPlatform.instance = platform;
    final encoder = _ControlledMusicXmlEncoder();

    Widget build(String? xml) => CupertinoApp(
      home: InteractiveScoreView(
        musicXml: xml,
        onMessage: (_) {},
        musicXmlEncoder: encoder.encode,
      ),
    );

    await tester.pumpWidget(build('<score-partwise id="old"/>'));
    platform.navigationDelegates.single.onPageFinished!(
      'file:///flutter_assets/assets/score_renderer/index.html',
    );
    await tester.pump();
    expect(encoder.requests, ['<score-partwise id="old"/>']);

    await tester.pumpWidget(build(null));
    await tester.pumpWidget(build('<score-partwise id="replacement"/>'));
    expect(platform.controllers, hasLength(2));
    platform.navigationDelegates.last.onPageFinished!(
      'file:///flutter_assets/assets/score_renderer/index.html',
    );
    await tester.pump();
    expect(encoder.requests, [
      '<score-partwise id="old"/>',
      '<score-partwise id="replacement"/>',
    ]);

    encoder.completers[1].complete('encoded-replacement');
    await tester.pump();
    encoder.completers[0].complete('encoded-stale');
    await tester.pump();

    expect(platform.controllers.first.scripts, isEmpty);
    expect(platform.controllers.last.scripts.single, contains('replacement'));
  });

  testWidgets('dispose 会使旧端口失效且不留异步异常', (tester) async {
    final platform = _TestWebViewPlatform();
    WebViewPlatform.instance = platform;
    final encoder = _ControlledMusicXmlEncoder();
    await tester.pumpWidget(
      CupertinoApp(
        home: InteractiveScoreView(
          musicXml: '<score-partwise/>',
          onMessage: (_) {},
          musicXmlEncoder: encoder.encode,
        ),
      ),
    );
    platform.navigationDelegate.onPageFinished!(
      'file:///flutter_assets/assets/score_renderer/index.html',
    );
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    encoder.completers.single.complete('encoded-after-dispose');
    await tester.pump();

    expect(platform.controller.scripts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('当前 surface 编码失败进入可读错误态', (tester) async {
    final platform = _TestWebViewPlatform();
    WebViewPlatform.instance = platform;
    final encoder = _ControlledMusicXmlEncoder();
    await tester.pumpWidget(
      CupertinoApp(
        home: InteractiveScoreView(
          musicXml: '<score-partwise/>',
          onMessage: (_) {},
          musicXmlEncoder: encoder.encode,
        ),
      ),
    );
    platform.navigationDelegate.onPageFinished!(
      'file:///flutter_assets/assets/score_renderer/index.html',
    );
    await tester.pump();

    encoder.completers.single.completeError(StateError('encoder failed'));
    await tester.pump();

    expect(find.textContaining('无法加载乐谱'), findsOneWidget);
    expect(find.textContaining('encoder failed'), findsOneWidget);
    expect(find.text('正在排版乐谱'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('当前 surface JavaScript 失败进入可读错误态', (tester) async {
    final platform = _TestWebViewPlatform();
    WebViewPlatform.instance = platform;
    await tester.pumpWidget(
      CupertinoApp(
        home: InteractiveScoreView(
          musicXml: '<score-partwise/>',
          onMessage: (_) {},
          musicXmlEncoder: (_) => SynchronousFuture<String>('encoded'),
        ),
      ),
    );
    platform.controller.javaScriptError = StateError('javascript failed');
    platform.navigationDelegate.onPageFinished!(
      'file:///flutter_assets/assets/score_renderer/index.html',
    );
    await tester.pump();

    expect(find.textContaining('无法加载乐谱'), findsOneWidget);
    expect(find.textContaining('javascript failed'), findsOneWidget);
    expect(find.text('正在排版乐谱'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同一 surface 的旧编码失败不会覆盖新谱成功态', (tester) async {
    final platform = _TestWebViewPlatform();
    WebViewPlatform.instance = platform;
    final encoder = _ControlledMusicXmlEncoder();

    Widget build(String xml) => CupertinoApp(
      home: InteractiveScoreView(
        musicXml: xml,
        onMessage: (_) {},
        musicXmlEncoder: encoder.encode,
      ),
    );

    await tester.pumpWidget(build('<score-partwise id="old"/>'));
    platform.navigationDelegate.onPageFinished!(
      'file:///flutter_assets/assets/score_renderer/index.html',
    );
    await tester.pump();

    await tester.pumpWidget(build('<score-partwise id="new"/>'));
    encoder.completers[1].complete('encoded-new');
    await tester.pump();
    platform.controller.emitBridgeMessage('{"type":"ready"}');
    await tester.pump();

    encoder.completers[0].completeError(StateError('stale encoder failed'));
    await tester.pump();

    expect(platform.controller.scripts.single, contains('encoded-new'));
    expect(find.textContaining('stale encoder failed'), findsNothing);
    expect(find.text('正在排版乐谱'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同一 surface 的旧 JavaScript 失败不会覆盖新谱成功态', (tester) async {
    final platform = _TestWebViewPlatform();
    WebViewPlatform.instance = platform;
    final javaScriptCompleters = <Completer<void>>[];

    Widget build(String xml) => CupertinoApp(
      home: InteractiveScoreView(
        musicXml: xml,
        onMessage: (_) {},
        musicXmlEncoder: (musicXml) => SynchronousFuture('encoded-$musicXml'),
      ),
    );

    await tester.pumpWidget(build('<score-partwise id="old"/>'));
    platform.controller.javaScriptHandler = (_) {
      final completer = Completer<void>();
      javaScriptCompleters.add(completer);
      return completer.future;
    };
    platform.navigationDelegate.onPageFinished!(
      'file:///flutter_assets/assets/score_renderer/index.html',
    );
    await tester.pump();

    await tester.pumpWidget(build('<score-partwise id="new"/>'));
    expect(javaScriptCompleters, hasLength(2));
    javaScriptCompleters[1].complete();
    await tester.pump();
    platform.controller.emitBridgeMessage('{"type":"ready"}');
    await tester.pump();

    javaScriptCompleters[0].completeError(
      StateError('stale javascript failed'),
    );
    await tester.pump();

    expect(platform.controller.scripts.single, contains('id=\\"new\\"'));
    expect(find.textContaining('stale javascript failed'), findsNothing);
    expect(find.text('正在排版乐谱'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _ControlledMusicXmlEncoder {
  final List<String> requests = [];
  final List<Completer<String>> completers = [];

  Future<String> encode(String musicXml) {
    requests.add(musicXml);
    final completer = Completer<String>();
    completers.add(completer);
    return completer.future;
  }
}

class _TestWebViewPlatform extends WebViewPlatform {
  final List<_TestPlatformWebViewController> controllers = [];
  final List<_TestPlatformNavigationDelegate> navigationDelegates = [];

  _TestPlatformWebViewController get controller => controllers.last;
  _TestPlatformNavigationDelegate get navigationDelegate =>
      navigationDelegates.last;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = _TestPlatformWebViewController(params);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    final delegate = _TestPlatformNavigationDelegate(params);
    navigationDelegates.add(delegate);
    return delegate;
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
  JavaScriptChannelParams? scoreBridgeChannel;
  Object? javaScriptError;
  Future<void> Function(String javaScript)? javaScriptHandler;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    if (params.name == 'ScoreBridge') scoreBridgeChannel = params;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> loadFlutterAsset(String key) async {}

  @override
  Future<void> runJavaScript(String javaScript) async {
    final error = javaScriptError;
    if (error != null) throw error;
    final handler = javaScriptHandler;
    if (handler != null) await handler(javaScript);
    scripts.add(javaScript);
  }

  void emitBridgeMessage(String message) {
    scoreBridgeChannel!.onMessageReceived(JavaScriptMessage(message: message));
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
