# DawnMesh iOS 1.0.0（build 1）

首个独立 iOS 版本。功能基线为 Android 1.1.x，共享会话、密码学和协议，配套 Server/Web 0.3.1。

- 公网房、文字/照片、加密媒体、权限管理、重连；支持局域网房和 16 人融合房。
- CoreBluetooth 加入安卓蓝牙房；LAN 使用 Bonjour、同网地址及单播发现。
- iOS 原生 Opus 1.6.1 与 RNNoise 0.2；同步最新稳定 Flutter/LiveKit/WebRTC 依赖及构建工具。
- iOS 蓝牙建房和 Android Wi-Fi Direct 群组创建保留为后续规划，当前可使用已有 LAN/热点。

已通过 Flutter、Swift、原生回归、完整 Xcode 构建、Android ↔ iOS 双向 Opus 和真实 Go 融合中继测试。
完整真机三端音频与后台行为验收见 [互通验收](INTEROPERABILITY.md)。

Actions 提供未签名 Runner.app；安装到 iPhone 需要在 Xcode 配置自己的 Apple Team 和签名。TestFlight/App Store 分发需对应账号与证书。
