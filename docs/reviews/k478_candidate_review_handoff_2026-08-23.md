# K.478 iOS 候选修复复审说明

> 日期：2026-08-23
>
> 分支：`codex/docs-product-governance`
>
> 基线：`main`
>
> 目标：供后续 GPT 或人工审阅当前 K.478 iOS CoreMIDI USB 候选修改。本文是审阅入口，不等同于 TestFlight 发布证明。
>
> 后续状态：本文件是 2026-08-23 的历史审阅快照。2026-08-24 的
> [`第二次复审整改记录`](k478_candidate_rereview_response_2026-08-24.md) 也只是
> 历史快照。当前结论以 [`../product/release_scope.md`](../product/release_scope.md)、
> [`../product/capability_matrix.md`](../product/capability_matrix.md) 和对应发布清单
> 为准。

## 本轮结论

本轮处理了外部 Review 中经代码核验成立的问题，并保留未进入候选范围的旧功能。自动化、无签名 iOS Release 构建和本地 bundle 审计已通过；真实 iPhone、签名 Archive/IPA、Privacy Report 和 TestFlight 上传仍未完成。

## 主要修改

### 1. MIDI 跟随正确性

- 只有演奏者输入第一个正确谱面起拍时，弦乐伴奏才开始。
- 首音前、普通跟随期间及长休止等待期间的错音都不会改变速度。
- 连续错音只触发与当前期待起拍一致的重新对齐请求。
- 长休止在前一正确起拍的实际结束时间暂停；播放器完成清音后才进入等待状态。
- 长休止期间只有正确重入音会执行 seek 并恢复播放。
- 区分快速重复同音与同一和弦分批到达的尾音。

关键实现：

- `packages/k478_practice/lib/src/core/follow_mode_controller.dart`
- `packages/k478_practice/lib/src/core/k478_midi_follow_session.dart`
- `packages/k478_practice/test/follow_mode_controller_test.dart`
- `packages/k478_practice/test/k478_midi_follow_session_test.dart`

### 2. 播放器与音源生命周期

- transport 与 engine 操作分别串行化，避免 pause、seek、stop、play 越过尚未完成的 `allNotesOff`。
- SoundFont 加载进入 engine 生命周期队列；加载失败后可重试。
- `dispose` 会先禁止新工作、停止 Timer，再等待在途 transport 和其追加的最新 engine 操作，最后只释放一次音源。
- `loadSong`、`play`、`pause`、`seek` 的异步续体在销毁后不会重新播放、通知或调用原生音源。
- 支持并恢复 K.478 弦乐轨中的 CC7 音量状态。

关键实现：

- `packages/k478_practice/lib/src/core/k478_player.dart`
- `packages/k478_practice/lib/src/core/midi_engine.dart`
- `packages/k478_practice/test/k478_player_test.dart`
- `packages/k478_practice/test/midi_engine_test.dart`

### 3. CoreMIDI 与 Session 生命周期

- Session 的 `start` 与 `dispose` 可安全并发；输入启动中退出不会重新绑定跟随回调或开始播放。
- iOS 平台 `start` 尚未返回时调用 `dispose`，会等待启动结束并最终调用平台 `stop`。
- 输入销毁后不会向已经关闭的消息流或状态流写入。

关键实现：

- `packages/core_midi_input/lib/src/ios_midi_input.dart`
- `packages/core_midi_input/test/ios_midi_input_test.dart`

### 4. iOS、CI 与分发边界

- 候选 host 的 Debug、Profile、Release 均限制为 iPhone，不声明 iPad 支持。
- CI 分开验证根 legacy host、CoreMIDI package、K.478 package 和 TestFlight 候选 host。
- 候选 App 在 macOS CI 执行无签名 iOS Release 构建和 bundle 审计。
- `packages/k478_practice/assets` 使用精确文件白名单；额外 SF2、图片或任意未登记文件都会令审计失败。
- 21 张分谱页面可由已核验 PDF 使用固定 Poppler 参数逐字节重现。

关键实现与证据：

- `.github/workflows/flutter.yml`
- `tool/verify_testflight_ios_bundle.sh`
- `tool/test_verify_testflight_ios_bundle.sh`
- `tool/verify_k478_score_pages.sh`
- `docs/evidence/asset_manifest.md`
- `docs/evidence/k478_asset_evidence.md`

### 5. 产品与发布文档

- README 明确区分 K.478 候选和根目录 legacy host。
- 验收清单改为与实际 UI、USB 启动顺序和长休止语义一致。
- 能力矩阵采用有限状态值，不把未完成真机试验写成已通过。
- 新增轻量 ADR 和 release dossier 模板；未伪造负责人、签名产物或批准记录。

## 已完成验证

| 范围 | Analyze | Test |
| --- | --- | --- |
| `packages/core_midi_input` | 通过 | 3/3 |
| `packages/k478_practice` | 通过 | 36/36 |
| `apps/testflight_ios` | 通过 | 4/4 |
| 根 legacy host | 通过 | 115/115 |

其他验证：

- Dart 格式化检查通过，0 个文件需要改写。
- `git diff --check` 通过。
- bundle allowlist 自测通过，已验证额外 SF2 和任意额外文件会被拒绝。
- 2026-08-23 21:35 重新完成 `flutter build ios --release --no-codesign`。
- 生成的 `Runner.app` 为 21.4 MB，`UIDeviceFamily` 仅含 iPhone `1`，bundle 审计通过。
- 三轮全新上下文独立审查中，前两轮发现的问题均已修复；最终结论为 `SHIP`。

## 尚未完成，不能据此宣称 TestFlight 就绪

- 真实 iPhone 与 USB 电子琴的首次连接、拔插、重连和长时间运行。
- 正确首音、连续错音、快速重复音、和弦和长休止的真机实奏。
- 两个 SF2 的真机听音、官方输入文件比对和最终授权通知复核。
- App 图标、截图、测试说明和反馈入口。
- 签名 Archive/IPA、IPA 内容复核、Privacy Report 和 TestFlight 上传。
- 最终负责人、试验数据和 Go/No-Go 记录。

## 建议后续 GPT 重点复审

1. 是否仍存在任何输入可以在第一个正确起拍前启动伴奏。
2. `pauseAt`、transport tail、engine tail 和 `dispose` 是否存在自等待、迟到续体或销毁后原生调用。
3. Session、CoreMIDI 平台启动和页面退出并发时是否仍可能泄漏订阅或设备连接。
4. bundle 精确白名单是否会误放未登记自定义资产，或误拒 Flutter 自带运行时资产。
5. GitHub Actions 的工作目录、lockfile 策略、macOS iOS 构建路径是否能在干净 clone 中运行。
6. 文档是否仍有把无签名本地构建、自动化测试或待判定试验写成 TestFlight 已就绪的表述。

## 审阅边界

以下工作区内容不属于本轮修改，不应混入本次提交评价：

- `CLAUDE.md`
- `docs/launch_roadmap.md`
- `packages/core_midi_input/example/`

旧曲库、通用导入、钢琴卷帘、MusicXML/OMR 和麦克风跟随等能力仍保留在 legacy 或后续开发范围，本轮没有以“暂不发布”为由删除这些实现。
