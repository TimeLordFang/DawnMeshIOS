import Flutter
import Foundation

// Standard LAN DNS-SD and Apple peer Wi-Fi share the same service identities.
// Ordinary Wi-Fi and fusion owners have independent browsers and listeners.
final class BonjourDiscoveryPlugin: NSObject, FlutterPlugin {
    private let events = DawnEventStream()
    private let applePeer = DawnApplePeerWiFi()
    private var protocols = [String: String]()

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = BonjourDiscoveryPlugin()
        let channel = FlutterMethodChannel(name: "dev.dawnmesh.intercom/bonjour", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)
        let peerChannel = FlutterMethodChannel(name: "dev.dawnmesh.intercom/apple_peer", binaryMessenger: registrar.messenger())
        peerChannel.setMethodCallHandler { call, result in
            let args = call.arguments as? [String: Any] ?? [:]
            if call.method == "open", let service = args["service"] as? String {
                instance.applePeer.open(service) { result($0) }
            } else if call.method == "close", let id = args["connectionId"] as? String {
                instance.applePeer.close(id); result(nil)
            } else { result(FlutterMethodNotImplemented) }
        }
        instance.applePeer.onRoom = { [weak instance] id, room in
            guard let instance = instance, let magic = instance.protocols[id] else { return }
            instance.events.sink?(room.merging(["id": id, "magic": magic], uniquingKeysWith: { _, new in new }))
        }
        instance.applePeer.onRemoved = { [weak instance] id, service in
            instance?.events.sink?(["type": "removed", "service": service, "id": id])
        }
        instance.applePeer.onError = { [weak instance] id, message in
            instance?.events.sink?(["type": "error", "message": message, "id": id])
        }
        FlutterEventChannel(name: "dev.dawnmesh.intercom/bonjour_events", binaryMessenger: registrar.messenger()).setStreamHandler(instance.events)
    }
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        guard let magic = args["magic"] as? String,
              magic == "DAWN_MESH_DISCOVERY_V1" || magic == "DAWN_MESH_FUSION_V1",
              let id = args["id"] as? String else { result(false); return }
        let type = magic == "DAWN_MESH_FUSION_V1" ? "_dawnfusion._tcp" : "_dawnmesh._tcp"
        switch call.method {
        case "start":
            protocols[id] = magic
            applePeer.startBrowsing(id: id, serviceType: type); result(true)
        case "advertise":
            guard protocols[id] == magic, let port = args["port"] as? Int, (1...65535).contains(port),
                  let roomID = args["roomId"] as? String else { result(false); return }
            let values = ["magic": magic, "roomId": String(roomID.prefix(48)), "roomName": String((args["roomName"] as? String ?? "").prefix(48)), "hostNickname": String((args["hostNickname"] as? String ?? "").prefix(48)), "members": String(args["members"] as? Int ?? 1), "port": String(port)]
            do { try applePeer.advertise(values: values, port: UInt16(port), id: id, serviceType: type); result(true) }
            catch { result(FlutterError(code: "APPLE_PEER_LISTEN", message: "无法开启附近 Wi-Fi", details: String(describing: error))) }
        case "stopAdvertising": applePeer.stopAdvertising(id: id); result(nil)
        case "stop":
            applePeer.stopBrowsing(id: id); applePeer.stopAdvertising(id: id)
            protocols.removeValue(forKey: id); result(nil)
        default: result(FlutterMethodNotImplemented)
        }
    }
}
