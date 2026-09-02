# 交互五线谱选择性集成边界

更新日期：2026-09-02

## 来源与目的

本次从 `liab/feature/interactive-musicxml-score` 的
`9d042042efd5d8b01c12c74b27fe2b9a84544ebf` 选择性移植可复用的记谱
领域能力到根 Legacy host。该分支与当前 `liab/main` 的共同基线为
`23b50d26484a9ec9cb50d1d66b977da06d8af6d9`，不是 main 的祖先，因而
不采用整分支 merge。

目标是固定“原始 MIDI 为播放真相、MusicXML 仅为显示派生物”的数据边界，
并让后续的渲染器和播放器适配器可以独立接入。

## 已移植

- `MidiScorePart`、`MidiScoreCatalog`：按轨道和 MIDI channel 分析可记谱
  声部，并给出可解释的推荐选择。
- `MidiScoreSelectionResolver`：曲目默认、全局默认和自动回退的选择优先级。
- `MidiToMusicXmlConverter`：有上限的同步 MIDI → MusicXML 派生转换；
  原始 `MidiSongData` 不被替换。
- `MidiNotationService`：在 isolate 中执行分析/转换，支持取消与重建。
- `ScoreSession`：保存原始播放数据、显示 MusicXML、小节映射状态与降级警告。
- `ScoreRendererMessage`：严格解析来自未来渲染器的布局、手势和错误消息。
- `ScoreRendererPort`、`ScorePlaybackPort` 与
  `ScorePlaybackCoordinator`：用最小端口协调点击跳转、播放器位置高亮、
  自动跟随与暂时性渲染失败后的重试。

这些能力目前仅位于根 Legacy host 的未接线领域层；没有页面、导航、导入入口或
候选二进制引用它们。

## 明确未移植

- `InteractiveScoreView`、WebView、OSMD、`assets/score_renderer`；
- 通用 MIDI/MusicXML/PDF 导入改造、OMR 和设置页面；
- 首页、播放页、K.478 页面、release scope/checklist；
- `apps/testflight_ios`、`packages/k478_practice`、
  `packages/core_midi_input` 及其依赖/锁文件；
- 现有 `MidiPlayerController`、`MeasureMap`、`ScoreImportService`、
  `MusicXmlParser` 的行为。

因此这不是“交互谱面已经上线”或“已进入 TestFlight”的证据。

## 端口合同与后续接入

| 端口 | 职责 | 不负责 |
| --- | --- | --- |
| `ScoreRendererPort` | 加载 MusicXML、缩放、按小节高亮/清除高亮 | WebView、资源加载、消息校验、播放器状态 |
| `ScorePlaybackPort` | 暴露 `ScoreSession`、当前小节、按小节跳转 | 渲染、MusicXML 生成、UI 手势 |
| `ScorePlaybackCoordinator` | 已验证的点击命中、不可映射拒绝、自动跟随、去重和失败重试 | 直接依赖当前播放器或渲染技术 |

建议按下列顺序接入：

1. 为目标 host 写一个 `ScorePlaybackPort` 适配器；不直接改动
   `MidiPlayerController` 的公共职责。
2. 以 `ScoreRendererProtocol` 建立受限消息通道，再实现
   `ScoreRendererPort`。
3. 先在隔离实验 host 做端到端测试；通过安全门槛和真机测试后，再决定是否接到
   K.478/TestFlight 候选。
4. UI、通用导入和 OMR 只能在前述边界稳定后单独审阅和合并。

## 安全与发布门槛

- 在读入或解析前限制 MIDI 和 MusicXML 输入字节数；保留解析时间、音符数、
  小节数和 XML 生成大小预算。
- 若使用 OSMD/WebView，设置严格 CSP、固定本地资源清单与许可证文件，并验证不
  会加载意外子资源。
- 若恢复 OMR，下载 URL 必须强制 HTTPS 与预期同源，且限制响应和文件大小。
- 用真实 iPhone 复核加载、手势、小节跳转、后台/前台恢复、长谱性能与内存；
  静态测试和模拟器不能替代这些证据。
- 任何进入候选包的改动必须重新通过候选验证矩阵，而不是以根 Legacy host 的
  测试结果替代。

## 本次验收

根 host 的纯单元测试覆盖声部分析、选择、转换器上限与输出、isolate 生命周期、
`ScoreSession` 不变量、渲染器消息校验，以及两个端口的协调器行为。验证命令为：

```bash
dart format lib/models/midi_score_part.dart lib/models/score_session.dart \
  lib/core/notation lib/core/score test/midi_part_analyzer_test.dart \
  test/midi_score_selection_test.dart test/midi_to_musicxml_converter_test.dart \
  test/midi_notation_service_test.dart test/score_session_test.dart \
  test/score_renderer_protocol_test.dart test/score_playback_coordinator_test.dart
flutter test test/midi_part_analyzer_test.dart test/midi_score_selection_test.dart \
  test/midi_to_musicxml_converter_test.dart test/midi_notation_service_test.dart \
  test/score_session_test.dart test/score_renderer_protocol_test.dart \
  test/score_playback_coordinator_test.dart
flutter analyze
```
