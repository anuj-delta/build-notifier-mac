import Foundation
import Security

// MARK: - Keychain Service

public enum KeychainError: Error, LocalizedError {
    case duplicateItem
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case invalidData
    
    public var errorDescription: String? {
        switch self {
        case .duplicateItem:
            return "Item already exists in keychain"
        case .itemNotFound:
            return "Item not found in keychain"
        case .unexpectedStatus(let status):
            return "Keychain error: \(status)"
        case .invalidData:
            return "Invalid data in keychain"
        }
    }
}

public final class KeychainService {
    public static let shared = KeychainService()
    
    private let service = "com.buildnotifier.circleci"
    private let account = "api_token"
    private let vercelAccount = "vercel_token"
    
    // Fallback key for UserDefaults (used when keychain access fails due to code signing)
    private let fallbackKey = "circleci_token_fallback"
    private let vercelFallbackKey = "vercel_token_fallback"
    
    // Persist across rebuilds/reinstalls:
    // - `suiteDefaults`: stable domain independent of bundle ID
    // - `standardDefaults`: normal app defaults (still useful when installed in /Applications)
    private let suiteDefaults = UserDefaults(suiteName: "buildnotifier.circleci.shared") ?? .standard
    private let standardDefaults = UserDefaults.standard
    private let legacySuiteDefaults = UserDefaults(suiteName: "group.buildnotifier.circleci.shared")
    
    // This app is distributed as an ad-hoc signed build in development/internal use.
    // Re-signing changes the code identity and causes repeated Keychain access prompts,
    // so token persistence intentionally relies on stable UserDefaults storage instead.
    private let usesKeychain = false
    
    private init() {}
    
    public func maskedCircleCIToken() -> String? {
        maskedToken(for: fallbackKey)
    }
    
    public func maskedVercelToken() -> String? {
        maskedToken(for: vercelFallbackKey)
    }
    
    // MARK: - Save Token
    
    public func saveToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        // Always save to UserDefaults fallbacks first (avoids keychain prompts & signature issues)
        suiteDefaults.set(token, forKey: fallbackKey)
        standardDefaults.set(token, forKey: fallbackKey)
        suiteDefaults.synchronize()
        standardDefaults.synchronize()
        
        guard usesKeychain else { return }
        
        // Delete existing keychain item (but NOT the UserDefaults fallback)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Try to save to keychain (best-effort)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            // Don't throw - fallbacks already persisted
            print("[KeychainService] Keychain save failed: \(status); using UserDefaults fallback")
        }
    }
    
    // MARK: - Get Token
    
    public func getToken() throws -> String {
        // Prefer stable app storage to avoid Keychain prompts for ad-hoc signed builds.
        if let token = suiteDefaults.string(forKey: fallbackKey), !token.isEmpty {
            return token
        }
        if let legacy = legacySuiteDefaults?.string(forKey: fallbackKey), !legacy.isEmpty {
            // Migrate legacy suite -> current
            suiteDefaults.set(legacy, forKey: fallbackKey)
            standardDefaults.set(legacy, forKey: fallbackKey)
            suiteDefaults.synchronize()
            standardDefaults.synchronize()
            return legacy
        }
        if let token = standardDefaults.string(forKey: fallbackKey), !token.isEmpty {
            // Ensure suite has a copy
            suiteDefaults.set(token, forKey: fallbackKey)
            suiteDefaults.synchronize()
            return token
        }
        
        guard usesKeychain else {
            throw KeychainError.itemNotFound
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let token = String(data: data, encoding: .utf8) {
            suiteDefaults.set(token, forKey: fallbackKey)
            standardDefaults.set(token, forKey: fallbackKey)
            suiteDefaults.synchronize()
            standardDefaults.synchronize()
            return token
        }
        
        if status == errSecItemNotFound {
            throw KeychainError.itemNotFound
        }
        throw KeychainError.unexpectedStatus(status)
    }
    
    // MARK: - Delete Token
    
    public func deleteToken() throws {
        // Clear UserDefaults fallback
        suiteDefaults.removeObject(forKey: fallbackKey)
        standardDefaults.removeObject(forKey: fallbackKey)
        legacySuiteDefaults?.removeObject(forKey: fallbackKey)
        suiteDefaults.synchronize()
        standardDefaults.synchronize()
        legacySuiteDefaults?.synchronize()
        
        guard usesKeychain else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    // MARK: - Check if Token Exists
    
    public func hasToken() -> Bool {
        // Prefer UserDefaults checks to avoid keychain prompts / signature issues
        if let token = suiteDefaults.string(forKey: fallbackKey), !token.isEmpty {
            return true
        }
        if let legacy = legacySuiteDefaults?.string(forKey: fallbackKey), !legacy.isEmpty {
            // Migrate legacy suite -> current
            suiteDefaults.set(legacy, forKey: fallbackKey)
            standardDefaults.set(legacy, forKey: fallbackKey)
            suiteDefaults.synchronize()
            standardDefaults.synchronize()
            return true
        }
        if let token = standardDefaults.string(forKey: fallbackKey), !token.isEmpty {
            // Ensure suite has a copy
            suiteDefaults.set(token, forKey: fallbackKey)
            suiteDefaults.synchronize()
            return true
        }
        
        guard usesKeychain else { return false }
        
        // Only if UserDefaults empty, attempt keychain
        do {
            _ = try getToken()
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Vercel Token Methods
    
    public func saveVercelToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        // Always save to UserDefaults fallbacks first
        suiteDefaults.set(token, forKey: vercelFallbackKey)
        standardDefaults.set(token, forKey: vercelFallbackKey)
        suiteDefaults.synchronize()
        standardDefaults.synchronize()
        
        guard usesKeychain else { return }
        
        // Delete existing keychain item
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vercelAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Try to save to keychain (best-effort)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vercelAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[KeychainService] Vercel keychain save failed: \(status); using UserDefaults fallback")
        }
    }
    
    public func getVercelToken() throws -> String {
        if let token = suiteDefaults.string(forKey: vercelFallbackKey), !token.isEmpty {
            return token
        }
        if let token = standardDefaults.string(forKey: vercelFallbackKey), !token.isEmpty {
            suiteDefaults.set(token, forKey: vercelFallbackKey)
            suiteDefaults.synchronize()
            return token
        }
        
        guard usesKeychain else {
            throw KeychainError.itemNotFound
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vercelAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let token = String(data: data, encoding: .utf8) {
            suiteDefaults.set(token, forKey: vercelFallbackKey)
            standardDefaults.set(token, forKey: vercelFallbackKey)
            suiteDefaults.synchronize()
            standardDefaults.synchronize()
            return token
        }
        
        if status == errSecItemNotFound {
            throw KeychainError.itemNotFound
        }
        throw KeychainError.unexpectedStatus(status)
    }
    
    public func deleteVercelToken() throws {
        // Clear UserDefaults fallback
        suiteDefaults.removeObject(forKey: vercelFallbackKey)
        standardDefaults.removeObject(forKey: vercelFallbackKey)
        suiteDefaults.synchronize()
        standardDefaults.synchronize()
        
        guard usesKeychain else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vercelAccount
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    public func hasVercelToken() -> Bool {
        if let token = suiteDefaults.string(forKey: vercelFallbackKey), !token.isEmpty {
            return true
        }
        if let token = standardDefaults.string(forKey: vercelFallbackKey), !token.isEmpty {
            suiteDefaults.set(token, forKey: vercelFallbackKey)
            suiteDefaults.synchronize()
            return true
        }
        
        guard usesKeychain else { return false }
        
        do {
            _ = try getVercelToken()
            return true
        } catch {
            return false
        }
    }
    
    private func maskedToken(for key: String) -> String? {
        let token =
            suiteDefaults.string(forKey: key) ??
            standardDefaults.string(forKey: key) ??
            legacySuiteDefaults?.string(forKey: key)
        
        guard let token, !token.isEmpty else { return nil }
        
        if token.count <= 8 {
            let visiblePrefix = token.prefix(min(2, token.count))
            let hiddenCount = max(token.count - visiblePrefix.count, 0)
            return "\(visiblePrefix)\(String(repeating: "•", count: hiddenCount))"
        }
        
        return "\(token.prefix(4))••••\(token.suffix(4))"
    }
}
