import Foundation
import Security

// MARK: - Keychain Service

enum KeychainError: Error, LocalizedError {
    case duplicateItem
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case invalidData
    
    var errorDescription: String? {
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

final class KeychainService {
    static let shared = KeychainService()
    
    private let service = "com.buildnotifier.circleci"
    private let account = "api_token"
    
    // Fallback key for UserDefaults (used when keychain access fails due to code signing)
    private let fallbackKey = "circleci_token_fallback"
    
    // Persist across rebuilds/reinstalls:
    // - `suiteDefaults`: stable domain independent of bundle ID
    // - `standardDefaults`: normal app defaults (still useful when installed in /Applications)
    private let suiteDefaults = UserDefaults(suiteName: "buildnotifier.circleci.shared") ?? .standard
    private let standardDefaults = UserDefaults.standard
    private let legacySuiteDefaults = UserDefaults(suiteName: "group.buildnotifier.circleci.shared")
    
    private init() {}
    
    // MARK: - Save Token
    
    func saveToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        // Always save to UserDefaults fallbacks first (avoids keychain prompts & signature issues)
        suiteDefaults.set(token, forKey: fallbackKey)
        standardDefaults.set(token, forKey: fallbackKey)
        suiteDefaults.synchronize()
        standardDefaults.synchronize()
        
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
    
    func getToken() throws -> String {
        // Try keychain first
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
            // Migrate keychain -> UserDefaults fallback so signature changes don't lose the token.
            suiteDefaults.set(token, forKey: fallbackKey)
            standardDefaults.set(token, forKey: fallbackKey)
            suiteDefaults.synchronize()
            standardDefaults.synchronize()
            return token
        }
        
        // Fallback to UserDefaults (for dev builds / reinstall)
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
        
        if status == errSecItemNotFound {
            throw KeychainError.itemNotFound
        }
        throw KeychainError.unexpectedStatus(status)
    }
    
    // MARK: - Delete Token
    
    func deleteToken() throws {
        // Clear UserDefaults fallback
        suiteDefaults.removeObject(forKey: fallbackKey)
        standardDefaults.removeObject(forKey: fallbackKey)
        legacySuiteDefaults?.removeObject(forKey: fallbackKey)
        suiteDefaults.synchronize()
        standardDefaults.synchronize()
        legacySuiteDefaults?.synchronize()
        
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
    
    func hasToken() -> Bool {
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
        
        // Only if UserDefaults empty, attempt keychain
        do {
            _ = try getToken()
            return true
        } catch {
            return false
        }
    }
}
