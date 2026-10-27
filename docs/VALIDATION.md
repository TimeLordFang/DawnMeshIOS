# 验证记录 · 2026-10-13

## 1.2.1 / 构建 62（2026-10-27）

- Android 352 项、iOS 371 项 Flutter 全量回归通过；两端均使用真实本机 Go 中继，无跳过。两端静态检查无问题。
- 新增 6 项回归覆盖并发握手、超过 4 秒的忙碌对端、退出取消、超时释放，以及加解密队列对网络事件的公平调度和顺序。旧实现在这 6 项均失败，修复后通过。
- 云端隔离分支连续 5 轮融合房测试通过，并完成原生检查与 iOS 编译：[验证运行](https://github.com/TimeLordFang/DawnMeshIOS/actions/runs/40473113690)。修复未通过放宽断言或自动重跑掩盖错误。
- 两端最终 Release 编译通过，包内版本为 1.2.1 / 62。Android APK v2 签名、ZIP 16 KiB 对齐、APK/AAB 全部 64 位 ELF 对齐、官方 bundletool AAB 验证、115 个 JAR 签名载荷及三个归档 CRC 检查通过。
- 本补丁仅改 Dart 连接/调度与版本资料；Android JVM、Lint 和原生音频验证沿用下方 1.2.0 对应的未变原生源码结果。iOS 云端再次运行了原生检查。
- iOS 仍为未签名 App；五台手机的射频、跨平台配对和锁屏验收由用户按 [清单](MANUAL_ACCEPTANCE.md) 执行，没有真机通过声明。构建包哈希以对应本地文件或 Release 随包校验文件为准。

## 1.2.0 / 构建 61（2026-10-27）

- Android：346 项 Flutter 回归全部通过；iOS：365 项全部通过。两端均配置本机真实 Go 中继，覆盖认证停滞备用入口、双网关去重、退出换钥和剩余上行，没有跳过该项。
- 最后针对文字备用设备过滤实时音频/留言占位，补充步骤在 Android 12 项、iOS 6 项专项测试中通过。
- 两端 Flutter 静态检查无问题。Android 应用 JVM 49 项通过，应用 Lint 通过（3 项工具版本/兼容图标资源告警，无错误）。
- 共享原生音频 C++ ASan/UBSan 2 项通过；iOS 原生 3 项、Opus/RNNoise 互操作、Pod 补丁幂等、Swift 190 项协议检查、512 KiB 双向 TCP 代理及断链检查通过。
- Android 签名 APK 与 AAB 均生成，包内版本 1.2.0 / 61。APK v2 签名、ZIP 16 KiB 对齐、ZIP CRC 与全部 64 位 ELF PT_LOAD 至少 16 KiB 对齐通过；AAB 结构经校验过官方 SHA-256 的 bundletool 1.18.3 验证，通过 CRC、ELF 对齐与 JarFile 115 个载荷逐项签名校验。
- AAB jarsigner 通过并提示自签名证书、无时间戳及 JarInputStream 读取方式告警；不能描述为无警告验证。JDK 27 对部分验证工具另有弃用 API 提示。
- iOS Release 设备目标编译通过，Info.plist 确认 1.2.0 / 61；新系统框架为弱链接，旧系统使用能力分支。产物未做发行签名，不能直接安装。
- 新增手动验收开关、五机步骤和明确的不支持回退。没有连接真实手机，射频、配对互通、功耗和锁屏稳定性仍由 [手动验收](MANUAL_ACCEPTANCE.md) 记录，不能从编译/回环推断通过。

此段为本地构建与测试记录。GitHub Actions 会从发布标签重新构建，下载时使用同一 Release 随包提供的校验文件；不同构建不承诺二进制哈希相同。


## 通过

- Flutter/Dart 分析：**No issues found**。
- Flutter 共享回归：**298 项通过，1 项沿用基线跳过**。包含浏览器聊天加密样本、PAKE、防重放/冒名、房主管理与禁麦、房间容量、融合成员/中继/恢复和 UI；新增 iOS 入口/蓝牙建房禁用/地址校验测试通过；本地 HTTP/TCP 测试，不连接真实生产房间。
- 跳过项为基线中的融合真实服务器集成测试，未配置 `DAWNMESH_FUSION_TEST_URL`；不计为已通过。
- Swift 核心：**30 个断言通过**，包括分段/合并字节流、最大帧、畸形帧、Android 厂商广播、短写续传、实时包过期、序列回绕、PLC、PTT 恢复。
- 原生 C/C++：实际编译 vendored Opus 137 个 C 源与 RNNoise；**2 个 CTest 目标通过**：voice_denoiser、ios_codec。
- Android/iOS 实际编解码互通：Concentus 1.0.2 生成 103 字节 16kHz/20ms Opus；iOS codec 解码成功；iOS codec 生成包，Concentus 解码为 320 个非静音样本。无手机射频/声学参与。
- iOS 工程 plist、entitlements、pbxproj 校验通过，Podfile/两个本地 podspec Ruby 语法检查通过。
- 所有 Swift 原生源语法解析通过；BLE、Bonjour 与 WireSupport 在 macOS SDK 下通过类型检查（使用最小 Flutter API 测试桩）。该本机检查为补充；完整 iOS 编译结果见下一项。

- **远程完整 iOS 编译通过**：[GitHub Actions](https://github.com/TimeLordFang/DawnMeshIOS/actions/runs/38353118485)，源码提交 `bb9829a`。锁定 Dart 依赖解析、Flutter 分析/回归、C/C++ 与 Swift 回归、CocoaPods 工程生成、AudioUnit/UIKit Swift 桥、WebRTC ObjC++ 降噪桥及 release iOS 链接均成功。
- 构建产物 `DawnMeshIOS-unsigned-app` 已上传，未过期，压缩包 15,635,359 字节；内容为未签名 `Runner.app`。不是已签名 IPA，也不能直接安装真机。
- 首次 CocoaPods 工程生成失败后，调整 vendored 私有头文件封装，并区分 RNNoise/Opus 的重名 C 源文件，复测通过。

## 当前未验证

- `ios/Podfile.lock` 尚未提交；正式发布前需保存经 CI/Xcode 解析的完整 iOS 依赖锁定文件。
- 真机 IPA 签名/安装、iOS↔Android↔网页的真实公网语音/E2EE、近场双向收发、六人 BLE 和十六人 LAN/融合容量。
- 锁屏/后台/系统挂起、耳机射频共存、音频中断、麦克风声学与 Apple 能力审批。

本机只有 Apple Command Line Tools；完整 iOS 编译由 GitHub macOS/Xcode Runner 完成。当前可以确认源码与原生桥编译通过，不能描述为“已签名或真机正常互通”。验收步骤见 [INTEROPERABILITY.md](INTEROPERABILITY.md)。

## 复现

```sh
./scripts/check.sh
./scripts/build-ios.sh
```

原生测试与编解码样本不包含邀请码、身份材料、真实音频或日志。仓库不提交本地 Flutter 工具链、Pods、签名证书和设备产物。
