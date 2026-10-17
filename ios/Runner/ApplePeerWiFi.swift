import Foundation
import Network

// Preserve the existing TCP protocol and PAKE. Only the network path changes:
// Bonjour service endpoints retain the IPv6 interface scope required by AWDL.
final class DawnApplePeerWiFi {
    static let serviceType = "_dawnmesh._tcp"
    private var browser: NWBrowser?
    private var listener: NWListener?
    private let publicationName = UUID().uuidString
    private var retainedEndpoints = [String: NWEndpoint]()
    private var endpoints = [String: NWEndpoint]()
    private var endpointIDs = [NWEndpoint: String]()
    private var clients = [String: DawnPeerProxy]()
    private var hostPipes = [UUID: DawnPeerPipe]()
    var onRoom: (([String: Any]) -> Void)?
    var onRemoved: ((String) -> Void)?
    var onError: ((String) -> Void)?

    static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
    func startBrowsing() {
        stopBrowsing()
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: "local."), using: Self.parameters())
        self.browser = browser
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            guard let self = self, self.browser === browser else { return }
            if case .failed(let error) = state {
                for id in Array(self.endpoints.keys) { self.onRemoved?(id) }
                self.stopBrowsing(); self.onError?("附近 Wi-Fi 发现失败：\(error)")
            }
            if case .waiting(let error) = state { self.onError?("等待本地网络权限或 Wi-Fi 恢复：\(error)") }
        }
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            guard let self = self, self.browser === browser else { return }
            let present = Set(results.map(\.endpoint))
            for (endpoint, id) in self.endpointIDs where !present.contains(endpoint) {
                self.endpoints.removeValue(forKey: id); self.endpointIDs.removeValue(forKey: endpoint); self.onRemoved?(id)
            }
            for result in results {
                guard case .bonjour(let txt) = result.metadata,
                      let roomID = txt["roomId"], !roomID.isEmpty,
                      let name = txt["roomName"], let nickname = txt["hostNickname"],
                      let port = Int(txt["port"] ?? "8988"), (1...65535).contains(port),
                      self.endpointIDs[result.endpoint] != nil || self.endpoints.count < 64 else { continue }
                let id = self.endpointIDs[result.endpoint] ?? UUID().uuidString
                self.endpointIDs[result.endpoint] = id; self.endpoints[id] = result.endpoint
                self.onRoom?(["service": id, "peerService": id, "roomId": String(roomID.prefix(64)), "roomName": String(name.prefix(64)), "hostNickname": String(nickname.prefix(64)), "port": port, "members": max(0, min(16, Int(txt["members"] ?? "1") ?? 1)), "address": "127.0.0.1", "type": "room"])
            }
        }
        browser.start(queue: .main)
    }
    func advertise(values: [String: String], port: UInt16) throws {
        if listener == nil {
            let listener = try NWListener(using: Self.parameters())
            self.listener = listener
            listener.newConnectionHandler = { [weak self, weak listener] connection in
                guard let self = self, self.listener === listener, self.hostPipes.count < 15 else { connection.cancel(); return }
                let id = UUID()
                let local = NWConnection(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!, using: Self.parameters())
                let pipe = DawnPeerPipe(connection, local)
                self.hostPipes[id] = pipe
                pipe.onClose = { [weak self] in self?.hostPipes.removeValue(forKey: id) }
                pipe.start()
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self = self, self.listener === listener else { return }
                if case .failed(let error) = state { self.onError?("Wi-Fi 直连监听失败：\(error)"); self.stopAdvertising() }
            }
            listener.service = NWListener.Service(name: publicationName, type: Self.serviceType, txtRecord: NWTXTRecord(values))
            listener.start(queue: .main)
        } else {
            listener?.service = NWListener.Service(name: publicationName, type: Self.serviceType, txtRecord: NWTXTRecord(values))
        }
    }
    func open(_ service: String, completion: @escaping ([String: Any]?) -> Void) {
        guard let endpoint = endpoints[service] ?? retainedEndpoints[service], clients.count < 4 else { completion(nil); return }
        if retainedEndpoints.count >= 4, retainedEndpoints[service] == nil, let oldest = retainedEndpoints.keys.first { retainedEndpoints.removeValue(forKey: oldest) }
        retainedEndpoints[service] = endpoint
        let id = UUID().uuidString
        let proxy = DawnPeerProxy(endpoint: endpoint)
        clients[id] = proxy
        proxy.onClose = { [weak self] in self?.clients.removeValue(forKey: id) }
        proxy.start { port in completion(port.map { ["port": Int($0), "connectionId": id] }) }
    }
    func close(_ id: String) { clients.removeValue(forKey: id)?.close() }
    func stopBrowsing() {
        browser?.cancel(); browser = nil
        endpoints.removeAll(); endpointIDs.removeAll()
        // Active room connections outlive the home-page discovery browser.
    }
    func stopAdvertising() {
        listener?.cancel(); listener = nil
        for pipe in Array(hostPipes.values) { pipe.close() }
        hostPipes.removeAll()
    }
}

// Exactly one chunk per direction may be in flight. TCP backpressure is
// propagated, instead of enqueueing unbounded audio/chat data on the main queue.
final class DawnPeerPipe {
    private let a: NWConnection
    private let b: NWConnection
    private var readyA = false
    private var readyB = false
    private var closed = false
    private var pumping = false
    private var timeout: DispatchWorkItem?
    var onClose: (() -> Void)?
    init(_ a: NWConnection, _ b: NWConnection) { self.a = a; self.b = b }
    func start() {
        let timeout = DispatchWorkItem { [weak self] in self?.close() }
        self.timeout = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)
        a.stateUpdateHandler = { [weak self] state in self?.state(state, first: true) }
        b.stateUpdateHandler = { [weak self] state in self?.state(state, first: false) }
        a.start(queue: .main); b.start(queue: .main)
    }
    private func state(_ state: NWConnection.State, first: Bool) {
        guard !closed else { return }
        switch state {
        case .ready:
            if first { readyA = true } else { readyB = true }
            if readyA && readyB && !pumping { pumping = true; timeout?.cancel(); pump(a, to: b); pump(b, to: a) }
        case .failed, .cancelled: close()
        default: break
        }
    }
    private func pump(_ source: NWConnection, to target: NWConnection) {
        guard !closed else { return }
        source.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            guard let self = self, !self.closed else { return }
            guard error == nil else { self.close(); return }
            if let data = data, !data.isEmpty {
                target.send(content: data, completion: .contentProcessed { [weak self] error in
                    guard let self = self else { return }
                    if error != nil || complete { self.close() } else { self.pump(source, to: target) }
                })
            } else if complete { self.close() }
            else { self.pump(source, to: target) }
        }
    }
    func close() {
        guard !closed else { return }
        closed = true; timeout?.cancel(); timeout = nil
        a.stateUpdateHandler = nil; b.stateUpdateHandler = nil; a.cancel(); b.cancel()
        let completion = onClose; onClose = nil; completion?()
    }
}

final class DawnPeerProxy {
    private let endpoint: NWEndpoint
    private var listener: NWListener?
    private var pipe: DawnPeerPipe?
    private var completion: ((UInt16?) -> Void)?
    private var timeout: DispatchWorkItem?
    private var closed = false
    var onClose: (() -> Void)?
    init(endpoint: NWEndpoint) { self.endpoint = endpoint }
    func start(completion: @escaping (UInt16?) -> Void) {
        self.completion = completion
        do {
            let parameters = DawnApplePeerWiFi.parameters()
            parameters.includePeerToPeer = false
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                guard let self = self, !self.closed else { return }
                switch state {
                case .ready:
                    let result = self.completion; self.completion = nil; result?(self.listener?.port?.rawValue)
                case .failed, .cancelled: self.close()
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self = self, !self.closed, self.pipe == nil else { connection.cancel(); return }
                self.timeout?.cancel(); self.listener?.stateUpdateHandler = nil; self.listener?.cancel(); self.listener = nil
                let remote = NWConnection(to: self.endpoint, using: DawnApplePeerWiFi.parameters())
                let pipe = DawnPeerPipe(connection, remote)
                self.pipe = pipe
                pipe.onClose = { [weak self] in self?.close() }
                pipe.start()
            }
            let timeout = DispatchWorkItem { [weak self] in self?.close() }
            self.timeout = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
            listener.start(queue: .main)
        } catch { close() }
    }
    func close() {
        guard !closed else { return }
        closed = true; timeout?.cancel(); timeout = nil
        listener?.stateUpdateHandler = nil; listener?.cancel(); listener = nil
        pipe?.close(); pipe = nil
        let result = completion; completion = nil; result?(nil)
        let done = onClose; onClose = nil; done?()
    }
}
