# 资产准入台账

> 更新日期：2026-09-04。每个随 App、TestFlight、CDN 或市场物料分发的
> 资源都必须有记录。`来源/完整性核验` 与 `分发许可` 是两条独立状态：前者为
> `已核验` 或 `待核验`，后者为 `允许`、`待批准` 或 `禁止`。
>
> 本表不是法律意见；来源 `已核验` 不自动等于获准分发，仍应保存原始许可文本、
> 合同或网页存档。分发许可为 `禁止` 表示不得进入最终 asset manifest、IPA、
> CDN、截图或其他对外物料；仅隐藏 UI 不等于没有分发。`待批准` 在批准前也不得
> 进入对外构建或物料。

## 目标边界

- **根 App**：默认首页提供 K.478 交互五线谱和 USB `PlayerPage`；谱面来自
  MIDI→MusicXML→本地 OSMD。`home_page_legacy.dart` 不是默认入口。
- **独立候选**：`apps/testflight_ios` + `packages/k478_practice`，使用固定 MIDI、
  21 张 PNG、Violin/Cello SF2 与 CoreMIDI。
- 两套构建必须分别检查最终产物。相同作品的不同文件路径、转换产物或分发用途
  不能自动共用批准结论。

## 当前已知资产

| 目标 | 资源 | 路径/哈希 | 来源/完整性核验 | 分发许可 | 已知证据与限制 | 进入对应试用版前的动作 |
| --- | --- | --- | --- | --- | --- | --- |
| 两者 | Mozart K.478 MIDI | 根：`assets/midi/mozart_k478_piano_quartet.mid`；候选：`packages/k478_practice/assets/midi/mozart_k478_piano_quartet.mid`；已记录 SHA-256 `06f5457a2831d88dc4a7def8a8b35903c6a9be23ceeb30964c1147d9d280a025` | 已核验 | 允许 | 与 Mutopia `k478-score.mid` 比对一致；来源页标注 Public Domain。具体记录见 [`k478_asset_evidence.md`](k478_asset_evidence.md)。 | 分别确认最终构建中的副本哈希；文件或渠道变化时重新核验。 |
| 根 App | K.478 对照 PDF | `assets/scores/mozart_k478_piano_part.pdf`；SHA-256 `d72a61d0102b797d9e89cb6c99741aa99d56f68af14ab78df15d5e244b0d12b4` | 已核验 | 禁止 | 只作来源追溯、人工对照和 OMR 开发输入；根交互谱不读取它。 | 从根 Flutter asset manifest / IPA 确认排除。 |
| 根 App | K.478 对照 PNG | `assets/scores/mozart_k478_piano_part/page-*.png` | 已核验 | 禁止 | 与同源 PDF 对应，但根练习页不读取 PNG；当前 `pubspec.yaml` 仍声明该目录。 | 根 App 发布前删除不必要的 asset 声明；若未来出现必须随包的产品理由，须重新审核并把分发许可改为“允许”。仅不显示不算排除。 |
| 根 App | OSMD 1.9.9 运行时 | `assets/score_renderer/opensheetmusicdisplay.min.js`；SHA-256 `658ed444554d43ec66bfb54c72d6833d369e5f93a3a2c06095187cd09a401034` | 已核验 | 允许 | 本地 bundle 与 `assets/score_renderer/LICENSE` 一并分发；运行时不得访问 CDN。 | 从最终包复核版本、哈希、LICENSE、CSP 与离线网络行为。 |
| 根 App | TimGM6mb SF2 | `assets/soundfonts/TimGM6mb.sf2` 或运行时下载缓存 | 待核验 | 禁止 | 随包文件缺完整许可/版本/校验记录；下载路径也须固定来源与完整性。 | 明确随包或下载策略，补许可证、署名、SHA-256、实际加载和失败体验；完成复核前不得改为“允许”。 |
| 根 App | 其余内置 MIDI | `assets/midi/` 中除 K.478 外文件 | 待核验 | 禁止 | 仓内无充分来源和渠道授权；非默认页面不可作为分发豁免。 | 逐首补证并重新批准，或从最终 manifest、IPA、截图和入口移除。 |
| 独立候选 | K.478 钢琴分谱 PNG | `packages/k478_practice/assets/scores/mozart_k478_piano_part/page-*.png` | 已核验 | 允许 | 已核验 PDF 通过 Poppler `pdftoppm 26.05.0 -r 180 -png` 复现，21 页逐字节一致。 | 运行 `tool/verify_k478_score_pages.sh`；转换参数或文件变化时重审。 |
| 独立候选 | K.478 原始 PDF | `packages/k478_practice/assets/scores/mozart_k478_piano_part.pdf` | 已核验 | 禁止 | 与 Mutopia `k478-piano-a4.pdf` 比对一致，仅用于复现 PNG。 | 保持不在 candidate Flutter manifest；如改为 App 内读取须重新审核。 |
| 独立候选 | K.478 Violin / Cello SF2 | `packages/k478_practice/assets/soundfonts/k478_{violin,cello}.sf2` | 待核验 | 待批准 | MuseScore_General 0.2 的 bank 0 Program 40/42 子集；授权通知、输入/输出哈希、转换链、preset 测试和 Apple sampler 离线渲染已有记录；仍缺官方输入全量比对与 iPhone 实听。 | 完成官方输入比对、签名 IPA 哈希/通知检查和 iPhone 离线听音；批准前阻止分发。 |
| 独立候选 | Cupertino Icons 字体 | `packages/cupertino_icons/assets/CupertinoIcons.ttf` | 待核验 | 待批准 | `cupertino_icons 1.0.9` 声明 MIT；候选 UI 使用该字体。 | 在 lockfile、签名 IPA、`FontManifest.json` 和第三方通知中复核版本与路径；批准前阻止分发。 |
| 两者 | App 图标、字体、截图、宣传音频 | 待补充 | 待核验 | 待批准 | 尚未按目标构建形成逐项清单。 | TestFlight 或宣传前分别登记来源、许可、渠道和实际构建路径。 |

## 当前分发判定

- **根 App：No-Go。** 当前根 `pubspec.yaml` 仍声明会带入禁止分发的 PDF/PNG、
  TimGM6mb 和其他 MIDI；运行时 SoundFont 下载也尚未完成固定来源、许可与完整性
  闭环。只有从最终构建排除所有“禁止”资产，且本轮实际使用资源全部为“允许”后
  才能重新判定。
- **独立候选：No-Go。** 技术白名单允许检查两个 SF2 与 Cupertino Icons 是否是
  唯一预期资产，但它不授予分发许可；二者仍为“待批准”，完成官方输入比对、
  iPhone 听音、签名 IPA/通知复核及负责人批准前不得分发。

## 新资产记录模板

| 字段 | 必填内容 |
| --- | --- |
| 目标构建 | 根 App / 独立 K.478 候选 / CDN / 市场物料 |
| 资产 ID / 文件哈希 | 文件名、版本、完整 SHA-256、存储位置 |
| 资源类型 | 作品、版次、MIDI、音频、采样、PDF、图像、字体等 |
| 来源 | 原始 URL / 合同 / 订单号；记录获取日期 |
| 权利链 | 作品、版次、表演/制作、录音、采样库分别说明 |
| 许可证与义务 | 商业分发、改编、署名、同许可、地域、期限、渠道限制 |
| 分发范围 | 随包 / 下载 / CDN / TestFlight / App Store / 市场截图 |
| 来源/完整性核验 | 已核验 / 待核验；核验日期与证据负责人 |
| 分发许可 | 允许 / 待批准 / 禁止；批准日期、负责人和适用渠道 |
| 证据位置 | 许可文本、网页存档、邮件授权或合同的受控存储位置 |

## 准入规则

1. 没有记录默认禁止分发；分发许可不是“允许”时一律不得进入对外构建或物料。
2. “作品公版”不足以覆盖现代版次、MIDI 制作、录音、SoundFont、封面或页面渲染。
3. 文件替换、重新编码、裁剪、拼接、移动到另一 host 或改变分发渠道后必须重新审核。
4. 发布前从对应构建产物反查实际资产；源码和文档清单不能替代 IPA 内容核验。
5. 独立候选的 package 资产采用精确白名单；拒绝 host 级未知 assets、TimGM、
   原始 PDF 和其他 MIDI。根 App 则单独审核 K.478 MIDI、OSMD 和音色交付路径。
6. 资产结论有疑问时停止分发，并交由目标法域专业人士核验。
