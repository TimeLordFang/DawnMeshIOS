# 首版延期事项与后续计划

## 1. Wi-Fi Direct 自动组网

iOS 15 基线没有对等的公开 Android WifiP2pManager 接口。首版用同一 Wi-Fi/热点，保持应用层帧、邀请码与加密一致。后续研究较新系统的邻近网络能力前，先验证跨 Android 的兼容性与可部署系统范围；不直接替换为只支持 Apple 设备的 MultipeerConnectivity。

## 2. iOS 蓝牙建房

[CoreBluetooth startAdvertising](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/startadvertising(_:))只允许 local name 和 service UUID；后台还会移除 local name。Android 1.1.0 读取公司号 `0xFFFF` 的厂商字段 PSM/人数。把 `DM_PSM_NAME` 塞到 local name 不会让现有安卓解析器发现房间。

首版 iOS central 读取现有 Android 广播、打开未配对 L2CAP CoC，并在 Dart 层执行现有 PAKE。iOS 的“蓝牙建房”按钮禁用，原生也明确拒绝该调用。

后续先设计跨平台 GATT 房间元数据/动态 PSM 读取，再同时升级 Android 扫描器与 iOS peripheral。保留旧厂商广告向后兼容；验收 iOS↔Android 双向建房、六人容量、后台广告、蓝牙开关与 PSM 重建。

## 3. Android UDP 自动发现

[Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)要求广播/组播操作使用 `com.apple.developer.networking.multicast`。普通本地网络授权并不等同于获准广播。

本仓库默认 `Runner.entitlements` 只有 Keychain Sharing。`Multicast.entitlements.example` 是能力获批后使用的模板，不能直接保证签名可用。获得 Apple 批准与包含该能力的描述文件后，在 Xcode 为 Runner 的所有配置选择相应 entitlements，重签并测试现有 UDP 8990/8992 广播。不要在 CI 或分发包里无条件启用未经批准的 entitlement。

无该能力时：iOS 间使用 Bonjour；iOS 加入安卓输入房主 IP；iOS 创建房后，房间设置“通知同网安卓设备”向指定安卓 IP 单播原版发现 JSON。单播地址在内存中最多保存 16 个，不扫描整个子网。Bonjour 服务类型为 `_dawnmesh._tcp` 与 `_dawnfusion._tcp`。

## 4. 锁屏对讲、后台重连与耳机并发

iOS 的 audio 后台模式仅为持续音频提供系统条件，不能保证应用无限执行后台扫描/重连。Apple [CoreBluetooth 后台说明](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)也限制扫描与广告行为。

首版保留现有语音会话、路由中断处理和恢复策略。Android 的前台通知/锁屏面板不移植为假按钮；`call_controls` 接收共享页面状态而不注册锁屏 PTT。

后续用真机确定音频与蓝牙共存码率，再评估 Apple PushToTalk 框架、所需账号能力、后台唤醒规则及现有多房型的集成。持续手势、后台按键与耳机声学效果均需真实 iPhone 验收。

## 5. 非硬件阻塞的交付条件

完整 iOS 工程已在 [GitHub macOS/Xcode Runner](https://github.com/TimeLordFang/DawnMeshIOS/actions/runs/38353118485) 编译通过并上传未签名 App。本机缺少完整 Xcode，不影响该远程编译结果。Apple 签名、安装及三端真机语音验收仍须完成；账号与构建环境条件不能当作“硬件限制”掩盖。当前仓库是可编译的实现和验证基线，尚未完成真机验收。
