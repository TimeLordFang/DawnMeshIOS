# 曙光之声 · DawnMesh iOS

当前 iOS 版本：**1.0.5**。详见 [发布说明](docs/RELEASE_1.0.5.md)。

1.0.5 修复没有 UDP 广播路由时的异步错误，保持房间和发现监听；包含下述侧滑、建房与蓝牙房名改进。配套 Android 1.1.6。

1.0.4 补齐侧滑返回的跟手和取消回弹动画，修复确认邀请码后无法建房，并完善安卓蓝牙房名发现与房内标题；完整名称补读配套 Android 1.1.5。

独立的 iOS 客户端源码仓库，功能基线为 DawnMesh Android **1.1.0**。iOS 宿主源自最初参考的 [SunsetRipple](https://github.com/Starlordzz/sunsetripple) 提交 `f63d418f7637972e5728e54cfcc7c8afbf25d26d`，共享 Dart 会话、UI、密码学与协议来自安卓版，保留 Apache-2.0 许可。

**新增无线能力待真机验收。** 1.0.3 实现 iOS 间苹果点对点 Wi-Fi，以及 iOS 蓝牙建房与跨平台 GATT 房间发现。已有原生编解码、协议与构建验证；无共同 Wi-Fi 时的无线直连、混合设备蓝牙语音及锁屏稳定性仍须按验收清单在真实设备上确认。

## 功能与互通

- **公网房**：与安卓版和服务器内网页客户端使用同一 DawnMesh HTTPS/WSS API、LiveKit/WebRTC、邀请码凭据、密钥封装与语音/聊天 E2EE；保持多人聊天、照片、房主禁麦、移交房主、房间改名、断线恢复与三档音质。
- **Wi-Fi 房**：16 人，同网/热点下兼容安卓 TCP 帧、PAKE 和 AES-256-GCM；两台 iOS 可通过苹果点对点 Wi-Fi 发现和连接，无需共同路由器或互联网。原生 16kHz/单声道/20ms Opus。支持按住对讲、自动发言、混音、标准/强力降噪与语音缓冲调参。
- **融合房**：16 人，共享 Android 1.1.0 的签名成员、离线入房、去重、附近成员与公网中继逻辑；服务器使用 **0.3.0** 协议。iOS 使用已有 LAN/热点，不自动建立 Android Wi-Fi Direct 群组。
- **蓝牙房**：iOS 可建房和加入，保留 6 人协议上限、PAKE、聊天与断线恢复；兼容旧安卓厂商广播，并通过 GATT 发布/读取 iOS 房主的动态 L2CAP 通道信息。安卓加入 iOS 房主需升级到 **1.1.4**。实际多人容量与后台行为待真机验收。
- **平台适配**：VoiceProcessingIO 回声处理、真正的 libopus 编解码、RNNoise 与 WebRTC 采集后处理、耳机/内置麦克风路由、音频中断恢复、昵称和设置保存、Keychain 设备身份、照片权限、中英文与诊断日志。

完整[功能矩阵](docs/FEATURE_PARITY.md)区分源码实现、系统限制和待验收项目。

## 与安卓同网互通

无需更改或升级 Android 1.1.0：

1. 两台设备先连接同一 Wi-Fi 或热点，允许 iOS 的本地网络权限。
2. **安卓建房 → iOS 加入**：iOS 首页选择 Wi-Fi，点“输入地址加入安卓 Wi-Fi 房”，输入安卓手机的 IPv4 地址，再输入四位邀请码。融合房也有同网地址入口，会先读取该成员的 `/fusion` 元数据。
3. **iOS 建房 → 安卓加入**：iOS 在房间设置中点“通知同网安卓设备”，输入安卓手机的 IPv4 地址。iOS 向该设备 UDP 8990（普通房）或 8992（融合房）发送现有发现报文，房间出现在安卓“附近”列表中。随后正常输入四位邀请码加入。地址只在进程内保存，最多 16 个目标。
4. **iOS ↔ iOS Wi-Fi 房**：双方在系统设置中开启 Wi-Fi 和蓝牙，并允许本地网络访问；可不连接共同路由器，在首页 Wi-Fi 模式建房、扫描并输入邀请码加入。普通 Wi-Fi 房的 Bonjour 浏览、监听和连接都启用苹果点对点链路；融合房目前仍使用同网 Bonjour/手动地址。
5. **蓝牙房**：iOS 或安卓均可建房。连接 iOS 房主时，其他 iOS 需为 1.0.3+，安卓需为 1.1.4+；先保持双方前台并开启/授权蓝牙。动态 PSM 经 GATT 读取，iOS 房主在蓝牙恢复后重新发布通道；旧安卓房间继续通过厂商广播发现。

Apple 对 UDP 广播/组播要求额外 entitlement，本仓库默认没有冒充已获审批的能力。单播发现与手动入房可在普通签名下使用。获得 Apple 许可后，可按 [iOS 限制说明](docs/IOS_LIMITATIONS.md)启用完整广播发现。

网页客户端当前只支持公网 LiveKit 房；浏览器不直接参加 LAN/L2CAP 或融合 Opus 房。本仓库不改变网页版已有的房型范围。

## 构建

要求 macOS、完整 Xcode 与 iOS SDK、Flutter **3.47.7** / Dart **3.13.5**、CocoaPods。最低 iOS **15.0**。原生 Opus 1.6.1 已包含源码与许可，不依赖过期的第三方 Opus 二进制。

```sh
flutter config --no-enable-swift-package-manager
flutter pub get --enforce-lockfile
./scripts/check.sh
./scripts/build-ios.sh
```

本工程显式使用 CocoaPods，以链接 `DawnMeshNative` 与锁定 `flutter_webrtc 1.6.2` 的 `DawnMeshDSP` 采集处理接口。`build-ios.sh` 生成未签名的 `build/ios/iphoneos/Runner.app`；未签名 App 不能直接装到真机。

### 本地通过 Xcode 安装到 iPhone

在仓库根目录执行：

```sh
./scripts/prepare-ios.sh
```

脚本检查 Xcode、iPhoneOS SDK、Flutter 和 CocoaPods，按 `pubspec.lock` 和
`ios/Podfile.lock` 安装依赖，生成 Flutter 配置，并自动打开
`ios/Runner.xcworkspace`。它沿用当前 Runner scheme 的 Run 构建模式，保留本地
Team、Bundle ID 和 scheme 设置。项目通过 `pubspec.yaml` 固定使用 CocoaPods；
准备脚本不会修改 Flutter 全局配置，也不会执行完整 App 编译或安装到手机。

仅准备、不打开 Xcode：

```sh
./scripts/prepare-ios.sh --no-open
```

若 Flutter 不在 PATH 中，可以指定 SDK：

```sh
FLUTTER_ROOT=/你的/flutter/sdk目录 ./scripts/prepare-ios.sh
```

在 Xcode 选择 Runner、自己的 iPhone，并在 Signing & Capabilities 中选择自己的
Team，再按 `⌘R` 构建安装。首次使用需在 Xcode 登录 Apple Account；普通账号可选择
Personal Team。手机需信任电脑，并按系统提示开启开发者模式。Bundle ID 默认是
`dev.dawnmesh.intercom.ios`，若签名提示该 ID 不可用，可在本地改成自己的唯一 ID。
签名与设备授权由 Xcode 完成，本仓库不包含证书或账号密钥。

[GitHub Actions](https://github.com/TimeLordFang/DawnMeshIOS/actions/runs/38363601148) 已通过源码检查、298 项 Flutter 回归、原生回归和完整 iOS 编译。该构建页面的 `DawnMeshIOS-unsigned-app` 产物包含未签名 App（压缩包约 16 MB）。完整[验收步骤](docs/INTEROPERABILITY.md)必须在发布前完成。

## 仓库结构

```text
ios/        SunsetRipple iOS 宿主、Swift 音频/BLE/Bonjour、WebRTC 降噪桥
lib/        Android 1.1.0 的共享 Dart UI/会话/协议及 iOS 入口适配
native/     C++ 编解码桥、降噪、官方 libopus/RNNoise 源码
test/      共享 Flutter 回归、Swift 字节流测试、Android 音频互通样本
scripts/    检查与 iOS 构建脚本
docs/       功能对标、协议合同、系统限制和验证记录
```

iOS 独立版本从 `1.0.0+1` 开始，对应标签 `v1.0.0`；功能和协议继续对标 Android 1.1.x。更新检查只使用 `DawnMeshIOS` Releases，不会引导 iOS 用户下载 Android APK。

## 安全与隐私

无账号、无预置服务器、无遥测。邀请码只保存在当前会话内存，聊天沿用安卓版内存会话策略。服务器由用户选择，默认不允许管理员收听。局域网发现信息未认证，真实入房必须通过 PAKE；发现到某个设备不代表信任它。公网使用 HTTPS/WSS 与用途分离的端到端密钥，不为 iOS 放宽 TLS 或密码学校验。

本地设置用 UserDefaults，服务器配置和安装身份通过 flutter_secure_storage 保存到 Keychain。卸载再安装时，iOS Keychain 可能保留原身份。照片仅在用户主动选择/保存时访问。

协议、安全设计和来源信息见 [互通说明](docs/INTEROPERABILITY.md)、[安卓版安全基线](docs/ANDROID_SECURITY_REVIEW.md)、[来源与许可](docs/UPSTREAM.md)。
