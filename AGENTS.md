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

## K.478 候选路径（优先发布实现）

- `apps/testflight_ios/`：iPhone-only、iOS 13.0+ 的独立候选 host；其
  `pubspec.lock` 必须提交并使用 `flutter pub get --enforce-lockfile`。
- `packages/k478_practice/`：K.478 UI、播放器与跟随逻辑；package lockfile
  不提交，不能使用 `--enforce-lockfile`。
- `packages/core_midi_input/`：CoreMIDI 输入 package；package lockfile 不提交。
- 根目录仍是 Legacy host（最低 iOS 13.6），其分析、测试和构建结果不能替代
  候选 host 的结果。不要为了候选清理或删除 legacy 功能。

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

## 项目速览

- `lib/core/midi/`：MIDI 解析、TempoMap、SoundFont 引擎、播放控制器。
- `lib/core/follow/`：麦克风输入、onset 检测、跟随算法、跟随会话生命周期。
- `lib/models/`：MIDI 曲目、轨道、音符、时间线事件和速度/拍号模型。
- `lib/ui/`：Cupertino UI 页面和黑金主题组件。
- `test/`：核心算法、引擎串行化、播放器调度、生命周期和 App smoke tests。

更多模块风险等级、接口细节和测试说明见 `CLAUDE.md`。
