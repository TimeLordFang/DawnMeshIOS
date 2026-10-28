# 跨平台功能、协议与 iOS 边界

适用于 1.2.x 当前近场 v3 实现。源码已接通与真机验收分开记录；设备步骤统一使用 [五机验收](MANUAL_ACCEPTANCE.md)。

## 功能与连接范围

| 范围 | iOS 与跨平台边界 |
| --- | --- |
| 公网 | 与 Android/网页共享 API、LiveKit E2EE、房主管理、聊天和三档音质；容量由服务器控制。 |
| Wi-Fi | 同网/热点兼容 Android；苹果点对点 Wi-Fi 使用 Bonjour/Network.framework，不与 Android Wi-Fi Direct 直接互联。 |
| 蓝牙 | 双端可建房/加入，L2CAP 语音优先，GATT 备用只承载文字与必要控制；协议上限 6 人。 |
| 融合 | LAN、苹果点对点入口与公网中继，签名名单、去重和恢复；协议上限 16 人。 |
| Wi-Fi Aware | 已建立融合房后主动启用；iOS 26+、兼容硬件、系统配对及授权签名配置均需满足。失败保留原路径。 |
| 身份与内容 | 近场逐帧成员签名、持钥证明、epoch 换钥、安全号码、可靠文字；全体近场成员需 1.2.0+。 |
| 可选数据 | 语音留言默认关闭、每段最多 15 秒；离线密封转交默认关闭并持久化密文/联系人，配额与边界见安全模型。 |
| 音频 | 原生 Opus、RNNoise/WebRTC 处理、输入路由、中断与 PLC；耳机/射频组合及实际延迟需真机确认。 |
| 后台与锁屏 | audio 后台模式支持持续音频的系统条件，不能保证无限扫描或重连；不提供 Android 前台通知/锁屏 PTT 面板的假替代。 |
| 调参与调试 | 共享 Dart 日志、诊断与缓冲参数；Android AudioTrack/flush 专属参数不套用到 iOS。 |

## 发现与首次入房

两端同网使用 `_dawnmesh._tcp`、`_dawnfusion._tcp` 的 Bonjour/NSD，并使用实际 SRV 端口；服务类型声明在 Info.plist 中。普通本地网络授权与 multicast 能力不是一回事，默认构建不无条件申请组播或 Aware entitlement。

过滤 mDNS 的网络可尝试同网房主 IPv4 地址；iOS 可向指定安卓 IP 单播邀请，目标只在内存有界保存。AP 客户端隔离或拒绝本地网络权限时，手动地址也不能保证可达。

iOS 前台蓝牙房主通过 GATT 发布动态 PSM、人数与完整 UTF-8 房名，兼容 Android GATT 元数据读取。后台广告服务 UUID 的系统限制意味着安卓不能依赖后台 iPhone 发现新房间；首次发现/加入先保持房主前台。系统蓝牙恢复后要重新解析 PSM，不复用旧通道。

## 协议合同与复核

| 路径 | 不变的互操作约束 |
| --- | --- |
| LAN / BLE | 6 字节帧头：type/u8、sender/u8、seq/u16 BE、length/u16 BE；最大载荷 512。具体类型见 `FrameType`。 |
| 近场语音 | 内层音频为 raw Opus，16 kHz、单声道、20 ms/320 样本；不传 PCM 或容器文件。 |
| 近场认证 | 四位码、SPAKE2 transcript/confirm、用途分离 HKDF、AES-GCM、防重放及 v3 成员身份校验。 |
| 蓝牙元数据 | 版本/PSM/人数/房名遵守同一格式向量，发现字段不是认证凭据；数据备用与元数据特征分开。 |
| 公网 | 相同凭据派生、密钥信封与浏览器加密样本；不能把近场或融合宣称为网页可直接参与。 |

`scripts/check-native.sh` 覆盖 Swift 字节流、队列、元数据、Pod 补丁、回环 TCP 及跨端 Opus 样本；`test/interop/` 保留双向编解码向量。无线、多人容量、系统切换和锁屏以手动结果为准。

当前默认包不申请 Wi-Fi Aware，基础签名可选 Personal Team；可选包需相应开发者团队与描述文件。见 [Xcode 签名](XCODE_SIGNING.md)、[开发指南](DEVELOPMENT.md) 与 [安全边界](SECURITY_REVIEW.md)。
