# MIDI 伴奏 App

> 当前产品范围的唯一事实源是 [`docs/product/release_scope.md`](docs/product/release_scope.md)。
> 本文件只保留项目入口；历史可行性研究与长期设想不能替代当前发布范围。

## 当前候选产品定义：iOS USB MIDI 封闭试用

面向拥有 class-compliant USB MIDI 电子琴和 iPhone 的古典音乐练习者。用户在电子琴上演奏指定的钢琴声部，App 接收 MIDI Note On、静音该钢琴声部，并以当前演奏速度播放其余声部。

当前选定的代表曲目是莫扎特 K.478 钢琴四重奏；是否可随某次试用分发以资产台账核验为准。电子琴自行发声；App 不承担电子琴音色输出。

本仓库当前**尚未达到 TestFlight 分发门槛**：资产台账、音色库交付、最终 IPA 资源排除和真实设备验收均待完成。以下内容定义候选验收路径，不是已上线功能清单。

## 当前范围

- iOS + CoreMIDI USB 输入；不承诺 Android MIDI 输入。
- 已标注声部的分轨 MIDI、基础播放控制、轨道静音与速度跟随。
- K.478 的离线钢琴分谱页面阅读（由同源 PDF 预渲染）；候选不含钢琴卷帘。
- 在全部发布门槛通过后，才可进入小范围 TestFlight 可用性验证；不面向公众正式商业发布。

## 当前不在范围内

- 麦克风识别小提琴、管乐或复调钢琴，并据此进行鲁棒乐谱跟随。
- 通用 PDF 识谱服务、MusicXML 原生排版、自动翻页与播放进度同步。
- Android、云曲库、教师 SaaS、预渲染 stem、实时动态层混合或 AI 生成伴奏。
- 未完成授权核验的曲库内容。

## 交付判断

不能仅以单元测试通过认定发布就绪。每次试用版必须同时满足：

1. 音色库交付策略和版权证据明确；
2. 目标曲目所有资产都可用于该分发渠道；
3. iPhone + 真实电子琴完成 USB 连接、跟随、钢琴休止期间的连续弦乐和退出恢复验证；
4. 已知限制在测试说明和产品页中如实披露。

详情见 [`docs/product/capability_matrix.md`](docs/product/capability_matrix.md) 与 [`docs/release_checklist.md`](docs/release_checklist.md)。

## 文档入口

- [`docs/product/release_scope.md`](docs/product/release_scope.md)：当前试用版的用户、范围和验收门槛。
- [`docs/product/capability_matrix.md`](docs/product/capability_matrix.md)：功能状态及证据边界。
- [`docs/product/strategy.md`](docs/product/strategy.md)：经审阅后的路线与 Go/No-Go 决策。
- [`docs/evidence/asset_manifest.md`](docs/evidence/asset_manifest.md)：内容和音频资产许可台账。
- [`docs/release_checklist.md`](docs/release_checklist.md)：真机和发布验收记录。
