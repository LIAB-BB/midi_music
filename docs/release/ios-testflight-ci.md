# 用 GitHub Actions 签名并上传 TestFlight

> 适用：`apps/testflight_ios`（bundle id `com.liab.k478Testflight`）。
> 不需要本地 Mac 硬盘装 Xcode：签名在 GitHub 托管的 macOS runner 上完成，
> 你的 Mac 只需要浏览器/钥匙串导出证书。第一次建议先用 `upload=false`
> 只验证 archive/export，再开启上传。

## 0. 前置条件

- 付费 Apple Developer Program 账号（免费账号不能上传 TestFlight）。
- App Store Connect 已创建 App 记录，bundle id 为 `com.liab.k478Testflight`。
- 一台能登录 Apple Developer / App Store Connect 的电脑（Windows 也可以；
  证书导出用 Keychain Access 或 OpenSSL，不需要 Xcode）。
- 本仓库有 Actions 权限；`main` 已开启分支保护。

## 1. 生成证书和描述文件

### 1.1 Apple Distribution 证书

1. 在 Apple Developer → Certificates → **+** → **Apple Distribution**。
2. 生成 CSR：
   - macOS：钥匙串访问 → 证书助理 → 从证书颁发机构请求证书，保存到磁盘；
   - Windows：`openssl req -new -newkey rsa:2048 -nodes -keyout dist.key -out dist.csr`。
3. 上传 CSR，下载 `.cer`，双击导入钥匙串（或在 macOS 上导入）。
4. 从钥匙串导出带私钥的 `.p12`，设置密码。
   - 这个 `.p12` 就是 `IOS_DIST_CERT_P12_BASE64` 的来源。

### 1.2 App Store 描述文件

1. Apple Developer → Profiles → **+** → **App Store**。
2. 选择 App ID `com.liab.k478Testflight`，选择上面的 Distribution 证书。
3. 下载 `.mobileprovision`，记住 Profile 的 **Name**（不是文件名）。
   - `.mobileprovision` 是 `IOS_PROVISIONING_PROFILE_BASE64` 的来源；
   - Name 是 `IOS_PROVISIONING_PROFILE_NAME`。

### 1.3 App Store Connect API Key

1. App Store Connect → Users and Access → Integrations → **App Store Connect API**。
2. Team Keys → **+**，角色至少 **App Manager**。
3. 记录 **Key ID** 和 **Issuer ID**；下载 `AuthKey_<KEY_ID>.p8`（只能下载一次）。
   - `.p8` 是 `APPSTORE_API_PRIVATE_KEY_BASE64` 的来源。

## 2. 配置 GitHub Secrets

仓库 → Settings → Secrets and variables → Actions → New repository secret：

| Secret | 内容 |
|---|---|
| `IOS_TEAM_ID` | Apple Developer Team ID（项目里是 `XV6N683H3X`，以账号为准） |
| `IOS_DIST_CERT_P12_BASE64` | Distribution `.p12` 的 base64 |
| `IOS_DIST_CERT_PASSWORD` | `.p12` 导出密码 |
| `IOS_PROVISIONING_PROFILE_BASE64` | `.mobileprovision` 的 base64 |
| `IOS_PROVISIONING_PROFILE_NAME` | 描述文件的 Name |
| `APPSTORE_API_KEY_ID` | API Key ID |
| `APPSTORE_API_ISSUER_ID` | Issuer ID |
| `APPSTORE_API_PRIVATE_KEY_BASE64` | `AuthKey_*.p8` 的 base64 |

base64 命令：

```bash
# macOS
base64 -i cert.p12 | pbcopy
base64 -i profile.mobileprovision | pbcopy
base64 -i AuthKey_ABC123.p8 | pbcopy
```

```powershell
# Windows PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\path\cert.p12')) | Set-Clipboard
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\path\profile.mobileprovision')) | Set-Clipboard
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\path\AuthKey_ABC123.p8')) | Set-Clipboard
```

> 不要把 `.p12`、`.p8` 或密码提交到仓库，也不要在聊天里发送。
> CI 在临时 keychain 中导入证书，任务结束会删除。

## 3. 运行

第一次只构建/导出，不上传：

```bash
gh workflow run ios-testflight.yml \
  --ref main \
  -f upload=false
```

确认 `k478-signed-ipa` artifact 存在且 IPA 大小合理后，再上传：

```bash
gh workflow run ios-testflight.yml \
  --ref main \
  -f upload=true \
  -f build_number=100
```

`build_number` 每个版本必须递增；不填则用 `GITHUB_RUN_NUMBER`。
`marketing_version` 不填则用 `pubspec.yaml` 的 `version`。

## 4. 常见问题

| 现象 | 处理 |
|---|---|
| `No signing certificate "iOS Distribution" found` | 证书不是 Apple Distribution，或 `.p12` 没带私钥；重新导出 |
| `Provisioning profile ... doesn't match bundle identifier` | 描述文件不是 `com.liab.k478Testflight` 的 App Store profile |
| `Provisioning profile ... doesn't include signing certificate` | 生成 profile 时没勾选这张 Distribution 证书 |
| `altool` 上传 401/403 | API Key 角色不足、Issuer ID/Key ID 错，或 `.p8` 不是对应 Key |
| TestFlight 不显示构建 | App Store Connect 处理中；检查 App 记录和 build number 是否重复 |

## 5. 关于 Mac 硬盘

- 签名/上传全部在 GitHub 托管的 macOS runner 上执行，**不占你的 Mac 硬盘**。
- 你的 Mac 不需要装 Xcode（约 40 GB+）；只需要钥匙串导出 `.p12` 和浏览器下载 profile。
- 如果连 Keychain Access 也不想用，可以在 Windows 用 OpenSSL 生成 CSR/导出 `.p12`。
- 真机听音和 USB MIDI 验收仍需要一台 iPhone + 电子琴；TestFlight 构建成功不等于验收通过。
