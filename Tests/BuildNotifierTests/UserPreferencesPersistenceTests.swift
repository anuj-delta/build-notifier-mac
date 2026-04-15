import XCTest
@testable import BuildNotifier
@testable import BuildNotifierCore

final class UserPreferencesPersistenceTests: XCTestCase {
    func testSharedDefaultsLoadDataFallsBackToStandardAndBackfillsSharedSuite() {
        let key = "prefs-\(UUID().uuidString)"
        let sharedSuiteName = "shared.\(UUID().uuidString)"
        let legacySuiteName = "legacy.\(UUID().uuidString)"
        let standardDefaults = UserDefaults(suiteName: "standard.\(UUID().uuidString)")!
        let sharedDefaults = UserDefaults(suiteName: sharedSuiteName)!
        let legacyDefaults = UserDefaults(suiteName: legacySuiteName)!

        let payload = Data("{\"watchedProjects\":[{\"orgName\":\"delta\",\"repoName\":\"api\"}]}".utf8)
        standardDefaults.set(payload, forKey: key)

        let loaded = BuildNotifierSharedDefaults.loadData(
            forKey: key,
            standardDefaults: standardDefaults,
            sharedDefaults: sharedDefaults,
            legacySharedDefaults: legacyDefaults
        )

        XCTAssertEqual(loaded, payload)
        XCTAssertEqual(sharedDefaults.data(forKey: key), payload)
    }
}
