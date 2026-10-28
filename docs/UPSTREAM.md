# 来源与许可

- 最初参考项目：[Starlordzz/sunsetripple](https://github.com/Starlordzz/sunsetripple)，提交 `f63d418f7637972e5728e54cfcc7c8afbf25d26d`。复制 iOS Xcode 工程、资源与 VoiceProcessingIO 宿主；重写原 PCM 占位路径、BLE 字节流路径，迁移新版 Flutter engine/scene 注册。
- 功能/协议基线：[TimeLordFang/DawnMesh](https://github.com/TimeLordFang/DawnMesh)，最初版本 `1.1.0+51`、提交 `02a072314d2b604d8efff5f69e72c26c281e81f8`；后续独立同步。独立快照复制 lib/test/native 公共源码；不包含 Android 宿主、发布签名、本地工具链或打包产物。
- 服务器与网页基线：同级 DawnMeshServer，最初参考提交 `20bd949d2c1333bd38b28110ad47b19bde8438ea`；当前协议以兼容测试和该仓库说明为准。
- libopus 1.6.1：Xiph [官方发行源码](https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz)。BSD 许可见 native/vendor/opus/COPYING。
- RNNoise：与 Android 一致，vendored v0.2，包含上游 ARM 编译修复；BSD 许可见 native/vendor/rnnoise/COPYING。iOS 增加 CELT/FFT 符号前缀，避免与 libopus 静态链接重名。

根目录 LICENSE 保留 Apache-2.0 原文。分发包需保留第三方许可。后续同步 Android 修改时，以互通合同为准，补充协议、密码学与失败路径回归。

最初复制的 Android 来源说明、融合说明和安全快照保留于 `v1.2.3` 标签；当前能力见 [兼容说明](COMPATIBILITY.md)，当前安全边界见 [安全模型](SECURITY_REVIEW.md)。不把最初参考版本当作当前实现版本。
