# 🎵 MIDI 伴奏 App

一款面向 iOS 的 Flutter MIDI 练习与伴奏应用。首页（乐库）同时提供内置曲目卡片与本地文件导入，当前主产品路径由此进入真实 MIDI 自动五线谱；用户可点击小节、选择声部、缩放谱面并播放原 MIDI。USB MIDI 变速跟随代码保留在高级演奏台，当前首页暂无产品入口。

## ✨ 核心功能

- **真实 MIDI 五线谱** — 内置和导入 MIDI 都从原始音符离线生成可点击的 MusicXML，不使用 seed 假谱；默认显示钢琴高低音双谱表，并保留 MIDI 中明确的 `upper/right hand` 与 `lower/left hand` 轨道归属，避免两只手的音被合并成不可演奏的大跨度和弦；也可多选弦乐等声部组成总谱；谱面默认以 70% 紧凑排版，底部 `− / +` 可在 50%–140% 间逐级缩放
- **统一导入管线** — MIDI 自动记谱；MusicXML 保持原文直接进入交互谱面；PDF 代码路径需先配置受控 OMR 服务，当前不作为默认试用能力
- **无损声部切换** — 原 `MidiSongData` 始终是唯一播放真值，换显示谱不重新加载歌曲，当前时间、速度、AB 循环和播放/暂停状态保持不变
- **可持久化声部默认** — 选择优先级为本曲默认 > 全局声部类别 > 自动钢琴 > 非打击乐合奏 > 打击乐回退
- **MIDI 文件播放** — 支持多轨道共享同一 MIDI 通道的复杂文件（如贝多芬月光奏鸣曲），播放/暂停/停止/进度控制
- **SoundFont 音色引擎** — 基于 FluidSynth (Android) / AVFoundation (iOS)，加载 SF2/SF3 音色库
- **轨道控制** — 按轨道控制音量和静音；共享通道上的同音重叠及通道级控制事件目前存在限制
- **USB MIDI 跟随（保留高级能力）** — 使用 iOS CoreMIDI 接收电子琴 Note On，实时调整伴奏速度；可选多个钢琴轨，并在跟随期间一起静音。当前首页不导航到该页，只在提供高级演奏台产品/调试入口时验收
- **iOS 风格 UI** — 全 Cupertino 组件，简约流畅

## 🏗️ 技术栈

| 技术 | 用途 |
|------|------|
| Flutter 3.44+ | 跨平台框架 |
| Cupertino Widgets | iOS 风格 UI |
| flutter_midi_pro | MIDI 引擎（FluidSynth/AVFoundation） |
| dart_midi_pro | MIDI 文件解析 |
| MIDI 记谱 + MusicXML + 离线 OSMD | 分析声部、生成显示谱、保留导入原文并离线排版交互五线谱；运行时不加载远程脚本 |
| iOS CoreMIDI | USB MIDI 设备发现和按键输入 |
| Provider | 状态管理 |

## 📁 项目结构

```
lib/
├── main.dart                          # 入口
├── app.dart                           # CupertinoApp 配置
├── core/
│   ├── midi/
│   │   ├── midi_engine.dart           # SoundFont 引擎封装
│   │   ├── midi_parser.dart           # MIDI 文件解析
│   │   ├── midi_player.dart           # 播放控制器
│   │   └── tempo_map.dart             # 速度映射
│   ├── midi_input/
│   │   ├── midi_input.dart             # MIDI 输入模型与接口
│   │   └── ios_midi_input.dart         # CoreMIDI 平台通道适配
│   ├── import/
│   │   ├── musicxml_parser.dart       # MusicXML 转播放时间线
│   │   └── score_import_service.dart  # MIDI/MusicXML/PDF 导入分流
│   ├── notation/
│   │   ├── midi_part_analyzer.dart     # 按轨道/channel 分析可选声部
│   │   ├── midi_score_selection.dart   # 本曲/全局/自动默认解析
│   │   ├── midi_to_musicxml_converter.dart # MIDI 转显示用 MusicXML
│   │   └── midi_notation_service.dart  # isolate 记谱服务边界
│   ├── score/                         # 谱面桥接协议与播放同步
│   └── follow/
│       ├── pitch_input.dart           # 音高输入抽象
│       ├── microphone_input.dart      # 麦克风音频输入
│       ├── onset_detector.dart        # 音符起始检测
│       ├── follow_mode_controller.dart # 变速跟随状态机
│       ├── midi_follow_mode_session.dart # USB MIDI 跟随会话
│       ├── follow_mode_session.dart   # 旧麦克风跟随会话（当前 UI 不使用）
│       └── follow_playback_target.dart # 跟随播放目标抽象
├── models/
│   ├── midi_track.dart                # MIDI 轨道模型
│   └── score_session.dart             # 谱面原文、播放数据与小节映射会话
└── ui/
    ├── pages/
    │   ├── home_page.dart             # 首页（文件选择）
    │   ├── score_practice_page.dart   # 交互谱面练习页
    │   └── player_page.dart           # 保留的高级演奏台
    ├── widgets/
    │   └── interactive_score_view.dart # 离线交互五线谱
    └── theme/
        └── luxury_theme.dart          # 黑金主题组件
test/
├── musicxml_import_test.dart           # MusicXML / PDF OMR 导入
├── score_session_test.dart             # 谱面会话与真实小节边界
├── score_measure_navigation_test.dart  # 小节导航
├── score_renderer_protocol_test.dart   # 渲染桥接消息校验
├── score_playback_coordinator_test.dart # 谱面与播放同步
├── score_practice_page_test.dart       # 练习页控制栏与状态
├── home_score_navigation_test.dart     # 首页导入导航
├── midi_part_analyzer_test.dart        # 声部识别与 K.478 默认钢琴
├── midi_score_selection_test.dart      # 默认选择优先级
├── midi_to_musicxml_converter_test.dart # 量化、总谱、tie/三连音
├── midi_notation_service_test.dart     # isolate 服务与播放真值
└── …                                  # MIDI、跟随与 App 回归测试
integration_test/
└── midi_notation_render_test.dart      # 真机本地 OSMD fixture
assets/
├── midi/
    ├── mozart_k478_piano_quartet.mid # 内置自动记谱 demo（钢琴四重奏）
    └── Beethoven-Moonlight-Sonata.mid # 其他测试用 MIDI 文件
├── score_renderer/                    # 离线 OSMD 运行时
└── scores/                            # 示例 PDF 与其 OMR 输入资源
docs/
└── release_checklist.md               # 上线前人工验收清单
```

## 🚀 快速开始

### 环境要求

- Flutter 3.44+
- Dart 3.12+
- iOS 13.6+

当前验证基线：Flutter 3.44.1 / Dart 3.12.1。

截至 2026-08-15 的验证记录中，`flutter test` 共 311 项；iOS WKWebView/OSMD fixture 另由
`integration_test/midi_notation_render_test.dart` 验证 dotted/triplet/tie、
multi-voice、grand-staff、percussion、缩放重排及缩放后小节点击。

### 安装与运行

```bash
# 克隆项目
git clone https://github.com/LIAB-BB/midi_music.git
cd midi_music

# 安装依赖
flutter pub get

# 运行（需连接设备或模拟器）
flutter run
```

### 质量检查

```bash
flutter analyze
flutter test
```

### 上线前验收

自动化测试通过后，发布或交付试用版前还需要完成人工验收。当前核心发布必测为 SoundFont、MIDI 自动五线谱、声部默认与无损总谱切换，以及 MusicXML 直接路径；PDF 只验证“未配置时明确拒绝”，除非本轮另行纳入受控 OMR 开发验收。真实电子琴 USB、轨道静音和跟随属于高级演奏台专项：仅在本版本提供该产品入口或调试入口时验收，且不阻断当前首页可达的核心发布路径。

详见 [`docs/release_checklist.md`](docs/release_checklist.md)。

### 项目文档

- [`PROJECT.md`](PROJECT.md)：当前产品目标、已实现范围和完成标准
- [`CONTEXT.md`](CONTEXT.md)：轨道、声部、左右手谱表和显示会话领域词汇
- [`docs/product/release_scope.md`](docs/product/release_scope.md)：当前试用范围唯一事实源
- [`docs/product/capability_matrix.md`](docs/product/capability_matrix.md)：实现、测试、设备和试用证据边界
- [`docs/product/strategy.md`](docs/product/strategy.md)：近期验证顺序与 Go/No-Go 决策
- [`docs/evidence/asset_manifest.md`](docs/evidence/asset_manifest.md)：MIDI、PDF、SoundFont 和渲染资源准入台账
- [`docs/demo_assets.md`](docs/demo_assets.md)：K.478 素材来源、许可与当前用途
- [`docs/omr_service_contract.md`](docs/omr_service_contract.md)：PDF OMR 服务协议
- [`docs/release_checklist.md`](docs/release_checklist.md)：自动门禁和人工验收
- [`战略规划.md`](战略规划.md) / [`MIDI伴奏可行报告.md`](MIDI伴奏可行报告.md)：长期路线与早期可行性研究，不代表当前产品入口

### 准备资源文件

App 首次运行会自动下载并缓存 TimGM6mb.sf2 SoundFont。也可以将 MIDI 测试文件放入 `assets/midi/` 目录。App 支持从设备文件系统选择 MIDI、MusicXML 和 PDF：MIDI 从真实音符自动生成显示谱，MusicXML 直接进入离线交互谱面，PDF 先经 OMR 服务生成 MusicXML。自动谱只负责显示，声音始终来自原始 MIDI 时间线。

当前“可以运行”不代表所有随包资源已经获准分发：K.478 证据仍需归档，其他内置 MIDI 和 TimGM6mb 随包文件在完成许可与交付核验前不得进入试用构建。具体状态见 [`docs/evidence/asset_manifest.md`](docs/evidence/asset_manifest.md)。

练习页的谱面默认按 70% 显示，便于一屏阅读更多系统；固定播放栏上方的 `− / 百分比 / +` 可按 10% 调整，范围为 50%–140%。连续点击会自动合并到最终档位，避免重复排版造成等待；缩放只重新排版显示谱，不会改变播放位置、速度、AB 循环或声部选择。

PDF 识谱服务通过 Dart define 配置：

```bash
flutter run --dart-define=OMR_SERVICE_BASE_URL=https://your-api.example.com
```

接口约定见 [`docs/omr_service_contract.md`](docs/omr_service_contract.md)，
最小服务端骨架见 [`server/omr_service`](server/omr_service)。

## 🎯 变速跟随模式

变速跟随由保留的高级演奏台提供，让伴奏跟着演奏者的节奏走。当前首页没有前往该页的产品入口；以下说明仅适用于提供高级演奏台产品入口或调试入口的专项验收。

### 工作原理

```
电子琴 USB MIDI Note On → 跟随状态机 → 实时调整伴奏速度
```

1. **CoreMidiInputPlugin** — 使用 iOS CoreMIDI 发现并连接输入源，解析通道消息
2. **IosMidiInput** — 将原生事件转换为 Dart 的设备状态和 `MidiInputMessage`
3. **FollowModeController** — 状态机（idle / following / waitingForOnset），默认精确匹配音符，并用 EMA 平滑速度因子
4. **MidiFollowModeSession** — 串联 MIDI 输入、跟随控制器和播放器；开始时静音选中的电子琴声部组，退出时恢复原状态

### 使用方式

前置条件：通过高级演奏台产品入口或调试入口进入 `PlayerPage`。当前普通首页导入会进入 `ScorePracticePage`，不能直接使用以下 USB 跟随流程。

1. 在播放器页面的轨道列表中，选择一个或多个由电子琴演奏的轨道；钢琴双手通常需要同时选择
2. 将 class-compliant USB MIDI 电子琴直接连接到 iPhone，确认页面显示设备名
3. 打开「跟随模式」开关；无需麦克风权限
4. 开始演奏，伴奏会自动跟随你的节奏
5. 关闭开关或点击停止按钮退出跟随模式

## 🔧 技术架构细节

### 多轨道共享 MIDI 通道

许多古典音乐 MIDI 文件（如贝多芬月光奏鸣曲）会将多个轨道（右手、左手）分配到同一个 MIDI 通道（channel 0）。本 App 使用 `trackIndex` 保留逻辑轨道身份：

- **TimelineEvent** 携带 `trackIndex` 字段标识事件所属轨道
- **解析器** 在解析每个轨道时自动填入 `trackIndex`
- **播放器** 按 `trackIndex`（而非 channel）判断静音并调整 NoteOn 力度

该机制可以覆盖多数按轨道静音和音量调整场景，但底层合成器仍按
`channel + note` 发声。多个轨道共享同一 channel/note 时，以及 Program
Change、Control Change、Pitch Bend 等通道级状态发生冲突时，暂不保证轨道完全独立。

### 钢琴左右手分谱

- 声部分析合并多个钢琴来源时，记谱转换会继续携带原始轨道身份。
- 名称明确包含 `upper`、`right hand`、“右手”的轨道优先进入高音谱表；`lower`、`left hand`、“左手”优先进入低音谱表。
- 没有明确手别名称的单轨钢琴 MIDI 仍使用音高、和弦跨度与上下文分谱；这是可读的练习谱推断，不是出版级指法或手指自动标注。

### 播放引擎

- 以约 5ms 周期轮询时间线，实际调度精度受平台、UI 和系统负载影响
- TempoMap 支持多 tempo 变化（如月光奏鸣曲含 61 个 tempo 变化点）
- 二分查找实现高效 seek 定位
- `updateScorePresentation()` 只替换复用同一 `MidiSongData` 的有效交互显示会话，因此声部切换不会重载播放数据
- `clearScore()` 用于等待异步资源或切换曲目时原子卸载旧播放会话，清空旧位置和 AB 循环，同时保留已准备的 SoundFont 与全局速度

## 📄 License

项目自有代码采用 MIT 许可。MIDI、PDF、SoundFont、OSMD、图标、字体及其他第三方/内容资产不自动适用该许可，须分别遵循 [`docs/evidence/asset_manifest.md`](docs/evidence/asset_manifest.md) 和随附许可证。
