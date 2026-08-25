# MIDI Music

当前仓库同时保留两条路径：**K.478 iOS Release Candidate** 是唯一候选发布实现；仓库根目录是保留旧能力的 Legacy host。两者不能互相替代验证结果。

候选范围、证据和试用门槛以 [release scope](docs/product/release_scope.md)、[能力矩阵](docs/product/capability_matrix.md) 和 [发布清单](docs/release_checklist.md) 为准。当前仍未完成真机、签名 Archive/IPA、SoundFont 官方输入比对与最终隐私报告核验，不能宣称已可 TestFlight 分发。

## Release Candidate：K.478 iPhone + CoreMIDI

- Host：`apps/testflight_ios`
- 实现包：`packages/k478_practice`；输入包：`packages/core_midi_input`
- 范围：iOS 13.0+、iPhone-only、固定莫扎特 K.478；首轮仅以直连 class-compliant USB 电子琴验收。
- 电子琴自行发出钢琴声；App 只播放轨道 1/2/3 的弦乐伴奏。中提琴声部当前暂用小提琴音色。
- 固定钢琴轨 4/5 用于跟随；没有通用选轨、钢琴卷帘、导入、自动翻页或 MusicXML 五线谱渲染承诺。
- 乐谱是 21 页独立 PDF 预渲染页，可从首页或演奏台手动进入；不随播放同步。

候选本地门禁：

```bash
cd packages/core_midi_input
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze && flutter test

cd ../k478_practice
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze && flutter test

cd ../../apps/testflight_ios
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze && flutter test
# 构建由发布负责人显式执行：flutter build ios --release --no-codesign
```

PDF 页面来源可复现验证：

```bash
tool/verify_k478_score_pages.sh
```

无签名或签名构建完成后，审核实际二进制而不是只看源码：

```bash
tool/verify_testflight_ios_bundle.sh apps/testflight_ios/build/ios/iphoneos/Runner.app
```

该脚本不替代签名 Archive 的 Privacy Report 或 iPhone 真机验收。

## 技术结构与保留能力索引

候选使用 Flutter + Cupertino；`core_midi_input` 负责 iOS CoreMIDI 输入，`dart_midi_pro` 解析固定 MIDI，`flutter_midi_pro` 驱动 SoundFont，Provider 管理页面播放状态。

```text
apps/testflight_ios/       独立 iPhone 候选 host 与 iOS 原生配置
packages/k478_practice/    K.478 UI、播放、Wait Mode 跟随与随包资产
packages/core_midi_input/  CoreMIDI Dart/原生输入边界
```

根 Legacy host 仍保留 import、麦克风跟随、PDF OMR 协议和钢琴卷帘研发代码；它们不进入候选二进制。更详细的模块与风险快照见 [CLAUDE.md](CLAUDE.md)（若该文件有本地未提交改动，以工作区内容为准）。

## Legacy host：根目录

根目录 `lib/`、`test/`、Android/iOS host 保留旧曲库、导入、麦克风跟随、PDF OMR 协议与钢琴卷帘等研发代码。它不属于 K.478 候选二进制边界，也不应被 TestFlight 文案或截图暗示为候选能力。

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

根 host 的最低 iOS 版本为 13.6；候选 host 的最低 iOS 版本为 13.0。旧 host 的 TimGM 下载路径和其他 MIDI 不进入候选包。

## 发布前仍需外部证据

- iPhone + 直连 USB 电子琴：连接、活动会话拔出/重插、跟随、长休止和听音。
- 签名 Archive/IPA：资产、插件、Info.plist 与 Privacy Report 复核。
- 两个 K.478 SF2：官方输入比对、授权通知复核与真机离线听音。
- App 图标、截图和任何对外物料：逐项登记到资产台账；当前未登记即阻止 TestFlight。
- 试用说明、反馈入口和 Go/No-Go 由负责人确认；本仓库不预设最终数字门槛。

## License

MIT。第三方音乐、PDF、页面图和 SoundFont 的分发结论以 [资产台账](docs/evidence/asset_manifest.md) 为准，不因仓库许可证自动获得授权。
