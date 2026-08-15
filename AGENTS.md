# AGENTS.md

This file provides repository-wide guidance to Codex and other AI coding agents.
Claude-specific handoff details and the current architecture snapshot live in
`CLAUDE.md`.

## 基本规则

- 始终使用简体中文和用户沟通。
- 一个任务只由一个 AI 主改代码，其他 AI 负责审阅 diff，避免并发改同一批文件。
- 不要主动启动或停止项目服务，除非用户明确要求。
- 不要提交 AI 署名、generated-by 或 co-authored-by footer。
- 不要提交本地 IDE 工作区文件，例如 `midi_music.code-workspace`。
- 这是 Flutter App，`pubspec.lock` 应提交入库以锁定依赖图。

## 常用命令

```bash
# 安装 Flutter 依赖
flutter pub get

# 安装 iOS 原生依赖
cd ios && pod install && cd ..

# 运行（接设备或模拟器）
flutter run

# 构建打包
flutter build ios --debug --no-codesign
flutter build apk --release

# 清理缓存
flutter clean && flutter pub get && cd ios && pod install && cd ..

# 提交前质量门禁
flutter analyze
flutter test
```

## 协作流程

- 接手前先运行 `git status --short --branch`，确认工作区里哪些改动属于当前任务。
- 混合工作区里只暂存当前任务相关文件，不要使用 `git add .`。
- 提交前必须跑 `flutter analyze` 和 `flutter test`。
- 新增模块、接口、架构约定时，同步更新 `CLAUDE.md`。
- 最近提交使用中文时，继续使用中文 commit message，并在提交前向用户确认。

## 项目速览

- `lib/core/midi/`：MIDI 解析、TempoMap、SoundFont 引擎、播放控制器。
- `lib/core/notation/`：`MidiPartAnalyzer` 按轨道/channel 建声部目录，`MidiScoreSelectionResolver` 解析默认选择，`MidiToMusicXmlConverter` 生成显示用 MusicXML，`MidiNotationService` 负责 isolate 边界。
- MIDI 会从真实音符自动生成可交互五线谱，不使用 seed 假谱；钢琴默认双谱表，可多选其他声部组成总谱。MusicXML 保持原文直接显示，PDF 经 OMR 后仍走 MusicXML 直接路径。
- 原 `MidiSongData` 是唯一播放真值。声部切换只调用 `updateScorePresentation()`，不重载歌曲，并保持 time、speed、AB 和 playing；默认优先级是本曲默认 > 全局声部类别 > 自动钢琴 > 非打击乐合奏 > 打击乐回退。
- `MidiPlayerController.clearScore()` 只用于异步载入等待期间原子卸载旧曲：清空旧会话、位置和 AB，保留 SoundFont 与全局速度。
- `assets/score_renderer/` 内的 OSMD、桥接页与许可证完全本地打包，运行时不得加载远程脚本；谱面默认 70%，只通过 OSMD 原生 Zoom 在 50%–140% 间重排，禁止 CSS transform 伪缩放。
- `lib/core/follow/`：麦克风输入、onset 检测、跟随算法、跟随会话生命周期。
- `lib/models/`：MIDI 曲目、轨道、音符、时间线事件和速度/拍号模型。
- `lib/ui/`：Cupertino UI 页面和黑金主题组件。
- `test/`：当前 Flutter 3.44.1 / Dart 3.12.1 基线共 311 项，包含声部分析、默认选择、MIDI→MusicXML、记谱服务、设置迁移、无损换谱、缩放和 App 回归；`integration_test/midi_notation_render_test.dart` 另做真实本地 OSMD 布局、50%/70% 缩放、CSS 坐标、resize 和点击验收。

更多模块风险等级、接口细节和测试说明见 `CLAUDE.md`。
