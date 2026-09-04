# 能力矩阵与证据边界

> 更新日期：2026-09-04。此表防止把“有代码”“有测试”“有设备证据”和“可对外试用”混为一谈。`root` 与独立 TestFlight 候选必须分别判断。

## 状态定义

- **已实现**：当前代码存在，且注明是否由首页主路径调用。
- **自动化证据**：有对应测试；不等于真实设备已成功。
- **设备证据**：有机型、系统、commit、日期和结论记录。
- **试用状态**：还要同时满足资产、音色、范围和发布门槛。

| 目标 | 能力 | 已实现/入口 | 自动化证据 | 设备证据 | 试用状态与边界 |
|---|---|---|---|---|---|
| root | K.478 MIDI 自动生成 MusicXML | 默认首页“查看交互五线谱” | converter/service/widget + iOS WKWebView fixture | 实体 iPhone 待当轮记录 | 候选；只承诺练习谱，不是出版谱 |
| root | 钢琴左右手来源保留 | 是，明确 upper/lower 来源 | 是 | 人工抽查待当轮记录 | 未标注单轨仍为启发式分谱 |
| root | 多选声部与默认 | 交互谱面页 | 是 | iOS 模拟器流程已核；实体 iPhone 待记录 | 换谱不改变播放状态 |
| root | 小节点击、高亮、AB、50%–140% 缩放 | 交互谱面页 | 单元/Widget + iOS WKWebView fixture | 实体 iPhone 待记录 | 原生重排；复杂反复按书写顺序并提示 |
| root | 通用 MIDI/MusicXML/PDF 导入 | `ScoreLibraryPage` 保留，默认首页不可达 | 是 | 实体 iPhone 待当轮记录 | MusicXML 保留原文；PDF 仅限配置受控 OMR 的开发验收 |
| root | SoundFont MIDI 播放 | K.478 首页和两个练习入口 | 是 | 实体 iPhone 待补 | TimGM 来源、许可、哈希与交付策略仍需闭环 |
| root | USB MIDI 设备与速度跟随 | 默认首页“开始 USB MIDI 排练”进入 `PlayerPage` | Dart/会话测试 | 完整电子琴记录待补 | 与交互谱面证据分开记录 |
| root | MIDI 卷帘 | 仅 `PlayerPage` | Widget 覆盖 | 不适用 | 不得作为交互练习页主视图宣传 |
| candidate | 固定 K.478、CoreMIDI、弦乐伴奏 | `apps/testflight_ios` + `packages/k478_practice` | 独立 package/App jobs | 双机 USB 记录待补 | iPhone-only 封闭候选，不包含 root OSMD/导入 |
| candidate | K.478 静态钢琴分谱 | 独立包 21 张 PNG | 页面哈希与 Widget 测试 | 双机人工阅读待补 | 不是 root `ScorePracticePage`，无自动翻页/播放同步承诺 |
| candidate | Violin/Cello 随包 SF2 与 bundle 审计 | 独立包/host | 独立测试与 allowlist 脚本 | 官方输入比对、签名 IPA、iPhone 听音待补 | 未闭环前阻止对外分发 |
| root | Android 当前版本 | 工程存在 | 部分跨平台测试 | 无全量真机证据 | 不承诺当前版本完整质量 |
| 全部 | 商业曲库/高质量 stem | 否 | 否 | 否 | 不在当前范围 |

## 使用规则

1. 对外文案只能描述 [`release_scope.md`](release_scope.md) 纳入且通过当轮发布门槛的能力。
2. 新能力进入核心范围前，先更新范围和本表，再补实现、测试、设备证据与发布清单。
3. root 设备记录使用 [`../release_checklist.md`](../release_checklist.md)；独立候选使用 [`../releases/k478_testflight_checklist.md`](../releases/k478_testflight_checklist.md)；资产结论统一使用 [`../evidence/asset_manifest.md`](../evidence/asset_manifest.md)。
4. 本表记录证据等级，不替代具体测试输出、截图、日志或法律审核。
