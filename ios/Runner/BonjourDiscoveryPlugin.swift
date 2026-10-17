import Flutter
import Foundation
import Darwin

// Bonjour provides iOS-to-iOS discovery without a multicast entitlement.
// Android 1.1.0 advertises UDP only; users can join its unicast TCP endpoint.
final class BonjourDiscoveryPlugin: NSObject, FlutterPlugin, NetServiceBrowserDelegate, NetServiceDelegate {
    private var browsers = [String: NetServiceBrowser]()
    private var services = [String: [NetService]]()
    private var publications = [String: NetService]()
    private let events = DawnEventStream()
    private let applePeer = DawnApplePeerWiFi()
    private var peerBrowseID: String?

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
        instance.applePeer.onRoom = { [weak instance] room in
            guard let instance = instance, let id = instance.peerBrowseID else { return }
            instance.events.sink?(room.merging(["id": id, "magic": "DAWN_MESH_DISCOVERY_V1"], uniquingKeysWith: { _, new in new }))
        }
        instance.applePeer.onRemoved = { [weak instance] service in
            guard let instance = instance, let id = instance.peerBrowseID else { return }
            instance.events.sink?(["type": "removed", "service": service, "id": id])
        }
        instance.applePeer.onError = { [weak instance] message in
            guard let instance = instance, let id = instance.peerBrowseID else { return }
            instance.events.sink?(["type": "error", "message": message, "id": id])
        }
        FlutterEventChannel(name: "dev.dawnmesh.intercom/bonjour_events", binaryMessenger: registrar.messenger()).setStreamHandler(instance.events)
    }
    private func serviceType(_ magic: String) -> String { magic == "DAWN_MESH_FUSION_V1" ? "_dawnfusion._tcp." : "_dawnmesh._tcp." }
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        guard let magic = args["magic"] as? String else { result(false); return }
        let type = serviceType(magic)
        let id = args["id"] as? String ?? magic
        if magic == "DAWN_MESH_DISCOVERY_V1" {
            switch call.method {
            case "start": peerBrowseID = id; applePeer.startBrowsing(); result(true)
            case "advertise":
                guard let port = args["port"] as? Int, (1...65535).contains(port), let roomID = args["roomId"] as? String else { result(false); return }
                let values = ["roomId": String(roomID.prefix(48)), "roomName": String((args["roomName"] as? String ?? "").prefix(48)), "hostNickname": String((args["hostNickname"] as? String ?? "").prefix(48)), "members": String(args["members"] as? Int ?? 1), "port": String(port)]
                do { try applePeer.advertise(values: values, port: UInt16(port)); result(true) }
                catch { result(FlutterError(code: "APPLE_PEER_LISTEN", message: "无法开启苹果点对点 Wi-Fi", details: String(describing: error))) }
            case "stopAdvertising": applePeer.stopAdvertising(); result(nil)
            case "stop": if peerBrowseID == id { applePeer.stopBrowsing(); applePeer.stopAdvertising(); peerBrowseID = nil }; result(nil)
            default: result(FlutterMethodNotImplemented)
            }
            return
        }
        switch call.method {
        case "start":
            stop(id)
            let browser = NetServiceBrowser(); browser.delegate = self
            browsers[id] = browser; services[id] = []
            browser.searchForServices(ofType: type, inDomain: "local.")
            result(true)
        case "advertise":
            guard let port = args["port"] as? Int, (1...65535).contains(port), let roomID = args["roomId"] as? String else { result(false); return }
            let values = ["magic": magic, "roomId": roomID, "roomName": args["roomName"] as? String ?? "", "hostNickname": args["hostNickname"] as? String ?? "", "members": String(args["members"] as? Int ?? 1)]
            let txt = NetService.data(fromTXTRecord: values.mapValues { Data(String($0.prefix(64)).utf8) })
            if let service = publications[id], service.port == port {
                service.setTXTRecord(txt)
            } else {
                publications[id]?.stop()
                let service = NetService(domain: "local.", type: type, name: String(roomID.prefix(32)) + "-" + String(UUID().uuidString.prefix(8)), port: Int32(port))
                service.delegate = self; service.setTXTRecord(txt); publications[id] = service; service.publish()
            }
            result(true)
        case "stopAdvertising": publications.removeValue(forKey: id)?.stop(); result(nil)
        case "stop": stop(id); result(nil)
        default: result(FlutterMethodNotImplemented)
        }
    }
    private func stop(_ id: String) {
        browsers.removeValue(forKey: id)?.stop()
        for service in services.removeValue(forKey: id) ?? [] { service.stop(); service.delegate = nil }
        publications.removeValue(forKey: id)?.stop()
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard (services[browsers.first(where: { $0.value === browser })?.key ?? ""]?.count ?? 0) < 64 else { return }
        let id = browsers.first(where: { $0.value === browser })?.key ?? ""
        services[id, default: []].append(service)
        service.delegate = self; service.resolve(withTimeout: 5)
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let id = browsers.first(where: { $0.value === browser })?.key ?? ""
        services[id]?.removeAll { $0.name == service.name }
        events.sink?(["type": "removed", "id": id, "service": service.name, "magic": service.type == "_dawnfusion._tcp." ? "DAWN_MESH_FUSION_V1" : "DAWN_MESH_DISCOVERY_V1"])
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        events.sink?(["type": "error", "id": browsers.first(where: { $0.value === browser })?.key ?? "", "message": "本地网络发现不可用，请允许本地网络权限或手动输入房主地址。"])
    }
    func netService(_ sender: NetService, didUpdateTXTRecord data: Data) { netServiceDidResolveAddress(sender) }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let txt = sender.txtRecordData() else { return }
        var fields: [String: Any] = NetService.dictionary(fromTXTRecord: txt).mapValues { String(data: $0, encoding: .utf8) ?? "" }
        for data in sender.addresses ?? [] {
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let success = data.withUnsafeBytes { raw -> Bool in
                guard let address = raw.baseAddress?.assumingMemoryBound(to: sockaddr.self), address.pointee.sa_family == sa_family_t(AF_INET) else { return false }
                return getnameinfo(address, socklen_t(data.count), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            }
            guard success else { continue }
            fields["address"] = String(cString: host); fields["port"] = sender.port
            fields["members"] = Int(fields["members"] as? String ?? "1") ?? 1
            fields["service"] = sender.name; fields["type"] = "room"
            for (id, known) in services where known.contains(where: { $0 === sender }) {
                fields["id"] = id; events.sink?(fields)
            }
            sender.startMonitoring()
            return
        }
    }
}
