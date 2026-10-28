# 更新记录

本轮候选：[1.2.4-rc.1](RELEASE_1.2.4.md)。最近正式版：[1.2.3](RELEASE_1.2.3.md)，统一晨光主题、设置入口、图标资源与默认 iOS 签名配置。

近场 v3 要求全体参与者使用 1.2.0 或更新客户端；公网 LiveKit 房沿用原通路。Wi-Fi/融合房协议上限 16 人，蓝牙房 6 人，不等于真机无线容量已验收。可选语音留言和离线转交默认关闭；Aware 需要设备、系统和签名能力。

## 历史摘要

完整旧版说明链接到当时的 Git 标签，避免把旧测试数字或环境结论当作当前结果。

| 版本 | 主要变化 |
| --- | --- |
| [1.2.2](https://github.com/TimeLordFang/DawnMeshIOS/blob/v1.2.2/docs/RELEASE_1.2.2.md) | 认证报文丢失后的有界补发、旧握手重放及换钥缓存清理。 |
| [1.2.1](https://github.com/TimeLordFang/DawnMeshIOS/blob/v1.2.1/docs/RELEASE_1.2.1.md) | 繁忙融合房握手、并发连接共享、超时取消和加密队列调度。 |
| [1.2.0](https://github.com/TimeLordFang/DawnMeshIOS/blob/v1.2.0/docs/RELEASE_1.2.0.md) | 两端统一版本；独立成员身份、退出换钥、可靠文字、GATT 文字备用和可选离线能力。 |
| [1.0.8](https://github.com/TimeLordFang/DawnMeshIOS/blob/v1.0.8/docs/RELEASE_1.0.8.md) | 融合入房流程与备用入口，移除 Nearby 实验。 |
| [1.0.6](https://github.com/TimeLordFang/DawnMeshIOS/blob/v1.0.6/docs/RELEASE_1.0.6.md) | 同网 Bonjour/NSD 双向发现。 |
| [1.0.5](https://github.com/TimeLordFang/DawnMeshIOS/blob/v1.0.5/docs/RELEASE_1.0.5.md) | 异步 UDP 错误处理与发现恢复。 |
| [1.0.4](https://github.com/TimeLordFang/DawnMeshIOS/blob/v1.0.4/docs/RELEASE_1.0.4.md) | 侧滑与键盘建房恢复、蓝牙房名；Android 同号版本详见历史说明。 |
| [1.0.3](https://github.com/TimeLordFang/DawnMeshIOS/blob/v1.0.3/docs/RELEASE_1.0.3.md) | iOS 点对点 Wi-Fi、蓝牙建房及 GATT 发现；Android 同号版本详见历史说明。 |
| [1.0.2](https://github.com/TimeLordFang/DawnMeshIOS/blob/v1.0.2/docs/RELEASE_1.0.2.md) | 构建、依赖与原生桥整理。 |
| [1.0.1](https://github.com/TimeLordFang/DawnMeshIOS/blob/v1.0.1/docs/RELEASE_1.0.1.md) | 初期稳定性与音频改进。 |
| [1.0.0](https://github.com/TimeLordFang/DawnMeshIOS/blob/v1.0.0/docs/RELEASE_1.0.0.md) | 独立客户端初始版本。 |

当前自动化见 [验证基线](VALIDATION.md)，设备步骤见 [手动验收](MANUAL_ACCEPTANCE.md)，安全边界见 [安全模型](SECURITY_REVIEW.md)。
