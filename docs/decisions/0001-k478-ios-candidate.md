# ADR 0001：K.478 iPhone CoreMIDI 候选边界

- 状态：已采纳、待合并生效
- Owner：合并时填写
- 生效日期：合并时填写

## 决定

1. 发布实现使用 `apps/testflight_ios` + `packages/k478_practice`；根目录 Legacy host 继续保留，不删除旧功能。
2. 首轮只做 iOS、iPhone、固定 K.478；真机验收只以直连 class-compliant USB 电子琴作为通过依据。
3. 固定钢琴轨 4/5 仅用于跟随，电子琴自身发声；App 只播放弦乐轨 1/2/3。
4. K.478 当前禁用自动 Wait Mode：钢琴声部休止不能单独暂停弦乐。只有经过人工审阅、确认全体声部均可等待的重入点才可启用边界暂停；当前批准点集合为空。
5. 当前中提琴声部暂用小提琴音色；不为此决定新增 Viola 资产或改写源 MIDI。

## 后果与边界

候选不承诺 Android、蓝牙 MIDI、通用选轨、卷帘、导入、OMR、麦克风跟随、自动 Wait Mode 或自动翻页。该 ADR 不代表签名 IPA、真机听音、资产权利或 Go/No-Go 已获批准。
