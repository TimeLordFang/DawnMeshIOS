# 开发与构建

以下为 2026-10-28 的锁定构建基线，具体依赖以 `pubspec.lock`、平台锁文件和构建脚本为准。

| 工具或依赖 | 发布基线 |
| --- | --- |
| Flutter / Dart | 3.47.8 / 3.13.7 |
| JDK / Gradle / AGP / Kotlin | 27.0.1 / 9.8.2 / 9.4.1 / 2.4.21 |
| Android SDK / Build Tools / NDK | compile 37.2、target 37 / 37.0.0 / 30.0.16248370 |
| Android SDK CMake / 主机 CMake | 4.1.2 / 4.4.4 |
| Xcode / CocoaPods / 最低 iOS | 27.1 / 1.17.0 / 15.0 |
| Flutter WebRTC / 原生 WebRTC SDK | 1.6.3 / 150.7871.04 |
| LiveKit Flutter / Opus / RNNoise | 2.13.2 / 1.6.1 / 0.2 |

Android 最低 API 26，BLE L2CAP 语音需要 API 29+；JDK 27 运行 Gradle，应用字节码仍为 Java 17。iOS 使用 CocoaPods，保留 `ios/Podfile.lock`，不强制覆盖 Flutter 或插件对传递依赖的约束。

## 本地检查

```sh
./scripts/check.sh
```

脚本解析锁定依赖并运行静态、Flutter 和原生检查。真实 Go 中继用例需启动测试服务并设置 `DAWNMESH_FUSION_TEST_URL`；未配置时会跳过该项。两端网络回归应串行运行，以免固定端口冲突。

## iOS 构建与安装

```sh
./scripts/prepare-ios.sh
./scripts/build-ios.sh
./scripts/build-ios.sh --wifi-aware
```

准备脚本安装锁定依赖并打开 `ios/Runner.xcworkspace`，保留本机 Team 与 Run scheme。默认构建为普通未签名 App；可选变体在 `build/ios/iphoneos-aware/Runner.app`。真机安装、Personal Team 与 Aware 授权见 [Xcode 签名](XCODE_SIGNING.md)。Flutter 不在 PATH 时可指定 `FLUTTER_ROOT`。

Swift、C++、双向 Opus 样本、Pod 补丁与回环 TCP 由 `scripts/check-native.sh` 检查。插件补丁只写入 Pods，升级后上游文件变化必须复核，见 [补丁维护](../ios/patches/README.md)。

## 维护约定

- 版本、更新声明、两种语言的更新日志与发布说明一起更新；候选和正式标签的同提交规则见 [发布流程](RELEASING.md)。
- 共享 Dart 代码仍在两仓维护；同步时保留各自的平台入口、能力判定和仓库地址，不覆盖本机签名设置。
- 修改协议、认证或音频格式时运行对应互操作和失败路径回归；源码检查、回环与构建不替代 [真机验收](MANUAL_ACCEPTANCE.md)。
- 不通过全局关闭告警或强制 dependency override 掩盖兼容问题；SDK、插件、原生 WebRTC 与锁文件一起复核。
- 只保留当前需要的本地产物及配套校验文件；一次性诊断脚本和日志不作为当前验证文档。

图标源图、生成工具和配色规范见 [品牌资源](../assets/branding/README.md)。安全与许可分别见 [安全模型](SECURITY_REVIEW.md) 和 [来源](UPSTREAM.md)。
