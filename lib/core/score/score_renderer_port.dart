/// 面向谱面渲染实现的最小命令端口。
///
/// WebView/OSMD 与测试渲染器都通过此端口接入播放协调器。
abstract interface class ScoreRendererPort {
  Future<void> loadMusicXml(String musicXml);

  Future<void> setZoom(double zoom);

  Future<void> highlightMeasure(int ordinal, {required bool scrollIntoView});

  Future<void> clearHighlight();
}
