# K.478 试用资源核验记录

> 核验日期：2026-08-20。此记录已逐字节核验 K.478 MIDI 与源 PDF；钢琴分谱页面图目前只完成本地完整性记录，尚缺可复现渲染证据。弦乐 SoundFont 已完成许可留档、成品哈希、结构和 Apple sampler 离线渲染验证，但输入 SF3 与 MuseScore 官方归档的字节级比对仍待完成。它不是对其他仓库资产的授权结论。

## 来源与许可标注

- 曲目页：[Mutopia — Piano Quartet KV 478（Music ID 499）](https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=499)
- 来源页标注：`Copyright: Public Domain`；来源版为 Breitkopf & Härtel（1880s），使用 LilyPond 2.4.2 排版。
- MIDI 原始包：[k478-mids.zip](https://www.mutopiaproject.org/ftp/MozartWA/KV478/k478/k478-mids.zip)
- PDF 原始包：[k478-a4-pdfs.zip](https://www.mutopiaproject.org/ftp/MozartWA/KV478/k478/k478-a4-pdfs.zip)

## 本地文件与原始包比对

2026-08-19 从上述 HTTPS 地址下载原始压缩包到临时目录后解压，以下两个仓库文件与原始文件的 SHA-256 完全一致：

| 本地文件 | 对应原始文件 | SHA-256 | 本轮 Flutter 随包 |
| --- | --- | --- | --- |
| `assets/midi/mozart_k478_piano_quartet.mid` | `k478-score.mid` | `06f5457a2831d88dc4a7def8a8b35903c6a9be23ceeb30964c1147d9d280a025` | 是 |
| `assets/scores/mozart_k478_piano_part.pdf` | `k478-piano-a4.pdf` | `d72a61d0102b797d9e89cb6c99741aa99d56f68af14ab78df15d5e244b0d12b4` | 否，仅作为页面图来源留存 |

候选包中有 21 张页面图，目录为 `packages/k478_practice/assets/scores/mozart_k478_piano_part/`。逐页 SHA-256 清单见 [`k478_page_sha256.txt`](k478_page_sha256.txt)，可在仓库根目录运行以下命令核对候选实际资产的完整性：

```bash
shasum -a 256 -c docs/evidence/k478_page_sha256.txt
```

这份清单只能证明页面图之后未变化，不能替代渲染来源证据：当前没有保存从已核验 PDF 生成 PNG 的命令、渲染器及版本、参数和逐页输出记录。将页面图放入试用包前，必须补齐并复验这条链路。

## 弦乐 SoundFont

独立候选包 `packages/k478_practice` 随包声明两个 MuseScore_General 0.2
衍生子集：

| 文件 | 唯一 preset | 大小 | SHA-256 |
| --- | --- | ---: | --- |
| `assets/soundfonts/k478_violin.sf2` | bank 0 / Program 40 / Violin | 1,525,840 bytes | `834b56f2a981ee5bd630a40f4ae7d0683969b8d319d2d8e8835303ed4a8dbd58` |
| `assets/soundfonts/k478_cello.sf2` | bank 0 / Program 42 / Cello | 975,632 bytes | `b0d2a8029c6e62cc07e2ba7229b1ed33af1892967eba2c0eb8f04bccb183da9a` |

两者均为未压缩 PCM SF2，无 `OggS`；`MidiPro.parseSoundfontPresets` 静态
测试通过，Apple `AVAudioUnitSampler` 离线渲染也产生非零波形。完整输入
哈希、Polyphone 无界面转换链、GUI 崩溃边界、授权通知与复验命令见
[`../../packages/k478_practice/assets/soundfonts/README.md`](../../packages/k478_practice/assets/soundfonts/README.md)。

尚未完成的证据是：当前上游包来自 Gentoo 的 MuseScore_General 0.2
打包源；MuseScore OSUOSL 官方归档存在同版本 SF2/SF3、授权与样本来源
文件，但镜像吞吐过低，本轮未完成官方 SF3 的全量 SHA-256 比对。因此该
资产在台账中仍为“待核验”，不能仅凭技术加载成功宣布可分发。

## 分发边界

- 仓库根目录仍是保留旧功能的开发 host，不作为本轮发布边界。独立候选 host 位于 `apps/testflight_ios`，其功能包只声明 K.478 MIDI、21 张钢琴分谱页面图、上述两个 SF2 与第三方授权通知；原始 PDF、其他 MIDI 和旧 TimGM6mb 不进入候选资产清单。
- 2026-08-20 在清理该 host 生成缓存后重新构建并检查 `apps/testflight_ios` 的无签名 iOS Release（`0.1.0+1`，`com.liab.k478Testflight`）：AOT App 包含当前双 SoundFont 路由、队列清理与 USB 状态展示符号；两个 SF2 和第三方通知均进入 App 资产目录且 SHA-256 与源码文件一致；21 张页面图全部进入包内。注册插件/Pods 只有 `core_midi_input` 与 `flutter_midi_pro`，另含依赖图需要的传递性 `objective_c.framework`；两个插件的 `PrivacyInfo.xcprivacy` 均随各自 framework 进入 App，Release Info.plist 不含麦克风、本地网络或 Bonjour 用途声明。尚未生成签名 Archive/IPA，因此仍需在最终归档后再次检查 AssetManifest、Privacy Report 与 IPA 内容。
- TestFlight 文案需保留来源页链接或等效的归档记录；若替换、重新编码或新增任何资源，必须重新核验本表与 `asset_manifest.md`。
- 这不是法律意见。若分发范围扩展到公开 App Store、付费内容或市场物料，应再次核对目标市场与 App Store 的权利要求。
