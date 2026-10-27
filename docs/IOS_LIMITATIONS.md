# iOS 能力边界与签名要求（1.2.x）

当前默认构建适配 Personal Team，不申请 Wi-Fi Aware。该加速能力改为显式选择获授权签名配置，详见 [Xcode 签名](XCODE_SIGNING.md)。普通通信路径不变。

## 1. 苹果点对点 Wi-Fi 与 Android Wi-Fi Direct

1.0.3 的普通 Wi-Fi 房使用 `NWBrowser`、`NWListener` 和 `NWConnection`，三个环节均设置 `includePeerToPeer = true`。保留 Bonjour 服务端点及其接口信息，由 Network.framework 处理点对点链路和 IPv6 作用域。原生转接只绑定本机回环端口，将已有的加密 TCP 协议送入 Dart 传输层；房主仍监听原有 IPv4 LAN 端口，保持安卓同网兼容。每方向最多一个 4096 字节转发块在途，并有建链超时、连接数上限和断线清理。

两台 iOS 的普通 Wi-Fi 房可在没有共同路由器、没有互联网时尝试发现和连接，需开启 Wi-Fi/蓝牙、授权本地网络并先保持前台。该链路仅用于苹果设备；Android Wi-Fi Direct 的无线协议不与之互通。iOS 与安卓仍使用共同 Wi-Fi/热点、蓝牙或公网房。融合房也保留苹果点对点入口与 LAN/公网中继；1.2.0 另提供主动启用的 Wi-Fi Aware 加速。

源码和真实回环 TCP 测试不等同于无线验收。需两台 iPhone 验证首次发现、无共同 AP、弱信号、Wi-Fi/蓝牙开关、漫游与锁屏；16 人是应用协议上限，实际无线容量须测试。

参考：[Apple TN3151](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api)。

## 2. iOS 蓝牙建房

1.0.3 实现 `CBPeripheralManager` 房主，动态发布未配对 L2CAP CoC，并通过可读 GATT characteristic 发布房名、人数和系统分配的 PSM。1.2.0 的近场认证升级为 v3，增加独立成员身份与换钥；应用线帧仍不超过 512 字节载荷。系统广播仅发布既有服务 UUID，不把 PSM 塞入 local name 或不受支持的厂商数据字段。

元数据服务 UUID 为 `7f75d4e0-7a46-4d74-9f8d-1e4bc5e4b004`，特征 UUID 为 `7f75d4e1-7a46-4d74-9f8d-1e4bc5e4b004`。值为 `version=1:u8 | PSM:u16be | members:u8 | roomName:utf8`，名称最多 64 字节，总长 4…68 字节；PSM 1…255、人数 1…6，拒绝无效 UTF-8 和控制字符。元数据不作为认证凭据，入房仍执行 PAKE。

iOS 1.0.3 和 Android 1.1.4 均可读取这套发现信息；继续识别旧安卓 `0xFFFF` 厂商广播。旧安卓版不会发现 iOS 房主，需升级。iOS 房主限制最多 5 条客户端通道，逐链路维护有界发送队列与停滞超时；认证后的密文由 Dart 决定转发，禁止客户端注入房主命令。蓝牙开关恢复时重新分配并发布 PSM。

需真机、蓝牙开启和授权；标准 Core Bluetooth 不需 MFi 配件或额外组播 entitlement。已声明 `bluetooth-peripheral` 后台模式，但 iOS 后台广告服务 UUID 会进入 Apple overflow 区，安卓不能依赖它发现新房间。因此建房/首次加入保持房主前台，锁屏既有通话与重连仍需实测。不承诺硬件能稳定承载协议上限的六人语音。

参考：[L2CAP 发布](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/publishl2capchannel(withencryption:))、[广播限制](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/startadvertising(_:))。

## 3. Android UDP 自动发现

[Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)要求广播/组播操作使用 `com.apple.developer.networking.multicast`。普通本地网络授权并不等同于获准广播。

本仓库默认 `Runner.entitlements` 包含 Keychain Sharing 和 Wi-Fi Aware Publish/Subscribe；后者需描述文件包含对应能力。`Multicast.entitlements.example` 是能力获批后使用的模板，不能直接保证签名可用。获得 Apple 批准与包含该能力的描述文件后，在 Xcode 为 Runner 的所有配置选择相应 entitlements，重签并测试现有 UDP 8990/8992 广播。不要在 CI 或分发包里无条件启用未经批准的组播 entitlement。

iOS 1.0.6 配套 Android 1.1.7 后，两端同网使用系统 Bonjour/NSD 双向发现，服务类型为 `_dawnmesh._tcp` 与 `_dawnfusion._tcp`。具体服务类型已列入 Info.plist，因此无需新增 multicast entitlement。Android 使用解析后的 SRV 端口，兼容苹果点对点 TCP 转接的动态端口。

旧安卓或过滤 mDNS 的网络可保留手动地址/单播路径：iOS 加入安卓输入房主 IP；iOS 房间设置“通知同网安卓设备”向指定安卓 IP 单播 JSON。单播地址只在内存中最多保存 16 个。用户拒绝本地网络权限或 AP 开启客户端隔离时，手动地址也不能保证可达。

1.2.0 已接入可选 Wi-Fi Aware 发布、订阅、系统配对与本地 TCP 转接。在已建立的融合房里主动启用，iOS 需 26+ 与兼容硬件/签名能力，Android 使用 API 37 标准配对数据通道并检查硬件能力。它不代替首次入房，也不让 AWDL 与 Wi-Fi Direct 变为同一协议。跨平台射频互通尚无真机结果，具体步骤与不支持回退见 [五机验收](MANUAL_ACCEPTANCE.md)。

参考：[Apple Wi-Fi Aware](https://developer.apple.com/documentation/WiFiAware)、[Android Wi-Fi Aware](https://developer.android.com/develop/connectivity/wifi/wifi-aware)。

## 4. 锁屏对讲、后台重连与耳机并发

iOS 的 audio 后台模式仅为持续音频提供系统条件，不能保证应用无限执行后台扫描/重连。Apple [CoreBluetooth 后台说明](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)也限制扫描与广告行为。

首版保留现有语音会话、路由中断处理和恢复策略。Android 的前台通知/锁屏面板不移植为假按钮；`call_controls` 接收共享页面状态而不注册锁屏 PTT。

后续用真机确定音频与蓝牙共存码率，再评估 Apple PushToTalk 框架、所需账号能力、后台唤醒规则及现有多房型的集成。持续手势、后台按键与耳机声学效果均需真实 iPhone 验收。

## 5. 非硬件阻塞的交付条件

完整 iOS 工程已在 [GitHub macOS/Xcode Runner](https://github.com/TimeLordFang/DawnMeshIOS/actions/runs/38353118485) 编译通过并上传未签名 App。本机缺少完整 Xcode，不影响该远程编译结果。Apple 签名、安装及三端真机语音验收仍须完成；账号与构建环境条件不能当作“硬件限制”掩盖。当前仓库是可编译的实现和验证基线，尚未完成真机验收。


## 1.2.0 数据与兼容性

GATT 数据特征 `7f75d4e2-7a46-4d74-9f8d-1e4bc5e4b004` 提供仅文字备用通道，图片和语音仍需较快链路。原生后台广告限制不会因此消失。

普通聊天和可选语音留言仍在房间内存中；离线转交为独立、默认关闭的持久化能力，详见 [安全模型](SECURITY_REVIEW.md)。所有近场参与者需更新至 1.2.0，不协商降级到旧共享密钥协议。公网 LiveKit 房保持现有三端通路。
