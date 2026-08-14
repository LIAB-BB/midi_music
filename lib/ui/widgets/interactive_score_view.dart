import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/cupertino.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/score/score_playback_coordinator.dart';
import '../../core/score/score_renderer_protocol.dart';

class ScoreSurface {
  final ScoreRendererPort port;
  final Widget child;

  const ScoreSurface({required this.port, required this.child});
}

typedef ScoreSurfaceFactory =
    ScoreSurface Function(ValueChanged<ScoreRendererMessage> onMessage);
typedef MusicXmlEncoder = Future<String> Function(String musicXml);

class InteractiveScoreView extends StatefulWidget {
  final String? musicXml;
  final ValueChanged<ScoreRendererMessage> onMessage;
  final ValueChanged<ScoreRendererPort>? onPortReady;
  final VoidCallback? onImportScore;
  final ScoreSurfaceFactory? surfaceFactory;
  final MusicXmlEncoder? musicXmlEncoder;

  const InteractiveScoreView({
    super.key,
    required this.musicXml,
    required this.onMessage,
    this.onPortReady,
    this.onImportScore,
    this.surfaceFactory,
    this.musicXmlEncoder,
  });

  @override
  State<InteractiveScoreView> createState() => _InteractiveScoreViewState();
}

class _InteractiveScoreViewState extends State<InteractiveScoreView> {
  ScoreSurface? _surface;
  bool _isLoading = false;
  bool _pageReady = false;
  bool _portAnnounced = false;
  String? _errorMessage;
  Object? _surfaceToken;

  @override
  void initState() {
    super.initState();
    if (widget.musicXml != null) {
      _isLoading = true;
      _createSurface();
    }
  }

  @override
  void didUpdateWidget(covariant InteractiveScoreView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.musicXml == widget.musicXml) return;

    final musicXml = widget.musicXml;
    if (musicXml == null) {
      setState(() {
        _surfaceToken = null;
        _surface = null;
        _pageReady = false;
        _portAnnounced = false;
        _isLoading = false;
        _errorMessage = null;
      });
      return;
    }

    if (_surface == null) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _createSurface();
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    if (_pageReady) unawaited(_surface!.port.loadMusicXml(musicXml));
  }

  void _createSurface() {
    final surfaceToken = Object();
    _surfaceToken = surfaceToken;
    _portAnnounced = false;
    final factory = widget.surfaceFactory;
    if (factory != null) {
      _surface = factory(
        (message) => _acceptMessage(message, surfaceToken: surfaceToken),
      );
      _pageReady = true;
      final musicXml = widget.musicXml;
      if (musicXml != null) unawaited(_surface!.port.loadMusicXml(musicXml));
      return;
    }

    late final WebViewController controller;
    controller = WebViewController();
    final port = _WebViewScoreRendererPort(
      controller,
      encoder: widget.musicXmlEncoder,
    );
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF8F0DC))
      ..addJavaScriptChannel(
        'ScoreBridge',
        onMessageReceived: (message) {
          try {
            _acceptMessage(
              ScoreRendererMessage.parse(message.message),
              surfaceToken: surfaceToken,
              sourcePort: port,
            );
          } on FormatException {
            // 丢弃非法本地桥接消息，不触发播放器操作。
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (!_isCurrentSurface(surfaceToken, sourcePort: port)) return;
            final uri = Uri.tryParse(url);
            if (uri == null ||
                !uri.path.endsWith('/assets/score_renderer/index.html')) {
              return;
            }
            if (_pageReady) return;
            _pageReady = true;
            final musicXml = widget.musicXml;
            if (musicXml != null) unawaited(port.loadMusicXml(musicXml));
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            final isLocal =
                uri != null && (uri.scheme == 'file' || uri.scheme == 'about');
            return request.isMainFrame && !isLocal
                ? NavigationDecision.prevent
                : NavigationDecision.navigate;
          },
        ),
      )
      ..loadFlutterAsset('assets/score_renderer/index.html');
    _surface = ScoreSurface(
      port: port,
      child: WebViewWidget(
        key: const Key('interactive-score-webview'),
        controller: controller,
      ),
    );
  }

  bool _isCurrentSurface(Object surfaceToken, {ScoreRendererPort? sourcePort}) {
    return mounted &&
        identical(_surfaceToken, surfaceToken) &&
        (sourcePort == null || identical(_surface?.port, sourcePort));
  }

  void _acceptMessage(
    ScoreRendererMessage message, {
    required Object surfaceToken,
    ScoreRendererPort? sourcePort,
  }) {
    if (!_isCurrentSurface(surfaceToken, sourcePort: sourcePort)) return;
    switch (message.type) {
      case ScoreRendererMessageType.ready:
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
        if (!_portAnnounced && _surface != null) {
          _portAnnounced = true;
          widget.onPortReady?.call(_surface!.port);
        }
      case ScoreRendererMessageType.error:
        setState(() {
          _isLoading = false;
          _errorMessage = message.errorMessage;
        });
      case ScoreRendererMessageType.layout:
      case ScoreRendererMessageType.gestureEnd:
        break;
    }
    widget.onMessage(message);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.musicXml == null) return _buildMidiOnlyState();

    return ColoredBox(
      color: const Color(0xFFF8F0DC),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_surface != null) _surface!.child,
          if (_isLoading) const _ScoreLoadingOverlay(),
          if (_errorMessage case final message?)
            _ScoreErrorOverlay(
              message: message,
              onImportScore: widget.onImportScore,
            ),
        ],
      ),
    );
  }

  Widget _buildMidiOnlyState() {
    return ColoredBox(
      color: const Color(0xFFF8F0DC),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.music_note_2,
                color: Color(0xFFA2773F),
                size: 34,
              ),
              const SizedBox(height: 14),
              const Text(
                '暂无可显示乐谱',
                style: TextStyle(
                  color: Color(0xFF2A2118),
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '导入 MIDI 或 MusicXML',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF7E6C55), fontSize: 14),
              ),
              if (widget.onImportScore != null) ...[
                const SizedBox(height: 18),
                CupertinoButton(
                  color: const Color(0xFF5F4A35),
                  onPressed: widget.onImportScore,
                  child: const Text('导入文件'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreLoadingOverlay extends StatelessWidget {
  const _ScoreLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xE6F8F0DC),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoActivityIndicator(color: Color(0xFFA2773F)),
            SizedBox(height: 12),
            Text(
              '正在排版乐谱',
              style: TextStyle(color: Color(0xFF5F4A35), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreErrorOverlay extends StatelessWidget {
  final String message;
  final VoidCallback? onImportScore;

  const _ScoreErrorOverlay({
    required this.message,
    required this.onImportScore,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF8F0DC),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_triangle,
                color: Color(0xFFA2773F),
                size: 32,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF5F4A35), fontSize: 14),
              ),
              if (onImportScore != null) ...[
                const SizedBox(height: 18),
                CupertinoButton(
                  color: const Color(0xFF5F4A35),
                  onPressed: onImportScore,
                  child: const Text('重新导入'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WebViewScoreRendererPort implements ScoreRendererPort {
  final WebViewController controller;
  final MusicXmlEncoder _encoder;
  int _loadGeneration = 0;

  _WebViewScoreRendererPort(this.controller, {MusicXmlEncoder? encoder})
    : _encoder = encoder ?? _encodeMusicXmlInBackground;

  @override
  Future<void> loadMusicXml(String musicXml) async {
    final generation = ++_loadGeneration;
    final encoded = await _encoder(musicXml);
    if (generation != _loadGeneration) return;
    await controller.runJavaScript(
      'window.scoreBridge.loadMusicXmlBase64(${jsonEncode(encoded)})',
    );
  }

  @override
  Future<void> highlightMeasure(int ordinal, {required bool scrollIntoView}) {
    return controller.runJavaScript(
      'window.scoreBridge.highlightMeasure($ordinal, $scrollIntoView)',
    );
  }

  @override
  Future<void> clearHighlight() {
    return controller.runJavaScript('window.scoreBridge.clearHighlight()');
  }
}

Future<String> _encodeMusicXmlInBackground(String musicXml) => Isolate.run(
  () => base64Encode(utf8.encode(musicXml)),
  debugName: 'MusicXML UTF-8/base64 encoding',
);
