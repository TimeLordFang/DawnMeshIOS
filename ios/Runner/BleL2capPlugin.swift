import Flutter
import CoreBluetooth

// The legacy Android manufacturer advertisement and versioned GATT discovery
// share the existing authenticated L2CAP wire protocol.
public final class BleL2capPlugin: NSObject, FlutterPlugin, CBCentralManagerDelegate, CBPeripheralDelegate, CBPeripheralManagerDelegate, StreamDelegate {
    private static let service = CBUUID(string: "7f75d4e0-7a46-4d74-9f8d-1e4bc5e4b004")
    private static let metadata = CBUUID(string: "7f75d4e1-7a46-4d74-9f8d-1e4bc5e4b004")
    private lazy var central = CBCentralManager(delegate: self, queue: .main)
    private lazy var peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
    private var peripherals = [String: CBPeripheral]()
    private var rooms = [String: AndroidBleRoom]()
    private var discovery = DawnDiscoveryLedger()
    private var lastReported = [String: TimeInterval]()
    private var metadataReads = [String: CBPeripheral]()
    private var metadataTimers = [String: Timer]()
    private var lastRead = [String: TimeInterval]()
    private var rssi = [String: Int]()
    private var preferenceObserver: NSObjectProtocol?
    private var peer: CBPeripheral?
    private var links = [String: Link]()
    private var scanning = false
    private let dataEvents = DawnEventStream()
    private let scanEvents = DawnEventStream()
    private var connectResult: FlutterResult?
    private var targetPSM: CBL2CAPPSM?
    private var awaitingMetadataDisconnect = false
    private var connectTimer: Timer?
    private var hostResult: FlutterResult?
    private var hostTimer: Timer?
    private var hosting = false
    private var publishing = false
    private var hostPSM: CBL2CAPPSM = 0
    private var roomName = ""
    private var members = 1
    private var authenticatedRelay = true
    private var maxAge: TimeInterval = 0.18
    private var watchdog: Timer?

    private final class Link {
        let channel: CBL2CAPChannel
        var reader = DawnFrameReader()
        var writer = DawnWriteQueue()
        var lastProgress = ProcessInfo.processInfo.systemUptime
        init(_ channel: CBL2CAPChannel) { self.channel = channel }
    }
    override init() {
        super.init()
        refreshTuning()
        preferenceObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshTuning() }
    }
    deinit { if let observer = preferenceObserver { NotificationCenter.default.removeObserver(observer) } }
    private func refreshTuning() {
        maxAge = max(0.02, min(0.3, (UserDefaults.standard.dictionary(forKey: "audioTuningParameters")?["maxRealtimeAgeMillis"] as? Double ?? 180) / 1000))
    }
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = BleL2capPlugin()
        let methods = FlutterMethodChannel(name: "dev.dawnmesh.intercom/ble_l2cap", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: methods)
        FlutterEventChannel(name: "dev.dawnmesh.intercom/ble_l2cap_data", binaryMessenger: registrar.messenger()).setStreamHandler(instance.dataEvents)
        FlutterEventChannel(name: "dev.dawnmesh.intercom/ble_l2cap_scan", binaryMessenger: registrar.messenger()).setStreamHandler(instance.scanEvents)
    }
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "isSupported": result(CBCentralManager.authorization != .denied && CBCentralManager.authorization != .restricted && central.state != .unsupported)
        case "startAdvertising":
            stop()
            roomName = args["roomName"] as? String ?? "蓝牙房"
            members = max(1, min(6, args["memberCount"] as? Int ?? 1))
            authenticatedRelay = args["authenticatedRelay"] as? Bool ?? true
            hosting = true; hostResult = result
            hostTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in self?.failHost("蓝牙房创建超时，请检查蓝牙开关和权限。") }
            if peripheralManager.state == .poweredOn { publish() }
            else if [.unauthorized, .unsupported, .poweredOff].contains(peripheralManager.state) { failHost("请开启蓝牙并允许应用使用蓝牙。") }
        case "updateMemberCount": members = max(1, min(6, args["memberCount"] as? Int ?? 1)); result(nil)
        case "startScan":
            guard central.state != .unauthorized, central.state != .unsupported else { result(false); return }
            scanning = true
            if central.state == .poweredOn { scan() }
            result(true)
        case "stopScan": stopScan(); result(nil)
        case "connectL2cap":
            guard !hosting, central.state == .poweredOn, let address = args["address"] as? String,
                  let peripheral = peripherals[address], let psm = args["psm"] as? Int, (1...255).contains(psm) else { result(false); return }
            disconnectClient(notify: false)
            connectResult = result; peer = peripheral; targetPSM = CBL2CAPPSM(psm)
            metadataReads.removeValue(forKey: address)
            metadataTimers.removeValue(forKey: address)?.invalidate()
            peripheral.delegate = self
            awaitingMetadataDisconnect = peripheral.state == .disconnecting
            if peripheral.state == .connected { peripheral.openL2CAPChannel(CBL2CAPPSM(psm)) }
            else if !awaitingMetadataDisconnect { central.connect(peripheral) }
            connectTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in self?.disconnectClient(notify: true) }
        case "sendL2capData":
            guard let bytes = args["data"] as? FlutterStandardTypedData else { result(false); return }
            result(send(bytes.data, realtime: args["realtime"] as? Bool ?? false, excluding: args["excludeAddress"] as? String))
        case "flush": for id in Array(links.keys) { drain(id) }; result(nil)
        case "stop": stop(); result(nil)
        default: result(FlutterMethodNotImplemented)
        }
    }
    private func publish() {
        guard hosting, !publishing, hostPSM == 0 else { return }
        publishing = true
        peripheralManager.publishL2CAPChannel(withEncryption: false)
    }
    private func failHost(_ message: String) {
        let completion = hostResult; hostResult = nil
        stop()
        completion?(FlutterError(code: "BLE_HOST_FAILED", message: message, details: nil))
    }
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn { if hosting { publish() } }
        else if peripheral.state != .unknown && peripheral.state != .resetting {
            publishing = false; hostPSM = 0
            for id in Array(links.keys) { closeLink(id) }
            if hostResult != nil { failHost("蓝牙不可用，请检查开关和权限。") }
            // An established host stays armed and republishes after radio recovery.
        }
    }
    public func peripheralManager(_ peripheral: CBPeripheralManager, didPublishL2CAPChannel PSM: CBL2CAPPSM, error: Error?) {
        publishing = false
        guard hosting else { if error == nil { peripheral.unpublishL2CAPChannel(PSM) }; return }
        guard error == nil, (1...255).contains(Int(PSM)) else { failHost("无法创建蓝牙 L2CAP 通道。请重试。"); return }
        hostPSM = PSM
        let service = CBMutableService(type: Self.service, primary: true)
        service.characteristics = [CBMutableCharacteristic(type: Self.metadata, properties: [.read], value: nil, permissions: [.readable])]
        peripheral.removeAllServices(); peripheral.add(service)
    }
    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard hosting, hostPSM > 0 else { return }
        guard error == nil else { failHost("无法发布蓝牙房间信息。"); return }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.service]])
    }
    public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        guard hosting else { return }
        guard error == nil else { failHost("蓝牙广播未能开启。"); return }
        hostTimer?.invalidate(); hostTimer = nil
        let completion = hostResult; hostResult = nil; completion?(true)
    }
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard hosting, hostPSM > 0, request.characteristic.uuid == Self.metadata else { peripheral.respond(to: request, withResult: .attributeNotFound); return }
        let bytes = DawnBleMetadata.encode(psm: Int(hostPSM), members: members, name: roomName)
        guard request.offset <= bytes.count else { peripheral.respond(to: request, withResult: .invalidOffset); return }
        request.value = Data(bytes.dropFirst(request.offset)); peripheral.respond(to: request, withResult: .success)
    }
    public func peripheralManager(_ peripheral: CBPeripheralManager, didOpen channel: CBL2CAPChannel?, error: Error?) {
        guard let channel = channel else { return }
        guard hosting, error == nil, channel.psm == hostPSM, links.count < 5 else { channel.inputStream.close(); channel.outputStream.close(); return }
        install(channel)
    }
    private func scan() {
        central.scanForPeripherals(withServices: [Self.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    private func stopScan() {
        scanning = false; central.stopScan()
        for peripheral in Array(metadataReads.values) { finishMetadata(peripheral) }
    }
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { if scanning { scan() } }
        else if central.state != .unknown && central.state != .resetting {
            disconnectClient(notify: true)
            for peripheral in Array(metadataReads.values) { finishMetadata(peripheral) }
        }
    }
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard scanning else { return }
        let id = peripheral.identifier.uuidString
        let now = ProcessInfo.processInfo.systemUptime
        guard let expired = discovery.observe(id, now: now, protecting: peer?.identifier.uuidString) else { return }
        for key in expired {
            if let old = metadataReads[key] { finishMetadata(old) }
            peripherals.removeValue(forKey: key); rooms.removeValue(forKey: key); lastReported.removeValue(forKey: key); lastRead.removeValue(forKey: key); rssi.removeValue(forKey: key)
        }
        peripherals[id] = peripheral; rssi[id] = RSSI.intValue
        if let bytes = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, let room = AndroidBleRoom.parse(bytes) {
            report(id, room: room, now: now)
        } else {
            if let room = rooms[id] { report(id, room: room, now: now) }
            guard metadataReads[id] == nil, metadataReads.count < 4, peer !== peripheral, now - (lastRead[id] ?? -.infinity) >= 3 else { return }
            lastRead[id] = now; metadataReads[id] = peripheral; peripheral.delegate = self
            metadataTimers[id] = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self, weak peripheral] _ in
                if let peripheral = peripheral { self?.finishMetadata(peripheral) }
            }
            central.connect(peripheral)
        }
    }
    private func report(_ id: String, room: AndroidBleRoom, now: TimeInterval) {
        let previous = rooms[id]
        let name = room.name == "蓝牙房" ? previous?.name ?? room.name : room.name
        rooms[id] = AndroidBleRoom(psm: room.psm, members: room.members, name: name)
        let changed = previous?.name != name || previous?.psm != room.psm || previous?.members != room.members
        guard scanning, changed || now - (lastReported[id] ?? -.infinity) >= 2 else { return }
        lastReported[id] = now
        scanEvents.sink?(["address": id, "roomName": name, "psm": room.psm, "memberCount": room.members, "rssi": rssi[id] ?? 0])
    }
    private func finishMetadata(_ peripheral: CBPeripheral) {
        let id = peripheral.identifier.uuidString
        metadataTimers.removeValue(forKey: id)?.invalidate()
        guard metadataReads.removeValue(forKey: id) != nil else { return }
        if peer !== peripheral { central.cancelPeripheralConnection(peripheral) }
    }
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if peer === peripheral, let psm = targetPSM { peripheral.openL2CAPChannel(psm) }
        else if metadataReads[peripheral.identifier.uuidString] != nil { peripheral.discoverServices([Self.service]) }
        else { central.cancelPeripheralConnection(peripheral) }
    }
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard metadataReads[peripheral.identifier.uuidString] != nil else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else { finishMetadata(peripheral); return }
        peripheral.discoverCharacteristics([Self.metadata], for: service)
    }
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard metadataReads[peripheral.identifier.uuidString] != nil else { return }
        guard error == nil, let characteristic = service.characteristics?.first(where: { $0.uuid == Self.metadata }) else { finishMetadata(peripheral); return }
        peripheral.readValue(for: characteristic)
    }
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard metadataReads[peripheral.identifier.uuidString] != nil, characteristic.uuid == Self.metadata else { return }
        if error == nil, let data = characteristic.value, let room = DawnBleMetadata.parse(data) { report(peripheral.identifier.uuidString, room: room, now: ProcessInfo.processInfo.systemUptime) }
        finishMetadata(peripheral)
    }
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if peer === peripheral { disconnectClient(notify: true) } else { finishMetadata(peripheral) }
    }
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peer === peripheral, awaitingMetadataDisconnect {
            awaitingMetadataDisconnect = false; central.connect(peripheral)
        } else if peer === peripheral { disconnectClient(notify: true) }
        else { finishMetadata(peripheral) }
    }
    public func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        guard peer === peripheral else { channel?.inputStream.close(); channel?.outputStream.close(); return }
        guard let channel = channel, error == nil else { disconnectClient(notify: true); return }
        install(channel)
        connectTimer?.invalidate(); connectTimer = nil
        let completion = connectResult; connectResult = nil; completion?(true)
    }
    private func install(_ channel: CBL2CAPChannel) {
        let id = channel.peer.identifier.uuidString
        closeLink(id)
        links[id] = Link(channel)
        for stream in [channel.inputStream as Stream, channel.outputStream as Stream] {
            stream.delegate = self; stream.schedule(in: .main, forMode: .common); stream.open()
        }
        if watchdog == nil { watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            for (id, link) in Array(self.links) where !link.writer.isEmpty && ProcessInfo.processInfo.systemUptime - link.lastProgress > 5 { self.closeLink(id, notify: true) }
        } }
    }
    private func send(_ bytes: Data, realtime: Bool, excluding: String?) -> Bool {
        var sent = false
        for (id, link) in Array(links) where id != excluding {
            let now = ProcessInfo.processInfo.systemUptime
            if link.writer.isEmpty { link.lastProgress = now }
            guard link.writer.append(bytes, realtime: realtime, now: now) else { closeLink(id, notify: true); continue }
            drain(id); sent = true
        }
        return sent
    }
    private func drain(_ id: String) {
        guard let link = links[id] else { return }
        guard let output = link.channel.outputStream else { closeLink(id, notify: true); return }
        do {
            try link.writer.drain(now: ProcessInfo.processInfo.systemUptime, maxAge: maxAge) { data in
                guard output.hasSpaceAvailable else { return 0 }
                let written = data.withUnsafeBytes { output.write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: data.count) }
                if written > 0 { link.lastProgress = ProcessInfo.processInfo.systemUptime }
                return written
            }
        } catch { closeLink(id, notify: true) }
    }
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        guard let (id, link) = links.first(where: { aStream === $0.value.channel.inputStream || aStream === $0.value.channel.outputStream }) else { return }
        switch eventCode {
        case .hasBytesAvailable:
            guard let input = aStream as? InputStream else { return }
            var bytes = [UInt8](repeating: 0, count: 2048)
            let count = input.read(&bytes, maxLength: bytes.count)
            if count <= 0 { closeLink(id, notify: true); return }
            do {
                for frame in try link.reader.append(Data(bytes.prefix(count))) {
                    if hosting {
                        if DawnBleMetadata.mayRelayFromClient(frame, authenticated: authenticatedRelay) { _ = send(frame, realtime: frame[0] == 1, excluding: id) }
                        if [3, 7, 8, 13, 16].contains(frame[0]) { continue }
                    }
                    dataEvents.sink?(["type": "data", "data": FlutterStandardTypedData(bytes: frame), "peerAddress": id])
                }
            } catch { closeLink(id, notify: true) }
        case .hasSpaceAvailable: drain(id)
        case .errorOccurred, .endEncountered: closeLink(id, notify: true)
        default: break
        }
    }
    private func closeLink(_ id: String, notify: Bool = false) {
        guard let link = links.removeValue(forKey: id) else { return }
        for stream in [link.channel.inputStream as Stream, link.channel.outputStream as Stream] {
            stream.delegate = nil; stream.close(); stream.remove(from: .main, forMode: .common)
        }
        if notify && !hosting { disconnectClient(notify: true) }
        if links.isEmpty { watchdog?.invalidate(); watchdog = nil }
    }
    private func disconnectClient(notify: Bool) {
        connectTimer?.invalidate(); connectTimer = nil
        let previous = peer; peer = nil; targetPSM = nil; awaitingMetadataDisconnect = false
        if let previous = previous { closeLink(previous.identifier.uuidString); central.cancelPeripheralConnection(previous) }
        let completion = connectResult; connectResult = nil; completion?(false)
        if notify && previous != nil { dataEvents.sink?(["type": "disconnected", "reason": "ios_l2cap_closed"]) }
    }
    private func stop() {
        hosting = false; publishing = false
        hostTimer?.invalidate(); hostTimer = nil
        let completion = hostResult; hostResult = nil; completion?(false)
        peripheralManager.stopAdvertising()
        if hostPSM > 0 { peripheralManager.unpublishL2CAPChannel(hostPSM); hostPSM = 0 }
        peripheralManager.removeAllServices()
        stopScan(); disconnectClient(notify: false)
        for id in Array(links.keys) { closeLink(id) }
    }
}

final class DawnEventStream: NSObject, FlutterStreamHandler {
    var sink: FlutterEventSink?
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? { sink = events; return nil }
    func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }
}
