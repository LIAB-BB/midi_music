# K.478 Demo 素材

> 本页记录来源及两个 host 的不同用途，不单独构成分发批准。分发状态以
> [资产台账](evidence/asset_manifest.md) 为准；原始包与哈希证据见
> [K.478 资源记录](evidence/k478_asset_evidence.md)。

## Mozart — Piano Quartet in G minor, K.478

- 来源：Mutopia Project，Piano Quartet KV 478（Music ID 499）；来源页标注
  Public Domain。
- MIDI 下载地址：<https://www.mutopiaproject.org/ftp/MozartWA/KV478/k478/k478-mids.zip>
- PDF 下载地址：<https://www.mutopiaproject.org/ftp/MozartWA/KV478/k478/k478-a4-pdfs.zip>
- 编制：小提琴、中提琴、大提琴、钢琴；钢琴 MIDI 的右手和左手为独立轨道。

## 根目录 App

- MIDI：`assets/midi/mozart_k478_piano_quartet.mid`。
- 对照 PDF：`assets/scores/mozart_k478_piano_part.pdf`。
- 对照页面：`assets/scores/mozart_k478_piano_part/page-01.png` 至
  `page-21.png`。
- 默认首页的“查看交互五线谱”从真实 MIDI 生成 MusicXML，并在本地 OSMD
  中显示；钢琴默认合并 upper/lower 来源但保持高低音谱表归属，也可多选弦乐
  组成总谱。
- PDF/PNG 只作来源追溯、人工对照和 OMR 开发输入，不是根 App 练习页的显示
  来源。默认首页另有 USB MIDI `PlayerPage` 入口；
  `home_page_legacy.dart` 仅保留非默认通用库/导入。

## 独立 TestFlight 候选

- MIDI：`packages/k478_practice/assets/midi/mozart_k478_piano_quartet.mid`。
- 仅作渲染来源且不随包的 PDF：
  `packages/k478_practice/assets/scores/mozart_k478_piano_part.pdf`。
- 随包页面：同目录 `page-01.png` 至 `page-21.png`。
- 离线音色：`packages/k478_practice/assets/soundfonts/k478_violin.sf2` 与
  `k478_cello.sf2`；中提琴声部暂用小提琴音色。
- 候选页面是从 PDF 生成的 21 张独立图片，可手动翻页；不承诺 OSMD、小节
  点击、自动翻页、MusicXML 编辑或播放位置同步。

页面使用 Poppler `pdftoppm 26.05.0 -r 180 -png` 生成，复现命令为：

```bash
tool/verify_k478_score_pages.sh
```

若 Poppler 不在 `PATH`，可显式传入任务专用渲染器：
`PDFTOPPM_BIN=/path/to/pdftoppm tool/verify_k478_score_pages.sh`。

两个 host 即使引用同源作品，也必须分别从最终 asset manifest / IPA 反查实际
分发内容；一个 host 的核验结果不能自动批准另一 host 中路径或用途不同的副本。
