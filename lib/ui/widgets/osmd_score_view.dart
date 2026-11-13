import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/score/osmd_score_renderer.dart';

bool get osmdWebViewAvailable => WebViewPlatform.instance != null;

class OsmdScoreView extends StatefulWidget {
  final OsmdScoreRenderer renderer;
  final String musicXml;

  const OsmdScoreView({
    super.key,
    required this.renderer,
    required this.musicXml,
  });

  @override
  State<OsmdScoreView> createState() => _OsmdScoreViewState();
}

class _OsmdScoreViewState extends State<OsmdScoreView> {
  late final WebViewController _controller;
  var _booted = false;
  var _loadedXml = '';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF161311))
      ..addJavaScriptChannel(
        'ScoreRenderer',
        onMessageReceived: (message) {
          widget.renderer.handleRawMessage(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            return osmdNavigationAllowed(request.url)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onPageFinished: (_) {
            unawaited(_boot());
          },
        ),
      );
    widget.renderer.bind((source) => _controller.runJavaScript(source));
    unawaited(_controller.loadFlutterAsset(osmdPageAsset));
  }

  @override
  void didUpdateWidget(OsmdScoreView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_booted && widget.musicXml != _loadedXml) {
      _loadedXml = widget.musicXml;
      unawaited(widget.renderer.loadMusicXml(widget.musicXml));
    }
  }

  Future<void> _boot() async {
    if (_booted) return;
    _booted = true;
    try {
      final library = await rootBundle.loadString(osmdLibraryAsset);
      await _controller.runJavaScript(library);
      await widget.renderer.markLibraryReady();
      _loadedXml = widget.musicXml;
      await widget.renderer.loadMusicXml(widget.musicXml);
    } catch (error) {
      widget.renderer.handleRawMessage(
        '{"type":"error","message":${jsonEncode(_bootMessage(error))}}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}

String _bootMessage(Object error) {
  final message = '刻谱引擎加载失败：$error';
  return message.length <= 500 ? message : message.substring(0, 500);
}
