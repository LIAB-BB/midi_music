# 资产准入台账

> 用途：每个要随 App、TestFlight、CDN 或市场物料分发的资源必须有一条记录。
>
> 状态标记：`已核验`、`待核验`、`禁止分发`。本表不是法律意见；`已核验`也应保留原始许可文本或合同副本。
>
> `禁止分发` 指资源不得出现在最终 Flutter asset manifest、IPA、CDN、TestFlight、截图或其他对外物料中。仅从 UI 隐藏并不改变其已随包分发的事实。

## 当前已知资产

| 资源 | 路径/用途 | 当前状态 | 已知来源与限制 | 进入试用版前的动作 |
| --- | --- | --- | --- | --- |
| Mozart K.478 MIDI | `assets/midi/mozart_k478_piano_quartet.mid` | 待核验 | `docs/demo_assets.md` 记录为 Mutopia 同源、公版/CC0。 | 保存来源页、下载日期和具体许可文本；核对 MIDI 与 PDF 版本一致。 |
| Mozart K.478 PDF 与页面图 | `assets/scores/mozart_k478_piano_part*` | 待核验 | `docs/demo_assets.md` 记录为 Mutopia 同源分谱。 | 保留原始 PDF、来源 URL、许可与页面渲染来源。 |
| 其余内置 MIDI | `assets/midi/` 中其他文件 | 禁止分发 | 当前仓内无充分来源/商业授权证据。 | 逐首获得许可或替换为可复核来源后再恢复入口。 |
| TimGM6mb SF2 | `assets/soundfonts/TimGM6mb.sf2` | 禁止分发 | 随包文件没有完整许可/版本/校验和记录，且默认运行路径未使用它。 | 决定随包或下载策略；记录来源、许可证、SHA-256、署名和完整性校验。 |
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
