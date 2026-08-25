# K.478 Demo 素材

分发状态以 [资产台账](evidence/asset_manifest.md) 为准；来源、原始包和哈希证据见 [K.478 资源记录](evidence/k478_asset_evidence.md)。

## Mozart — Piano Quartet in G minor, K.478

- 候选 MIDI：`packages/k478_practice/assets/midi/mozart_k478_piano_quartet.mid`
- 仅作渲染来源的 PDF：`packages/k478_practice/assets/scores/mozart_k478_piano_part.pdf`（不随包）
- 随包页面图：`page-01.png` 至 `page-21.png`
- 来源：Mutopia Project，Piano Quartet KV 478（Music ID 499）；来源页标注 Public Domain。
- 编制：小提琴、中提琴、大提琴、钢琴（钢琴 MIDI 分为右手和左手两轨）。

候选乐谱阅读是从 PDF 生成的 **21 张独立页面图**，首页和演奏台均有手动入口；没有 MIDI 钢琴卷帘、自动翻页、MusicXML 编辑或播放位置同步。页面通过 `pdftoppm -r 180 -png` 从已核验 PDF 复现，验证命令为：

```bash
tool/verify_k478_score_pages.sh
```

若 Poppler 不在 `PATH`，可显式传入任务专用渲染器：`PDFTOPPM_BIN=/path/to/pdftoppm tool/verify_k478_score_pages.sh`。

演奏中电子琴自行发声。App 只播放固定弦乐轨；其中中提琴声部当前暂用小提琴音色，不能表述为已提供独立中提琴 SoundFont。原始 PDF、其他 MIDI 和 TimGM 不进入候选 bundle。
