# 🎵 MIDI 伴奏 App

> 当前定位：**iOS USB MIDI 封闭试用候选方案**，尚未达到 TestFlight 分发门槛。它不是面向所有乐器、所有乐谱或所有平台的通用智能伴奏产品。

这是一个 Flutter iOS 应用：电子琴通过 USB MIDI 向 iPhone 发送按键；App 静音由用户演奏的钢琴轨，并按演奏节奏播放其余 MIDI 声部。电子琴自身负责钢琴发声。

当前唯一的产品范围以 [`docs/product/release_scope.md`](docs/product/release_scope.md) 为准；功能实现状态见 [`docs/product/capability_matrix.md`](docs/product/capability_matrix.md)。

## 当前已实现的候选试用路径

- **iOS USB MIDI 输入** — 使用 CoreMIDI 接收 class-compliant USB MIDI 电子琴的 Note On。
- **分轨 MIDI 跟随** — 用户选择钢琴右、左手等演奏轨；App 在跟随期间静音这些轨，并调整其余伴奏轨的速度。
- **基础 MIDI 播放** — 支持 MIDI Format 0/1 的导入、播放、暂停、停止、seek、轨道音量和静音。
- **K.478 候选演示曲目** — 莫扎特 K.478 钢琴四重奏的离线钢琴分谱阅读与 MIDI 钢琴卷帘位置反馈；分发前仍须完成逐项资产核验。
- **iPhone 真机验收** — USB 热插拔、跟随和长休止恢复必须在真实 iPhone 与电子琴上验证；模拟器只适合界面检查。

## 当前不承诺

- 麦克风识别、任意乐器跟随、错音/跳段/复调鲁棒跟随，或“AI 交响乐团”。
- Android、蓝牙 MIDI、云曲库、教师功能、订阅、stem 混音或预渲染管弦乐音频。
- 通用 PDF 识谱、手写谱识别、MusicXML 五线谱渲染、自动翻页或乐谱与播放进度同步。
- 除完成授权核验的 K.478 候选资产外的内置曲库内容。

PDF OMR、麦克风输入和 MusicXML 解析代码可能出现在仓库中，但这不代表它们已可用于本次试用或可以对外宣传。

## 🏗️ 技术栈

| 技术 | 用途 |
|------|------|
| Flutter 3.44.1（CI 基线） | 应用框架 |
| Cupertino Widgets | iOS 风格 UI |
| flutter_midi_pro | iOS MIDI/SoundFont 播放引擎 |
| dart_midi_pro | MIDI 文件解析 |
| MusicXML 轻量解析器 | 实验性地转为播放数据，不等于五线谱渲染 |
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
│   └── follow/
│       ├── pitch_input.dart           # 音高输入抽象
│       ├── microphone_input.dart      # 麦克风音频输入
│       ├── onset_detector.dart        # 音符起始检测
│       ├── follow_mode_controller.dart # 变速跟随状态机
│       ├── midi_follow_mode_session.dart # USB MIDI 跟随会话
│       ├── follow_mode_session.dart   # 旧麦克风跟随会话（当前 UI 不使用）
│       └── follow_playback_target.dart # 跟随播放目标抽象
├── models/
│   └── midi_track.dart                # MIDI 轨道模型
└── ui/
    ├── pages/
    │   ├── home_page.dart             # 首页（文件选择）
    │   └── player_page.dart           # 播放器页面
    └── theme/
        └── luxury_theme.dart          # 黑金主题组件
test/
├── follow_mode_controller_test.dart
├── follow_mode_session_test.dart
├── microphone_input_test.dart
├── midi_engine_test.dart
├── midi_parse_test.dart
├── midi_player_controller_test.dart
├── midi_timeline_test.dart
└── widget_test.dart
assets/
├── midi/
    ├── mozart_k478_piano_quartet.mid # USB MIDI demo（钢琴四重奏）
    └── Beethoven-Moonlight-Sonata.mid # 其他测试用 MIDI 文件
└── scores/
    ├── mozart_k478_piano_part.pdf # K.478 公版钢琴分谱源文件
    └── mozart_k478_piano_part/    # 离线翻页使用的 PDF 页面图像
docs/
├── release_checklist.md               # 真机与试用发布验收清单
├── product/                            # 当前范围、能力证据与策略
└── evidence/                           # 资产准入台账
```

## 🚀 快速开始

### 环境要求

- Flutter 3.44.1（CI 使用版本）
- Dart 3.11+
- iOS 13.6+

### 安装与运行

```bash
# 克隆项目
git clone https://github.com/LIAB-BB/midi_music.git
cd midi_music

# 安装依赖
flutter pub get

# 运行（模拟器可检查 UI；USB MIDI 必须连接真机）
flutter run
```

### 质量检查

```bash
flutter analyze
flutter test
```

### 上线前验收

自动化测试通过不等于可以发布。交付封闭试用版前，还需要用 iPhone 和真实电子琴完成 USB MIDI 热插拔、轨道静音、播放控制、跟随和长休止恢复的人工验收；所有分发资产和音色库策略也必须通过核验。

详见 [`docs/release_checklist.md`](docs/release_checklist.md)、[`docs/evidence/asset_manifest.md`](docs/evidence/asset_manifest.md) 与 [`docs/product/release_scope.md`](docs/product/release_scope.md)。

### 资源与音色库的当前状态

当前默认运行路径会下载并缓存 TimGM6mb.sf2；它**尚不构成离线可用或可发布的保证**。随包 SF2 的来源、许可证和实际加载路径也尚未闭环。进入 TestFlight 前，必须按当前范围文档选择并验证一种音色库交付策略（随包离线，或固定版本且可校验的下载）。

K.478 以外的内置 MIDI 不应被当作试用曲库或对外展示内容，除非先在资产台账中完成授权核验。更重要的是，标为“禁止分发”的资源必须从最终 Flutter asset manifest 和 IPA 中排除；仅隐藏首页入口不能消除分发风险。详细记录见 [`docs/evidence/asset_manifest.md`](docs/evidence/asset_manifest.md)。

### 仅供开发的 PDF OMR 接口

PDF OMR 不在当前封闭试用范围内。开发中如要调试协议，可通过 Dart define 配置受控服务：

```bash
flutter run --dart-define=OMR_SERVICE_BASE_URL=https://your-api.example.com
```

接口约定见 [`docs/omr_service_contract.md`](docs/omr_service_contract.md)。仓库中的 [`server/omr_service`](server/omr_service) 是无认证的开发骨架，不能直接公开部署。

## 🎯 变速跟随模式

变速跟随是本 App 的核心特色功能，让伴奏跟着演奏者的节奏走。

### 工作原理

```
电子琴 USB MIDI Note On → 跟随状态机 → 实时调整伴奏速度
```

1. **CoreMidiInputPlugin** — 使用 iOS CoreMIDI 发现并连接输入源，解析通道消息
2. **IosMidiInput** — 将原生事件转换为 Dart 的设备状态和 `MidiInputMessage`
3. **FollowModeController** — 状态机（idle / following / waitingForOnset），默认精确匹配音符，并用 EMA 平滑速度因子
4. **MidiFollowModeSession** — 串联 MIDI 输入、跟随控制器和播放器；开始时静音选中的电子琴声部组，退出时恢复原状态

当前跟随是预期音符匹配与速度平滑，不保证处理错音、跳段、复调或任意 rubato。多轨同 MIDI 通道的限制见下文“多轨道共享 MIDI 通道”。

### 使用方式

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
