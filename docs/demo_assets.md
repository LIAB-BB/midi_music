# Demo 乐谱素材

## Mozart — Piano Quartet in G minor, K.478

- App 内文件：`assets/midi/mozart_k478_piano_quartet.mid`
- PDF 分谱源文件：`assets/scores/mozart_k478_piano_part.pdf`
- App 内页面资源：`assets/scores/mozart_k478_piano_part/page-01.png` 至 `page-21.png`
- 来源：Mutopia Project，[`Piano Quartet KV 478`](https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=499)（Music ID 499）
- MIDI 下载地址：<https://www.mutopiaproject.org/ftp/MozartWA/KV478/k478/k478-mids.zip>
- PDF 下载地址：<https://www.mutopiaproject.org/ftp/MozartWA/KV478/k478/k478-a4-pdfs.zip>
- 下载日期：2026-07-21（MIDI）、2026-07-22（PDF）
- 来源页标注许可：Public Domain
- 编制：小提琴、中提琴、大提琴、钢琴（右手与左手分为两条 MIDI 轨）

当前产品入口将该 MIDI 作为“内置真实 MIDI 自动记谱”的主要 demo：默认合并钢琴 `upper` 和 `lower` 来源，但在 MusicXML 生成期间保留两条轨道的高低音谱表归属；声部面板还可加入小提琴、中提琴和大提琴组成总谱。

PDF 和分页 PNG 现作为同源公版对照材料、OMR 输入和保留资产，不是 K.478 练习页主视图。练习页只显示由 MIDI 生成的交互五线谱；保留的 `PdfScoreViewer` 和 MIDI 卷帘属于旧/高级组件，当前首页路径不会导航到它们。
