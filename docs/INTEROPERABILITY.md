# 跨平台互通合同与验收

## 协议合同

| 路径 | 必须与 Android/网页一致的内容 |
| --- | --- |
| LAN / BLE | 6 字节帧头：type/u8、sender/u8、seq/u16 BE、length/u16 BE；最大载荷 512；type 0x01–0x13 |
| 近场语音 | 解密后的 audio 帧载荷为 raw Opus，16000 Hz/单声道/320 样本；不能传 PCM 或容器文件 |
| 近场验证 | 同一四位邀请码、P-256 SPAKE2 transcript/confirm、用途分离 HKDF、AES-GCM 与防重放 |
| 蓝牙发现 | UUID `7f75d4e0-7a46-4d74-9f8d-1e4bc5e4b004`；CoreBluetooth 厂商数据前两字节 `FF FF`，随后 PSM u16 BE、人数 u8、UTF-8 房名；PSM 1–255、人数 1–6 |
| LAN 发现 | UDP 8990，magic `DAWN_MESH_DISCOVERY_V1`，现有 JSON 和源地址；单播使用同一报文 |
| 融合发现 | UDP 8992，magic `DAWN_MESH_FUSION_V1`，本地 `/fusion` 和 `/fusion/{roomId}` WebSocket；签名名单、能力票据、Opus 加密帧与 Android 一致 |
| 公网房 | 同一 `/api/v1` 控制 API、HTTPS/WSS、scrypt 邀请凭据、32 字节随机密钥封装、成员身份校验 |
| 公网媒体 | 相同 LiveKit keyProvider 参数与带填充的 base64url 密钥；E2EE 保持开启 |
| 公网聊天 | 同一 `DawnMesh internet chat v1` HKDF 和 `dawnmesh.chat.v1\0{senderId}` AAD；不使用 iOS 专属密钥格式 |

Dart 协议、密码学、普通公网会话与融合协议直接来自 Android 基线；仅局域网发现加入 Bonjour/单播入口，不改变线上帧格式。Web 只参与普通公网房。

## 已自动验证

- 现有 Flutter 回归包含浏览器加密聊天已知向量、邀请码凭据、PAKE、重放/冒名/禁麦、防未认证转发、HTTP API、融合签名名单与恢复等路径。
- `test/interop/AndroidOpusInterop.java` 用 Android 相同 Concentus 1.0.2、VoIP/24kbps/20ms 参数生成包。测试样本 `android-opus-16k-20ms.bin` 为合成正弦波，无真实用户录音。
- C++ `ios_codec_test` 用 iOS 相同 vendored Opus 解码该 Android 样本，并可输出 iOS 包，由 Concentus 解码回 320 样本；测试实际 codec 格式，而非模拟音频。
- Swift `WireSupport.swift` 独立测试头部拆包、粘包、载荷边界、PSM、人数、短写、丢旧实时包、序列回绕、PLC 和 PTT 静音后恢复。

可选双向 codec 命令：

```sh
# DAWNMESH_CONCENTUS_JAR 指向 Maven io.github.jaredmdobson:concentus:1.0.2
java -cp "$DAWNMESH_CONCENTUS_JAR" test/interop/AndroidOpusInterop.java encode /tmp/android.opus
native/build/ios_codec_test /tmp/android.opus /tmp/ios.opus
java -cp "$DAWNMESH_CONCENTUS_JAR" test/interop/AndroidOpusInterop.java decode /tmp/ios.opus
```

## 发布前必须完成的真机验收

以下当前均**未执行**；需完整 Xcode、签名 iOS 包、至少一台 iPhone、一台 Android、浏览器和自部署 Server/LiveKit。

1. **三端公网同房**：三个客户端连接同一服务器；轮流创建/加入/退出；四位码正确/错误；每端分别 PTT/自动发言，其他两端均能听到；文字与照片三端同步。核对 E2EE 实际启用与服务器不能直接解码媒体。
2. **管理与恢复**：分别由 iOS/Android/网页房主禁麦、解禁、改名和移交；禁麦成员重连与音频重启仍不能发送；断网/切 Wi-Fi↔移动网络后恢复，成员不重复。
3. **同网双向**：Android 建房后 iOS 地址加入；iOS 建房后单播通知 Android，安卓列表出现并可加入；iOS↔iOS Bonjour 发现；不同邀请码/伪造发现不能绕过 PAKE。
4. **近场语音**：双方按住与自动发言、同时发言混音、标准/强力降噪；Wi-Fi 到 16 人的功能容量，实际热点承载量另测。
5. **蓝牙**：Android 房主+iOS 成员，最多 6 人；首音、静音、照片分片、开关蓝牙后的新 PSM、短写与断流重连；iOS 不应显示蓝牙建房可用。
6. **融合**：离线建房/手动入房；任一联网成员接入同一服务器；公网与近场数据去重，名单签名与恢复；16 人协议容量。网页不参加该房型。
7. **系统行为**：锁屏、后台、耳机插拔/HFP、内置麦克风、电话中断、系统音频服务重置、麦克风/蓝牙/本地网络拒绝与重新授权；空闲应停止使用麦克风。
8. **照片与设置**：相册选择/保存、相机授权、昵称与音频档位跨启动保存；Keychain Sharing 签名正确；无 APK 更新入口。

把设备型号、iOS/Android 版本、服务端提交、包版本和结果写入验收记录。不得用模拟测试或 CI 编译成功代替实际三端语音验证。

## 1.0.3 无线能力新增验收

1. 两台 iPhone 均安装 1.0.3，开启系统 Wi-Fi/蓝牙并授权本地网络；不连接共同 AP，关闭蜂窝数据排除公网路径。交替作为普通 Wi-Fi 房主，验证发现、错误邀请码拒绝、正确邀请码加入、双向语音、聊天和图片。
2. 断开 Wi-Fi、关闭/开启蓝牙再恢复，验证重连不重复播放旧密文、不生成重复成员；验证解散后房间消失、链路关闭。
3. iOS 1.0.3 蓝牙建房，分别用另一台 iOS 1.0.3 和安卓 1.1.4 加入；安卓旧房主继续供新版 iOS/安卓加入。确认动态 PSM、人数变化和中文/emoji 房名。
4. 扩展至最多六台蓝牙设备，测试连续语音、按住对讲、聊天与图片并发、慢客户端、房主蓝牙开关和锁屏。记录实际稳定容量，不能以协议上限代替实测结果。
5. 安卓从前台 iOS 房主完成发现后再锁屏测试既有连接；iOS 后台广告对安卓不可见时应明确记录，不把失败描述成已支持后台发现。
6. 同网 iOS/安卓、旧版 iOS Bonjour、公网 iOS/安卓/Web 与融合房各做一次回归。

以上为真机验收清单；本地源码、回环和编译验证不代表这些无线项目已经通过。
