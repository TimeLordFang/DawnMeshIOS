# 来源与许可

- 最初参考项目：[Starlordzz/sunsetripple](https://github.com/Starlordzz/sunsetripple)，提交 `f63d418f7637972e5728e54cfcc7c8afbf25d26d`。复制 iOS Xcode 工程、资源与 VoiceProcessingIO 宿主；重写原 PCM 占位路径、BLE 字节流路径，迁移新版 Flutter engine/scene 注册。
- 功能/协议基线：[TimeLordFang/DawnMesh](https://github.com/TimeLordFang/DawnMesh)，版本 `1.1.0+51`；具体提交见 BASELINE.txt。独立快照复制 lib/test/native 公共源码；不包含 Android 宿主、发布签名、本地工具链或打包产物。
- 服务器与网页基线：同级 DawnMeshServer，提交见 BASELINE.txt；未修改服务器或网页协议。
- libopus 1.5.2：Xiph 官方源，SHA-256 核对官方[发布记录](https://opus-codec.org/release/stable/2024/04/12/libopus-1_5_2.html)。BSD 许可见 native/vendor/opus/COPYING。
- RNNoise：沿用 Android vendored v0.1；BSD 许可见 native/vendor/rnnoise/COPYING。iOS 增加 CELT/FFT 符号前缀，避免与 libopus 静态链接重名。

根目录 LICENSE 保留 Apache-2.0 原文。分发包需保留第三方许可。后续同步 Android 修改时，以互通合同为准，补充协议、密码学与失败路径回归。
