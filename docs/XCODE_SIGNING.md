# Xcode 真机签名与可选 Wi-Fi Aware

当前应用版本为 `1.2.3+64`。Personal Team 报错 “do not support the Wi-Fi Aware capability” 是签名权限限制，不是 Swift 语法错误；未签名编译成功也不证明描述文件可用。

## Personal Team：直接使用默认配置

1. 打开 `ios/Runner.xcworkspace`，选择 Runner → Signing & Capabilities，保持 Automatically manage signing，选择自己的 Personal Team。
2. 默认 Debug、Profile、Release 都读取 `Signing.xcconfig`，只使用 `Runner/Runner.entitlements`。它保留原有 Keychain 配置，不申请 Wi-Fi Aware。
3. 选择已配对、已开启开发者模式的 iPhone，再 Build/Run。必要时在 Xcode 中清理构建目录并重试自动签名。不要删除账号、证书或安全存储。
4. 普通 Wi-Fi/热点、苹果点对点 Wi-Fi、蓝牙和公网路径继续使用原有实现。应用会明确显示当前安装包未启用可选 Aware 加速。

当前源码已通过 Personal Team 在已连接 iPhone 17 Pro 目标上的实际签名编译及签名验证；没有自动安装或启动应用，也没有进行无线互通验收。既有个人 Team 和 Scheme 设置不提交到仓库。

## 显式启用 Wi-Fi Aware

需要支持此能力的开发者团队、获准的 Publish/Subscribe 权限及匹配的描述文件；购买会员本身不代替具体能力授权。

在本机创建被 Git 忽略的 `ios/Flutter/Signing.local.xcconfig`：

```xcconfig
#include "Signing.wifi-aware.xcconfig"
```

然后在 Xcode 选择有该权限的团队并重新签名。此配置会同时选择 `Runner/RunnerAware.entitlements` 与应用内启用标记，防止无权限构建仍尝试调用 Aware。删除该本机配置即可恢复 Personal Team 默认模式。

仅检查可选变体能否编译（不申请或绕过 Apple 签名权限）：

```sh
./scripts/build-ios.sh --wifi-aware
```

输出 `build/ios/iphoneos-aware/Runner.app`，未签名，不能直接装机。普通 `./scripts/build-ios.sh` 输出 `build/ios/iphoneos/Runner.app`。CI 编译两种变体；之后的候选/正式 Release 分别提供普通与 `wifi-aware` 未签名压缩包，选择与签名团队能力匹配的一种。

Apple 参考：[Wi-Fi Aware entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.wifi-aware)、[构建配置文件](https://developer.apple.com/documentation/xcode/adding-a-build-configuration-file-to-your-project)。
