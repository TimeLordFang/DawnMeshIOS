# iOS 插件兼容补丁

针对 Xcode 27 的实际构建诊断，保留最新稳定版插件，在 `pod install` 的
`post_install` 中应用以下源码修复。源码副本生成在 `ios/Pods/DawnMeshPatchedSources`；
不修改全局 pub 缓存，不关闭编译器告警，也不更改 Dart 插件 API 或网络协议。

| 包 | 固定来源版本 | 修复 |
| --- | --- | --- |
| livekit_client | 2.13.1 | 蓝牙 HFP 枚举采用新名称，保留 Dart 的 `allowBluetooth` 配置键 |
| flutter_webrtc | 1.6.2+hotfix.4 | 同一 HFP 枚举更名；Core Audio UInt32 字段在转换前检查乘法和尺寸边界；录音回调用 weak/strong 引用避免循环持有 |
| device_info_plus | 13.3.0 | 空闲内存以 64 位字节数计算，避免超过 4 GiB 时截断 |

`audio_sink_bridge.cpp` 由 `FlutterRTCAudioSink.mm` 直接包含，去掉它独立的重复编译项。
保留 `FlutterDataPacketCryptor.m`：它包含必要的 Objective-C category，即使 libtool
提示没有可索引的全局符号，也不能删除。AppIntents 未启用时 Xcode 的 metadata
扫描提示同样保留；不为消除提示引入无用 framework。

补丁采用无上下文 unified diff；应用前先校验整份原文件 SHA-256，避免补丁上下文的空白行被误报为源码尾随空格。
每个补丁绑定原文件 SHA-256。升级依赖后，如源文件不同，`pod install` 会明确失败，
要求复查补丁；不会静默把旧补丁套进新代码。

升级步骤：

1. 查看上游新版是否已包含修复；已包含的条目和补丁应删除。
2. 如仍需要补丁，依据新版源码重新生成统一 diff，更新 manifest 中版本和 SHA-256。
3. 执行 `ruby test/ios_pod_patches_test.rb`、`pod install`，再完整构建 iOS。

补丁保留上游原许可证；完整第三方声明见对应 pub 包中的 LICENSE 和源码版权声明。
