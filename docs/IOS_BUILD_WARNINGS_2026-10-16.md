# iOS 构建告警整理 · 2026-10-16

已在本机 Xcode 27.0 / iPhoneOS 27.0 SDK 完成独立目录的完整 Release 构建，
最低系统版本保持 iOS 15.0，结果为 `BUILD SUCCEEDED`。未进行新的真机安装或声学测试。

## 已修复

- 项目和插件使用蓝牙 HFP 枚举的新名称；选项位值仍为 `0x4`，Dart 配置键保持兼容。
- RNNoise 使用标准 C `(void)` 原型；模型加载在缩窄文件长度前检查错误、空文件和
  `INT_MAX` 上限，同时处理分配失败及文件所有权。
- Opus 修正文档参数名、显式初始化循环相关局部变量，并注明已知有界的整数转换。
- WebRTC 的 Core Audio 字段转换前检查尺寸与乘法溢出；录音回调避免循环持有。
- device_info_plus 用 64 位字节数计算可用内存，避免超过 4 GiB 时截断。
- 移除两项没有独立符号的多余编译：被直接 include 的 audio_sink_bridge.cpp，
  以及未开启 SILK_DEBUG/SILK_TIC_TOC 时的 silk/debug.c。
- Profile 使用专用的 Pods profile xcconfig，消除 `pod install` 的 base configuration 提示。

插件补丁生成在 Pods 内，绑定原文件 SHA-256，不修改全局 pub 缓存。
后续升级时如上游源码变化，会要求复查补丁，详见 [补丁维护说明](../ios/patches/README.md)。
没有全局关闭告警。现有 Apple Team、Bundle ID、签名方式、scheme、workspace 和
用户升级后的 pubspec.lock 均保留。

## 完整构建剩余的 2 条提示

1. `FlutterDataPacketCryptor.o has no symbols`：此源文件包含 Objective-C category，
   仍有必要的实现。libtool 提示缺少可索引的全局符号，保留编译项。
2. `Metadata extraction skipped, no AppIntents.framework dependency found`：
   Xcode 的可选 AppIntents 提取步骤跳过。当前未使用该功能，保留提示。

## 验证

- 3 个 CTest 目标通过：voice_denoiser、ios_codec、rnnoise_model。
- Android Concentus 16 kHz / 20 ms Opus 样本在 iOS codec 解码通过，PLC 与畸形长度测试通过。
- Swift 协议的 30 项检查和 discovery cache 检查通过。
- 模型边界回归覆盖空文件、空 FILE、无法打开的文件、超过 INT_MAX 的稀疏文件、
  不可 seek 的管道、成功读取和调用方 FILE 所有权。
- 补丁回归覆盖重复应用、保持原文件不变、拒绝变更的上游源码。
- 连续两次 `pod install` 成功且无配置提示；6 项上游源文件 SHA-256 未改变。
- Profile build settings 指向 `Profile-iphoneos` 的 Pods 配置，部署版本为 15.0。
- plist、pbxproj、Ruby 语法与 `git diff --check` 通过。

本次完整构建日志：`/private/tmp/dawnmesh-ios-warning-build.log`。
原生回归日志：`/private/tmp/dawnmesh-ios-native-check.log`。临时日志可能被系统清理。

重新测试可直接在 Xcode 打开 `ios/Runner.xcworkspace` 构建。若仍显示历史告警，
执行 Product → Clean Build Folder 后再次 Run。
