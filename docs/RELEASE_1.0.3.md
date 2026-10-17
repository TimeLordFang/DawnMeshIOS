# DawnMesh iOS 1.0.3

版本：1.0.3+4；配套 Android 1.1.4，Server/Web 0.3.3 无需升级。

- 普通 Wi-Fi 房新增苹果设备点对点链路：Bonjour 浏览、监听和连接均启用 peer-to-peer，保持服务端点的接口/IPv6 信息；继续使用原有 PAKE、加密语音和聊天协议。
- iOS 可创建蓝牙房；通过 GATT 提供动态 L2CAP PSM、人数和房名。iOS 可互相发现，也兼容旧安卓房主。安卓加入 iOS 房间需升级到 1.1.4。
- 蓝牙房主支持逐客户端有界收发、认证后转发、房主命令过滤和系统蓝牙恢复后重新发布通道。房主 1 台、客户端最多 5 台为协议限制，稳定容量待实测。
- 统一 iOS/安卓启动图标，iOS 提供对应深色外观。
- 新增 `./scripts/prepare-ios.sh`：安装锁定依赖、生成当前 Run 模式配置并打开 Xcode workspace，保留本机签名设置。
- tag CI 生成 GitHub Release，附未签名 App ZIP 与 SHA-256。ZIP 无法直接安装到 iPhone；普通 Apple 账号本地测试请运行准备脚本后在 Xcode 选择 Team 和设备构建安装。

## 兼容边界与验收

苹果点对点链路用于 iOS 间普通 Wi-Fi 房，不与安卓 Wi-Fi Direct 直接互联；融合房仍使用同网/热点与现有公网中继。公共服务器、网页版和线上加密协议保持兼容。

全量 Dart、JVM、原生与完整 iOS/Android 构建验证通过，详见 [验证记录](VALIDATION_2026-10-17.md)。尚未实测两台 iPhone 在无共同 AP 下的无线发现/语音，也未实测 iOS 房主的混合蓝牙多人容量与锁屏恢复。新建和首次加入蓝牙房请保持房主前台。
