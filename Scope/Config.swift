import Foundation

enum ReceiverLocationMode: String, Codable, CaseIterable, Identifiable {
    case local
    case remote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return "Local"
        case .remote: return "Remote"
        }
    }

    var detail: String {
        switch self {
        case .local: return "Local receiver support is not available yet"
        case .remote: return "Connect to an ADS-B receiver on your network"
        }
    }
}

enum DataSourceMode: String, Codable, CaseIterable, Identifiable {
    case beastBinary
    case httpJSON

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beastBinary: return "Beast Binary"
        case .httpJSON: return "HTTP JSON"
        }
    }

    var detail: String {
        switch self {
        case .beastBinary: return "Low-latency TCP stream, binary ADS-B parsing"
        case .httpJSON: return "Structured /data/aircraft.json if web server is enabled"
        }
    }
}

struct Config: Codable {
    var receiverLocationMode: ReceiverLocationMode = .remote
    var dataSourceMode: DataSourceMode = .beastBinary
    var beastHost: String = "192.168.1.146"
    var beastPort: UInt16 = 30002
    var httpEndpoint: String = "http://192.168.1.146:8080"
    var endpoint: String = "http://192.168.1.146:8080"
    var refreshMs: Int = 250
    var mapCenterLat: Double = 52.022
    var mapCenterLon: Double = 0.330
    var metadataCacheTTL: Double = 86400

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Config()
        receiverLocationMode = try container.decodeIfPresent(ReceiverLocationMode.self, forKey: .receiverLocationMode) ?? fallback.receiverLocationMode
        dataSourceMode = try container.decodeIfPresent(DataSourceMode.self, forKey: .dataSourceMode) ?? fallback.dataSourceMode
        beastHost = try container.decodeIfPresent(String.self, forKey: .beastHost) ?? fallback.beastHost
        beastPort = try container.decodeIfPresent(UInt16.self, forKey: .beastPort) ?? fallback.beastPort
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? fallback.endpoint
        httpEndpoint = try container.decodeIfPresent(String.self, forKey: .httpEndpoint) ?? endpoint
        refreshMs = try container.decodeIfPresent(Int.self, forKey: .refreshMs) ?? fallback.refreshMs
        mapCenterLat = try container.decodeIfPresent(Double.self, forKey: .mapCenterLat) ?? fallback.mapCenterLat
        mapCenterLon = try container.decodeIfPresent(Double.self, forKey: .mapCenterLon) ?? fallback.mapCenterLon
        metadataCacheTTL = try container.decodeIfPresent(Double.self, forKey: .metadataCacheTTL) ?? fallback.metadataCacheTTL
    }

    var activeEndpointDescription: String {
        switch receiverLocationMode {
        case .local:
            return "Local receiver"
        case .remote:
            switch dataSourceMode {
            case .beastBinary:
                return "\(beastHost):\(beastPort)"
            case .httpJSON:
                return httpEndpoint
            }
        }
    }

    static var configURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scope")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: configURL),
              var config = try? JSONDecoder().decode(Config.self, from: data)
        else { return Config() }

        if config.httpEndpoint.isEmpty {
            config.httpEndpoint = config.endpoint
        }
        return config
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Config.configURL)
    }
}
