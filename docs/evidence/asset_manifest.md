# 资产准入台账

> 更新日期：2026-08-16。每个随 App、下载、TestFlight、CDN 或市场物料分发的资源都必须有记录。
>
> 状态：`已核验`、`待核验`、`禁止分发`。本表不是法律意见；`已核验`仍应保留原始许可文本、合同或网页存档。
>
> `禁止分发` 表示不得出现在最终 Flutter asset manifest、IPA、CDN、TestFlight 截图或其他对外物料中；仅从 UI 隐藏不等于未分发。

## 当前已知资产

| 资源 | 路径/哈希 | 状态 | 已知证据与限制 | 进入试用版前的动作 |
|---|---|---|---|---|
| Mozart K.478 MIDI | `assets/midi/mozart_k478_piano_quartet.mid`；SHA-256 `06f5457a2831d88dc4a7def8a8b35903c6a9be23ceeb30964c1147d9d280a025` | 待核验 | [`../demo_assets.md`](../demo_assets.md) 指向 Mutopia Music ID 499，来源页标注 Public Domain。 | 保存来源页/许可存档，确认当前文件来自记录下载包。 |
| Mozart K.478 PDF | `assets/scores/mozart_k478_piano_part.pdf`；SHA-256 `d72a61d0102b797d9e89cb6c99741aa99d56f68af14ab78df15d5e244b0d12b4` | 待核验 | 与 K.478 同源；当前只作对照、OMR 输入和保留资产。 | 保存许可存档；决定试用包是否需要 PDF/页面图，不需要则从最终 manifest 排除。 |
| K.478 页面 PNG | `assets/scores/mozart_k478_piano_part/page-*.png` | 待核验 | 由同源 PDF 渲染；当前首页不使用。 | 记录生成方式与逐文件哈希，或从试用包排除。 |
| 其余内置 MIDI | `assets/midi/` 中除 K.478 外文件 | 禁止分发 | 仓库没有充分来源与分发授权证据。 | 逐首补证或移出最终 asset manifest 与 IPA。 |
| TimGM6mb SF2 | `assets/soundfonts/TimGM6mb.sf2`；SHA-256 `82475b91a76de15cb28a104707d3247ba932e228bada3f47bba63c6b31aaf7a1` | 禁止分发 | 缺完整许可证/版本证据；默认运行路径下载到缓存，并不使用随包文件。 | 决定随包或固定版本下载策略，补许可证、署名和完整性校验。 |
| OSMD 1.9.9 运行时 | `assets/score_renderer/opensheetmusicdisplay.min.js`；SHA-256 `658ed444554d43ec66bfb54c72d6833d369e5f93a3a2c06095187cd09a401034` | 已核验 | 本地 bundle 与 `assets/score_renderer/LICENSE` 一并分发；运行时不访问 CDN。 | 发布构建复核版本、哈希、LICENSE 与离线网络检查。 |
| App 图标、字体、截图、宣传音频 | 待补充 | 待核验 | 尚未形成逐项清单。 | TestFlight 或宣传前逐项登记来源、许可和渠道。 |

## 新资产记录模板

| 字段 | 必填内容 |
|---|---|
| 资产 ID / 文件哈希 | 文件名、版本、完整 SHA-256、存储位置 |
| 资源类型 | 作品、版次、MIDI、音频、采样、PDF、图像、字体等 |
| 来源 | 原始 URL / 合同 / 订单号；记录获取日期 |
| 权利链 | 作品、版次、表演/制作、录音、采样库分别说明 |
| 许可证与义务 | 商业分发、改编、署名、同许可、地域、期限、渠道限制 |
| 分发范围 | 随包 / 下载 / CDN / TestFlight / App Store / 市场截图 |
| 审核结论 | 已核验 / 待核验 / 禁止分发；审核日期与负责人 |
| 证据位置 | 许可文本、网页存档、邮件授权或合同的受控存储位置 |

## 准入规则

1. 没有记录默认禁止分发。
2. “作品公版”不足以覆盖现代版次、MIDI 制作、录音、SoundFont、封面或页面渲染。
3. 文件替换、重新编码、裁剪、拼接或改变分发渠道后必须重新审核。
4. 发布前应从构建产物反查实际资产；文档清单不能替代 IPA 内容核验。
5. 资产结论有疑问时停止分发并交由目标法域的专业人士核验。
