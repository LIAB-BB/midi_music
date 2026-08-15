# 交互五线谱缩放控制 Implementation Plan

> **历史状态（2026-08-15）：** 本计划已实施。当前默认 70%、范围 50%–140%、步长 10%；连续点击在 bridge 层使用 80ms 空闲窗口合并为最后一次 OSMD 全量重排，避免逐档排队延迟。

> **历史执行说明，禁止重新执行：** 当时曾要求用 subagent-driven-development 或 executing-plans 逐任务实施；这些步骤现只用于追溯设计与提交，不是待办清单。

**Goal:** 在交互五线谱练习页增加 50%–140% 的 OSMD 原生缩放，并在固定播放栏上沿提供可访问的减号、百分比和加号控件。

**Architecture:** `ScorePracticePage` 持有页面级 zoom，独立的 `ScoreZoomControls` 只负责界面和边界禁用；`InteractiveScoreView` 把 zoom 发送给 `ScoreRendererPort`。本地 JS bridge 通过 OSMD `Zoom` 重新排版，并沿用现有 SVG mapper 重建小节点击/高亮几何。

**Tech Stack:** Flutter 3.44.1、Dart 3.12.1、Cupertino widgets、webview_flutter 4.14.1、离线 OSMD 1.9.9、flutter_test、integration_test。

## Global Constraints

- 默认 zoom 为 0.7；最小 0.5、最大 1.4、步长 0.1。
- 切换声部或替换 MusicXML 保持当前页面 zoom；新建练习页恢复 0.7。
- 缩放只改变显示，不改变 MIDI 播放、MusicXML、声部选择、速度或 AB 循环。
- 必须使用 OSMD 原生 `Zoom` 重排；禁止 CSS transform 或 WKWebView page zoom。
- 缩放后必须重新发布 layout，小节点击、高亮和自动跟随继续使用新 CSS 文档坐标。
- 缩放控件触控区域至少 44×44 pt，只在存在 MusicXML 时显示。
- 每次提交前运行 focused tests、`flutter analyze`、完整 `flutter test` 和 `git diff --check`。

---

### Task 1: Renderer 原生缩放协议

**Files:**
- Modify: `lib/core/score/score_playback_coordinator.dart`
- Modify: `lib/ui/widgets/interactive_score_view.dart`
- Modify: `assets/score_renderer/score_bridge.js`
- Modify: `test/helpers/score_renderer_test_fakes.dart`
- Modify: `test/interactive_score_view_test.dart`

**Interfaces:**
- Consumes: 现有 `ScoreRendererPort.loadMusicXml/highlightMeasure/clearHighlight` 和 `window.scoreBridge` 本地协议。
- Produces: `Future<void> ScoreRendererPort.setZoom(double zoom)`；`InteractiveScoreView.zoom`；`window.scoreBridge.setZoom(zoom)`。

- [ ] **Step 1: 写失败测试固定 Dart 与 JS 契约**

在 `test/helpers/score_renderer_test_fakes.dart` 的两个 port 中增加 `zoomLevels` 记录，并在 `test/interactive_score_view_test.dart` 增加以下行为测试：首次 surface 先收到 0.7，再加载 XML；widget 从 0.7 更新到 0.6 时只收到一次 zoom、不重载 XML；相同 zoom 不重复发送；置空、替换 surface 或 dispose 后旧 zoom 失败不污染当前错误态。

```dart
testWidgets('初始缩放先于 MusicXML，后续缩放不重载谱面', (tester) async {
  final port = RecordingRendererPort();
  Widget build(double zoom) => CupertinoApp(
    home: InteractiveScoreView(
      musicXml: '<score-partwise/>',
      zoom: zoom,
      onMessage: (_) {},
      surfaceFactory: (onMessage) => ScoreSurface(
        port: port,
        child: const SizedBox(),
      ),
    ),
  );

  await tester.pumpWidget(build(0.7));
  await tester.pump();
  expect(port.zoomLevels, [0.7]);
  expect(port.loadedXml, ['<score-partwise/>']);

  await tester.pumpWidget(build(0.6));
  await tester.pump();
  expect(port.zoomLevels, [0.7, 0.6]);
  expect(port.loadedXml, hasLength(1));
});
```

JS 资源契约必须断言 `currentZoom`、`renderer.Zoom = currentZoom`、`setZoom`、`renderAndScrollBack()`、`rebuildLayer()` 与 `applyHighlight(activeOrdinal, true)` 同时存在，并断言没有 `style.transform`。

- [ ] **Step 2: 运行 RED**

Run: `flutter test test/interactive_score_view_test.dart`

Expected: FAIL，原因包括 `InteractiveScoreView` 没有 `zoom` 参数、`ScoreRendererPort` 没有 `setZoom`、bridge 没有 `setZoom`。

- [ ] **Step 3: 实现最小 renderer 缩放协议**

在 `ScoreRendererPort` 增加：

```dart
Future<void> setZoom(double zoom);
```

在 `InteractiveScoreView` 增加默认参数并在 surface 可用后顺序发送：

```dart
final double zoom;

const InteractiveScoreView({
  // existing fields
  this.zoom = 0.7,
});
```

`didUpdateWidget` 只在 `oldWidget.zoom != widget.zoom` 且当前 surface 存在时调用 `port.setZoom(widget.zoom)`；使用独立 zoom generation 收敛异步错误，不能递增 MusicXML load generation。

在 bridge 中保存并限制比例：

```javascript
let currentZoom = 0.7;

const clampZoom = (value) => Math.min(1.4, Math.max(0.5, value));

const rerenderAtCurrentZoom = () => {
  const renderer = osmd;
  if (!renderer) return;
  renderer.Zoom = currentZoom;
  renderer.renderAndScrollBack();
  rebuildLayer(renderer, true, generation);
  if (activeOrdinal !== null) applyHighlight(activeOrdinal, true);
};
```

在首次 `renderer.render()` 前设置 `renderer.Zoom = currentZoom`；公开 `setZoom(value)`，非法值抛出可读错误，合法值更新后调用 `rerenderAtCurrentZoom()`。不得清空 XML、active ordinal 或播放器状态。

- [ ] **Step 4: 运行 focused GREEN**

Run: `flutter test test/interactive_score_view_test.dart test/score_playback_coordinator_test.dart`

Expected: PASS，且既有 load/highlight/gesture 断言继续通过。

- [ ] **Step 5: 提交 renderer 协议**

```bash
git add assets/score_renderer/score_bridge.js lib/core/score/score_playback_coordinator.dart lib/ui/widgets/interactive_score_view.dart test/helpers/score_renderer_test_fakes.dart test/interactive_score_view_test.dart
git commit -m "feat: 支持交互谱面原生缩放"
```

---

### Task 2: 底部缩放控件与页面状态

**Files:**
- Create: `lib/ui/widgets/score_zoom_controls.dart`
- Create: `test/score_zoom_controls_test.dart`
- Modify: `lib/ui/pages/score_practice_page.dart`
- Modify: `test/score_practice_page_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `InteractiveScoreView.zoom`。
- Produces: `ScoreZoomControls(zoom, onZoomOut, onZoomIn)`；页面状态 `_scoreZoom`。

- [ ] **Step 1: 写失败的控件与页面测试**

新增 `test/score_zoom_controls_test.dart`，验证 70% 文案、44pt 触控、中文 semantics、边界禁用和回调：

```dart
await tester.pumpWidget(CupertinoApp(
  home: ScoreZoomControls(
    zoom: 0.7,
    onZoomOut: () => zoomOutCount += 1,
    onZoomIn: () => zoomInCount += 1,
  ),
));
expect(find.text('70%'), findsOneWidget);
expect(tester.getSemantics(find.byKey(const Key('score-zoom-out'))),
    matchesSemantics(label: '缩小乐谱', isButton: true, hasTapAction: true));
```

在 `test/score_practice_page_test.dart` 增加：有 MusicXML 显示胶囊；初始 port 收到 0.7；点击减号得到 0.6、再点击加号回到 0.7；切换声部后的新 XML 保持当前 zoom；无 MusicXML/首次错误态不显示；新建页面恢复 0.7。

- [ ] **Step 2: 运行 RED**

Run: `flutter test test/score_zoom_controls_test.dart test/score_practice_page_test.dart`

Expected: FAIL，原因是 `ScoreZoomControls` 与页面缩放状态尚不存在。

- [ ] **Step 3: 实现独立缩放胶囊**

新增 `ScoreZoomControls`，常量和百分比取整集中在该组件：

```dart
class ScoreZoomControls extends StatelessWidget {
  static const minZoom = 0.5;
  static const maxZoom = 1.4;
  static const step = 0.1;

  final double zoom;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
}
```

外观使用 `Color(0xF2403640)` 胶囊背景、`Color(0xFFF2DEAA)` 前景、圆角 22；左右 `CupertinoButton` 的 `minimumSize` 为 `Size(44, 44)`，中间宽度固定并显示 `${(zoom * 100).round()}%`。边界按钮的 `onPressed` 为 null。

- [ ] **Step 4: 接入页面级 zoom 与 overlay**

在 `_ScorePracticePageState` 增加：

```dart
double _scoreZoom = 0.7;

void _changeScoreZoom(double delta) {
  final next = (_scoreZoom + delta).clamp(
    ScoreZoomControls.minZoom,
    ScoreZoomControls.maxZoom,
  );
  if (next == _scoreZoom) return;
  setState(() => _scoreZoom = double.parse(next.toStringAsFixed(1)));
}
```

把 `Expanded(child: _buildScoreBody())` 改为同尺寸 `Stack`：底层为谱面；当 `_displaySession?.musicXml != null` 时，在 `right: 12, bottom: 12` 放缩放胶囊。把 `_scoreZoom` 传给 `InteractiveScoreView`。不要在声部 rebuild、renderer ready 或播放器 listener 中重置 zoom。

- [ ] **Step 5: 运行 focused GREEN**

Run: `flutter test test/score_zoom_controls_test.dart test/score_practice_page_test.dart test/interactive_score_view_test.dart`

Expected: PASS；现有五个 transport 控件、声部切换和错误态测试不回归。

- [ ] **Step 6: 提交页面控件**

```bash
git add lib/ui/widgets/score_zoom_controls.dart lib/ui/pages/score_practice_page.dart test/score_zoom_controls_test.dart test/score_practice_page_test.dart
git commit -m "feat: 增加底部乐谱缩放控件"
```

---

### Task 3: 真实 WKWebView、视觉与发布门禁

**Files:**
- Modify: `integration_test/midi_notation_render_test.dart`
- Modify: `README.md`
- Modify: `docs/release_checklist.md`

**Interfaces:**
- Consumes: Task 1 的 `setZoom` 和 Task 2 的 70% 默认 UI。
- Produces: 可重复的真实 WKWebView 缩放/点击验收与用户文档。

- [ ] **Step 1: 写真实 renderer 缩放测试并先观察 RED**

扩展 iOS integration fixture：以 `zoom: 0.7` 首次渲染，记录 complete layout 和 score document height；通过 production `ScoreRendererPort.setZoom(0.5)` 等待下一次 complete layout，断言高度下降、小节 ordinal 不变、所有 rect 为正且最右侧仍覆盖 WebView 主宽度；随后在非首小节 overlay 中心 dispatch PointerEvent，断言 gesture 命中新 layout 的同一小节。

Run: `flutter test integration_test/midi_notation_render_test.dart -d <iOS-simulator-id>`

Expected before production completion: FAIL，缺少第二次缩放 layout 或点击命中错误。

- [ ] **Step 2: 修正 production renderer 直到 integration GREEN**

只修 Task 1 文件中的真实问题：zoom 后 layout generation、SVG mapper、overlay 高度、active highlight 恢复或 scrollIntoView。禁止用放宽 rect/跳过点击断言来转绿。

Run: `flutter test integration_test/midi_notation_render_test.dart -d <iOS-simulator-id>`

Expected: `+2: All tests passed!` 或增加用例后的对应全绿数量。

- [ ] **Step 3: 同步用户文档和发布清单**

README 增加“默认 70%，底部 −/+，50%–140%，缩放不影响播放”的使用说明；release checklist 增加 70% 密度、两端边界、缩放后首/中/末小节点击、高亮和自动跟随验收。

- [ ] **Step 4: 跑完整自动门禁**

```bash
dart format lib test integration_test
flutter analyze
flutter test --reporter compact
env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 flutter build ios --debug --no-codesign
git diff --check
```

Expected: format 0 changed after final format；analyze `No issues found!`；完整测试全绿；iOS Runner.app 构建成功；diff check 无输出。

- [ ] **Step 5: 做同屏视觉比较**

在 iPhone 14 Pro 等效纵屏、K.478 默认钢琴状态启动 App，截取 70% 初始页及 50%/80% 两个状态。把用户参考图 `/var/folders/wt/b1dv1vrj4wb6823gjvtzzml80000gn/T/codex-clipboard-eb914392-269e-4ecc-a607-6c922aedaaad.jpg` 与 70% 实现截图放入同一图片比较输入，确认约 4–5 行可见、无裁切、缩放胶囊不遮住高亮或播放栏。发现视觉差异必须修复并重新比较。

- [ ] **Step 6: 提交 integration 与文档**

```bash
git add integration_test/midi_notation_render_test.dart README.md docs/release_checklist.md
git commit -m "test: 覆盖交互谱面缩放验收"
```

- [ ] **Step 7: 交付前复核**

Run: `git status --short --branch && git log --oneline -5 && git diff HEAD~3..HEAD --check`

Expected: 工作树干净、三个缩放提交连续存在、diff check 无输出。报告真实 simulator/physical device 状态，不把未执行的真机步骤声称为通过。

## Self-Review

- Spec coverage: renderer 原生缩放、默认/边界/步长、底部控件、页面生命周期、声部切换保持、错误/竞态、点击坐标、视觉和完整门禁分别由 Task 1–3 覆盖。
- Placeholder scan: 无 TBD/TODO/“类似前一步”等占位语；每个生产修改均给出接口、核心代码和可执行命令。
- Type consistency: `double zoom` 从 `ScorePracticePage` 经 `InteractiveScoreView` 到 `ScoreRendererPort.setZoom(double)`；测试 fake 使用同一方法签名；JS 统一使用 `setZoom(value)`。
