# Demo 乐谱素材

> 此页是来源线索，不是完整的分发授权结论。当前分发决定以 [`evidence/asset_manifest.md`](evidence/asset_manifest.md) 为准；在保存来源页、许可文本、文件哈希和署名义务前，资产状态均视为“待核验”。

## Mozart — Piano Quartet in G minor, K.478

- App 内文件：`assets/midi/mozart_k478_piano_quartet.mid`
- PDF 分谱源文件：`assets/scores/mozart_k478_piano_part.pdf`
- App 内页面资源：`assets/scores/mozart_k478_piano_part/page-01.png` 至 `page-21.png`
- 来源：Mutopia Project，`Piano Quartet KV 478`（Music ID 499）
- MIDI 下载地址：<https://www.mutopiaproject.org/ftp/MozartWA/KV478/k478/k478-mids.zip>
- PDF 下载地址：<https://www.mutopiaproject.org/ftp/MozartWA/KV478/k478/k478-a4-pdfs.zip>
- 下载日期：2026-07-21（MIDI）、2026-07-22（PDF）
- 来源页标注：Public Domain / CC0（须保存当时页面与具体许可文本后才能作为分发依据）
- 编制：小提琴、中提琴、大提琴、钢琴（右手与左手分为两条 MIDI 轨）

本项目将该文件作为 USB MIDI 跟随 demo。使用时应把钢琴右手和左手都加入「电子琴声部」，避免 App 与真实电子琴重复播放任一钢琴声部。

K.478 的阅读页使用同源钢琴分谱 PDF 的离线页面渲染，而不是把 MIDI 自动推断成五线谱；这保证了调号、分谱和记谱细节正确。PDF 阅读页暂不与播放位置自动翻页，实时跟随信息在演奏台的 MIDI 钢琴卷帘中展示。
