# DawnMesh iOS 1.0.2（build 3）

修复并规范 iOS 音频依赖与构建告警，保持 Android/Web 互通协议。

- 项目与插件的蓝牙 HFP 选项使用新名称，保留原位值和 Dart 配置键。
- RNNoise 标准 C 原型、模型文件边界及所有权检查与 Android 同步；Opus 修正文档、显式初始化和有界整数转换。
- WebRTC 的音频尺寸在缩窄前检查；录音回调用 weak/strong 引用避免循环持有；设备内存以 64 位字节数计算。
- 插件补丁在 pod install 时绑定 SHA-256 并生成在 Pods 内，不修改全局 pub 缓存；升级后源文件变化会明确要求复查。
- 规范 Profile xcconfig，提交真实 Podfile.lock；同步可升级 Dart 依赖，保证两移动端锁文件一致。
- 发布工程不包含本机 Apple Team 或设备签名材料。

验证：完整 iOS Release 构建通过，包版本 1.0.2 / 3；298 项 Dart 回归（包含真实 Go 中继）、分析、3 个原生 CTest、Android Opus 样本、30 项 Swift 协议检查、BLE 缓存及补丁回归通过。
完整构建保留两条工具提示：FlutterDataPacketCryptor 的归档符号提示，以及当前未使用 AppIntents 的 metadata 扫描提示。没有全局关闭编译告警。

配套 Android 1.1.3、Server/Web 0.3.3。本版验证构建未签名，安装仍需在 Xcode 选择自己的 Team；本次未重新进行真机音频/蓝牙验收。
详细记录见 [iOS 告警说明](IOS_BUILD_WARNINGS_2026-10-16.md) 与 [插件补丁维护](../ios/patches/README.md)。
