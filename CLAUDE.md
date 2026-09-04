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
5. **产品治理**：`docs/product/release_scope.md` 定义当前范围，`docs/product/capability_matrix.md` 记录证据等级，`docs/evidence/asset_manifest.md` 决定资源能否分发；历史 plan/spec 与长期报告不得覆盖这三份文档。

### 模块分工建议

| 模块路径 | 稳定性 | 改动建议 |
|---------|--------|---------|
| `lib/models/midi_track.dart` | 🔒 高 | **数据模型层**。改动会影响所有下游代码，改前确认 test 覆盖充分 |
| `lib/core/midi/midi_engine.dart` | 🔒 高 | 引擎封装层，底层依赖 `flutter_midi_pro`，改动后务必真机验证音质 |
| `lib/core/midi/midi_player.dart` | 🔒 中 | 核心播放控制器，`ChangeNotifier`，改动注意线程安全 |
| `lib/core/midi/midi_parser.dart` | 🔒 中 | 解析在后台 isolate 执行（`compute`），加字段注意序列化 |
| `lib/core/midi/tempo_map.dart` | 🔒 高 | 纯算法模块，tick ↔ 秒互转，有充分测试，改动安全 |
| `lib/models/score_session.dart` | 🔒 高 | 谱面会话边界；原文、播放数据和小节映射必须保持一致 |
| `lib/core/score/` | 🔒 高 | 受控谱面桥接与播放同步边界，网页层不得直接操作播放器 |
| `lib/core/notation/` | 🔒 高 | MIDI 声部分析、默认解析与显示谱生成；不得把量化结果写回播放数据 |
| `lib/core/follow/follow_mode_controller.dart` | 🔄 中 | 跟随算法核心，参数调优为主战场 |
| `lib/core/follow/follow_mode_session.dart` | 🔄 中 | 会话生命周期协调层，改动注意并发安全 |
| `lib/core/follow/midi_follow_mode_session.dart` | 🔒 高 | 当前 iOS USB MIDI 跟随会话，管理多条电子琴轨静音恢复 |
| `lib/core/midi_input/` | 🔒 高 | USB MIDI 平台边界；Dart 逻辑需测试，原生改动需 iPhone 真机验证 |
| `lib/core/follow/microphone_input.dart` | 🔒 中 | 麦克风→音高管道，改动后需真机验证 |
| `lib/core/follow/onset_detector.dart` | 🔒 中 | 纯信号检测逻辑，无平台依赖 |
| `lib/core/follow/pitch_input.dart` | 🔒 高 | 抽象接口，改了所有实现都得跟着改 |
| `lib/core/follow/follow_playback_target.dart` | 🔒 高 | 抽象接口，同上 |
| `lib/ui/pages/home_page.dart` | 🔄 低 | 首页 UI，改动影响范围小 |
| `lib/ui/pages/player_page.dart` | 🔄 低 | USB MIDI 高级演奏台，当前约 587 行；默认 K.478 首页可达 |
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
- `midi_score_part.dart` — MIDI 自动谱的声部类别、谱表模式、轨道/channel 来源、目录、默认来源与记谱警告模型
- `score_session.dart` — `ScoreSession` 统一保留谱面原文、`MidiSongData`、来源/映射状态与 `ScoreMeasureBoundary` 真实小节边界；`midiNotation` 会话保存生成谱、曲目指纹、选择和警告

### MIDI Playback (`lib/core/midi/`)
- `midi_engine.dart` — `MidiPlaybackEngine` 抽象 + `MidiEngine` 实现。封装 `flutter_midi_pro`，按 channel 串行化操作队列（`_channelOperations`），通过 `_operationGeneration` 代际机制确保 `allNotesOff` 时取消未完成的排队操作
- `midi_parser.dart` — `MidiFileParser`，使用 `dart_midi_pro` 解析 MIDI 文件。FIFO 配对重叠音符（`_PendingNote` 链表）；同步 `parseBytes()` 仅供 isolate/内部使用，asset 与文件入口调用 `parseBytesInBackground()`，`parseFile()` 复用同一后台 `compute` 边界
- `tempo_map.dart` — tick ↔ 秒互转，支持多 tempo 变化点，自动补齐 tick 0 默认 tempo、排序并合并同 tick 事件，二分查找，批量顺序应用优化
- `measure_map.dart` — `MeasureMap` 在 MIDI-only 会话中按拍号推算小节，在谱面会话中优先消费显式 MusicXML 真实边界；安全查询会拒绝越界或不可交互小节
- `midi_player.dart` — **核心播放控制器**，`ChangeNotifier`。5ms 调度 + 33ms UI 节流（~30Hz）、播放/暂停/停止/跳转/变速（0.25–4.0x）、`loadScore()`/`loadSong()` 原子替换会话与小节映射，并提供 `currentMeasureOrdinal`、`seekToMeasure()` 及前后可交互小节导航；`updateScorePresentation()` 只接受复用当前 `MidiSongData` 的有效交互会话，无损保持 time/speed/AB/playing；`clearScore()` 在等待异步资源时原子卸载旧曲、位置与 AB，但保留 SoundFont 和全局速度；按 `track.index` 查找轨道（非列表位置）、静音/音量控制（零音量自动停音）、每轨道活动音符追踪（重叠音符正确计数）、seek 后 Program Change 状态恢复、`_fireAndForget` 统一管理异步引擎操作 + `onPlaybackError` 异常回调、SoundFont 自动下载/缓存

### MIDI Notation (`lib/core/notation/`)
- `midi_part_analyzer.dart` — 按有音符轨道和 channel 建稳定来源，结合通道 10、明确轨道名和 GM program 分类；合并钢琴来源为默认 grand staff，并限制 64 条轨道 / 500,000 个音符
- `midi_score_selection.dart` — 默认优先级为有效本曲默认 > 匹配全局声部类别 > 自动钢琴 > 非打击乐合奏 > 打击乐回退，失效 ID 自动忽略且不会生成空谱
- `midi_to_musicxml_converter.dart` — 从原 MIDI 音符生成只供显示的 MusicXML 和原 tick 对齐的小节边界，覆盖双谱表、明确 upper/lower 左右手来源保留、和弦、休止、附点、三连音、最多四 voice、跨小节 tie 与打击乐；量化不进入播放时间线，最终 UTF-8 输出受 16 MiB 移动端安全上限约束
- `midi_notation_service.dart` — analyzer/resolver/converter 的可取消 isolate 编排边界；`prepare()` 生成初始目录、选择与会话，`rebuild()` 只更换选择后的显示谱；`MidiNotationBuilder.cancel()` 会真实终止当前 `Isolate.spawn` worker，`onError`/`onExit` 保证 Future 到达终态并关闭端口

### Interactive Score (`lib/core/score/`)
- `ScoreSession` 是谱面原文、播放数据与小节映射的唯一会话边界。
- `ScorePlaybackCoordinator` 是网页谱面事件进入播放器的唯一入口。
- OSMD 仅负责离线排版、命中候选与高亮；它不能直接调用播放器。
- MIDI 使用真实音符自动生成谱面，不恢复 seed 假谱、PDF 黑框或钢琴卷帘；OSMD 只消费显示用 MusicXML。
- `InteractiveScoreView` 在 isolate 中完成 MusicXML UTF-8/base64 编码；renderer 采用 last-request-wins，MusicXML 清空、surface 替换或 dispose 会使旧端口失效，当前 surface 的编码/JavaScript 异常进入可读错误态。
- `score_renderer_protocol.dart` 校验本地 renderer 消息的类型、范围和小节号；不可信或不可映射的小节不得触发跳转。

### Settings (`lib/core/settings/`)
- 声部默认 setter 返回可等待的 `Future<void>`，通过串行事务持久化；写盘失败会恢复完整声部设置快照并排队纠正写，练习页只在事务成功后显示“已设为默认”。

### Score Import (`lib/core/import/`)
- `score_import_service.dart` — 乐谱导入分流服务。支持 MIDI、MusicXML 和 PDF；PDF 通过 `PdfToMusicXmlConverter` 先转 MusicXML，再进入统一播放数据模型
- `musicxml_parser.dart` — 轻量 MusicXML → `ScoreSession`/`MidiSongData` 解析器。保留 MusicXML 原文并生成按书写顺序的真实小节边界，覆盖 MVP 所需的 partwise MusicXML：音高、休止、和弦、divisions、拍号和 tempo；钢琴二重奏按多个 part 转为多个轨道，不一致的小节标记为不可交互；总时长取所有音符最大 `endTick`
- `pdf_omr_client.dart` — HTTP OMR 客户端。通过 `OMR_SERVICE_BASE_URL` 配置服务端地址，创建 `/v1/omr/jobs` 任务并轮询 MusicXML 结果
- `pdf_to_musicxml_converter.dart` — PDF 到 MusicXML 转换抽象，隔离本地测试 Fake 和服务端 OMR 实现

### OMR Server (`server/omr_service/`)
- FastAPI 最小服务端骨架，接口遵循 `docs/omr_service_contract.md`
- 接收 PDF 后后台调用 Audiveris：`audiveris -batch -transcribe -export -output ...`
- 服务端不把 PDF 识谱逻辑放进 Flutter App；App 端只上传 PDF、轮询任务、消费 MusicXML
- Dockerfile 仅包含 Python API 服务，部署时仍需安装或挂载 Audiveris 运行时
- OMR 只属于受控开发路径，不进入根默认双入口或独立 K.478 TestFlight 候选

### Tempo Follow (`lib/core/follow/`)
- `midi_follow_mode_session.dart` — **默认 K.478 首页可达的高级演奏台跟随会话**。消费 USB MIDI Note On，驱动 `FollowModeController`；聚合选中的多条电子琴轨，启动时一起静音，退出时恢复用户原始静音状态
- `pitch_input.dart` — `PitchInput` 抽象接口（`pitchStream`、`start()`、`dispose()`）
- `microphone_input.dart` — `MicrophoneInput` 实现 `PitchInput`。`flutter_audio_capture` → `pitch_detector_dart`（YIN 算法）→ 输出 `Stream<PitchData>`。流控（处理中跳过新帧）、RMS 音量计算
- `onset_detector.dart` — 纯 Dart 的 onset 检测器。输入 `PitchData` 流，输出 `Stream<OnsetEvent>`。含 `PitchData` 和 `OnsetEvent` 数据模型。检测逻辑：音量/精度阈值 + 去抖（80ms）+ 静音帧计数
- `follow_mode_controller.dart` — 跟随模式状态机（idle → following → waitingForOnset）。可直接消费任意 `Stream<OnsetEvent>`；USB MIDI 默认精确音符匹配（0 半音、不跨八度），其余算法为 EMA 平滑、可信速度过滤、向前搜索、休止等待和按播放位置重对齐
- `follow_mode_session.dart` — **跟随模式会话**，串联 `PitchInput` → `OnsetDetector` → `FollowModeController` → `FollowPlaybackTarget` 的完整生命周期。防并发 start、dispose 打断 start、根据跟随状态自动控制播放器（休止时暂停、恢复时播放），支持 `resumeFromTime()` 在用户 seek 或连续未匹配时按当前播放时间重新对齐
- `follow_playback_target.dart` — `FollowPlaybackTarget` 抽象 + `MidiFollowPlaybackTarget` 实现，适配 `MidiPlayerController`

### MIDI Input (`lib/core/midi_input/` + `ios/Runner/`)
- `midi_input.dart` — 平台无关的设备、消息、状态模型和 `MidiInput` 接口
- `ios_midi_input.dart` — MethodChannel/EventChannel 适配，管理设备状态和 MIDI 消息流
- `CoreMidiInputPlugin.swift` — 直接使用 iOS CoreMIDI，自动连接当前全部 MIDI 输入源，处理热插拔与 running status；当前产品仅使用 Note On

### UI Layer (`lib/ui/`)
- `pages/home_page.dart` — 默认 K.478 首页，提供两个明确入口：“查看交互五线谱”进入 `ScorePracticePage`，“开始 USB MIDI 排练”进入 `PlayerPage`
- `pages/home_page_legacy.dart` — 非默认通用曲库/导入页；通过可注入的 `ScoreFilePicker` 与 `ScoreImportService` 导入 MIDI/MusicXML/PDF。它的可达能力不得写成默认首页承诺
- `pages/score_practice_page.dart` — 统一谱面练习页。以单一 `InteractiveScoreView`、悬浮 `ScoreZoomControls` 和固定 `ScoreTransportBar` 组成主界面；MIDI 等待设置加载后自动生成默认谱并支持无损多选总谱，MusicXML/PDF 保持直接路径；异步载入前用 `clearScore()` 隔离旧曲，失败态可重试且不泄漏上一曲
- `pages/player_page.dart` — USB MIDI 高级演奏台。初始化输入、展示连接状态并管理 `MidiFollowModeSession`；用户 seek 后同步跟随会话重对齐
- `widgets/interactive_score_view.dart` — 离线 MusicXML 谱面表面，负责加载/错误/暂无谱面状态，并通过受控 renderer port 与本地 OSMD 桥接；缩放使用 OSMD 原生 Zoom 重排，renderer ready、载入和缩放请求各自按代际收敛，连续缩放在桥接层以 80ms 空闲窗口合并为最后一次全量排版
- `widgets/score_zoom_controls.dart` — 固定栏上方的紧凑缩放控件；默认 70%，按 10% 在 50%–140% 间调整并提供中文语义与 44pt 点击区
- `widgets/score_transport_bar.dart` — 练习页固定控制栏，提供前后小节、播放/暂停、速度和 AB 循环
- `widgets/score_part_picker.dart` — `showScorePartPicker()` Cupertino 多选声部面板；入口快照选择与警告集合，返回应用、本曲默认或全局默认的不可变声部结果
- `widgets/stage_console.dart` — StageConsole（曲名/进度/BPM/仪表盘）、StageDial、StageMetric；进度条 seek 支持外部 `onSeek` 回调
- `widgets/transport_deck.dart` — TransportDeck（运输按钮）、TransportButton、ConsoleNote；回退/快进/归零支持外部 `onSeek` 回调
- `widgets/performance_console.dart` — PerformanceConsole（跟随模式开关/手动速度滑块）、ConsoleCard
- `widgets/track_salon.dart` — TrackSalon（轨道列表）、TrackTile（单轨道磁贴）
- `widgets/soundfont_banner.dart` — SoundfontBanner（音色下载/重试横幅）
- `widgets/player_helpers.dart` — 共享组件：SectionEyebrow、OrnamentLine、StatusBadge；工具函数：`followAccent()`、`followLabel()`、`formatClock()`、`displaySongTitle()`
- `widgets/midi_piano_roll.dart` — 解析后 MIDI 的实时钢琴卷帘组件，保留给旧高级演奏台；不是练习页主视图
- `widgets/pdf_score_viewer.dart` — 未接入默认 root 页面的一段旧分页组件；根练习页不得恢复为直接 PDF/PNG 显示，PDF 导入须先经 OMR 生成 MusicXML
- `theme/luxury_theme.dart` — 黑金主题。`LuxuryPalette`（颜色常量）、`LuxuryBackdrop`（渐变背景 + 光晕）、`LuxuryPanel`（圆角面板容器）、`luxuryDisplayStyle`（Georgia 展示字体）

### Tests

测试总数、Flutter/Dart 版本和通过结果必须由当前 commit 的实际命令输出刷新；
不要把历史数字写成合并后的验证结果。
- `midi_player_controller_test.dart` — 播放控制器调度测试（~24 用例，含 Program Change 追踪、轨道 index 查找、零音量/静音边界、播放异常上下文、同步/异步 NoteOn 失败清理）
- `midi_engine_test.dart` — 引擎通道串行化测试（5 用例）
- `midi_timeline_test.dart` — 事件排序和音符配对测试（2 用例）
- `midi_parse_test.dart` — 解析真实 MIDI 文件测试（1 用例）
- `musicxml_import_test.dart` — MusicXML/PDF 导入测试（4 用例，含服务端 OMR 任务协议 Fake 和钢琴二重奏多轨道）
- `midi_regression_test.dart` — **MIDI 解析回归测试**（22 用例）：16 个合成 MIDI（Format 0/1、重叠音符、tempo/拍号、PPQ、边界）+ 6 个真实古典 MIDI（巴赫/莫扎特/肖邦/贝多芬，来自 BitMidi）
- `follow_mode_controller_test.dart` — 跟随算法测试（10 用例，含 seek/currentTime 重对齐、idle 恢复、seek 到长休止等待和连续未匹配重对齐请求）
- `follow_mode_session_test.dart` — 跟随会话生命周期测试（9 用例，含长休止暂停恢复、按播放时间重对齐、seek 到长休止暂停等待、连续未匹配自动重对齐、dispose 回调清理）
- `microphone_input_test.dart` — 麦克风输入生命周期测试（4 用例）
- `player_seek_widgets_test.dart` — 播放页 seek 控件合同测试（2 用例）
- `score_session_test.dart` / `musicxml_import_test.dart` — `ScoreSession`、MusicXML 原文保留、真实小节边界与 PDF OMR 导入回归
- `score_renderer_protocol_test.dart` / `interactive_score_view_test.dart` / `score_renderer_assets_test.dart` — 本地 OSMD 桥接消息校验、谱面表面、原生缩放代际与 asset bundle 回归
- `score_playback_coordinator_test.dart` / `score_measure_navigation_test.dart` — 小节命中、播放同步、自动跟随与小节导航回归
- `midi_part_analyzer_test.dart` / `midi_score_selection_test.dart` — 轨道名、GM、打击乐、K.478 钢琴组合和本曲/全局/自动默认优先级
- `midi_to_musicxml_converter_test.dart` / `midi_notation_service_test.dart` — 双谱表、upper/lower 左右手来源保留、K.478 可演奏和弦跨度、总谱、量化、tie、三连音、多 voice、复杂度上限、isolate 会话与原播放真值
- `app_settings_test.dart` — 声部类别与曲目选择的 schema 迁移、非法值回退、稳定排序、容量限制、串行事务与失败纠正写
- `score_practice_page_test.dart` / `score_zoom_controls_test.dart` / `home_score_navigation_test.dart` — 自动记谱、生成/错误/重试、无损换谱、缩放边界与布局、默认保存、竞态隔离和首页导入导航回归
- `score_part_picker_test.dart` — 声部多选、默认动作、输入快照、中文语义及横屏大字号滚动回归
- `widget_test.dart` — App smoke test
- `integration_test/midi_notation_render_test.dart` — 独立于根单元/Widget 测试；在 iOS WebView 用生产 `InteractiveScoreView` 等待本地 OSMD `ready` 和非空 layout，覆盖 dotted/triplet/tie、multi-voice、grand-staff、percussion、50%/70% 原生缩放、CSS rect、resize 与缩放后非首小节 gesture 命中

测试使用 `Completer` 做异步时序控制，Fake 实现（`_FakeMidiPlaybackEngine`、`_FakePitchInput`、`_FakePlaybackTarget`、`_FakeAudioCaptureAdapter`、`_FakeMidiPro`）覆盖完整。

### Assets (`assets/midi/`)
- `mozart_k478_piano_quartet.mid` — 莫扎特钢琴四重奏 K.478（Format 1；钢琴右手/左手与三条弦乐轨独立，来源与许可见 `docs/demo_assets.md`）
- `Beethoven-Moonlight-Sonata.mid` — 贝多芬月光奏鸣曲（Format 1，8 tracks，PPQ=120）
- `bach_wtc1_prelude.mid` — 巴赫平均律前奏曲 BWV 846（Format 1，13 tracks，PPQ=96）
- `mozart_k545.mid` — 莫扎特钢琴奏鸣曲 K545（Format 1，4 tracks，PPQ=120）
- `chopin_nocturne.mid` — 肖邦夜曲（Format 1，14 tracks，PPQ=384）
- `beethoven_moonlight_2.mid` — 贝多芬月光第二乐章（Format 1，11 tracks，PPQ=96）

### Assets (`assets/score_renderer/`)
- 离线 OSMD 运行时、桥接页与许可证随 Flutter asset bundle 打包；运行时不加载远程脚本。

### Assets (`assets/scores/`)
- `mozart_k478_piano_part.pdf` 与 `mozart_k478_piano_part/page-01.png` 至 `page-21.png` — K.478 同源对照/OMR 开发素材，不是根练习页的显示来源；根 `pubspec.yaml` 若仍声明 PNG 目录，发布前必须按资产台账移除或给出分发理由

### 独立 K.478 TestFlight 候选

- `apps/testflight_ios/` 是 iPhone-only、iOS 13.0+ 的独立 host。
- `packages/k478_practice/` 提供固定 K.478、21 张静态 PNG 分谱、离线
  Violin/Cello SF2 和候选播放器；不包含根 App 的 OSMD 交互谱面。
- `packages/core_midi_input/` 提供候选 CoreMIDI 输入边界。
- 根 App 与候选 App 的依赖、资产白名单、测试、真机与签名 IPA 证据分别验收，
  不能互相替代。对应清单为 `docs/release_checklist.md` 和
  `docs/releases/k478_testflight_checklist.md`。

---

## iOS Specifics

- **部署目标**: 根 App 为 iOS 13.6（根 `Podfile`）；独立候选为 iOS 13.0+
- **CocoaPods 镜像**: `https://mirrors.tuna.tsinghua.edu.cn/git/CocoaPods/Specs.git`
- **音频会话**: AppDelegate 配置 `playback` + `mixWithOthers`；电子琴自行发声，当前 demo 不占用麦克风
- **USB MIDI**: `CoreMidiInputPlugin.swift` 使用系统 CoreMIDI，无第三方 MIDI 输入依赖
- **xcconfig**: 3 个配置文件（Debug/Profile/Release）均 `#include` Pods 配置
- **麦克风权限**: `Info.plist` 中 `NSMicrophoneUsageDescription` 已配置

---

## Key Patterns

- **状态管理**: Provider + ChangeNotifier（`MidiPlayerController` 是唯一全局状态）
- **多轨道共享 channel**: 通过 `trackIndex`（而非 channel）做静音/音量控制
- **钢琴手别来源**: 合并钢琴 part 不等于丢弃轨道语义；记谱端优先保留 `upper/right hand/右手` 上谱表与 `lower/left hand/左手` 下谱表，无明确标记时才进入音高/跨度启发式分谱
- **当前跟随管道**: USB MIDI Note On → `MidiFollowModeSession` → `FollowModeController` → `setSpeed()`
- **线程安全**: UI 回调使用 `SchedulerBinding.addPostFrameCallback()` 包裹
- **生命周期守卫**: 所有公开方法开头检查 `_isDisposed`，异步操作支持 `dispose()` 打断
- **SoundFont**: 首次运行自动从 CDN 下载 TimGM6mb.sf2（~6MB），缓存到应用目录，3 个后备 URL
- **依赖注入**: `MidiPlayerController`、`MidiEngine`、`MicrophoneInput` 等均支持通过构造函数注入替代实现，便于测试
- **异步错误处理**: 引擎操作（NoteOn/NoteOff/ProgramChange）通过 `_fireAndForget()` 统一调度，失败时触达 `onPlaybackError` 回调；UI 端以红色横幅展示 4 秒后自动消失
- **PlayerPage 现状**: USB MIDI 高级演奏台约 587 行；默认 K.478 首页可达，改动 UI 时优先定位对应页面或 widget

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
| webview_flutter | 4.14.1 | iOS/Android 本地 OSMD 谱面 WebView |
