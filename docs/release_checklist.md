# K.478 封闭试用候选验收清单

适用对象：`apps/testflight_ios` + `packages/k478_practice`，iPhone-only、iOS 13.0+。根目录 Legacy host（iOS 13.6、导入/麦克风/OMR/卷帘）不构成此清单的通过证据。

自动化、真机、签名 IPA 是三条不同证据链；任一未完成都不能写成“已发布”。建议将本次记录填入 [release dossier 模板](releases/k478_release_dossier_template.md)。

## 双机真机装机（开发签名，先于 TestFlight）

目标：两台 iPhone 都脱离 Mac 数据线，各自直连电子琴完成 S1–S7。当前候选 Team 为 `XV6N683H3X`（`com.liab.k478Testflight`），Automatic Signing。

### 装机前（每台手机各做一次）

1. iPhone 与 Mac 同一 Wi‑Fi；首次仍建议 **USB 连一次** 完成“信任此电脑”。
2. iPhone：设置 → 隐私与安全性 → 开发者模式 → 打开（若系统要求）。
3. Xcode → Window → Devices and Simulators：确认设备出现；勾选 **Connect via network**（无线调试）。
4. 该 Apple ID / Team 下把两台设备 UDID 加进开发设备列表（Automatic 首次 Run 时常会自动注册；失败则到 developer.apple.com 手动加）。
5. 本机已有 Development 证书即可；无需先上 TestFlight。

### 安装命令（候选 host）

```bash
cd apps/testflight_ios
flutter pub get --enforce-lockfile
# 查看设备 ID（含 wireless）
flutter devices
# 装到指定真机（示例：把 <device_id> 换成 flutter devices 里的 ID）
flutter run --release -d <device_id>
```

装成功后：**拔掉 Mac 线**（若仍插着），只保留电子琴 USB 通路，再跑下面 S5–S7。

### 双机记录表（必填）

| 项 | 手机 A（负责人） | 手机 B（协作者） |
| --- | --- | --- |
| 机型 / iOS | | |
| 设备 ID（`flutter devices`） | | |
| 接线：无线调试 / 直连琴的转接头 | | |
| 电子琴型号 | | |
| 构建 commit | | |
| S1 听音 | 待测 | 待测 |
| S5 连接与拔插 | 待测 | 待测 |
| S6 跟随启停与首音 | 待测 | 待测 |
| S7 钢琴休止弦乐连续 | 待测 | 待测 |
| 阻塞问题 | | |

两台都未完成 S5–S7 前，不把单机结果写成“真机已通过”。

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
- [ ] 资产台账仅允许 K.478 MIDI、21 张 PNG、两个 SF2、`cupertino_icons` 图标字体与第三方通知进入候选；原始 PDF、TimGM 和其他 MIDI 不得随包。

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
- [ ] 从点击「开始 MIDI 跟随」到连接与首个正确起拍之间，播放、暂停、seek、停止和速度控制均不可抢先启动或改变伴奏。
- [ ] 不请求麦克风权限；输入 stream 错误后页面清理失效 Session，显示可重试错误。
- [ ] 首个普通错音、后续 onset 音或连续错音均不启动；首个正确起拍才开始弦乐。

## S7：钢琴休止期间的连续弦乐（真机必测）

- [ ] K.478 的钢琴单独休止期间，弦乐不暂停、不 seek，状态保持跟随；不能将钢琴停顿误写成“全体等待”。
- [ ] 当前批准等待点集合为空，测试说明、截图和口头引导均不得宣传 Wait Mode。
- [ ] 如未来申请增加等待点，必须先记录 MIDI tick、所有声部活动审计、人工批准人和真机回归结果，再单独更新 ADR、测试和本清单。

## S8：试用材料与判定

- [ ] 测试说明列出 iPhone/iOS、电子琴型号、直连方式、K.478、已知限制与反馈入口。
- [ ] 记录 commit、build、IPA hash、设备、资产、隐私、S0-S7 结果与问题。
- [ ] Go/No-Go 数字与放大试用条件由负责人确认；本清单不擅自设为生效门槛。

未完成资产权利、音色真机、崩溃、明显误跟随、签名 IPA 隐私异常任一项，均应记录为阻止本轮分发，而非以自动化通过替代。
