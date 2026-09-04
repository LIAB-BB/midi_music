# ADR 0001：K.478 iPhone CoreMIDI 候选边界

- 状态：Accepted
- 生效日期：2026-09-04

## 决定

1. 仓库维护两个独立目标：根目录 host 默认提供 K.478 交互五线谱与 USB
   `PlayerPage` 双入口；`apps/testflight_ios` + `packages/k478_practice` 作为固定
   K.478 的独立 TestFlight 候选。`home_page_legacy.dart` 只保留非默认开发测试
   用的通用曲库/导入，不是任一默认试用入口。
2. 首轮只做 iOS、iPhone、固定 K.478；真机验收只以直连 class-compliant USB 电子琴作为通过依据。
3. 固定钢琴轨 4/5 仅用于跟随，电子琴自身发声；App 只播放弦乐轨 1/2/3。
4. K.478 当前禁用自动 Wait Mode：钢琴声部休止不能单独暂停弦乐。只有经过人工审阅、确认全体声部均可等待的重入点才可启用边界暂停；当前批准点集合为空。
5. 当前中提琴声部暂用小提琴音色；不为此决定新增 Viola 资产或改写源 MIDI。

## 后果与边界

候选不承诺 Android、蓝牙 MIDI、通用选轨、卷帘、导入、OMR、麦克风跟随、自动 Wait Mode 或自动翻页。该 ADR 不代表签名 IPA、真机听音、资产权利或 Go/No-Go 已获批准。
