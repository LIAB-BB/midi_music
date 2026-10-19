# 跟随内核 v2：在线多假设对齐

> 状态：已接入 `packages/k478_practice` 的 `K478AdaptiveFollowSession`，
> 候选页面默认使用；旧 `K478MidiFollowSession` 保留回退。**尚未完成
> iPhone + USB 电子琴真机验收**，不能据此宣称跟随鲁棒性已通过发布门槛。

## 1. 为什么重写

旧候选的 `FollowModeController` 是严格逐音匹配：

- 只接受当前期待的 onset；漏一个音后期待位置停在原处，后续正确音都
  被算作错音；
- 连续 3 次错音只把播放器 seek 回“期待位置”，期待位置本身不前进；
- 没有谱面相位反馈；速度只在两次正确起拍之间做一次 EMA；
- 和弦尾音超过 80 ms 就算错音；
- 生产配置的 `approvedWaitReentryTicks` 为空，`pauseAt` 休止路径从未
  在真实曲目上启用。

静态审计还确认：内置 K.478 MIDI 有 23 处钢琴起拍间隔 > 1 s（最长
13.4 s），8 分钟曲目对漂移非常敏感。旧算法在干净演奏里能靠“严格顺序”
走到最后，但一旦有错音、漏音或跳页，位置就无法恢复。

## 2. 算法

### 2.1 状态

每个假设维护：

- `lastIndex` / `nextIndex`：已匹配和下一期待 onset；
- `anchorScore` / `anchorWall`：最近一次“和弦第一个音”的谱面/墙钟锚点；
- `speed`：当前速度估计（倍速）；
- `matches` / `misses` / `confidence` / `prior`；
- `isFork`：是否由漏音分支创建。

### 2.2 单次输入

1. 对每个假设，在 `[nextIndex - 1, nextIndex + lookahead]` 内找音高
   匹配；向前最多跳 2 个 onset，向后 1 个用于和弦尾音。
2. 预测时间 = `anchorWall + (onset.time - anchorScore) / speed`；
   时间门限按局部起拍间隔自适应（快速跑动收紧）。
3. 代价 = 归一化时间误差² + 跳音/回看惩罚；取最小代价。
4. 命中后更新速度（谱面间隔 / 墙钟间隔，EMA α=0.3；跳音降权），
   更新锚点、位置和置信度。
5. 同一 onset 的后续 Note On（和弦尾音）只确认位置，不更新锚点、
   不推进位置、不增加匹配数——否则和弦越宽速度估计越偏快。
6. 长时间停顿后，若输入正好命中期待 onset，允许重锚，不把停顿当成
   极慢速度。

### 2.3 漏音分支与重新捕获

- 某假设漏音时，在向前 32 个 onset 内按“预测谱面时间”排序，开最多
  6 个低置信度分支；
- 主假设存活期间，分支置信度封顶 0.35，避免并行重复段落抢走位置；
- 主假设全部淘汰后，分支才可升为最佳；
- 分支本身不再分支，避免指数增长；
- 假设全部失效时，用最近一次匹配的锚点 + 墙钟推进 × 当前速度预测
  谱面时间，按时间距离重新捕获。

### 2.4 初始锁谱

- 第一次输入只在 `preferredStartIndex .. +startWindow`（默认 24 个
  onset）内找候选；窗口内没有该音高才回退全曲。
- 这样曲首的反复音型不会被锁到几十个 onset 之后；从中间起奏时由
  上层传入 `preferredStartIndex`。

## 3. 量化结果

`dart run tool/benchmark.dart`，K.478 钢琴轨 4/5（1922 onset / 3116
音符 / 8:00），确定性模拟：

| 场景 | v1 精确 | v2 精确 | v2 误差≤1 | v1 跳页恢复 | v2 跳页恢复 |
|---|---:|---:|---:|---|---|
| 干净 rubato + 和弦拆分 | 98.8% | 99.1% | 99.9% | — | — |
| 3% 错音 / 1.5% 漏音 / 2% 装饰音 | 1.5% | 97.7% | 99.8% | — | — |
| 中段跳页 +10 | 4.0% | 97.3% | 99.3% | 未恢复 | 12 音 |

速度 MAE：干净场景 v1 0.027、v2 0.023；失误场景 v1 0.016（但只剩
1.5% 的样本位置正确）、v2 0.024。详细表见包 README。

## 4. 当前接入

`K478AdaptiveFollowSession`（`packages/k478_practice/lib/src/core/`）：

- 从候选的轨道 4/5 `MidiNote` 构建 `Score`，不重解析 MIDI；
- 输入时间使用会话自己的 `Stopwatch`（测试可注入 `timeProvider`），
  不使用 CoreMIDI 的 host timestamp；
- `confidence >= 0.5` 才启动伴奏；从上一个 onset 起播，避免切掉第一个
  弦乐起拍；
- 普通匹配只 `setSpeed`；`reacquired` 时 seek/play；只有
  `confidence >= 0.6` 且 `|drift| > 0.8 s` 才做一次大漂移 seek；
- 订阅 `MidiInput.states`，设备列表为空时暂停并回调 `onTerminated`；
- 默认 `FollowConfig(minSpeed: 0.25, maxSpeed: 2)`，与播放器的变速范围
  对齐；
- 旧 `K478MidiFollowSession` 与 `FollowModeController` 保留，作为回退
  和对照，仍由原测试覆盖。

## 5. 仍未完成

1. **连续相位反馈**：目前只有 0.8 s 的大漂移保护，没有 PLL/连续相位
   控制；长曲目的慢漂移仍靠速度估计。
2. **播放器单调时钟**：`K478PlayerController` 仍用 `DateTime.now()` 的
   5 ms ticker，没有 delta 上限、前后台/音频中断处理。
3. **休止/等待**：没有自动生成休止边界；候选仍不因钢琴休止而暂停伴奏。
4. **EventChannel 生命周期**：没有引用计数；快速重进页面、锁屏/来电
   恢复仍需真机验证。
5. **真机验收**：iPhone + USB 电子琴、长休止、连续错音、跳页、锁屏/
   来电中断；不能用纯 Dart 模拟替代。

## 6. 已知边界

- 只处理 MIDI Note On，不做音频 onset/音高检测。
- 不处理完整反复（da capo）；并行重复段落仍可能重新捕获到错误位置，
  基准里 B/C 场景的最大位置跳变分别为 10/19 个 onset。
- 模拟演奏是确定性合成，不代表真实演奏者的全部表情；真机数据仍需
  单独采集。
- 任意段落起奏需要 start hint；没有做全曲序列对齐。
