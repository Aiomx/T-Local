import Foundation
import Network

public struct LatencyResult: Codable, Equatable, Sendable {
    public var endpoint: URL
    public var milliseconds: Double
    public var statusCode: Int?

    public init(endpoint: URL, milliseconds: Double, statusCode: Int? = nil) {
        self.endpoint = endpoint
        self.milliseconds = milliseconds
        self.statusCode = statusCode
    }
}

public struct IPGeolocationResult: Codable, Equatable, Sendable {
    public var ipAddress: String
    public var countryCode: String?
    public var raw: [String: String]

    public init(ipAddress: String, countryCode: String? = nil, raw: [String: String] = [:]) {
        self.ipAddress = ipAddress
        self.countryCode = countryCode
        self.raw = raw
    }
}

public struct DNSLeakResult: Codable, Equatable, Sendable {
    public var testedDomains: [String]
    public var expectedCountryCode: String?
    public var resolverSummaries: [String]
    public var leakDetected: Bool

    public init(
        testedDomains: [String],
        expectedCountryCode: String?,
        resolverSummaries: [String],
        leakDetected: Bool
    ) {
        self.testedDomains = testedDomains
        self.expectedCountryCode = expectedCountryCode
        self.resolverSummaries = resolverSummaries
        self.leakDetected = leakDetected
    }
}

public protocol NetworkDiagnosticsClient: Sendable {
    func measureLatency(to endpoint: URL) async throws -> LatencyResult
    func fetchIPGeolocation(from endpoint: URL) async throws -> IPGeolocationResult
    func checkDNSLeak(domains: [String], expectedCountryCode: String?) async throws -> DNSLeakResult
}

public struct URLSessionNetworkDiagnosticsClient: NetworkDiagnosticsClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func measureLatency(to endpoint: URL) async throws -> LatencyResult {
        let start = ContinuousClock.now
        let (_, response) = try await session.data(from: endpoint)
        let elapsed = start.duration(to: ContinuousClock.now)
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        return LatencyResult(
            endpoint: endpoint,
            milliseconds: Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15,
            statusCode: statusCode
        )
    }

    public func fetchIPGeolocation(from endpoint: URL) async throws -> IPGeolocationResult {
        let (data, _) = try await session.data(from: endpoint)
        if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let normalized = object.reduce(into: [String: String]()) { partialResult, pair in
                partialResult[pair.key] = String(describing: pair.value)
            }
            let ip = normalized["ip"] ?? normalized["query"] ?? normalized["origin"] ?? "unknown"
            let country = normalized["country"] ?? normalized["countryCode"] ?? normalized["country_code"]
            return IPGeolocationResult(ipAddress: ip, countryCode: country, raw: normalized)
        }

        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return IPGeolocationResult(ipAddress: text ?? "unknown")
    }

    public func checkDNSLeak(domains: [String], expectedCountryCode: String?) async throws -> DNSLeakResult {
        let summaries = try await withThrowingTaskGroup(of: String.self) { group in
            for domain in domains {
                group.addTask {
                    let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(domain), port: 443)
                    return "\(endpoint)"
                }
            }

            var values: [String] = []
            for try await value in group {
                values.append(value)
            }
            return values.sorted()
        }

        return DNSLeakResult(
            testedDomains: domains,
            expectedCountryCode: expectedCountryCode,
            resolverSummaries: summaries,
            leakDetected: false
        )
    }
}
