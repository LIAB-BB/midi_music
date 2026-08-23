# 资产准入台账

> 用途：每个要随 App、TestFlight、CDN 或市场物料分发的资源必须有一条记录。
>
> 状态标记：`已核验`、`待核验`、`禁止分发`。本表不是法律意见；`已核验`也应保留原始许可文本或合同副本。
>
> `禁止分发` 指资源不得出现在最终 Flutter asset manifest、IPA、CDN、TestFlight、截图或其他对外物料中。仅从 UI 隐藏并不改变其已随包分发的事实。

## 当前已知资产

| 资源 | 路径/用途 | 当前状态 | 已知来源与限制 | 进入试用版前的动作 |
| --- | --- | --- | --- | --- |
| Mozart K.478 MIDI | `assets/midi/mozart_k478_piano_quartet.mid` | 已核验 | 与 Mutopia `k478-score.mid` 的 SHA-256 一致；来源页标注 Public Domain。 | 随包前保持哈希不变；替换文件或扩展分发范围时重新核验。 |
| Mozart K.478 钢琴分谱页面图 | `assets/scores/mozart_k478_piano_part/page-*.png` | 已核验 | 已核验 PDF 用 Poppler `pdftoppm 26.05.0` 的 `-r 180 -png` 复现，21 页与随包 PNG 逐字节一致；脚本见 `tool/verify_k478_score_pages.sh`。 | 文件替换、重编码或渲染参数变化时重新核验。 |
| Mozart K.478 原始 PDF | `assets/scores/mozart_k478_piano_part.pdf` | 已核验，不随包 | 与 Mutopia `k478-piano-a4.pdf` 的 SHA-256 一致；仅用于追溯页面图来源。 | 不加入 Flutter manifest；如改为应用内 PDF 读取，再确认实际分发清单。 |
| 其余内置 MIDI | `assets/midi/` 中其他文件 | 禁止分发 | 当前仓内无充分来源/商业授权证据。 | 逐首获得许可或替换为可复核来源后再恢复入口。 |
| TimGM6mb SF2 | `assets/soundfonts/TimGM6mb.sf2` | 禁止分发 | 随包文件没有完整许可/版本/校验和记录，且默认运行路径未使用它。 | 决定随包或下载策略；记录来源、许可证、SHA-256、署名和完整性校验。 |
| K.478 Violin / Cello SF2 | `packages/k478_practice/assets/soundfonts/k478_{violin,cello}.sf2` | 待核验 | MuseScore_General 0.2 的 bank 0 Program 40/42 子集；MIT 授权通知、输入与输出哈希、无界面转换链、preset 测试和 Apple sampler 离线渲染均已记录。官方 OSUOSL 归档存在同版本文件，但输入 SF3 的全量字节比对与 iPhone 真机发声尚未完成。 | 完成官方输入比对；在签名 Archive/IPA 中复核哈希与授权通知；iPhone 离线加载并分别听音后再改为“已核验”。 |
| App 图标、字体、截图、宣传音频 | 待补充 | 待核验 | 未形成清单。 | 在 TestFlight 前逐项登记。 |

## 新资产记录模板

| 字段 | 必填内容 |
| --- | --- |
| 资产 ID / 文件哈希 | 文件名、版本、SHA-256、存储位置 |
| 资源类型 | 作品、版次、MIDI、音频、采样、PDF、图像、字体等 |
| 来源 | 原始 URL / 合同 / 订单号；记录获取日期 |
| 权利链 | 作品、版次、表演/制作、录音、采样库分别说明 |
| 许可证与义务 | 商业分发、改编、署名、同许可、地域、期限、渠道限制 |
| 分发范围 | 随包 / CDN / TestFlight / App Store / 市场截图 |
| 审核结论 | 已核验 / 待核验 / 禁止分发；审核日期与负责人 |
| 证据位置 | 许可文本、网页存档、邮件授权或合同的受控存储位置 |

## 准入规则

1. 没有记录即默认**禁止分发**。
2. “作品公版”不足以覆盖现代版次、MIDI 制作、录音、SoundFont 或图片。
3. 不从第三方平台抓取、转换或下载其受保护音频/视频内容；App Store 对知识产权与第三方媒体有明确要求，见 [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)。
4. 发生文件替换、重新编码、裁剪、拼接或改变分发渠道时，重新审核记录。

K.478 的来源页、原始包与 SHA-256 比对记录见 [`k478_asset_evidence.md`](k478_asset_evidence.md)。

候选 `Runner.app` 的 `packages/k478_practice/assets` 子树采用精确白名单：仅允许本表登记的 K.478 MIDI、21 张页面 PNG、Violin/Cello 两个 SF2 与 `legal/third_party_notices.txt`。`tool/verify_testflight_ios_bundle.sh` 会拒绝该子树内任何额外文件；Flutter 自带 manifest、shader 等运行时资源不属于此子树。
