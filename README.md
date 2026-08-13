# 🎵 MIDI 伴奏 App

一款面向 iOS 的 Flutter MIDI 伴奏应用。电子琴通过 USB MIDI 向 iPhone 发送按键，App 根据演奏速度调整其余声部的伴奏；电子琴本身负责钢琴发声。

## ✨ 核心功能

- **交互五线谱** — MusicXML 在 App 内离线排版；点击小节可跳转，播放时高亮当前小节
- **统一导入管线** — MusicXML 直接进入交互谱面；PDF 经 OMR 转为 MusicXML；MIDI-only 曲目标记为“仅伴奏”
- **MIDI 文件播放** — 支持多轨道共享同一 MIDI 通道的复杂文件（如贝多芬月光奏鸣曲），播放/暂停/停止/进度控制
- **SoundFont 音色引擎** — 基于 FluidSynth (Android) / AVFoundation (iOS)，加载 SF2/SF3 音色库
- **轨道控制** — 按轨道控制音量和静音；共享通道上的同音重叠及通道级控制事件目前存在限制
- **USB MIDI 跟随** — 使用 iOS CoreMIDI 接收电子琴 Note On，实时调整伴奏速度；可选多个钢琴轨，并在跟随期间一起静音
- **iOS 风格 UI** — 全 Cupertino 组件，简约流畅

## 🏗️ 技术栈

| 技术 | 用途 |
|------|------|
| Flutter 3.44+ | 跨平台框架 |
| Cupertino Widgets | iOS 风格 UI |
| flutter_midi_pro | MIDI 引擎（FluidSynth/AVFoundation） |
| dart_midi_pro | MIDI 文件解析 |
| MusicXML 解析器 + 离线 OSMD | 保留原文、生成播放小节映射并离线排版交互五线谱 |
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
└── …                                  # MIDI、跟随与 App 回归测试
assets/
├── midi/
    ├── mozart_k478_piano_quartet.mid # USB MIDI demo（钢琴四重奏）
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

自动化测试通过后，发布或交付试用版前还需要完成人工验收。当前核心发布必测为 SoundFont、MIDI-only 的固定播放控制，以及交互 MusicXML 谱面。真实电子琴 USB、轨道静音和跟随属于高级演奏台专项：仅在本版本提供该产品入口或调试入口时验收，且不阻断当前首页可达的核心发布路径。

详见 [`docs/release_checklist.md`](docs/release_checklist.md)。

### 准备资源文件

App 首次运行会自动下载并缓存 TimGM6mb.sf2 SoundFont。也可以将 MIDI 测试文件放入 `assets/midi/` 目录。App 支持从设备文件系统选择 MIDI、MusicXML 和 PDF：MusicXML 直接进入离线交互谱面，PDF 需要先经 OMR 服务生成 MusicXML，纯 MIDI 保持可播放的“仅伴奏”状态。

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

### 播放引擎

- 以约 5ms 周期轮询时间线，实际调度精度受平台、UI 和系统负载影响
- TempoMap 支持多 tempo 变化（如月光奏鸣曲含 61 个 tempo 变化点）
- 二分查找实现高效 seek 定位

## 📄 License

MIT
