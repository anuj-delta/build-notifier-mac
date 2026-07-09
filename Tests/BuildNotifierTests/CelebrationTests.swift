import XCTest
@testable import BuildNotifier

final class ProductionBranchMatcherTests: XCTestCase {
    func testExactMatch() {
        XCTAssertTrue(ProductionBranchMatcher.isProduction(branch: "main", patterns: ["main", "master"]))
        XCTAssertTrue(ProductionBranchMatcher.isProduction(branch: "master", patterns: ["main", "master"]))
    }

    func testCaseInsensitive() {
        XCTAssertTrue(ProductionBranchMatcher.isProduction(branch: "Main", patterns: ["MAIN"]))
    }

    func testGlobMatch() {
        XCTAssertTrue(ProductionBranchMatcher.isProduction(branch: "release/2.1", patterns: ["release/*"]))
        XCTAssertTrue(ProductionBranchMatcher.isProduction(branch: "hotfix-prod", patterns: ["*-prod"]))
        XCTAssertTrue(ProductionBranchMatcher.isProduction(branch: "anything", patterns: ["*"]))
    }

    func testNonMatch() {
        XCTAssertFalse(ProductionBranchMatcher.isProduction(branch: "feature/x", patterns: ["main", "master"]))
        XCTAssertFalse(ProductionBranchMatcher.isProduction(branch: "release", patterns: ["release/*"]))
    }

    func testNilOrEmptyBranch() {
        XCTAssertFalse(ProductionBranchMatcher.isProduction(branch: nil, patterns: ["main"]))
        XCTAssertFalse(ProductionBranchMatcher.isProduction(branch: "   ", patterns: ["main"]))
    }

    func testEmptyPatterns() {
        XCTAssertFalse(ProductionBranchMatcher.isProduction(branch: "main", patterns: []))
    }
}

final class ConfettiParticleTests: XCTestCase {
    private func makeParticle(spawnDelay: Double = 0, lifetime: Double = 4) -> ConfettiParticle {
        ConfettiParticle(
            x0: 0.5, y0: 0.0, vx: 0.1, vy: 0.2,
            rotation0: 0, angularVelocity: 1,
            size: 10, colorIndex: 0, shape: .rectangle,
            spawnDelay: spawnDelay, lifetime: lifetime
        )
    }

    func testPositionAtSpawnEqualsOrigin() {
        let p = makeParticle(spawnDelay: 0.3)
        let pos = p.position(at: 0.3)
        XCTAssertEqual(pos.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(pos.y, 0.0, accuracy: 1e-9)
    }

    func testGravityPullsDown() {
        let p = makeParticle()
        XCTAssertGreaterThan(p.position(at: 2).y, p.position(at: 1).y)
    }

    func testOpacityZeroBeforeSpawnAndAfterLifetime() {
        let p = makeParticle(spawnDelay: 0.5, lifetime: 4)
        XCTAssertEqual(p.opacity(at: 0.2), 0, accuracy: 1e-9)
        XCTAssertEqual(p.opacity(at: 0.5 + 4 + 0.1), 0, accuracy: 1e-9)
    }

    func testOpacityFullMidLife() {
        let p = makeParticle(spawnDelay: 0, lifetime: 4)
        XCTAssertEqual(p.opacity(at: 1.5), 1, accuracy: 1e-9)
    }

    func testSeededBurstIsReproducible() {
        let a = ConfettiParticle.spawnBurst(count: 50, seed: 42)
        let b = ConfettiParticle.spawnBurst(count: 50, seed: 42)
        XCTAssertEqual(a.count, 50)
        XCTAssertEqual(a.map(\.x0), b.map(\.x0))
        XCTAssertEqual(a.map(\.vy), b.map(\.vy))
    }

    func testDifferentSeedsDiffer() {
        let a = ConfettiParticle.spawnBurst(count: 50, seed: 1)
        let b = ConfettiParticle.spawnBurst(count: 50, seed: 2)
        XCTAssertNotEqual(a.map(\.x0), b.map(\.x0))
    }
}

final class CelebrationSoundTests: XCTestCase {
    func testBucketsAreDisjointAndCoverAllCases() {
        let all = Set(CelebrationSound.allCases)
        let buckets = Set(CelebrationSound.successBucket + CelebrationSound.failureBucket)
        XCTAssertEqual(all, buckets)
        let overlap = Set(CelebrationSound.successBucket).intersection(CelebrationSound.failureBucket)
        XCTAssertTrue(overlap.isEmpty)
    }

    func testDefaultsBelongToTheirBuckets() {
        XCTAssertTrue(CelebrationSound.successBucket.contains(.defaultSuccess))
        XCTAssertTrue(CelebrationSound.failureBucket.contains(.defaultFailure))
    }

    func testRawValueMatchesFileName() {
        for sound in CelebrationSound.allCases {
            XCTAssertEqual(sound.fileName, sound.rawValue)
        }
    }

    func testInvalidRawValueFallsBack() {
        XCTAssertNil(CelebrationSound(rawValue: "does-not-exist"))
    }
}

final class UserPreferencesCelebrationTests: XCTestCase {
    func testDefaultsIncludeCelebrationFields() {
        let prefs = UserPreferences.default
        XCTAssertTrue(prefs.celebrateProdSuccess)
        XCTAssertTrue(prefs.playFailureSound)
        XCTAssertEqual(prefs.successSound, CelebrationSound.defaultSuccess.rawValue)
        XCTAssertEqual(prefs.failureSound, CelebrationSound.defaultFailure.rawValue)
        XCTAssertEqual(prefs.productionBranches, ["main", "master"])
        XCTAssertTrue(prefs.celebrateDeployedBranches)
    }

    func testOldSchemaBlobDefaultsDeployedBranchesOn() throws {
        let legacy: [String: Any] = ["celebrateProdSuccess": false]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        UserDefaults.standard.set(data, forKey: "UserPreferences")
        defer { UserDefaults.standard.removeObject(forKey: "UserPreferences") }

        let loaded = UserPreferences.load()
        XCTAssertFalse(loaded.celebrateProdSuccess)
        XCTAssertTrue(loaded.celebrateDeployedBranches)
    }

    func testNewSchemaRoundTrips() throws {
        var prefs = UserPreferences.default
        prefs.productionBranches = ["main", "release/*"]
        prefs.successSound = CelebrationSound.carHorn.rawValue
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: data)
        XCTAssertEqual(decoded.productionBranches, ["main", "release/*"])
        XCTAssertEqual(decoded.successSound, CelebrationSound.carHorn.rawValue)
    }

    func testOldSchemaBlobFallsBackToDefaults() throws {
        // An old preferences blob lacking the celebration fields.
        let legacy: [String: Any] = [
            "pollingIntervalSeconds": 30,
            "notificationsEnabled": false,
            "watchedProjects": [],
            "watchedVercelProjects": []
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        UserDefaults.standard.set(data, forKey: "UserPreferences")
        defer { UserDefaults.standard.removeObject(forKey: "UserPreferences") }

        let loaded = UserPreferences.load()
        XCTAssertEqual(loaded.pollingIntervalSeconds, 30)
        XCTAssertFalse(loaded.notificationsEnabled)
        // New fields fall back to defaults.
        XCTAssertTrue(loaded.celebrateProdSuccess)
        XCTAssertEqual(loaded.successSound, CelebrationSound.defaultSuccess.rawValue)
        XCTAssertEqual(loaded.productionBranches, ["main", "master"])
    }
}

@MainActor
final class DeployKeyTests: XCTestCase {
    func testKeyIsCaseInsensitive() {
        let triggered = AppState.deployKey(projectSlug: "Delta-Exchange/API-Console", branch: "Feature/My-Branch")
        let observed = AppState.deployKey(projectSlug: "delta-exchange/api-console", branch: "feature/my-branch")
        XCTAssertEqual(triggered, observed)
    }

    func testDifferentBranchesDoNotMatch() {
        let a = AppState.deployKey(projectSlug: "org/repo", branch: "feature/a")
        let b = AppState.deployKey(projectSlug: "org/repo", branch: "feature/b")
        XCTAssertNotEqual(a, b)
    }
}
