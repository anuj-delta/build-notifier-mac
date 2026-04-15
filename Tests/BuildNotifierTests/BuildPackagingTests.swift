import XCTest

final class BuildPackagingTests: XCTestCase {
    func testBuildAppScriptBundlesMCPHelper() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repoRoot.appendingPathComponent("build-app.sh")
        let script = try String(contentsOf: scriptURL)

        XCTAssertTrue(script.contains("BuildNotifierMCP"))
        XCTAssertTrue(script.contains("HELPERS_DIR"))
    }
}
