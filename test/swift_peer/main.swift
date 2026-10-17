import Foundation
import Network

var failure: String?
var finished = false
var echoConnections = [NWConnection]()
var proxy: DawnPeerProxy?
var client: NWConnection?
var received = Data()
var closed = 0
let payload = Data((0..<524_288).map { UInt8($0 % 251) })
let listener = try NWListener(using: .tcp, on: .any)
func echo(_ connection: NWConnection) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, complete, error in
        if let data = data, !data.isEmpty {
            connection.send(content: data, completion: .contentProcessed { error in
                if error == nil && !complete { echo(connection) } else { connection.cancel() }
            })
        } else if error == nil && !complete { echo(connection) }
        else { connection.cancel() }
    }
}
func receive() {
    client?.receive(minimumIncompleteLength: 1, maximumLength: 317) { data, _, complete, error in
        if let data = data { received.append(data) }
        if received.count >= payload.count {
            if received != payload { failure = "Byte stream corrupted or reordered" }
            client?.cancel()
        } else if error != nil || complete { failure = "Unexpected EOF"; finished = true }
        else { receive() }
    }
}
listener.newConnectionHandler = { connection in
    echoConnections.append(connection)
    connection.stateUpdateHandler = { state in if case .ready = state { echo(connection) } }
    connection.start(queue: .main)
}
listener.stateUpdateHandler = { state in
    guard case .ready = state, let port = listener.port else { return }
    let value = DawnPeerProxy(endpoint: .hostPort(host: .ipv4(.loopback), port: port))
    proxy = value
    value.onClose = { closed += 1; finished = true }
    value.start { port in
        guard let port = port else { failure = "Loopback proxy failed"; finished = true; return }
        let connection = NWConnection(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        client = connection
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                receive()
                connection.send(content: payload, completion: .contentProcessed { error in
                    if error != nil { failure = "Send failed"; finished = true }
                })
            }
        }
        connection.start(queue: .main)
    }
}
listener.start(queue: .main)
let deadline = Date().addingTimeInterval(20)
while !finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
precondition(finished, "Network proxy test timed out")
precondition(failure == nil, failure ?? "")
precondition(received == payload && closed == 1, "Data and disconnect must propagate exactly once")
proxy?.close(); proxy?.close()
precondition(closed == 1, "Closing proxy must be idempotent")
client?.cancel(); listener.cancel()
for connection in echoConnections { connection.cancel() }
print("Apple peer TCP proxy: 512 KiB ordered bidirectional echo and disconnect passed")
