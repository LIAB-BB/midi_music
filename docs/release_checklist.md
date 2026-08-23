# K.478 封闭试用候选验收清单

适用对象：`apps/testflight_ios` + `packages/k478_practice`，iPhone-only、iOS 13.0+。根目录 Legacy host（iOS 13.6、导入/麦克风/OMR/卷帘）不构成此清单的通过证据。

自动化、真机、签名 IPA 是三条不同证据链；任一未完成都不能写成“已发布”。建议将本次记录填入 [release dossier 模板](releases/k478_release_dossier_template.md)。

## 预检

```bash
cd packages/core_midi_input && flutter pub get && flutter analyze && flutter test
cd ../k478_practice && flutter pub get && flutter analyze && flutter test
cd ../../apps/testflight_ios && flutter pub get --enforce-lockfile && flutter analyze && flutter test
cd ../.. && tool/verify_k478_score_pages.sh
```

- [ ] 候选首页预载 K.478 MIDI 与离线弦乐音色成功；没有通用导入、选轨、卷帘或 OMR 入口。
- [ ] App 图标、TestFlight 截图和其他市场物料均已在资产台账登记并获准分发；未登记即阻止 TestFlight。
- [ ] 候选 lockfile、Pods 与本次源码一致；构建不以旧 Debug `Runner.app` 或旧 AssetManifest 作为证据。
- [ ] 已运行 K.478 页面验证脚本。页面图技术来源已核验；SF2 官方输入比对、iPhone 听音、签名 IPA 仍分别待验。
- [ ] 资产台账仅允许 K.478 MIDI、21 张 PNG、两个 SF2、第三方通知进入候选；原始 PDF、TimGM 和其他 MIDI 不得随包。

## S0：范围、可访问性与二进制

- [ ] 对外文案仅描述 iPhone + CoreMIDI 输入（首轮以直连 USB 电子琴验收）、固定 K.478、电子琴自发声和弦乐伴奏。
- [ ] 编制写作“小提琴 / 中提琴声部 / 大提琴”；明确中提琴声部当前暂用小提琴音色。
- [ ] VoiceOver 检查主页通知、播放位置、弦乐开关/音量和乐谱页码；在 2× 与 3× Dynamic Type 下检查首页、演奏台、乐谱入口不遮挡关键操作。
- [ ] 构建后运行 `tool/verify_testflight_ios_bundle.sh <Runner.app>`；确认 iPhone-only、插件与隐私 manifest、资产内容和禁止资产。
- [ ] 签名 Archive/IPA 另行复核插件、AssetManifest、Info.plist 与 Privacy Report；脚本通过不替代此项。

## S1：离线 SoundFont（真机必测）

- [ ] 首次离线启动后，Violin 40 与 Cello 42 能载入；失败提示可理解并可重试。
- [ ] K.478 弦乐轨在 iPhone 实听正常；停止、seek、重新进入不会卡音。
- [ ] 记录 SF2 来源、哈希、许可证通知和设备听音结论。官方输入比对未完成时不得将资产改为“已核验”。

## S2：固定曲目载入

- [ ] 从首页等待预载完成，点击「进入 MIDI 排练」进入「K.478 演奏台」。
- [ ] 首页与演奏台均可手动打开 21 页钢琴分谱；没有自动翻页或播放同步承诺。

## S3：基础播放

- [ ] 手动播放、暂停、拖动播放位置、回到开头工作；没有“快进/后退”按钮验收项。
- [ ] seek、pause、stop 后不残留长音；跟随活动期间上述手动 transport 与速度控制应禁用。

## S4：速度与弦乐

- [ ] 非跟随状态下 0.50×、0.75×、1×、1.25× 改变会话速度。
- [ ] 弦乐开关和音量生效；钢琴轨 4/5 从不进入 App 音频，电子琴保持自身发声。

## S5：CoreMIDI（真机必测）

- [ ] 先物理连接 class-compliant USB 电子琴到 iPhone，再点击「开始 MIDI 跟随」并确认活动会话显示设备名；页面在开始 Session 前不承诺持续监视设备。
- [ ] 在**活动会话**中拔出并重新插入，记录状态、错误提示和重新开始跟随是否可用。
- [ ] 不以 Hub、虚拟、网络或蓝牙端点作为首轮通过依据，也不在代码中按“USB”名称过滤端点。
- [ ] 若 Mac 调试线占用 iPhone 接口，使用 Xcode 无线调试或合适的供电 Hub/转接器；记录实际接线方式。

## S6：开始/停止 MIDI 跟随

- [ ] 使用「开始 MIDI 跟随」/「停止 MIDI 跟随」反复进入退出；启动中按钮禁用，不创建重复 Session。
- [ ] 不请求麦克风权限；输入 stream 错误后页面清理失效 Session，显示可重试错误。
- [ ] 首个普通错音、后续 onset 音或连续错音均不启动；首个正确起拍才开始弦乐。

## S7：Wait Mode 长休止（真机必测）

- [ ] 匹配休止前一 onset 后，边界前伴奏继续、状态仍为跟随；提前正确音和错误音都不重入。
- [ ] 到达休止边界后时间线暂停、状态等待；错误重入仍暂停。
- [ ] 正确重入后先 seek 到下一起拍再恢复播放/跟随；停止后清理等待状态。

## S8：试用材料与判定

- [ ] 测试说明列出 iPhone/iOS、电子琴型号、直连方式、K.478、已知限制与反馈入口。
- [ ] 记录 commit、build、IPA hash、设备、资产、隐私、S0-S7 结果与问题。
- [ ] Go/No-Go 数字与放大试用条件由负责人确认；本清单不擅自设为生效门槛。

未完成资产权利、音色真机、崩溃、明显误跟随、签名 IPA 隐私异常任一项，均应记录为阻止本轮分发，而非以自动化通过替代。
