import 'dart:convert';

import 'score_renderer_port.dart';
import 'score_renderer_protocol.dart';

const osmdLibraryAsset = 'assets/score_renderer/opensheetmusicdisplay.min.js';
const osmdPageAsset = 'assets/score_renderer/index.html';
const osmdLibrarySha256 =
    '54d8e763a75559f78308d09b7bf36cd33f538a280c3c816b34355240335d6630';

/// 刻谱页只允许加载本地渲染器。其余导航一律拒绝。
bool osmdNavigationAllowed(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (uri.scheme == 'about' || uri.scheme == 'data') return true;
  return uri.path.endsWith('/assets/score_renderer/index.html') ||
      uri.path.endsWith('assets/score_renderer/index.html');
}

/// 本地 OSMD 的命令端口。JavaScript 由宿主注入，本类不打开网络。
class OsmdScoreRenderer implements ScoreRendererPort {
  final void Function(ScoreRendererMessage message) onMessage;
  Future<void> Function(String source)? _runJavaScript;
  var _libraryReady = false;
  String? _pendingMusicXml;

  OsmdScoreRenderer({
    required this.onMessage,
    Future<void> Function(String source)? runJavaScript,
  }) : _runJavaScript = runJavaScript;

  void bind(Future<void> Function(String source) runJavaScript) {
    _runJavaScript = runJavaScript;
  }

  Future<void> _run(String source) {
    final runJavaScript = _runJavaScript;
    if (runJavaScript == null) return Future<void>.value();
    return runJavaScript(source);
  }

  void handleRawMessage(String raw) {
    try {
      onMessage(ScoreRendererMessage.parse(raw));
    } on FormatException catch (error) {
      final message = error.message.trim();
      onMessage(
        ScoreRendererMessage.error(message.isEmpty ? '无法解析刻谱消息' : message),
      );
    }
  }

  Future<void> markLibraryReady() async {
    _libraryReady = true;
    final pending = _pendingMusicXml;
    if (pending == null) return;
    _pendingMusicXml = null;
    await loadMusicXml(pending);
  }

  @override
  Future<void> loadMusicXml(String musicXml) async {
    if (!_libraryReady) {
      _pendingMusicXml = musicXml;
      return;
    }
    await _run('window.loadMusicXml(${jsonEncode(musicXml)})');
  }

  @override
  Future<void> setZoom(double zoom) {
    final safeZoom = zoom.clamp(0.4, 2.5);
    return _run('window.setZoom($safeZoom)');
  }

  @override
  Future<void> highlightMeasure(int ordinal, {required bool scrollIntoView}) {
    return _run(
      'window.highlightMeasure($ordinal, ${scrollIntoView ? 'true' : 'false'})',
    );
  }

  @override
  Future<void> clearHighlight() {
    return _run('window.clearHighlight()');
  }
}
