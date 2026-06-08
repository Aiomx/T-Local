import Foundation

#if canImport(NetworkExtension)
import NetworkExtension

@MainActor
public final class PersonalVPNService: ObservableObject {
    @Published public private(set) var status: NEVPNStatus = .invalid
    @Published public private(set) var lastError: String?

    private let manager: NEVPNManager

    public init(manager: NEVPNManager = .shared()) {
        self.manager = manager
        self.status = manager.connection.status
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(vpnStatusDidChange),
            name: .NEVPNStatusDidChange,
            object: manager.connection
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func configure(node: VPNNode) async {
        do {
            try await manager.loadFromPreferences()

            let protocolConfiguration = NEVPNProtocolIKEv2()
            protocolConfiguration.serverAddress = node.serverHost
            protocolConfiguration.remoteIdentifier = node.remoteIdentifier
            protocolConfiguration.localIdentifier = node.localIdentifier
            protocolConfiguration.useExtendedAuthentication = true
            protocolConfiguration.disconnectOnSleep = false

            switch node.authentication {
            case let .usernamePassword(username, passwordReference):
                protocolConfiguration.username = username
                protocolConfiguration.passwordReference = passwordReference.data(using: .utf8)
                protocolConfiguration.authenticationMethod = .none
            case let .certificate(identityReference):
                protocolConfiguration.identityReference = identityReference.data(using: .utf8)
                protocolConfiguration.authenticationMethod = .certificate
            }

            manager.protocolConfiguration = protocolConfiguration
            manager.localizedDescription = node.displayName
            manager.isEnabled = true
            try await manager.saveToPreferences()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func connect() {
        do {
            try manager.connection.startVPNTunnel()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func disconnect() {
        manager.connection.stopVPNTunnel()
    }

    @objc private func vpnStatusDidChange() {
        status = manager.connection.status
    }
}

@MainActor
extension NEVPNManager {
    fileprivate func loadFromPreferences() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    fileprivate func saveToPreferences() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            saveToPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
#else
@MainActor
public final class PersonalVPNService: ObservableObject {
    @Published public private(set) var statusDescription = "Unsupported"
    @Published public private(set) var lastError: String?

    public init() {}

    public func configure(node: VPNNode) async {
        lastError = "NetworkExtension is unavailable on this platform."
    }

    public func connect() {}
    public func disconnect() {}
}
#endif
