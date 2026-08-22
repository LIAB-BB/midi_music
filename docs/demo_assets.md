# Demo 乐谱素材

> 当前分发决定以 [`evidence/asset_manifest.md`](evidence/asset_manifest.md) 为准。K.478 的来源、原始包和 SHA-256 比对见 [`evidence/k478_asset_evidence.md`](evidence/k478_asset_evidence.md)；其他资源仍须单独核验。

## Mozart — Piano Quartet in G minor, K.478

- App 内文件：`assets/midi/mozart_k478_piano_quartet.mid`
- PDF 分谱源文件：`assets/scores/mozart_k478_piano_part.pdf`
- App 内页面资源：`assets/scores/mozart_k478_piano_part/page-01.png` 至 `page-21.png`
- 来源：Mutopia Project，`Piano Quartet KV 478`（Music ID 499）
- MIDI 下载地址：<https://www.mutopiaproject.org/ftp/MozartWA/KV478/k478/k478-mids.zip>
- PDF 下载地址：<https://www.mutopiaproject.org/ftp/MozartWA/KV478/k478/k478-a4-pdfs.zip>
- 下载日期：2026-07-21（MIDI）、2026-07-22（PDF）
- 来源页标注：Public Domain；2026-08-19 已将本地 MIDI/PDF 与官方下载包逐字节比对。
- 编制：小提琴、中提琴、大提琴、钢琴（右手与左手分为两条 MIDI 轨）

本项目将该文件作为 USB MIDI 跟随 demo。使用时应把钢琴右手和左手都加入「电子琴声部」，避免 App 与真实电子琴重复播放任一钢琴声部。

K.478 的阅读页显示钢琴分谱的离线页面图，而不是把 MIDI 自动推断成五线谱；这保留了调号、分谱和记谱细节。源 PDF 已逐字节核验；页面图的逐页哈希已记录，但在保存可复现渲染命令、工具版本与输出记录前，不能将其视为完成分发核验。Flutter 计划仅随包 21 张页面图，不随包原始 PDF。PDF 阅读页暂不与播放位置自动翻页，实时跟随信息在演奏台的 MIDI 钢琴卷帘中展示。
