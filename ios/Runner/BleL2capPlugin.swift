import Flutter
import CoreBluetooth

// Derived from SunsetRipple's CoreBluetooth host. iOS joins the existing
// Android manufacturer advertisement; incompatible iOS hosting is explicit.
public final class BleL2capPlugin: NSObject, FlutterPlugin, CBCentralManagerDelegate, CBPeripheralDelegate, StreamDelegate {
    private static let service = CBUUID(string: "7f75d4e0-7a46-4d74-9f8d-1e4bc5e4b004")
    private lazy var central = CBCentralManager(delegate: self, queue: .main)
    private var peripherals = [String: CBPeripheral]()
    private var rooms = [String: AndroidBleRoom]()
    private var peer: CBPeripheral?
    private var channel: CBL2CAPChannel?
    private var reader = DawnFrameReader()
    private var writer = DawnWriteQueue()
    private var scanning = false
    private var dataEvents = DawnEventStream()
    private var scanEvents = DawnEventStream()
    private var connectResult: FlutterResult?
    private var targetPSM: CBL2CAPPSM?
    private var connectTimer: Timer?
    private var maxAge: TimeInterval { max(0.02, min(0.3, (UserDefaults.standard.dictionary(forKey: "audioTuningParameters")?["maxRealtimeAgeMillis"] as? Double ?? 180) / 1000)) }

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
        case "startAdvertising": result(FlutterError(code: "IOS_BLE_HOST_UNSUPPORTED", message: "iOS 首版支持加入安卓蓝牙房；建房请使用 Wi-Fi、公网或融合房。", details: nil))
        case "updateMemberCount": result(nil)
        case "startScan":
            guard central.state != .unauthorized, central.state != .unsupported else { result(false); return }
            scanning = true
            if central.state == .poweredOn { scan() }
            result(true)
        case "stopScan": scanning = false; central.stopScan(); result(nil)
        case "connectL2cap":
            guard central.state == .poweredOn, let address = args["address"] as? String,
                  let peripheral = peripherals[address], let psm = args["psm"] as? Int, (1...255).contains(psm) else { result(false); return }
            disconnect(notify: false)
            connectResult = result; peer = peripheral; targetPSM = CBL2CAPPSM(psm)
            peripheral.delegate = self
            central.connect(peripheral)
            connectTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in self?.disconnect(notify: true) }
        case "sendL2capData":
            guard channel != nil, let bytes = args["data"] as? FlutterStandardTypedData else { result(false); return }
            guard writer.append(bytes.data, realtime: args["realtime"] as? Bool ?? false, now: ProcessInfo.processInfo.systemUptime) else {
                disconnect(notify: true); result(false); return
            }
            drain(); result(channel != nil)
        case "flush": drain(); result(nil)
        case "stop": scanning = false; central.stopScan(); disconnect(notify: false); result(nil)
        default: result(FlutterMethodNotImplemented)
        }
    }
    private func scan() {
        central.scanForPeripherals(withServices: [Self.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { if scanning { scan() } }
        else if central.state != .unknown && central.state != .resetting { disconnect(notify: true) }
    }
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let bytes = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let room = AndroidBleRoom.parse(bytes) else { return }
        let id = peripheral.identifier.uuidString
        if peripherals.count >= 64 && peripherals[id] == nil { return }
        peripherals[id] = peripheral
        let name = room.name == "蓝牙房" ? rooms[id]?.name ?? room.name : room.name
        rooms[id] = AndroidBleRoom(psm: room.psm, members: room.members, name: name)
        scanEvents.sink?(["address": id, "roomName": name, "psm": room.psm, "memberCount": room.members, "rssi": RSSI.intValue])
    }
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peer === peripheral, let psm = targetPSM else { central.cancelPeripheralConnection(peripheral); return }
        peripheral.openL2CAPChannel(psm)
    }
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if peer === peripheral { disconnect(notify: true) }
    }
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peer === peripheral { disconnect(notify: true) }
    }
    public func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        guard peer === peripheral else { channel?.inputStream.close(); channel?.outputStream.close(); return }
        guard let channel = channel, error == nil else { disconnect(notify: true); return }
        self.channel = channel
        for stream in [channel.inputStream as Stream, channel.outputStream as Stream] {
            stream.delegate = self; stream.schedule(in: .main, forMode: .common); stream.open()
        }
        connectTimer?.invalidate(); connectTimer = nil
        let completion = connectResult; connectResult = nil; completion?(true)
    }
    private func drain() {
        guard let output = channel?.outputStream else { return }
        do {
            try writer.drain(now: ProcessInfo.processInfo.systemUptime, maxAge: maxAge) { data in
                guard output.hasSpaceAvailable else { return 0 }
                return data.withUnsafeBytes { output.write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: data.count) }
            }
        } catch { disconnect(notify: true) }
    }
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        guard aStream === channel?.inputStream || aStream === channel?.outputStream else { return }
        switch eventCode {
        case .hasBytesAvailable:
            guard let input = aStream as? InputStream else { return }
            var bytes = [UInt8](repeating: 0, count: 2048)
            let count = input.read(&bytes, maxLength: bytes.count)
            if count <= 0 { disconnect(notify: true); return }
            do {
                for frame in try reader.append(Data(bytes.prefix(count))) {
                    dataEvents.sink?(["type": "data", "data": FlutterStandardTypedData(bytes: frame), "peerAddress": peer?.identifier.uuidString ?? "unknown"])
                }
            } catch { disconnect(notify: true) }
        case .hasSpaceAvailable: drain()
        case .errorOccurred, .endEncountered: disconnect(notify: true)
        default: break
        }
    }
    private func disconnect(notify: Bool) {
        connectTimer?.invalidate(); connectTimer = nil
        let previous = peer; peer = nil; targetPSM = nil
        if let channel = channel {
            for stream in [channel.inputStream as Stream, channel.outputStream as Stream] {
                stream.delegate = nil; stream.close(); stream.remove(from: .main, forMode: .common)
            }
        }
        channel = nil; reader = DawnFrameReader(); writer = DawnWriteQueue()
        if let previous = previous { central.cancelPeripheralConnection(previous) }
        let completion = connectResult; connectResult = nil; completion?(false)
        if notify { dataEvents.sink?(["type": "disconnected", "reason": "ios_l2cap_closed"]) }
    }
}

final class DawnEventStream: NSObject, FlutterStreamHandler {
    var sink: FlutterEventSink?
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? { sink = events; return nil }
    func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }
}
