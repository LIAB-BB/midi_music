# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**本项目的施工者**: 你（Claude）+ Codex（另一个 AI 编码工具）。你们两个 AI 在这个项目上共同施工，本文档是 Claude Code 的"交接单"。

通用仓库规则以 `AGENTS.md` 为准；本文只补充 Claude Code 需要特别注意的协作细节和当前架构快照。

---

## Build & Run Commands

```bash
# 安装 Flutter 依赖
flutter pub get

# 安装 iOS 原生依赖
cd ios && pod install && cd ..

# 运行（接设备或模拟器）
flutter run

# 构建打包
flutter build ios --debug --no-codesign   # iOS 调试（免签名）
flutter build apk --release               # Android 发布

# 清理缓存
flutter clean && flutter pub get && cd ios && pod install && cd ..

# 静态分析（提交前必跑）
flutter analyze

# 运行全部测试（提交前必跑）
flutter test
```

---

## 双 AI 协作规则（你 + Codex）

这是最重要的部分。不管上次修改是谁做的，每次接手都要遵守以下规则：

### 核心原则

1. **测试是契约**：不论谁写的代码，`flutter test` 必须全绿。测试是你们两个之间最稳定的接口规范。
2. **提交前必跑**：`flutter analyze && flutter test`，一个不能少。
3. **单任务单主改**：一个任务只让一个 AI 改代码，另一个 AI 负责审阅 diff，避免交替改同一个核心文件。
4. **文档同步**：任何一方加了新概念、新模块、新接口，必须更新 `AGENTS.md` / `CLAUDE.md` 中对应内容。不更新 = 不存在。

### 模块分工建议

| 模块路径 | 稳定性 | 改动建议 |
|---------|--------|---------|
| `lib/models/midi_track.dart` | 🔒 高 | **数据模型层**。改动会影响所有下游代码，改前确认 test 覆盖充分 |
| `lib/core/midi/midi_engine.dart` | 🔒 高 | 引擎封装层，底层依赖 `flutter_midi_pro`，改动后务必真机验证音质 |
| `lib/core/midi/midi_player.dart` | 🔒 中 | 核心播放控制器，`ChangeNotifier`，改动注意线程安全 |
| `lib/core/midi/midi_parser.dart` | 🔒 中 | 文件/asset 解析在后台 isolate 执行（`compute`），加字段注意序列化 |
| `lib/core/midi/tempo_map.dart` | 🔒 高 | 纯算法模块，tick ↔ 秒互转，有充分测试，改动安全 |
| `lib/core/follow/follow_mode_controller.dart` | 🔄 中 | 跟随算法核心，参数调优为主战场 |
| `lib/core/follow/follow_mode_session.dart` | 🔄 中 | 会话生命周期协调层，改动注意并发安全 |
| `lib/core/follow/microphone_input.dart` | 🔒 中 | 麦克风→音高管道，改动后需真机验证 |
| `lib/core/follow/onset_detector.dart` | 🔒 中 | 纯信号检测逻辑，无平台依赖 |
| `lib/core/follow/pitch_input.dart` | 🔒 高 | 抽象接口，改了所有实现都得跟着改 |
| `lib/core/follow/follow_playback_target.dart` | 🔒 高 | 抽象接口，同上 |
| `lib/ui/pages/home_page.dart` | 🔄 低 | 首页 UI，改动影响范围小 |
| `lib/ui/pages/diagnostics_page.dart` | 🔄 低 | 测试诊断页，显示音色、麦克风、曲目和构建状态 |
| `lib/ui/pages/player_page.dart` | 🔄 低 | 播放页 UI，1410 行太大，后续会拆分 |
| `lib/ui/widgets/player_display_data.dart` | 🔄 低 | UI 展示数据层，适合随界面结构一起迭代 |
| `lib/ui/theme/luxury_theme.dart` | 🔒 高 | 主题定义，改动影响全部 UI |
| `lib/main.dart` + `lib/app.dart` | 🔒 高 | 入口，极少改动 |

- 🔒 = 核心基础设施，改动后务必跑全量测试
- 🔄 = 迭代活跃区，改动频率高，做好测试即可

### Commit 约定

- **改 `lib/models/` 中的字段或接口**：commit message 第一行加 `BREAKING:` 前缀，提醒另一个 AI 注意兼容性
  - 例如：`BREAKING: MidiNote 新增 rubatoOffset 字段`
- **commit message 用中文**（项目惯例）
- **不要提交 `🤖 Generated with Claude Code` 等 AI 签名行**
- **不要提交本地 IDE 工作区**：`midi_music.code-workspace` 属于本机配置，不入库
- **提交 `pubspec.lock`**：这是 Flutter App，需要锁定依赖版本，保证 Codex / Claude Code / CI 使用同一依赖图

### 代码风格统一

项目已开启严格的 lint 规则（见 `analysis_options.yaml`），包括：
- `strict-casts: true` — 禁止不安全隐式类型转换
- `strict-inference: true` — 防止推断失败时退化为 `dynamic`
- `unawaited_futures` — 未 await 的 Future 必须用 `unawaited()` 包裹
- `require_trailing_commas` — 减少 git diff 冲突，对双人施工至关重要
- `avoid_void_async` — 禁止 async void
- `prefer_const_constructors` — Flutter 性能优化

接手代码时，如果 `flutter analyze` 不通过，先修 lint 再动工。

### 加新模块/新概念时的 checklist

- [ ] 新模块放在对应的 `lib/core/` 或 `lib/ui/` 子目录下
- [ ] 如果是核心逻辑，提供抽象接口（参考 `PitchInput`、`MidiPlaybackEngine` 的模式）
- [ ] 写测试（至少覆盖核心路径和生命周期边界）
- [ ] 更新 `AGENTS.md` / `CLAUDE.md` 的架构部分
- [ ] 跑 `flutter analyze && flutter test` 全绿再提交

---

## Project Architecture

### Entry Point (`lib/main.dart` + `lib/app.dart`)
- Provider 注入 `MidiPlayerController`，全局单一实例
- `CupertinoApp`，暗色主题

### Models (`lib/models/`)
- `midi_track.dart` — 全部数据模型：`MidiEventType`（枚举）、`MidiNote`（音符）、`TimelineEvent`（时间线事件，带 `trackIndex`、`Comparable`，通过 `_eventPriority` 确保同 tick 时 NoteOff 优先于 NoteOn）、`MidiTrackInfo`（轨道，支持多 channel、静音/音量）、`MidiSongData`（歌曲）、`TempoChange`/`TimeSignatureChange`

### MIDI Playback (`lib/core/midi/`)
- `midi_engine.dart` — `MidiPlaybackEngine` 抽象 + `MidiEngine` 实现。封装 `flutter_midi_pro`，按 channel 串行化操作队列（`_channelOperations`），通过 `_operationGeneration` 代际机制确保 `allNotesOff` 时取消未完成的排队操作
- `midi_parser.dart` — `MidiFileParser`，使用 `dart_midi_pro` 解析 MIDI 文件。支持文件路径、Flutter asset 和原始 bytes 解析；文件/asset/后台 bytes 路径通过 `compute` isolate 执行。FIFO 配对重叠音符（`_PendingNote` 链表）
- `tempo_map.dart` — tick ↔ 秒互转，支持多 tempo 变化点，二分查找，批量顺序应用优化
- `midi_player.dart` — **核心播放控制器**，`ChangeNotifier`。5ms 调度 + 33ms UI 节流（~30Hz）、播放/暂停/停止/跳转/变速（0.25–4.0x）、按 `track.index` 查找轨道（非列表位置）、静音/音量控制（零音量自动停音）、每轨道活动音符追踪（重叠音符正确计数）、seek 后 Program Change 状态恢复、`_fireAndForget` 统一管理异步引擎操作 + `onPlaybackError` 异常回调、SoundFont 自动下载/缓存

### Tempo Follow (`lib/core/follow/`)
- `pitch_input.dart` — `PitchInput` 抽象接口（`pitchStream`、`start()`、`dispose()`）
- `microphone_input.dart` — `MicrophoneInput` 实现 `PitchInput`。`flutter_audio_capture` → `pitch_detector_dart`（YIN 算法）→ 输出 `Stream<PitchData>`。流控（处理中跳过新帧）、RMS 音量计算
- `onset_detector.dart` — 纯 Dart 的 onset 检测器。输入 `PitchData` 流，输出 `Stream<OnsetEvent>`。含 `PitchData` 和 `OnsetEvent` 数据模型。检测逻辑：音量/精度阈值 + 去抖（80ms）+ 静音帧计数
- `follow_mode_controller.dart` — 跟随模式状态机（idle → following → waitingForOnset）。核心算法：onset 与乐谱音符匹配（容差 + 可选八度误差容忍）、EMA（α=0.3）平滑速度因子、测量速度可信范围过滤、音符跳跃检测（向前最多 3 个）、休止符检测、连续未匹配降速并请求外部按播放位置重对齐。含 `FollowModeConfig` 配置
- `follow_mode_session.dart` — **跟随模式会话**，串联 `PitchInput` → `OnsetDetector` → `FollowModeController` → `FollowPlaybackTarget` 的完整生命周期。防并发 start、dispose 打断 start、根据跟随状态自动控制播放器（休止时暂停、恢复时播放），支持 `resumeFromTime()` 在用户 seek 或连续未匹配时按当前播放时间重新对齐
- `follow_playback_target.dart` — `FollowPlaybackTarget` 抽象 + `MidiFollowPlaybackTarget` 实现，适配 `MidiPlayerController`

### UI Layer (`lib/ui/`)
- `pages/home_page.dart` — 首页，文件选择器（`file_picker`）和内置示例曲目入口，加载 MIDI 并跳转播放页。页面状态类只处理导入/导航，首页 hero 和指标布局拆到 `_HomeContent` / `_HomeHeroPanel`
- `pages/diagnostics_page.dart` — 测试诊断页，显示 SoundFont 状态/重试、麦克风权限/系统设置、当前曲目、版本和隐私提示，用于真机测试反馈
- `pages/player_page.dart` — 播放器页面。仅保留页面骨架和跟随模式状态管理（`_PlayerBodyState`），滚动内容拆到 `_PlayerStageContent`，状态横幅拆到 `_PlayerStatusStack`；用户 seek 后会同步跟随会话的播放时间重对齐
- `widgets/player_display_data.dart` — UI 展示数据层。把播放器、跟随状态、SoundFont 状态和轨道信息转换成界面需要的标题、标签、颜色、时间文本和 Key 友好的轨道数据，降低人工重做 UI 时误碰核心控制器的概率
- `widgets/stage_console.dart` — StageConsole（曲名/进度/BPM/仪表盘）、StageDial、StageMetric；进度条 seek 支持外部 `onSeek` 回调
- `widgets/transport_deck.dart` — TransportDeck（运输按钮）、TransportButton、ConsoleNote；回退/快进/归零支持外部 `onSeek` 回调
- `widgets/performance_console.dart` — PerformanceConsole（跟随模式开关/手动速度滑块）、ConsoleCard
- `widgets/track_salon.dart` — TrackSalon（轨道列表）、TrackTile（单轨道磁贴）
- `widgets/soundfont_banner.dart` — SoundfontBanner（音色下载/重试横幅）
- `widgets/luxury_controls.dart` — 共享 UI 控件：`LuxuryActionButton`（主/次操作按钮）、`LuxuryMetricTile`（指标卡），用于减少首页和播放器组件之间的样式重复
- `widgets/player_helpers.dart` — 共享组件：SectionEyebrow、OrnamentLine、StatusBadge；稳定控件 Key：`PlayerUiKeys`；工具函数：`followAccent()`、`followLabel()`、`formatClock()`、`displaySongTitle()`
- `theme/luxury_theme.dart` — 黑金主题。`LuxuryPalette`（颜色常量）、`LuxuryBackdrop`（渐变背景 + 光晕）、`LuxuryPanel`（圆角面板容器）、`luxuryDisplayStyle`（Georgia 展示字体）
- `docs/ui施工说明.md` — UI 人工施工说明，列出可改区域、禁止误改的跟随生命周期函数、必须保留的回调语义和验收命令

### Tests (`test/`，共 81 用例)
- `midi_player_controller_test.dart` — 播放控制器调度测试（~24 用例，含 Program Change 追踪、轨道 index 查找、零音量/静音边界、播放异常上下文、同步/异步 NoteOn 失败清理）
- `midi_engine_test.dart` — 引擎通道串行化测试（5 用例）
- `midi_timeline_test.dart` — 事件排序和音符配对测试（2 用例）
- `midi_parse_test.dart` — 解析真实 MIDI 文件和 Flutter asset 测试（2 用例）
- `midi_regression_test.dart` — **MIDI 解析回归测试**（22 用例）：16 个合成 MIDI（Format 0/1、重叠音符、tempo/拍号、PPQ、边界）+ 6 个真实古典 MIDI（巴赫/莫扎特/肖邦/贝多芬，来自 BitMidi）
- `follow_mode_controller_test.dart` — 跟随算法测试（10 用例，含 seek/currentTime 重对齐、idle 恢复、seek 到长休止等待和连续未匹配重对齐请求）
- `follow_mode_session_test.dart` — 跟随会话生命周期测试（9 用例，含长休止暂停恢复、按播放时间重对齐、seek 到长休止暂停等待、连续未匹配自动重对齐、dispose 回调清理）
- `microphone_input_test.dart` — 麦克风输入生命周期测试（4 用例）
- `player_seek_widgets_test.dart` — 播放页 seek 控件合同测试（2 用例）
- `widget_test.dart` — App smoke test

测试使用 `Completer` 做异步时序控制，Fake 实现（`_FakeMidiPlaybackEngine`、`_FakePitchInput`、`_FakePlaybackTarget`、`_FakeAudioCaptureAdapter`、`_FakeMidiPro`）覆盖完整。

### Assets (`assets/midi/`)
- `Beethoven-Moonlight-Sonata.mid` — 贝多芬月光奏鸣曲（Format 1，8 tracks，PPQ=120）
- `bach_wtc1_prelude.mid` — 巴赫平均律前奏曲 BWV 846（Format 1，13 tracks，PPQ=96）
- `mozart_k545.mid` — 莫扎特钢琴奏鸣曲 K545（Format 1，4 tracks，PPQ=120）
- `chopin_nocturne.mid` — 肖邦夜曲（Format 1，14 tracks，PPQ=384）
- `beethoven_moonlight_2.mid` — 贝多芬月光第二乐章（Format 1，11 tracks，PPQ=96）

---

## iOS Specifics

- **部署目标**: iOS 13.6（`Podfile` 中指定）
- **CocoaPods 镜像**: `https://mirrors.tuna.tsinghua.edu.cn/git/CocoaPods/Specs.git`
- **音频会话**: AppDelegate 配置 `playAndRecord` + `allowBluetooth` + `defaultToSpeaker` + `mixWithOthers`
- **xcconfig**: 3 个配置文件（Debug/Profile/Release）均 `#include` Pods 配置
- **麦克风权限**: `Info.plist` 中 `NSMicrophoneUsageDescription` 已配置

---

## Key Patterns

- **状态管理**: Provider + ChangeNotifier（`MidiPlayerController` 是唯一全局状态）
- **多轨道共享 channel**: 通过 `trackIndex`（而非 channel）做静音/音量控制
- **音频处理管道**: 麦克风 → `PitchDetector` → `OnsetDetector` → `FollowModeController` → `setSpeed()`
- **线程安全**: UI 回调使用 `SchedulerBinding.addPostFrameCallback()` 包裹
- **生命周期守卫**: 所有公开方法开头检查 `_isDisposed`，异步操作支持 `dispose()` 打断
- **SoundFont**: 首次运行自动从 CDN 下载 TimGM6mb.sf2（~6MB），缓存到应用目录，3 个后备 URL
- **依赖注入**: `MidiPlayerController`、`MidiEngine`、`MicrophoneInput` 等均支持通过构造函数注入替代实现，便于测试
- **异步错误处理**: 引擎操作（NoteOn/NoteOff/ProgramChange）通过 `_fireAndForget()` 统一调度，失败时触达 `onPlaybackError` 回调；UI 端以红色横幅展示 4 秒后自动消失
- **PlayerPage 已拆分**: 原先 1410 行的单文件已拆为 7 个文件（1 页面 + 5 组件 + 1 工具），改 UI 时优先找对应的 widget 文件

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| flutter_midi_pro | ^3.1.4 | MIDI 引擎（SF2 播放） |
| dart_midi_pro | ^1.0.4 | MIDI 文件解析 |
| flutter_audio_capture | ^1.1.11 | 麦克风音频输入 |
| pitch_detector_dart | ^0.0.7 | 音高检测（YIN 算法） |
| provider | ^6.1.0 | 状态管理 |
| file_picker | ^8.0.0 | 文件选择 |
| permission_handler | ^11.3.0 | 权限管理 |
| path_provider | ^2.1.0 | 应用目录路径 |
