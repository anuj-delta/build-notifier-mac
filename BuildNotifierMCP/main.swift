import BuildNotifierCore
import Foundation
import MCP

@main
struct BuildNotifierMCP {
    static func main() async throws {
        let server = Server(
            name: "BuildNotifierMCP",
            version: "1.0.0",
            capabilities: .init(tools: .init(listChanged: false))
        )
        let service = CircleCIMCPService()

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: [
                Tool(
                    name: "list_projects_by_activity",
                    description: "List followed CircleCI projects sorted by latest build activity.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "limit": .object([
                                "type": .string("integer"),
                                "description": .string("Maximum number of projects to return, between 1 and 100.")
                            ]),
                            "watched_only": .object([
                                "type": .string("boolean"),
                                "description": .string("When true, only return projects currently watched in Build Notifier.")
                            ])
                        ]),
                        "additionalProperties": .bool(false)
                    ])
                ),
                Tool(
                    name: "get_build_details",
                    description: "Get details for a specific CircleCI build in a followed project.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "project_slug": .object([
                                "type": .string("string"),
                                "description": .string("Project slug in org/repo format as returned by list_projects_by_activity.")
                            ]),
                            "build_num": .object([
                                "type": .string("integer"),
                                "description": .string("CircleCI build number.")
                            ])
                        ]),
                        "required": .array([.string("project_slug"), .string("build_num")]),
                        "additionalProperties": .bool(false)
                    ])
                )
            ])
        }

        await server.withMethodHandler(CallTool.self) { params in
            do {
                switch params.name {
                case "list_projects_by_activity":
                    let limit = params.arguments?["limit"]?.intValue ?? 25
                    let watchedOnly = params.arguments?["watched_only"]?.boolValue ?? false
                    let projects = try await service.listProjectsByActivity(limit: limit, watchedOnly: watchedOnly)
                    return .init(content: [.text(text: Self.encode(projects), annotations: nil, _meta: nil)], isError: false)
                case "get_build_details":
                    guard let projectSlug = params.arguments?["project_slug"]?.stringValue,
                          let buildNumber = params.arguments?["build_num"]?.intValue else {
                        return .init(content: [.text(text: "Missing required arguments: project_slug and build_num", annotations: nil, _meta: nil)], isError: true)
                    }

                    let details = try await service.getBuildDetails(projectSlug: projectSlug, buildNumber: buildNumber)
                    return .init(content: [.text(text: Self.encode(details), annotations: nil, _meta: nil)], isError: false)
                default:
                    return .init(content: [.text(text: "Unknown tool: \(params.name)", annotations: nil, _meta: nil)], isError: true)
                }
            } catch {
                return .init(content: [.text(text: Self.errorPayload(for: error), annotations: nil, _meta: nil)], isError: true)
            }
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        while !Task.isCancelled {
            try await Task.sleep(for: .seconds(86_400))
        }
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(value),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"Failed to encode response\"}"
        }

        return json
    }

    private static func errorPayload(for error: Error) -> String {
        let payload = [
            "error": error.localizedDescription
        ]
        return encode(payload)
    }
}
