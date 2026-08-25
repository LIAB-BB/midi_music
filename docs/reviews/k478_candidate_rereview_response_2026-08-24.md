# K.478 第二次复审整改记录

> 日期：2026-08-24  
> 分支：`codex/docs-product-governance`  
> 依据：用户提供的第二次项目治理复审报告，以及本地代码和 K.478 MIDI 审计。  
> 本文记录整改范围，不是 TestFlight、签名 IPA 或真机验收通过证明。

## 当前结论

此前 2026-08-23 的本地 `SHIP` 结论仅适用于当时的修复集合，不能覆盖本次复审新增的图标资源、异步会话与 Wait Mode 语义问题。整改完成并通过自动化后，候选仍是 **TestFlight No-Go**：真机 USB、签名 Archive/IPA、Privacy Report、SF2 听音与资产权利闭环仍未完成。

## 已采纳的产品决定

K.478 不再把“钢琴轨出现长休止”解释成“全体应暂停”。本地 MIDI 审计确认所有自动识别出的钢琴休止区间中，弦乐仍有进行或重入事件；因此当前批准等待点集合为空，弦乐持续演奏。未来如要增加 Wait Mode，必须逐点记录重入 tick、所有声部活动审计、人工批准人和真机回归证据。

## 整改项

1. 显式加入 `cupertino_icons` 1.0.9，随包校验字体及 `FontManifest.json`，并把 MIT 通知写入候选内置第三方通知。
2. 跟随控制器仅对人工批准的重入 tick 生成等待边界；休止后第一拍不再用跨休止间隔测量速度。
3. Wait Mode 重入 seek 保留目标时刻事件，避免跳过恰在重入点开始的弦乐音符。
4. Session 把 match、pauseAt 和重新对齐统一放入单一命令队列；退出会取消在途等待并在停止播放器后排空本 Session 命令。
5. 页面在 MIDI Session 启动期间就持有 pending Session，并禁用手动播放、暂停、seek、停止和速度控制。
6. `IosMidiInput` 在 dispose 后忽略已排队的平台错误，不再向已释放输入对象发布错误。
7. bundle 审计扩展到 host 顶层 Flutter assets、未知 package asset 目录和 Cupertino 字体；产品范围、矩阵、ADR、验收清单与 dossier 同步改为“连续弦乐，不宣传自动 Wait Mode”。

## 未擅自处理的事项

- 根 README 的 `MIT` 表述与根目录未见统一 `LICENSE` 的冲突，属于仓库权利人需要确认的许可证选择；本轮不替用户指定许可证。
- 根 Legacy host 的旧 UI、重复开发资产和 `docs/launch_roadmap.md` 仍保留，未删除、未覆盖，也不构成本候选发布边界。
- 此文不把自动化、无签名构建或 bundle 审计写成真机/TestFlight 已通过。

## 验证记录

- `flutter analyze`：`packages/core_midi_input`、`packages/k478_practice`、`apps/testflight_ios` 与根 legacy host 均通过。
- `flutter test`：CoreMIDI package 4 项、K.478 package 40 项、TestFlight host 5 项、根 legacy host 115 项均通过。
- `tool/test_verify_testflight_ios_bundle.sh` 通过；自测覆盖候选包额外文件、host 顶层 Flutter asset 和未知 package asset 的拒绝路径。
- `apps/testflight_ios` 的 `flutter build ios --release --no-codesign` 成功，`tool/verify_testflight_ios_bundle.sh build/ios/iphoneos/Runner.app` 通过，并实际确认 Cupertino 字体在 `FontManifest.json` 中登记。
- `tool/verify_k478_score_pages.sh` 本轮未通过：当前环境没有 `pdftoppm`。页面文件未改动，因此这不否定既有页面证据，但本轮不能把页面复现校验写为重新完成。
