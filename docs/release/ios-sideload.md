# 未签名 IPA + Windows 侧载（临时真机试用）

> 这不是 TestFlight，也不是正式签名发布。产物是 CI 用
> `flutter build ios --release --no-codesign` 构建的未签名 IPA，需要在你自己的
> Windows 电脑上用 Sideloadly / AltStore 以 Apple ID 重新签名后安装。
>
> 适合：临时把候选装到 iPhone 上试 USB MIDI/跟随；不适合分发给别人。

## 1. 让 CI 产出未签名 IPA

在 GitHub Actions 手动运行 `iOS Unsigned IPA`：

```bash
gh workflow run ios-unsigned-ipa.yml --ref main
```

或网页：Actions → **iOS Unsigned IPA** → Run workflow。

构建完成后下载 artifact **k478-unsigned-ipa**，里面是：

- `K478-unsigned-<run>.ipa`
- `sha256.txt`

这个 IPA 没有签名，不能直接安装，也不能上传 TestFlight。

## 2. Windows 侧载

1. 安装 [Sideloadly](https://sideloadly.io/)（或 AltStore）。
2. iPhone 用 USB 连接 Windows，信任电脑。
3. 把 IPA 拖进 Sideloadly，输入你的 Apple ID。
4. Start；Sideloadly 会用你的开发证书重签并安装。
5. iPhone → 设置 → 通用 → VPN 与设备管理 → 信任你的开发者证书。
6. 打开 App，连接 USB 电子琴做真机试用。

## 3. 限制与注意

- **免费 Apple ID**：签名 7 天过期，最多 3 个 App；到期需重新侧载。
- **付费开发者账号**：签名通常 1 年；仍需在设备上信任证书。
- Bundle ID 冲突时 Sideloadly 可能要求改 bundle id；CoreMIDI 本身不需要特殊
  entitlement，但改 id 后要重新签名。
- 侧载不是 TestFlight：没有 App Store Connect 处理、没有外部测试分发、
  没有正式的隐私报告和审核。
- 真机验收必须由你完成：USB 连接、热插拔、长休止、连续错音/跳页、
  锁屏/来电后的恢复。CI 只能证明能编译和打包。
- 不要把这个 IPA 上传到公共渠道；里面可能包含未完成授权的资产。
- 使用独立 Apple ID 或应用专用密码，不要把账号密码发给任何人。

## 4. 与正式签名 workflow 的关系

- 本流程不需要任何 Apple 证书/Secret，随时可跑。
- 正式 TestFlight 用 `.github/workflows/ios-testflight.yml`，见
  [`ios-testflight-ci.md`](ios-testflight-ci.md)。
- 两者共用同一份 `apps/testflight_ios` 源码和 host lockfile。
