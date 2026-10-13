import Flutter
import UIKit
import AVFoundation

final class DawnMeshPlatformPlugin: NSObject, FlutterPlugin {
    private let logs = DawnEventStream()
    private let wifiEvents = DawnEventStream()
    private let preferences = UserDefaults.standard
    private let speech = AVSpeechSynthesizer()
    private var channels = [FlutterMethodChannel]()

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = DawnMeshPlatformPlugin()
        for name in ["preferences", "external_links", "wifi_direct", "call_controls", "presence_audio", "debug_log_control"] {
            let channel = FlutterMethodChannel(name: "dev.dawnmesh.intercom/\(name)", binaryMessenger: registrar.messenger())
            channel.setMethodCallHandler { call, result in instance.handle(name, call, result) }
            instance.channels.append(channel)
        }
        FlutterEventChannel(name: "dev.dawnmesh.intercom/debug_logs", binaryMessenger: registrar.messenger()).setStreamHandler(instance.logs)
        FlutterEventChannel(name: "dev.dawnmesh.intercom/wifi_direct_events", binaryMessenger: registrar.messenger()).setStreamHandler(instance.wifiEvents)
    }
    private func handle(_ name: String, _ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch name {
        case "preferences":
            let keys = ["Nickname": "nickname", "DebugLoggingEnabled": "debugLoggingEnabled", "AudioTuningProfile": "audioTuningProfile", "AudioTuningParameters": "audioTuningParameters"]
            if call.method.hasPrefix("get"), let key = keys[String(call.method.dropFirst(3))] {
                result(preferences.object(forKey: key)); return
            }
            if call.method.hasPrefix("set"), let key = keys[String(call.method.dropFirst(3))] {
                let value: Any? = key == "audioTuningParameters" ? args : args[key == "audioTuningProfile" ? "profile" : key == "debugLoggingEnabled" ? "enabled" : key]
                if let value = value { preferences.set(value, forKey: key) }
                result(nil); return
            }
            result(FlutterMethodNotImplemented)
        case "external_links":
            guard call.method == "openUrl", let raw = args["url"] as? String, let url = URL(string: raw),
                  url.scheme == "https", url.host == "github.com", url.path.hasPrefix("/TimeLordFang/DawnMeshIOS/releases") else { result(false); return }
            UIApplication.shared.open(url, options: [:]) { result($0) }
        case "wifi_direct":
            switch call.method {
            case "hybridAvailability": result("unsupported")
            case "getConnectionInfo": result(["isConnected": false, "isGroupOwner": false, "groupFormed": false, "groupOwnerAddress": ""])
            case "stopFusionDiscovery", "stopAdvertisingFusionRoom": result(nil)
            default: result(false)
            }
        case "call_controls":
            if call.method == "update" { result(nil) }
            else { result(FlutterMethodNotImplemented) }
        case "presence_audio":
            if call.method == "stop" { speech.stopSpeaking(at: .immediate); result(nil); return }
            guard call.method == "announce", let nickname = args["name"] as? String else { result(FlutterMethodNotImplemented); return }
            let english = Locale.preferredLanguages.first?.hasPrefix("en") ?? false
            let left = args["kind"] as? String == "left"
            let utterance = AVSpeechUtterance(string: String(nickname.prefix(64)) + (english ? (left ? " left the room" : " disconnected") : (left ? "已离开房间" : "已断线")))
            utterance.voice = AVSpeechSynthesisVoice(language: english ? "en-US" : "zh-CN")
            speech.speak(utterance); result(nil)
        case "debug_log_control":
            guard call.method == "captureSystemSnapshot" else { result(FlutterMethodNotImplemented); return }
            let session = AVAudioSession.sharedInstance()
            logs.sink?(["level": "info", "tag": "DawnSystem", "message": "iOS \(UIDevice.current.systemVersion); sampleRate=\(session.sampleRate); input=\(session.currentRoute.inputs.map { $0.portType.rawValue }); output=\(session.currentRoute.outputs.map { $0.portType.rawValue }); multicast=provisioning-dependent; Wi-Fi Direct=unavailable"])
            result(true)
        default: result(FlutterMethodNotImplemented)
        }
    }
}
