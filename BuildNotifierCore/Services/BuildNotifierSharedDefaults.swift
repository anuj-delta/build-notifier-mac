import Foundation

public enum BuildNotifierSharedDefaults {
    public static let suiteName = "buildnotifier.circleci.shared"
    public static let legacySuiteName = "group.buildnotifier.circleci.shared"
    public static let userPreferencesKey = "UserPreferences"

    public static func sharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    public static func legacySharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: legacySuiteName)
    }

    public static func loadData(
        forKey key: String,
        standardDefaults: UserDefaults = .standard,
        sharedDefaults: UserDefaults? = UserDefaults(suiteName: suiteName),
        legacySharedDefaults: UserDefaults? = UserDefaults(suiteName: legacySuiteName)
    ) -> Data? {
        if let data = sharedDefaults?.data(forKey: key) {
            return data
        }

        if let legacyData = legacySharedDefaults?.data(forKey: key) {
            sharedDefaults?.set(legacyData, forKey: key)
            standardDefaults.set(legacyData, forKey: key)
            sharedDefaults?.synchronize()
            standardDefaults.synchronize()
            return legacyData
        }

        if let standardData = standardDefaults.data(forKey: key) {
            sharedDefaults?.set(standardData, forKey: key)
            sharedDefaults?.synchronize()
            return standardData
        }

        return nil
    }

    public static func saveData(
        _ data: Data,
        forKey key: String,
        standardDefaults: UserDefaults = .standard,
        sharedDefaults: UserDefaults? = UserDefaults(suiteName: suiteName)
    ) {
        sharedDefaults?.set(data, forKey: key)
        standardDefaults.set(data, forKey: key)
        sharedDefaults?.synchronize()
        standardDefaults.synchronize()
    }
}
