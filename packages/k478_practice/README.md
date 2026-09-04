# k478_practice

面向 iOS TestFlight 候选的 K.478 功能包。它把待完成资产、真机与签名验收的
最小候选路径从根目录 host 中隔离出来，避免将遗留功能或原生权限一并带入
测试包；“代码已隔离”不代表已经获准分发。

## 包含内容

- 内置 `mozart_k478_piano_quartet.mid` 解析、时间线与变速调度；
- USB CoreMIDI 钢琴跟随；
- 21 张由钢琴声部 PDF 预渲染得到的 PNG 页面，原始 PDF 不随包；
- 只输出 K.478 的小提琴 I/II 与大提琴轨；
- 基于 `flutter_midi_pro 4.0.4` 的显式 iOS 音频会话与生命周期。

## 不包含内容

- 泛 MIDI 导入、文件选择、MusicXML/OMR；
- 麦克风跟随、音高检测、麦克风权限；
- 在线下载的 SoundFont；
- 钢琴 Program 0 的 App 内音频。

K.478 的轨道 1、2、3 是弦乐，轨道 4、5 是钢琴。播放器会在 Program
Change、Note On、Note Off 进入引擎前过滤钢琴轨；回归测试覆盖此边界。

## SoundFont

候选技术 bundle 声明 `assets/soundfonts/k478_violin.sf2` 与
`assets/soundfonts/k478_cello.sf2`；它们分别只包含 bank 0 Program 40
（Violin）和 42（Cello）。制作记录、输入哈希和复验要求见
[`assets/soundfonts/README.md`](assets/soundfonts/README.md)，第三方授权通知
随应用资产位于 `assets/legal/third_party_notices.txt`。两个 SF2 只有在
[`../../docs/evidence/asset_manifest.md`](../../docs/evidence/asset_manifest.md)
中的分发许可变为“允许”后才能进入对外构建。

本包使用 `publish_to: none`，不可作为公开 pub 包发布。
