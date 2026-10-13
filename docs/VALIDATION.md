# 验证记录 · 2026-10-13

## 通过

- Flutter/Dart 分析：**No issues found**。
- Flutter 共享回归：**298 项通过，1 项沿用基线跳过**。包含浏览器聊天加密样本、PAKE、防重放/冒名、房主管理与禁麦、房间容量、融合成员/中继/恢复和 UI；新增 iOS 入口/蓝牙建房禁用/地址校验测试通过；本地 HTTP/TCP 测试，不连接真实生产房间。
- 跳过项为基线中的融合真实服务器集成测试，未配置 `DAWNMESH_FUSION_TEST_URL`；不计为已通过。
- Swift 核心：**30 个断言通过**，包括分段/合并字节流、最大帧、畸形帧、Android 厂商广播、短写续传、实时包过期、序列回绕、PLC、PTT 恢复。
- 原生 C/C++：实际编译 vendored Opus 137 个 C 源与 RNNoise；**2 个 CTest 目标通过**：voice_denoiser、ios_codec。
- Android/iOS 实际编解码互通：Concentus 1.0.2 生成 103 字节 16kHz/20ms Opus；iOS codec 解码成功；iOS codec 生成包，Concentus 解码为 320 个非静音样本。无手机射频/声学参与。
- iOS 工程 plist、entitlements、pbxproj 校验通过，Podfile/两个本地 podspec Ruby 语法检查通过。
- 所有 Swift 原生源语法解析通过；BLE、Bonjour 与 WireSupport 在 macOS SDK 下通过类型检查（使用最小 Flutter API 测试桩）。这不是完整 iOS SDK 编译。

## 当前未验证

- 完整 iOS 应用编译、CocoaPods 实际解析/链接、`Podfile.lock`、Swift AudioUnit/UIKit 桥和 WebRTC ObjC 后处理桥的 iOS SDK 类型检查。
- 真机 IPA 签名/安装、iOS↔Android↔网页的真实公网语音/E2EE、近场双向收发、六人 BLE 和十六人 LAN/融合容量。
- 锁屏/后台/系统挂起、耳机射频共存、音频中断、麦克风声学与 Apple 能力审批。
- 远程 GitHub CI；已提供 workflow，运行结果另记。

本机只有 Apple Command Line Tools，没有 `/Applications/Xcode.app`、iOS SDK 或 CocoaPods。不能把当前回归结果描述为“iOS 已编译、已签名或真机正常互通”。验收步骤见 [INTEROPERABILITY.md](INTEROPERABILITY.md)。

## 复现

```sh
./scripts/check.sh
./scripts/build-ios.sh
```

原生测试与编解码样本不包含邀请码、身份材料、真实音频或日志。仓库不提交本地 Flutter 工具链、Pods、签名证书和设备产物。
