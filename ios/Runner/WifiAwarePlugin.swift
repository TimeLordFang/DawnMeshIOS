import Flutter
import UIKit
import Network
import WiFiAware
import DeviceDiscoveryUI

final class WifiAwarePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var sink: FlutterEventSink?
    private var backend: AnyObject?
    static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = WifiAwarePlugin()
        let channel = FlutterMethodChannel(name: "dev.dawnmesh.intercom/wifi_aware", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(plugin, channel: channel)
        FlutterEventChannel(name: "dev.dawnmesh.intercom/wifi_aware_events", binaryMessenger: registrar.messenger()).setStreamHandler(plugin)
    }
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? { sink = events; return nil }
    func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 26.0, *) else {
            if call.method == "capabilities" { result(["supported": false, "reason": "此系统未提供 Wi-Fi Aware"]) }
            else if call.method == "stop" { result(nil) }
            else { result(["started": false, "status": "此系统未提供 Wi-Fi Aware"]) }
            return
        }
        #if targetEnvironment(simulator)
        result(["supported": false, "started": false, "reason": "模拟器不提供 Wi-Fi Aware 无线连接"])
        #else
        if backend == nil {
            let service = DawnWifiAware()
            service.emit = { [weak self] event in self?.sink?(event) }
            backend = service
        }
        guard let service = backend as? DawnWifiAware else { result(nil); return }
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "capabilities": result(service.capabilities)
        case "start": result(service.start(args))
        case "pair": service.pair(owner: args["owner"] as? String); result(nil)
        case "stop": if args["owner"] as? String == service.owner { service.stop() }; result(nil)
        default: result(FlutterMethodNotImplemented)
        }
        #endif
    }
}

@available(iOS 26.0, *)
private final class DawnWifiAware {
    private let name = "_dawnmesh._tcp"
    private(set) var owner: String?
    private var generation = 0
    private var localPort: UInt16 = 0
    private var isHost = false
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var pipes = [UUID: DawnPeerPipe]()
    private var proxies = [NWEndpoint: DawnPeerProxy]()
    private weak var pairingController: UIViewController?
    private var pickerTask: Task<Void, Never>?
    var emit: (([String: Any]) -> Void)?
    var capabilities: [String: Any] {
        let supported = WACapabilities.supportedFeatures.contains(.wifiAware)
        let configured = (Bundle.main.object(forInfoDictionaryKey: "WiFiAwareServices") as? [String: Any])?[name] != nil
        return ["supported": supported && configured, "pairing": supported, "systemPairingUi": true,
                "reason": !supported ? "此设备未提供 Wi-Fi Aware" : !configured ? "安装包未配置 Wi-Fi Aware 服务" : "可尝试系统配对；需要已授权的签名配置，实际可用性由系统决定"]
    }
    private func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        params.wifiAware = .realtime
        params.serviceClass = .interactiveVoice
        return params
    }
    func start(_ args: [String: Any]) -> [String: Any] {
        guard let requested = args["owner"] as? String, let port = args["port"] as? Int,
              (1...65535).contains(port), capabilities["supported"] as? Bool == true else {
            return ["started": false, "status": capabilities["reason"] ?? "无法启用 Wi-Fi Aware"]
        }
        if let owner = owner, owner != requested { return ["started": false, "status": "其他房间正在使用 Wi-Fi Aware"] }
        stop(); owner = requested; localPort = UInt16(port); isHost = args["host"] as? Bool == true
        do {
            if isHost {
                guard let service = WAPublishableService.allServices[name] else { throw failure() }
                let provider: WAPublisherListener = .wifiAware(.connecting(to: service, from: .allPairedDevices, datapath: .realtime))
                let params = parameters(); provider.configureParameters(params)
                let listener = try NWListener(using: params)
                self.listener = listener; listener.service = provider.service
                listener.newConnectionHandler = { [weak self, weak listener] connection in
                    guard let self = self, self.listener === listener, self.pipes.count < 4 else { connection.cancel(); return }
                    let local = NWConnection(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: self.localPort)!, using: .tcp)
                    let pipe = DawnPeerPipe(connection, local); let id = UUID(); self.pipes[id] = pipe
                    pipe.onClose = { [weak self] in self?.pipes.removeValue(forKey: id) }
                    pipe.start()
                }
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self = self, self.listener === listener else { return }
                    if case .failed = state { self.status("系统未能发布加速服务，请检查 Wi-Fi Aware 签名权限", active: false); self.stop() }
                }
                listener.start(queue: .main)
            } else {
                guard let service = WASubscribableService.allServices[name] else { throw failure() }
                let provider: WASubscriberBrowser = .wifiAware(.connecting(to: .allPairedDevices, from: service))
                let params = provider.configureParameters(parameters())
                let browser = NWBrowser(for: provider.makeDescriptor(), using: params)
                self.browser = browser
                browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
                    guard let self = self, self.browser === browser else { return }
                    for entry in results.prefix(4) { self.open(entry.endpoint, parameters: provider.configureParameters(self.parameters())) }
                }
                browser.stateUpdateHandler = { [weak self, weak browser] state in
                    guard let self = self, self.browser === browser else { return }
                    if case .failed = state { self.status("系统未能发现加速设备，原连接继续", active: false); self.stop() }
                }
                browser.start(queue: .main)
            }
            return ["started": true, "status": "等待已配对设备；可点按系统配对添加设备"]
        } catch { status("无法启用加速链路，原连接继续", active: false); stop(); return ["started": false, "status": "无法启用加速链路，原连接继续"] }
    }
    private func failure() -> NSError { NSError(domain: "DawnWiFiAware", code: 1) }
    private func open(_ endpoint: NWEndpoint, parameters: NWParameters) {
        guard proxies[endpoint] == nil, proxies.count < 4, let owner = owner else { return }
        let token = generation
        let proxy = DawnPeerProxy(endpoint: endpoint, remoteParameters: parameters)
        proxies[endpoint] = proxy
        proxy.onClose = { [weak self] in self?.proxies.removeValue(forKey: endpoint) }
        proxy.start { [weak self] port in
            guard let self = self, self.owner == owner, self.generation == token else { proxy.close(); return }
            if let port = port { self.emit?(["owner": owner, "type": "endpoint", "port": Int(port)]) }
        }
    }
    func pair(owner requested: String?) {
        guard requested == owner, pairingController == nil,
              let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        if isHost {
            guard let service = WAPublishableService.allServices[name] else { return }
            let provider: WAPublisherListener = .wifiAware(.connecting(to: service, from: .userSpecifiedDevices))
            guard DDDevicePairingViewController.isSupported(provider) else { status("系统配对暂不可用"); return }
            let controller = DDDevicePairingViewController(listenerProvider: provider, access: .default)
            pairingController = controller; presenter.present(controller, animated: true)
        } else {
            guard let service = WASubscribableService.allServices[name] else { return }
            let provider: WASubscriberBrowser = .wifiAware(.connecting(to: .userSpecifiedDevices, from: service))
            let params = provider.configureParameters(parameters())
            guard DDDevicePickerViewController.isSupported(provider.makeDescriptor(), using: params),
                  let controller = DDDevicePickerViewController(browseDescriptor: provider.makeDescriptor(), parameters: params, access: .default) else { status("系统配对暂不可用"); return }
            pairingController = controller; presenter.present(controller, animated: true)
            let token = generation
            pickerTask = Task { [weak self, weak controller] in
                do {
                    guard let controller = controller else { return }
                    let endpoint = try await controller.endpoint
                    guard !Task.isCancelled, let self = self, self.owner == requested, self.generation == token else { return }
                    self.open(endpoint, parameters: provider.configureParameters(self.parameters()))
                } catch { self?.status("配对未完成，原连接继续") }
            }
        }
    }
    private func status(_ text: String, active: Bool = true) {
        emit?(["owner": owner as Any, "type": "status", "status": text, "active": active])
    }
    func stop() {
        generation += 1
        owner = nil; pickerTask?.cancel(); pickerTask = nil
        pairingController?.dismiss(animated: false); pairingController = nil
        listener?.stateUpdateHandler = nil; listener?.cancel(); listener = nil
        browser?.stateUpdateHandler = nil; browser?.cancel(); browser = nil
        for pipe in Array(pipes.values) { pipe.close() }; pipes.removeAll()
        for proxy in Array(proxies.values) { proxy.close() }; proxies.removeAll()
    }
    deinit { stop() }
}
