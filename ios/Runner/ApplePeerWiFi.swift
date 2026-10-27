import Foundation
import Network

// Each discovery owner has its own browser/listener. Endpoint proxies outlive
// browsing, so popping a discovery page does not terminate an active room.
final class DawnApplePeerWiFi {
    static let serviceType = "_dawnmesh._tcp"
    private final class Browse {
        let browser: NWBrowser
        var endpoints = [NWEndpoint: String]()
        init(_ browser: NWBrowser) { self.browser = browser }
    }
    private final class Publication {
        let listener: NWListener
        let port: UInt16
        let name = UUID().uuidString
        var pipes = [UUID: DawnPeerPipe]()
        init(_ listener: NWListener, port: UInt16) { self.listener = listener; self.port = port }
        func close() {
            listener.cancel()
            for pipe in Array(pipes.values) { pipe.close() }
            pipes.removeAll()
        }
    }
    private var browsers = [String: Browse]()
    private var publications = [String: Publication]()
    private var retainedEndpoints = [String: NWEndpoint]()
    private var endpoints = [String: NWEndpoint]()
    private var clients = [String: DawnPeerProxy]()
    var onRoom: ((String, [String: Any]) -> Void)?
    var onRemoved: ((String, String) -> Void)?
    var onError: ((String, String) -> Void)?

    static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
    func startBrowsing(id: String = "default", serviceType: String = DawnApplePeerWiFi.serviceType) {
        stopBrowsing(id: id)
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: "local."), using: Self.parameters())
        let state = Browse(browser)
        browsers[id] = state
        browser.stateUpdateHandler = { [weak self, weak state] update in
            guard let self = self, let state = state, self.browsers[id] === state else { return }
            if case .failed(let error) = update {
                for endpointID in state.endpoints.values { self.onRemoved?(id, endpointID) }
                self.stopBrowsing(id: id); self.onError?(id, "附近 Wi-Fi 发现失败：\(error)")
            }
            if case .waiting(let error) = update { self.onError?(id, "等待本地网络权限或 Wi-Fi 恢复：\(error)") }
        }
        browser.browseResultsChangedHandler = { [weak self, weak state] results, _ in
            guard let self = self, let state = state, self.browsers[id] === state else { return }
            let present = Set(results.map(\.endpoint))
            for (endpoint, endpointID) in Array(state.endpoints) where !present.contains(endpoint) {
                self.endpoints.removeValue(forKey: endpointID)
                state.endpoints.removeValue(forKey: endpoint)
                self.onRemoved?(id, endpointID)
            }
            for result in results {
                if case .service(let name, _, _, _) = result.endpoint,
                   self.publications.values.contains(where: { $0.name == name }) { continue }
                guard case .bonjour(let txt) = result.metadata,
                      let roomID = txt["roomId"], !roomID.isEmpty,
                      let name = txt["roomName"], let nickname = txt["hostNickname"],
                      let port = Int(txt["port"] ?? "8988"), (1...65535).contains(port),
                      state.endpoints[result.endpoint] != nil || state.endpoints.count < 64 else { continue }
                let endpointID = state.endpoints[result.endpoint] ?? UUID().uuidString
                state.endpoints[result.endpoint] = endpointID; self.endpoints[endpointID] = result.endpoint
                self.onRoom?(id, ["service": endpointID, "peerService": endpointID, "roomId": String(roomID.prefix(64)), "roomName": String(name.prefix(64)), "hostNickname": String(nickname.prefix(64)), "port": port, "members": max(0, min(16, Int(txt["members"] ?? "1") ?? 1)), "address": "127.0.0.1", "type": "room"])
            }
        }
        browser.start(queue: .main)
    }
    func advertise(values: [String: String], port: UInt16, id: String = "default", serviceType: String = DawnApplePeerWiFi.serviceType) throws {
        if let current = publications[id], current.port == port {
            current.listener.service = NWListener.Service(name: current.name, type: serviceType, txtRecord: NWTXTRecord(values))
            return
        }
        stopAdvertising(id: id)
        let listener = try NWListener(using: Self.parameters())
        let publication = Publication(listener, port: port)
        publications[id] = publication
        listener.newConnectionHandler = { [weak self, weak publication] connection in
            guard let self = self, let publication = publication,
                  self.publications[id] === publication, publication.pipes.count < 15 else { connection.cancel(); return }
            let pipeID = UUID()
            let local = NWConnection(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!, using: Self.parameters())
            let pipe = DawnPeerPipe(connection, local)
            publication.pipes[pipeID] = pipe
            pipe.onClose = { [weak publication] in publication?.pipes.removeValue(forKey: pipeID) }
            pipe.start()
        }
        listener.stateUpdateHandler = { [weak self, weak publication] update in
            guard let self = self, let publication = publication, self.publications[id] === publication else { return }
            if case .failed(let error) = update { self.onError?(id, "Wi-Fi 点对点监听失败：\(error)"); self.stopAdvertising(id: id) }
        }
        listener.service = NWListener.Service(name: publication.name, type: serviceType, txtRecord: NWTXTRecord(values))
        listener.start(queue: .main)
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
    func stopBrowsing(id: String = "default") {
        guard let state = browsers.removeValue(forKey: id) else { return }
        state.browser.cancel()
        for endpointID in state.endpoints.values { endpoints.removeValue(forKey: endpointID) }
    }
    func stopAdvertising(id: String = "default") { publications.removeValue(forKey: id)?.close() }
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
    private let remoteParameters: NWParameters?
    private var listener: NWListener?
    private var pipe: DawnPeerPipe?
    private var completion: ((UInt16?) -> Void)?
    private var timeout: DispatchWorkItem?
    private var closed = false
    var onClose: (() -> Void)?
    init(endpoint: NWEndpoint, remoteParameters: NWParameters? = nil) { self.endpoint = endpoint; self.remoteParameters = remoteParameters }
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
                let remote = NWConnection(to: self.endpoint, using: self.remoteParameters ?? DawnApplePeerWiFi.parameters())
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
