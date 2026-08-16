# MIDI 伴奏 App：当前项目定义

> 当前产品边界以 [`docs/product/release_scope.md`](docs/product/release_scope.md) 为唯一事实源；本文件记录已经落地的工程能力与完成标准。

## 项目目标

打造一款面向 iOS 的 Flutter 古典音乐练习工具：使用 SoundFont 播放原始 MIDI，把 MIDI 离线生成可点击五线谱，并保留 MusicXML/PDF OMR 导入路径。当前产品入口以“乐库 → 交互谱面练习页”为主。

## 已实现

- [x] MIDI/MusicXML 导入进入统一练习页；MIDI 后台解析并生成显示用 MusicXML。PDF 代码路径可经已配置的 OMR 服务获得 MusicXML，但不属于默认试用范围。
- [x] 离线 OSMD 五线谱、小节点击跳转、播放高亮、前后小节与 AB 循环。
- [x] 钢琴默认高低音双谱表，保留明确 upper/lower 轨道的左右手谱表归属。
- [x] 声部多选组成总谱，支持本曲默认和跨曲全局类别默认。
- [x] 换显示谱不重载原 MIDI，保持时间、速度、AB 和播放/暂停状态。
- [x] 谱面默认 70%，可在 50%–140% 用 OSMD 原生重排缩放，快速连点合并为最终一次排版。
- [x] SoundFont 准备、MIDI 播放和基本控制。
- [x] USB MIDI 设备、轨道静音与变速跟随代码保留在高级演奏台。

## 当前产品边界

- 首页当前不导航到高级 `PlayerPage`，因此 USB MIDI 跟随是保留能力，不是当前核心入口的发布阻断项。
- PDF OMR 依赖外部服务；未配置 `OMR_SERVICE_BASE_URL` 时会给出明确错误，不在手机本地运行 OMR。
- MIDI 自动谱是清晰、可交互的练习谱，不承诺出版级指法、装饰线或排版编辑。
- 当前验证基线是 Flutter 3.44.1 / Dart 3.12.1；主要发布与真机验收目标为 iOS 13.6+。Android 代码可构建不等于已完成当前版本的全量真机验收。
- “代码已实现”不等于“资产可分发”或“试用版就绪”；证据等级与资产结论分别见 [`docs/product/capability_matrix.md`](docs/product/capability_matrix.md) 和 [`docs/evidence/asset_manifest.md`](docs/evidence/asset_manifest.md)。

## 完成标准（当前版本）

- [x] 截至 2026-08-15，`flutter analyze` 无问题，`flutter test` 共 311 项通过；新增测试后应刷新此验证记录。
- [x] 真实 iOS WKWebView 中的本地 OSMD fixture 可排版、缩放、高亮并命中非首小节。
- [x] iOS Debug no-codesign 构建通过。
- [ ] 每次试用发布前按 `docs/release_checklist.md` 完成当轮 iPhone 真机人工验收并记录结果。
- [ ] 如当前版本恢复高级演奏台产品入口，再完成 USB MIDI 电子琴专项验收。
