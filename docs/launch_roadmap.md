# 上线路线（Launch Roadmap）

> **状态：历史快照（2026-08-03），不是当前发布范围。**
> 当前唯一权威范围与试用门槛见 [`product/release_scope.md`](product/release_scope.md)、
> [`product/capability_matrix.md`](product/capability_matrix.md)、
> [`release_checklist.md`](release_checklist.md)。
> 本文仅保留长期愿景差距与曲库版权核查备忘，不得作为 TestFlight / 验收依据。
>
> 产品愿景见 `MIDI伴奏可行报告.md`；乐谱素材来源见 `demo_assets.md`。

## 1. 现状快照（2026-08-03）

- 版本：`1.0.0+1`，当前仅 iOS（Android 未实现 MIDI 输入；CoreMIDI 为原生实现）
- 质量门禁：`flutter analyze` 零问题、`flutter test` 113/113 全绿、无 TODO/FIXME 遗留
- 已具备：MIDI/MusicXML/PDF 导入、播放/暂停/seek/变速/静音、SoundFont 自动下载（TimGM6mb ~6MB）、USB MIDI 电子琴跟随（多轨静音恢复、长休止等待、重对齐）、内置曲库（6 首 MIDI + K.478 PDF 分谱 21 页）、钢琴卷帘、设置页
- 依赖 CDN：SoundFont 从 jsdelivr / raw.githubusercontent / sourceforge 三个后备 URL 下载

## 2. 两种上线形态

| 形态 | 定义 | 目标 | 主要风险 |
|---|---|---|---|
| **A. 试用版** | 当前能力：USB 电子琴直连 + 速度跟随伴奏 | 小范围试用（TestFlight） | 音质、版权、真机验收 |
| **B. 正式产品** | 报告愿景：麦克风独奏输入（小提琴/长笛/钢琴）+ 鲁棒跟随 + 高质量管弦音色 | 面向专业演奏者发布 | 跟随算法鲁棒性（最大风险） |

## 3. 差距矩阵（对照 `MIDI伴奏可行报告.md`）

| 维度 | 报告目标 | 当前实现 | 差距等级 | 备注 |
|---|---|---|---|---|
| 输入源 | 麦克风捕捉独奏 | USB MIDI 电子琴直连 | 🟡 | 麦克风管线有骨架（`MicrophoneInput` + YIN），未成产品路径 |
| 跟随算法 | OLTW/HMM，容忍错音/跳跃/复调 | 精确音符匹配（0 半音、不跨八度）+ 速度跟随 | 🔴 | 最大技术差距 |
| 音质 | 150–500MB 管弦 SoundFont + 人性化 + 动态耦合 + 卷积混响 | TimGM6mb ~6MB GM | 🔴 | 报告自判为「玩具音色」 |
| 乐谱渲染 | MusicXML 原生渲染（Lomse/VexFlow） | PDF 分谱图片 + 钢琴卷帘 | 🟡 | 可用，非报告方案 |
| 平台 | iOS + Android（Oboe 低延迟） | 仅 iOS | 🔴 | Android 空白 |
| 内容 | 5 首协奏曲 + CC11 表情曲线 | 6 首内置古典 MIDI（无表情） | 🟡 | 且版权待核查（见 §4） |
| 动态交互 | 伴奏音量随独奏起伏、休止 AI 填充 | 速度跟随 + 休止等待 | 🟡 | 动态耦合未实现 |

## 4. 曲库版权合规核查（2026-08-03）

报告明确警告：MIDI 文件即使曲子是公版，**第三方制作的 MIDI 属于衍生作品，受版权保护**；BitMidi 等聚合站的多数文件严禁商用。内置曲库逐一核查如下：

| 曲目 | 文件 | 来源线索 | 版权状态 | 处置 |
|---|---|---|---|---|
| 莫扎特 K.478 钢琴四重奏 | `mozart_k478_piano_quartet.mid` | Mutopia Project（Music ID 499），见 `demo_assets.md` | ✅ Public Domain / CC0，可商用 | 无动作 |
| 巴赫 BWV 846 前奏曲 | `bach_wtc1_prelude.mid` | copyright 元事件：`© 2007 (Apr 12) by Benjamin Robert Tubb` | ⚠️ 个人 MIDI Performance 版权（站点 pdmusic.org），**未查到明确商业许可条款** | 联系作者授权（brtubb@pdmusic.org），或替换为 Mutopia/IMSLP 公版自制版本 |
| 贝多芬月光一乐章 | `Beethoven-Moonlight-Sonata.mid` | 无 copyright 元事件；代码/文档无来源记录 | ⚠️ 来源不明，商用风险高 | 替换为可确认来源版本 |
| 贝多芬月光二乐章 | `beethoven_moonlight_2.mid` | 同上 | ⚠️ 来源不明，商用风险高 | 同上 |
| 肖邦夜曲 | `chopin_nocturne.mid` | 同上 | ⚠️ 来源不明，商用风险高 | 同上 |
| 莫扎特 K545 | `mozart_k545.mid` | 无 copyright；仅含轨道名 Piano | ⚠️ 来源不明，商用风险高 | 同上 |

**结论：6 首中仅 1 首可确认商用。** 上架（形态 A 试用版）前必须完成逐首确认或替换；最安全的长期路径是全部换成 Mutopia（CC0）或 IMSLP 公版乐谱自制版本，并在 `docs/demo_assets.md` 记录每首的许可凭证。

## 5. 执行路线

### 阶段 0 — 法务底线（并行于任何发布，1 周内）
- [ ] 逐首确认/替换内置曲库，形成许可清单（每首：来源 URL、许可证、下载日期）
- [ ] 与 Benjamin Robert Tubb 邮件确认巴赫前奏曲商业使用授权（或直接替换）
- [ ] 确认 App 图标、字体（Georgia 展示字体）、SoundFont（TimGM6mb 的许可：需确认其分发条款）无版权问题

### 阶段 1 — 形态 A 试用版（1–2 周）
- [ ] **S1–S7 真机验收**（`docs/release_checklist.md`）：USB 热插拔、跟随模式、长休止恢复，需 iPhone + class-compliant USB MIDI 电子琴，记录验收结论
- [ ] 音质第一步：评估并替换为 30–100MB 高质量音色（候选：Salamander 钢琴 ~50MB、Sonatina Symphonic Orchestra 子集、VSCO2 子集），验证 `flutter_midi_pro` 对大 SF2 的加载
- [ ] 中国大陆网络下的 SoundFont 下载失败路径实测（3 个后备 URL 均不可达时的恢复体验）
- [ ] TestFlight 分发链路：证书、`1.0.0+1` 版本号策略、上传与内测流程

### 阶段 2 — 形态 B 核心（1–3 个月）
- [ ] 跟随算法鲁棒性：OLTW（参考 Matchmaker）移植，支持错音容忍、跳段重对齐、复调独奏（当前 `FollowModeController` 为精确匹配，无法处理）
- [ ] 麦克风独奏输入真机化：iPhone 真机验证 YIN 管线延迟、串音、音量阈值；钢琴复调场景单独调参
- [ ] 音色库制作：Polyphone 从 VPO/VSCO2 提取管弦乐器子集，目标 ≤200MB，SF3 压缩
- [ ] 动态耦合：伴奏音量随独奏 RMS 起伏（报告称「体验杀手锏」）

### 阶段 3 — 平台与体验（3 个月+）
- [ ] Android：Oboe 低延迟音频，低端机延迟测试（报告称「成败关键风险点」）
- [ ] 卷积混响（音乐厅 IR）、休止 Vamp 填充
- [ ] 内容生产：5 首热门协奏曲自制 MIDI（含 CC11 表情曲线），Mutopia/IMSLP 公版来源

## 6. 发布判定（形态 A）

- [ ] 自动化质量门禁全绿（`flutter analyze` + `flutter test`）
- [ ] `release_checklist.md` S1–S7 全部通过并有验收记录
- [ ] 内置曲库版权核查完成（阶段 0 清单全勾）
- [ ] TestFlight 包已在小范围试用户手上完成一轮实弹反馈

## 7. 与报告路线图的映射

| 报告阶段 | 报告目标 | 当前进度 |
|---|---|---|
| 第一阶段（1–2 月）：原型验证 | 音频输入 → 引擎 → MIDI 同步最小闭环 | ✅ 已跑通（以 USB MIDI 输入替代麦克风+OLTW） |
| 第二阶段（3–4 月）：内容与 UI | 乐谱渲染 + 5 首协奏曲曲库 | 🟡 部分（PDF 分谱阅读 + 6 首曲目，但版权未核） |
| 第三阶段（5–6 月）：打磨发布 | 动态耦合、混响、内测调参 | ❌ 未开始 |
