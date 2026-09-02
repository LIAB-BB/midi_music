/// 面向谱面渲染实现的最小命令端口。
///
/// 根 Legacy host 暂不提供 WebView/OSMD 实现；未来的原生、Web 或测试渲染器
/// 只需实现此端口即可接入播放协调器。
abstract interface class ScoreRendererPort {
  Future<void> loadMusicXml(String musicXml);

  Future<void> setZoom(double zoom);

  Future<void> highlightMeasure(int ordinal, {required bool scrollIntoView});

  Future<void> clearHighlight();
}
