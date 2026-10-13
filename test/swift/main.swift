import Foundation
var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message); checks += 1
}
let packet = Data([11, 2, 255, 255, 0, 3, 4, 5, 6])
for split in 0...packet.count {
    var reader = DawnFrameReader()
    let a = try reader.append(packet.prefix(split))
    let b = try reader.append(packet.dropFirst(split))
    expect(a + b == [packet], "Split \(split)")
}
var reader = DawnFrameReader()
let coalesced = try reader.append(packet + packet)
expect(coalesced == [packet, packet], "Coalesced frames")
var maximum = Data([11, 1, 0, 1, 2, 0]); maximum.append(Data(repeating: 10, count: 512))
let maximumFrames = try reader.append(maximum)
expect(maximumFrames == [maximum], "512-byte payload")
do { _ = try reader.append(Data([11, 1, 0, 1, 2, 1])); fatalError("Oversized frame accepted") } catch { checks += 1 }
do { _ = try reader.append(Data([255, 1, 0, 1, 0, 0])); fatalError("Invalid type accepted") } catch { checks += 1 }
let room = AndroidBleRoom.parse(Data([255, 255, 0, 129, 3] + Array("测试房".utf8)))
expect(room?.psm == 129 && room?.members == 3 && room?.name == "测试房", "Android manufacturer record")
expect(AndroidBleRoom.parse(Data([255, 255, 0, 129, 3]))?.name == "蓝牙房", "Header-only advertisement")
expect(AndroidBleRoom.parse(Data([255, 255, 1, 0, 3])) == nil, "PSM range")
expect(AndroidBleRoom.parse(Data([255, 255, 0, 129, 7])) == nil, "Six member cap")
expect(AndroidBleRoom.parse(Data([254, 255, 0, 129, 3])) == nil, "Company ID")
var queue = DawnWriteQueue(); var sent = Data()
expect(queue.append(packet, realtime: true, now: 0), "Enqueue audio")
try queue.drain(now: 0, maxAge: 0.1) { suffix in sent.append(suffix.prefix(2)); return 2 }
try queue.drain(now: 1, maxAge: 0.1) { suffix in sent.append(suffix); return suffix.count }
expect(sent == packet && queue.isEmpty, "Partially sent old audio must finish")
expect(queue.append(packet, realtime: true, now: 0), "Enqueue stale audio")
expect(queue.append(packet, realtime: false, now: 0), "Enqueue control")
sent.removeAll()
try queue.drain(now: 1, maxAge: 0.1) { suffix in sent.append(suffix); return suffix.count }
expect(sent == packet, "Drop only unwritten stale realtime, retain control")
var jitter = DawnJitterQueue(); jitter.prebuffer = 2
jitter.append(sequence: 65535, packet: Data([1]), now: 1)
jitter.append(sequence: 0, packet: Data([2]), now: 1.02)
expect(jitter.pop() == Data([1]), "First sequence")
expect(jitter.pop() == Data([2]), "Sequence wraparound")
jitter.append(sequence: 65535, packet: Data([9]), now: 1.03)
expect(jitter.pop() == Data(), "Late duplicate ignored and PLC requested")
expect(jitter.pop() == Data(), "PLC bounded")
expect(jitter.pop() == nil, "Silence after PLC bound")
jitter.append(sequence: 10, packet: Data([3]), now: 2)
jitter.append(sequence: 11, packet: Data([4]), now: 2.02)
expect(jitter.pop() == Data([3]), "Resume after PTT silence")
print("Swift wire/BLE/write queue/jitter: \(checks) checks passed")
