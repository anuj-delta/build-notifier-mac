import Foundation

struct MCPServerIntegration {
    static let helperExecutableName = "BuildNotifierMCP"

    static var bundledHelperPath: String? {
        helperURL?.path
    }

    static var isBundledHelperAvailable: Bool {
        guard let helperURL else { return false }
        return FileManager.default.isExecutableFile(atPath: helperURL.path)
    }

    static var configSnippet: String {
        guard let helperPath = bundledHelperPath else {
            return """
            {
              "mcpServers": {
                "build-notifier": {
                  "command": "/Applications/Build Notifier.app/Contents/Helpers/BuildNotifierMCP"
                }
              }
            }
            """
        }

        return """
        {
          "mcpServers": {
            "build-notifier": {
              "command": "\(helperPath)"
            }
          }
        }
        """
    }

    private static var helperURL: URL? {
        let bundledURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Helpers")
            .appendingPathComponent(helperExecutableName)

        if FileManager.default.fileExists(atPath: bundledURL.path) {
            return bundledURL
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let debugURL = currentDirectory
            .appendingPathComponent(".build")
            .appendingPathComponent("debug")
            .appendingPathComponent(helperExecutableName)
        if FileManager.default.fileExists(atPath: debugURL.path) {
            return debugURL
        }

        let releaseURL = currentDirectory
            .appendingPathComponent(".build")
            .appendingPathComponent("release")
            .appendingPathComponent(helperExecutableName)
        if FileManager.default.fileExists(atPath: releaseURL.path) {
            return releaseURL
        }

        return nil
    }
}
