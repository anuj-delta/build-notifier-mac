import Foundation
import Security

// MARK: - Keychain Service

enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case invalidData

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Item not found in keychain"
        case .invalidData:
            return "Invalid data in keychain"
        }
    }
}

/// Stores API tokens in the Keychain, falling back to an owner-only file when the Keychain
/// refuses. Ad-hoc re-signing changes the code identity, which can lock the app out of its
/// own Keychain items, and the app must keep working when that happens.
final class KeychainService {
    static let shared = KeychainService()

    private let service = "com.buildnotifier.circleci"

    private enum Account: String {
        case circleCI = "api_token"
        case vercel = "vercel_token"

        /// Where tokens lived before they moved out of UserDefaults. Read once, then erased.
        var plaintextKey: String {
            switch self {
            case .circleCI: return "circleci_token_fallback"
            case .vercel: return "vercel_token_fallback"
            }
        }
    }

    private init() {}

    // MARK: - CircleCI

    func saveToken(_ token: String) throws { try save(token, for: .circleCI) }
    func getToken() throws -> String { try read(.circleCI) }
    func deleteToken() { delete(.circleCI) }
    func hasToken() -> Bool { (try? read(.circleCI)) != nil }
    func maskedCircleCIToken() -> String? { masked(.circleCI) }

    // MARK: - Vercel

    func saveVercelToken(_ token: String) throws { try save(token, for: .vercel) }
    func getVercelToken() throws -> String { try read(.vercel) }
    func deleteVercelToken() { delete(.vercel) }
    func hasVercelToken() -> Bool { (try? read(.vercel)) != nil }
    func maskedVercelToken() -> String? { masked(.vercel) }

    // MARK: - Storage

    private func save(_ token: String, for account: Account) throws {
        guard let data = token.data(using: .utf8) else { throw KeychainError.invalidData }

        if writeToKeychain(data, for: account) {
            removeFile(for: account)
        } else {
            try writeFile(data, for: account)
        }
        erasePlaintext(for: account)
    }

    private func read(_ account: Account) throws -> String {
        // A token in the clear is the one the app has been running on, so it wins over any
        // Keychain item left by an older build. Moved into place and erased on sight.
        if let token = plaintextToken(for: account) {
            try? save(token, for: account)
            return token
        }
        if let token = keychainToken(for: account) { return token }
        if let token = fileToken(for: account) { return token }
        throw KeychainError.itemNotFound
    }

    private func delete(_ account: Account) {
        SecItemDelete(query(for: account) as CFDictionary)
        removeFile(for: account)
        erasePlaintext(for: account)
    }

    private func masked(_ account: Account) -> String? {
        guard let token = try? read(account), !token.isEmpty else { return nil }

        guard token.count > 8 else {
            let visible = token.prefix(min(2, token.count))
            return visible + String(repeating: "•", count: token.count - visible.count)
        }
        return "\(token.prefix(4))••••\(token.suffix(4))"
    }

    // MARK: - Keychain

    private func query(for account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]
    }

    private func writeToKeychain(_ data: Data, for account: Account) -> Bool {
        SecItemDelete(query(for: account) as CFDictionary)

        var item = query(for: account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess {
            print("[KeychainService] Keychain save failed: \(status); storing in a private file")
        }
        return status == errSecSuccess
    }

    private func keychainToken(for account: Account) -> String? {
        var item = query(for: account)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - File fallback

    private func fileURL(for account: Account) -> URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("BuildNotifier", isDirectory: true)
            .appendingPathComponent("\(account.rawValue).token", isDirectory: false)
    }

    private func writeFile(_ data: Data, for account: Account) throws {
        guard let url = fileURL(for: account) else { throw KeychainError.invalidData }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: url, options: .atomic)
        // An atomic write swaps in a new file, so the mode has to be set afterwards.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func fileToken(for account: Account) -> String? {
        guard let url = fileURL(for: account),
              let data = try? Data(contentsOf: url),
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else { return nil }
        return token
    }

    private func removeFile(for account: Account) {
        guard let url = fileURL(for: account) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Plaintext migration

    /// Domains that held tokens in the clear. Kept only to migrate off them.
    private var plaintextDomains: [UserDefaults] {
        [
            UserDefaults(suiteName: "buildnotifier.circleci.shared"),
            UserDefaults(suiteName: "group.buildnotifier.circleci.shared"),
            .standard
        ].compactMap { $0 }
    }

    private func plaintextToken(for account: Account) -> String? {
        for defaults in plaintextDomains {
            if let token = defaults.string(forKey: account.plaintextKey), !token.isEmpty {
                return token
            }
        }
        return nil
    }

    private func erasePlaintext(for account: Account) {
        for defaults in plaintextDomains {
            defaults.removeObject(forKey: account.plaintextKey)
        }
    }
}
