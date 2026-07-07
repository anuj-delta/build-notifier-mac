import XCTest
@testable import BuildNotifier

final class TriggerPipelineTests: XCTestCase {
    func testRequestEncodesBranchAndParameters() throws {
        let request = TriggerPipelineRequest(branch: "feature/x", parameters: ["env": "devnet"])
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["branch"] as? String, "feature/x")
        let params = try XCTUnwrap(json["parameters"] as? [String: String])
        XCTAssertEqual(params, ["env": "devnet"])
    }

    func testRequestOmitsParametersWhenNil() throws {
        let request = TriggerPipelineRequest(branch: "main", parameters: nil)
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["branch"] as? String, "main")
        XCTAssertNil(json["parameters"])
    }

    func testTriggeredPipelineDecodesV2Response() throws {
        let payload = """
        {
            "id": "abc-123",
            "number": 4567,
            "state": "created",
            "created_at": "2026-07-07T12:00:00Z"
        }
        """.data(using: .utf8)!

        let pipeline = try JSONDecoder().decode(TriggeredPipeline.self, from: payload)
        XCTAssertEqual(pipeline.id, "abc-123")
        XCTAssertEqual(pipeline.number, 4567)
        XCTAssertEqual(pipeline.state, "created")
        XCTAssertEqual(pipeline.createdAt, "2026-07-07T12:00:00Z")
    }
}
