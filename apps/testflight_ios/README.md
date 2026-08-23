# K.478 TestFlight iOS Host

这是面向 TestFlight 的独立 iOS Flutter host，不是仓库根目录的开发 host。
它只依赖 `../../packages/k478_practice`，因此不会链接根工程保留的文件导入、
OMR、麦克风输入、`permission_handler` 或旧的泛曲库入口。

## 当前发布范围

- 一首内置曲目：莫扎特《钢琴四重奏 K.478》；
- CoreMIDI 输入（首轮只以直连 class-compliant USB 电子琴验收）；
- 电子琴自行发钢琴声，App 只播放小提琴 / 中提琴声部 / 大提琴伴奏；中提琴声部当前暂用小提琴音色；
- 本地打包的 SF2，不在启动时下载音色；
- 21 页钢琴声部 PDF 预渲染页。

当前 Bundle ID 是构建占位符 `com.liab.k478Testflight`；在创建 App Store
Connect 记录和签名配置前，必须确认它是否为最终 App ID。当前版本号为
`0.1.0 (1)`，不可直接视为可上传的 Archive。

## 本地验证

```bash
cd apps/testflight_ios
flutter pub get
flutter analyze
flutter test
flutter build ios --release --no-codesign
../../tool/verify_testflight_ios_bundle.sh build/ios/iphoneos/Runner.app
```

构建产物必须复核 `ios/Podfile.lock` 只包含 `core_midi_input` 与
`flutter_midi_pro`（以及 Flutter 自身），并确认 Release `Info.plist` 没有
麦克风或本地网络用途说明。

真机验收、签名 Archive、App Store Connect 上传和 TestFlight 分发均为后续
显式步骤，不由本 host 自动执行。
