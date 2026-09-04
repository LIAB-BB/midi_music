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

## 两个 K.478 目标

- 根目录 host（iOS 13.6+）的默认 `HomePage` 有两个入口：交互五线谱
  `ScorePracticePage` 与 USB MIDI `PlayerPage`。`home_page_legacy.dart` 只保留
  通用曲库/导入，不是默认首页。
- 根交互谱必须走 MIDI→MusicXML→本地 OSMD；不得恢复旧 PDF/PNG 或钢琴卷帘
  作为 `ScorePracticePage` 主视图。
- 根目录验证执行 `docs/release_checklist.md`，不能替代下面独立候选的结果。

独立 K.478 TestFlight 候选：

- `apps/testflight_ios/`：iPhone-only、iOS 13.0+ 的独立候选 host；其
  `pubspec.lock` 必须提交并使用 `flutter pub get --enforce-lockfile`。
- `packages/k478_practice/`：K.478 UI、播放器与跟随逻辑；package lockfile
  不提交，不能使用 `--enforce-lockfile`。
- `packages/core_midi_input/`：CoreMIDI 输入 package；package lockfile 不提交。
- 独立候选仍使用 21 张静态 PNG 分谱与随包 Violin/Cello SF2，不接入根 App
  的 OSMD 交互谱；其验证执行 `docs/releases/k478_testflight_checklist.md`。
- 根 host 与候选 host 的分析、测试、资产、真机和构建结果不能互相替代。

候选验证矩阵：

```bash
cd packages/core_midi_input && flutter pub get && flutter analyze && flutter test
cd ../k478_practice && flutter pub get && flutter analyze && flutter test
cd ../../apps/testflight_ios && flutter pub get --enforce-lockfile && flutter analyze && flutter test
cd ../.. && tool/verify_k478_score_pages.sh
# 构建后才运行：tool/verify_testflight_ios_bundle.sh <Runner.app>
```

候选二进制仍须由真实 iPhone、签名 Archive/IPA 与 Privacy Report 复核；脚本和
CI 不得将它们写成已完成。`CLAUDE.md` 若有用户未提交改动，除非得到明确授权不得编辑。

## 协作流程

- 接手前先运行 `git status --short --branch`，确认工作区里哪些改动属于当前任务。
- 混合工作区里只暂存当前任务相关文件，不要使用 `git add .`。
- 提交前必须跑 `flutter analyze` 和 `flutter test`。
- 新增模块、接口、架构约定时，同步更新 `CLAUDE.md`。
- 最近提交使用中文时，继续使用中文 commit message，并在提交前向用户确认。

## 文档事实源

- `docs/product/release_scope.md` 是当前产品边界唯一事实源；不得用历史计划或不可达代码路径改写当前入口。
- `docs/product/capability_matrix.md` 区分实现、自动化、设备证据和可试用状态；测试通过不能替代真机或分发门槛。
- `docs/evidence/asset_manifest.md` 是随包、下载和宣传资产准入台账；没有记录默认禁止分发，仅隐藏 UI 不等于从 IPA 排除。
- `docs/release_checklist.md` 是根 App 的执行门槛；独立候选使用 `docs/releases/k478_testflight_checklist.md`。新增产品能力时同时更新范围、能力矩阵、资产影响和对应验收场景。
- `PROJECT.md` / `README.md` 记录工程入口与实现快照，`docs/superpowers/` 旧 plan/spec 和根目录长期报告只作历史材料，不得重新执行或作为当前发布承诺。

## 项目速览

- `lib/core/midi/`：MIDI 解析、TempoMap、SoundFont 引擎、播放控制器。
- `lib/core/notation/`：`MidiPartAnalyzer` 按轨道/channel 建声部目录，`MidiScoreSelectionResolver` 解析默认选择，`MidiToMusicXmlConverter` 生成显示用 MusicXML，`MidiNotationService` 负责 isolate 边界。
- MIDI 会从真实音符自动生成可交互五线谱，不使用 seed 假谱；钢琴默认双谱表，可多选其他声部组成总谱。MusicXML 保持原文直接显示，PDF 经 OMR 后仍走 MusicXML 直接路径。
- 钢琴来源合并时必须保留明确的 `upper/right hand/右手` 与 `lower/left hand/左手` 轨道语义；不得在进入 MusicXML 前丢掉来源后只按整体音高重分谱表。
- 原 `MidiSongData` 是唯一播放真值。声部切换只调用 `updateScorePresentation()`，不重载歌曲，并保持 time、speed、AB 和 playing；默认优先级是本曲默认 > 全局声部类别 > 自动钢琴 > 非打击乐合奏 > 打击乐回退。
- `MidiPlayerController.clearScore()` 只用于异步载入等待期间原子卸载旧曲：清空旧会话、位置和 AB，保留 SoundFont 与全局速度。
- `assets/score_renderer/` 内的 OSMD、桥接页与许可证完全本地打包，运行时不得加载远程脚本；谱面默认 70%，只通过 OSMD 原生 Zoom 在 50%–140% 间重排，禁止 CSS transform 伪缩放。
- `lib/core/follow/`：麦克风输入、onset 检测、跟随算法、跟随会话生命周期。
- `lib/models/`：MIDI 曲目、轨道、音符、时间线事件和速度/拍号模型。
- `lib/ui/`：Cupertino UI 页面和黑金主题组件。
- `lib/ui/pages/home_page.dart`：默认 K.478 双入口；`home_page_legacy.dart`：非默认通用库/导入。
- `test/`：包含声部分析、默认选择、MIDI→MusicXML、记谱服务、设置迁移、无损换谱、缩放和 App 回归。测试总数与版本必须使用当前 commit 的实际输出，不能沿用历史数字。`integration_test/midi_notation_render_test.dart` 另做真实本地 OSMD 布局、50%/70% 缩放、CSS 坐标、resize 和点击验收。

更多模块风险等级、接口细节和测试说明见 `CLAUDE.md`。
