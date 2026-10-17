import Foundation

// Same six-byte big-endian framing and 512-byte cap as Android 1.1.0.
struct DawnFrameReader {
    private var buffer = Data()
    mutating func append(_ bytes: Data) throws -> [Data] {
        buffer.append(bytes)
        var frames = [Data]()
        var offset = 0
        while buffer.count - offset >= 6 {
            let length = Int(buffer[offset + 4]) << 8 | Int(buffer[offset + 5])
            guard length <= 512, (1...19).contains(buffer[offset]) else {
                buffer.removeAll()
                throw NSError(domain: "DawnFrame", code: 1)
            }
            guard buffer.count - offset >= length + 6 else { break }
            frames.append(buffer.subdata(in: offset..<(offset + length + 6)))
            offset += length + 6
        }
        if offset > 0 { buffer = Data(buffer.dropFirst(offset)) }
        return frames
    }
}

struct AndroidBleRoom {
    let psm: Int
    let members: Int
    let name: String
    // CoreBluetooth keeps the little-endian company ID in manufacturer data.
    static func parse(_ bytes: Data) -> AndroidBleRoom? {
        guard bytes.count >= 5, bytes[0] == 255, bytes[1] == 255 else { return nil }
        let psm = Int(bytes[2]) << 8 | Int(bytes[3])
        let members = Int(bytes[4])
        guard (1...255).contains(psm), (1...6).contains(members) else { return nil }
        let text = String(data: bytes.dropFirst(5), encoding: .utf8) ?? ""
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = !clean.isEmpty && !clean.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        return AndroidBleRoom(psm: psm, members: members, name: valid ? String(clean.prefix(64)) : "蓝牙房")
    }
}

// A byte-stream write may consume only a prefix. Never discard its remainder.
struct DawnWriteQueue {
    private struct Item { var bytes: Data; var offset = 0; let realtime: Bool; let created: TimeInterval }
    private var items = [Item]()
    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }
    mutating func append(_ data: Data, realtime: Bool, now: TimeInterval) -> Bool {
        guard items.count < 256 else { return false }
        items.append(Item(bytes: data, realtime: realtime, created: now))
        return true
    }
    mutating func drain(now: TimeInterval, maxAge: TimeInterval,
                        write: (Data) -> Int) throws {
        while !items.isEmpty {
            if items[0].realtime && items[0].offset == 0 && now - items[0].created > maxAge {
                items.removeFirst(); continue
            }
            let suffix = Data(items[0].bytes.dropFirst(items[0].offset))
            let sent = write(suffix)
            if sent < 0 { throw NSError(domain: "DawnWrite", code: 1) }
            if sent == 0 { return }
            items[0].offset += sent
            if items[0].offset == items[0].bytes.count { items.removeFirst() }
            else { return }
        }
    }
}

struct DawnJitterQueue {
    var prebuffer = 6
    var maxFrames = 24
    var concealmentLimit = 2
    private var packets = [UInt16: Data]()
    private var next: UInt16?
    private var started = false
    private var misses = 0
    private var lastArrival: TimeInterval = 0
    mutating func append(sequence: UInt16, packet: Data, now: TimeInterval) {
        if now - lastArrival > 0.4 {
            packets.removeAll(); next = sequence; started = false; misses = 0
        }
        lastArrival = now
        if let expected = next {
            let distance = sequence &- expected
            if distance > 32767 { return } // Late / already played, including wraparound.
        } else { next = sequence }
        packets[sequence] = packet
        if packets.count > maxFrames, let expected = next {
            let oldest = packets.keys.min { ($0 &- expected) < ($1 &- expected) }!
            packets.removeValue(forKey: oldest); next = oldest &+ 1
        }
    }
    // nil means silence; empty Data requests one 20ms Opus PLC frame.
    mutating func pop() -> Data? {
        if !started {
            guard packets.count >= prebuffer else { return nil }
            started = true
        }
        guard let expected = next else { return nil }
        next = expected &+ 1
        if let packet = packets.removeValue(forKey: expected) { misses = 0; return packet }
        misses += 1
        if misses <= concealmentLimit { return Data() }
        started = false
        next = packets.keys.min { ($0 &- expected) < ($1 &- expected) }
        return nil
    }
}

// Bounded scan metadata, independent of CoreBluetooth for deterministic tests.
struct DawnDiscoveryLedger {
    private var seen = [String: TimeInterval]()
    let capacity: Int
    let ttl: TimeInterval
    init(capacity: Int = 64, ttl: TimeInterval = 30) { self.capacity = capacity; self.ttl = ttl }
    mutating func observe(_ id: String, now: TimeInterval, protecting: String?) -> [String]? {
        var removed = seen.compactMap { key, time in key != protecting && now - time > ttl ? key : nil }
        for key in removed { seen.removeValue(forKey: key) }
        if seen[id] == nil && seen.count >= capacity {
            guard let oldest = seen.filter({ $0.key != protecting }).min(by: { $0.value < $1.value })?.key else { return nil }
            seen.removeValue(forKey: oldest); removed.append(oldest)
        }
        seen[id] = now
        return removed
    }
}

// Cross-platform GATT metadata: version(1), PSM(big endian,2), members(1), UTF-8 name.
// Discovery is untrusted. Admission and encrypted frame validation remain mandatory.
struct DawnBleMetadata {
    static func encode(psm: Int, members: Int, name: String) -> Data {
        var bytes = Data([1, UInt8((psm >> 8) & 255), UInt8(psm & 255), UInt8(max(1, min(6, members)))])
        var text = ""
        for scalar in name.unicodeScalars where !CharacterSet.controlCharacters.contains(scalar) {
            let next = text + String(scalar)
            if next.utf8.count > 64 { break }
            text = next
        }
        bytes.append(contentsOf: text.utf8)
        return bytes
    }
    static func parse(_ bytes: Data) -> AndroidBleRoom? {
        guard (4...68).contains(bytes.count), bytes[0] == 1,
              let text = String(data: bytes.dropFirst(4), encoding: .utf8),
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        let psm = Int(bytes[1]) << 8 | Int(bytes[2])
        let members = Int(bytes[3])
        guard (1...255).contains(psm), (1...6).contains(members) else { return nil }
        return AndroidBleRoom(psm: psm, members: members, name: text.isEmpty ? "蓝牙房" : text)
    }
    static func mayRelayFromClient(_ frame: Data, authenticated: Bool) -> Bool {
        guard let type = frame.first else { return false }
        if [3, 7, 8, 13, 16].contains(type) { return false }
        // Fragments carry the original control type in their first payload byte.
        if type == 19, frame.count > 6, [3, 7, 8, 13, 16].contains(frame[6]) { return false }
        return !(authenticated && type == 11)
    }
}
