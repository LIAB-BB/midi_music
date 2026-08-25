# K.478 弦乐 SoundFont 交付记录

发布候选只捆绑以下两个单预设音色库：

- `k478_violin.sf2`：GM melodic bank 0、Program 40（Violin）；
- `k478_cello.sf2`：GM melodic bank 0、Program 42（Cello）。

K.478 的钢琴两轨（原 MIDI 轨道 4、5；Program 0）由外接电子琴自行
发声，不能进入 App 的音频引擎。使用两个独立 SF2 是有意的发布设计：
播放器按 Program 选择对应的 `sfId`，不依赖 GUI 工具把两个预设合并。

上游输入采用 MuseScore_General 0.2 的 SF3 包，保存的校验值如下：

- 上游压缩包：`MuseScore_General-0.2.0.tar.bz2`
- 来源：Gentoo 打包的 MuseScore_General 0.2。MuseScore 的 OSUOSL 官方
  归档也列出了同版本的 SF2、SF3、授权说明、样本来源与 VERSION；由于
  归档镜像当前吞吐过低，上线前仍需完成输入 SF3 的字节级比对。
- 压缩包 SHA-256：`657c0f2c84f503fc3d296baa105208654f6eaf19cad2526221a257766a374780`
- 输入 SF3 SHA-256：`5b85b6c2c61d10b2b91cddd41efcce7b25cd31c8271d511c73afafbef20b6fa3`
- 上游授权说明 SHA-256：`5ad8d737e13c7f01f5b9674872a82a92b4ba253603e8ed14b9db12293550b4b9`
- 官方归档目录：`https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/`

## 可复验制作链

使用 Polyphone 2.6.0 macOS arm64 的官方命令行转换模式，DMG SHA-256：
`9b53047fa33208921ee40f68b6817cb6bbb94379980a537b029a757f45da856e`。

1. `-3` 将已校验的 `MuseScore_General.sf3` 解压为 SFZ 与 PCM WAV；
2. 从 bank `000` 选择 `040_Violin.sfz` 与 `042_Cello.sfz`；
3. 分别用 `-1` 转换为 SF2；
4. 分别用 `-4 -c raw` 反向解析成 CSV，确认 preset 文件名为
   `preset 000_040 Violin.csv` 与 `preset 000_042 Cello.csv`；
5. 用 `MidiPro.parseSoundfontPresets` 再做应用侧静态断言。

Polyphone 2.6.0 GUI 在当前 macOS 26.5.2 上多次发生 `EXC_BAD_ACCESS`，
因此 GUI 裁剪/合并产物已废弃，最终文件只来自上述成功完成并反向解析
通过的无界面转换链。

## 成品

- `k478_violin.sf2`：1,525,840 bytes；SHA-256
  `834b56f2a981ee5bd630a40f4ae7d0683969b8d319d2d8e8835303ed4a8dbd58`；
- `k478_cello.sf2`：975,632 bytes；SHA-256
  `b0d2a8029c6e62cc07e2ba7229b1ed33af1892967eba2c0eb8f04bccb183da9a`。

两个文件均为 RIFF SoundFont/Bank，样本为未压缩 PCM，未发现 `OggS`。
运行 `xcrun swift tool/validate_soundfonts_apple.swift` 可直接用 Apple
`AVAudioUnitSampler` 加载并离线渲染两个音色；本次峰值分别为
`0.19762793` 与 `0.22572052`，均非静音。发布前仍必须重跑 iOS Release
构建，并在 iPhone 真机分别实际发声后才可放行。
