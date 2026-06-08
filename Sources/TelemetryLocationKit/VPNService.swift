import Foundation

#if canImport(NetworkExtension)
import NetworkExtension
import Security

public enum VPNCredentialStore {
    private static let service = "com.enterprise.telemetryqa.vpn"

    public static func savePassword(_ password: String, reference: String) throws {
        let account = normalizedReference(reference)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(password.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw VPNCredentialError.keychainWriteFailed(status)
        }
    }

    public static func passwordPersistentReference(reference: String) throws -> Data {
        let account = normalizedReference(reference)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnPersistentRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw VPNCredentialError.keychainReadFailed(status)
        }
        return data
    }

    public static func normalizedReference(_ reference: String) -> String {
        if reference.hasPrefix("keychain:") {
            return String(reference.dropFirst("keychain:".count))
        }
        return reference
    }
}

public enum VPNCredentialError: Error, LocalizedError, Sendable {
    case keychainWriteFailed(OSStatus)
    case keychainReadFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case let .keychainWriteFailed(status):
            "Unable to save VPN credential to Keychain. OSStatus=\(status)."
        case let .keychainReadFailed(status):
            "Unable to read VPN credential from Keychain. Save the VPN secret on this iPhone first. OSStatus=\(status)."
        }
    }
}

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
                protocolConfiguration.passwordReference = try VPNCredentialStore.passwordPersistentReference(reference: passwordReference)
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

    public var statusText: String {
        switch status {
        case .invalid:
            "Invalid"
        case .disconnected:
            "Disconnected"
        case .connecting:
            "Connecting"
        case .connected:
            "Connected"
        case .reasserting:
            "Reasserting"
        case .disconnecting:
            "Disconnecting"
        @unknown default:
            "Unknown"
        }
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
public enum VPNCredentialStore {
    public static func savePassword(_ password: String, reference: String) throws {}
    public static func passwordPersistentReference(reference: String) throws -> Data { Data(reference.utf8) }
    public static func normalizedReference(_ reference: String) -> String { reference }
}

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

    public var statusText: String {
        statusDescription
    }
}
#endif
