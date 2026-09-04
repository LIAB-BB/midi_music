# 交互五线谱集成边界

更新日期：2026-09-04

## 历史与当前状态

本文件最初记录从 `feature/interactive-musicxml-score` 向 LIAB 主线选择性移植
领域层的过程。当前合并目标已经扩大为：在**根目录 host** 接入完整交互谱面，
同时保留 LIAB 的 USB MIDI 演奏台和隔离的 K.478 TestFlight 候选。

因此旧结论“只有领域层、没有页面或 OSMD”已经失效。当前边界如下：

- 根默认 `HomePage` 提供 K.478 双入口：交互五线谱 `ScorePracticePage` 与 USB
  MIDI `PlayerPage`。
- `home_page_legacy.dart` 保存通用曲库与 MIDI/MusicXML/PDF 导入，但不是默认
  首页。
- `apps/testflight_ios` + `packages/k478_practice` 是独立候选，继续使用静态
  21 页 PNG、离线 SF2 和 CoreMIDI；不接入根 App 的 OSMD 页面。
- 根 App 和独立候选的依赖、资产、自动化、真机及签名证据分别验收。

## 根交互谱数据边界

1. 原始 `MidiSongData` 是唯一播放真值。
2. `MidiPartAnalyzer` 与 `MidiScoreSelectionResolver` 建立可选声部和默认选择。
3. `MidiToMusicXmlConverter` 只生成显示用 MusicXML 与小节映射；量化结果不得
   回写播放时间线。
4. `MidiNotationService` 在可取消 isolate 中执行分析和转换。
5. `ScoreSession` 同时保存原始播放数据、MusicXML 原文、真实小节边界、选择和
   降级警告。
6. `InteractiveScoreView` 使用完全本地的 OSMD 资源排版、缩放、命中和高亮。
7. `ScorePlaybackCoordinator` 是渲染事件进入播放器的唯一协调边界；具体
   `MidiPlayerController` 通过适配器实现端口，不由 WebView 直接调用。

MusicXML 导入和 PDF OMR 结果必须保留原文直接进入 OSMD，同时从同一原文解析
播放时间线与小节边界；不得把 OMR 结果再次送入 MIDI 自动记谱转换器。

## 端口合同

| 端口 | 职责 | 不负责 |
| --- | --- | --- |
| `ScoreRendererPort` | 加载 MusicXML、缩放、按小节高亮/清除高亮 | 播放器状态与业务导航 |
| `ScorePlaybackPort` | 暴露 `ScoreSession`、当前小节、按小节跳转 | 渲染、MusicXML 生成、UI 手势 |
| `ScorePlaybackCoordinator` | 验证点击命中、拒绝不可映射小节、自动跟随、去重和失败重试 | 直接依赖具体播放器或渲染技术 |

`InteractiveScoreView` 的 renderer 消息必须先经 `ScoreRendererProtocol` 校验。
无效类型、越界小节、过期 surface 或已取消请求不能改变播放器。

## 根 UI 约束

- `ScorePracticePage` 只显示交互五线谱，不恢复 PDF 黑框、静态 PNG、钢琴卷帘
  或 seed 假谱。
- K.478 默认显示钢琴 upper/lower 双谱表，并保留明确左右手来源；可多选其他
  声部形成总谱。
- 换谱只更新 presentation，必须保持 time、speed、AB 和 playing。
- 小节点击、高亮、前后小节、AB 与缩放共享同一小节/布局坐标。
- OSMD 使用原生 Zoom 在 50%–140% 重排；不得用 CSS transform 伪缩放。

## 与独立候选的隔离

独立候选的 21 张 PNG 是 PDF 的预渲染页面，只支持手动阅读，不承诺小节点击、
播放同步或 OSMD。候选播放器和 SF2 位于 `packages/k478_practice`；根 App 的
TimGM 下载路径、OSMD、导入与旧组件不得因此进入候选 bundle。

同理，候选的 bundle 白名单、CoreMIDI 单元测试或 iPhone 实听，不能证明根 App
的交互谱面已经通过。两个目标分别使用：

- 根 App：`docs/release_checklist.md`；
- 独立候选：`docs/releases/k478_testflight_checklist.md`。

## 安全与发布门槛

- 在读取或解析前限制 MIDI/MusicXML 字节数，并保留解析时间、音符数、小节数和
  XML 输出大小预算。
- OSMD/WebView 使用严格 CSP、固定本地资源清单与许可证；运行时不得加载远程
  脚本或意外子资源。
- OMR 不属于任一默认试用范围。若受控开发恢复 OMR，下载 URL 必须使用 HTTPS
  与预期来源，并补鉴权/授权、限流、文件防护、隔离、保留与删除机制。
- 用实体 iPhone 分别复核根 App 的交互谱手势/布局/恢复与 USB 演奏台，以及独立
  候选的 CoreMIDI、SF2、静态分页、签名 IPA 和 Privacy Report。
- 测试数量、工具版本与通过结果只记录当前 commit 的实际输出，不在架构文档中
  写死历史数字。
