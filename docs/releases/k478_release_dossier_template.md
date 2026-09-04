# K.478 Release Dossier（模板，非发布记录）

> 此文件只适用于 `apps/testflight_ios` + `packages/k478_practice` 独立候选，
> 不能作为“已发布”证据。每个字段由发布负责人按实际构建填写。
> 根 App 的交互五线谱与 USB `PlayerPage` 使用
> [`../release_checklist.md`](../release_checklist.md)，其结果不能填入本表冒充
> 独立候选证据。

| 字段 | 实际记录 |
| --- | --- |
| Git commit / 分支 |  |
| 构建号 / Bundle ID |  |
| Archive / IPA SHA-256 |  |
| 构建日期与负责人 |  |
| iPhone 型号 / iOS |  |
| 电子琴型号 / 直连方式 |  |
| Flutter / Xcode / CocoaPods |  |
| Runner.app 二进制审计 | 通过 / 失败 / 未执行 |
| Archive Privacy Report | 通过 / 失败 / 未执行 |
| K.478 MIDI / PNG / SF2 / notices 哈希 |  |
| SF2 官方输入比对与真机听音 |  |
| 专用清单版本 | `docs/releases/k478_testflight_checklist.md` |
| 与根 App 证据隔离复核 | 通过 / 失败 / 未执行 |

## 场景结果

| 场景 | 结果 | 证据 / 问题 |
| --- | --- | --- |
| S0 范围、可访问性、二进制 |  |  |
| S1 离线 SoundFont |  |  |
| S2 固定曲目预载 |  |  |
| S2a 21 张静态 PNG 手动翻页（无 OSMD/播放同步承诺） |  |  |
| S3 基础播放 |  |  |
| S4 速度与弦乐 |  |  |
| S5 CoreMIDI 拔插 |  |  |
| S6 开始/停止跟随 |  |  |
| S7 钢琴休止期间的连续弦乐 |  |  |
| S8 试用说明与反馈 |  |  |

## Go / No-Go

- 建议值/待负责人确认的数字指标：
- 阻止项：
- 负责人结论（Go / No-Go / 暂缓）：
- 结论日期与签署人：
