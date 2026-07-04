import Foundation
import Network

final class BeastStreamClient {
    var onReady: (() -> Void)?
    var onSnapshot: ((BeastSnapshot) -> Void)?
    var onError: ((String) -> Void)?

    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let decoder = BeastDecoder()
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "scope.beast-stream")

    init(host: String, port: UInt16) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port) ?? 30002
    }

    func start() {
        let connection = NWConnection(host: host, port: port, using: .tcp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onReady?()
                self?.receive()
            case .failed(let error):
                self?.onError?("Beast stream failed: \(error.localizedDescription)")
                self?.cancel()
            case .waiting(let error):
                self?.onError?("Waiting for Beast stream: \(error.localizedDescription)")
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    func cancel() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty, let snapshot = self.decoder.ingest(data) {
                self.onSnapshot?(snapshot)
            }

            if let error {
                self.onError?("Beast receive failed: \(error.localizedDescription)")
                self.cancel()
                return
            }

            if isComplete {
                self.onError?("Beast stream closed")
                self.cancel()
                return
            }

            self.receive()
        }
    }
}
