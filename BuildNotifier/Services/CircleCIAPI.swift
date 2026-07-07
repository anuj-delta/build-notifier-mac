import Foundation

// MARK: - API Errors

enum CircleCIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int, String?)
    case decodingError(Error)
    case noToken
    case unauthorized
    case rateLimited
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message ?? "Unknown error")"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .noToken:
            return "No API token configured"
        case .unauthorized:
            return "Invalid API token"
        case .rateLimited:
            return "Rate limited - please wait"
        }
    }
}

// MARK: - CircleCI API Client

actor CircleCIAPI {
    static let shared = CircleCIAPI()
    
    private let baseURLv1 = "https://circleci.com/api/v1.1"
    private let baseURLv2 = "https://circleci.com/api/v2"
    
    private var token: String?
    
    private init() {}
    
    // MARK: - Token Management
    
    func setToken(_ token: String) {
        self.token = token
    }
    
    func clearToken() {
        self.token = nil
    }
    
    func loadTokenFromKeychain() {
        self.token = try? KeychainService.shared.getToken()
    }
    
    // MARK: - API v1.1 Endpoints
    
    /// Validate token by fetching user info
    func validateToken() async throws -> User {
        return try await request(
            url: "\(baseURLv1)/me",
            method: "GET"
        )
    }
    
    /// Get all followed projects (projects with CircleCI configured that user follows)
    func getProjects() async throws -> [Project] {
        let projects: [Project] = try await request(
            url: "\(baseURLv1)/projects",
            method: "GET"
        )
        return projects.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }
    
    /// Get recent builds for a project
    func getBuilds(
        vcsType: String,
        orgName: String,
        repoName: String,
        limit: Int = 30,
        filter: String? = nil
    ) async throws -> [Build] {
        var url = "\(baseURLv1)/project/\(vcsType)/\(orgName)/\(repoName)?limit=\(limit)&shallow=true"
        if let filter = filter {
            url += "&filter=\(filter)"
        }
        return try await request(url: url, method: "GET")
    }
    
    /// Retry a failed build
    func retryBuild(
        vcsType: String,
        orgName: String,
        repoName: String,
        buildNum: Int
    ) async throws -> Build {
        return try await request(
            url: "\(baseURLv1)/project/\(vcsType)/\(orgName)/\(repoName)/\(buildNum)/retry",
            method: "POST"
        )
    }
    
    /// Cancel a running build
    func cancelBuild(
        vcsType: String,
        orgName: String,
        repoName: String,
        buildNum: Int
    ) async throws -> Build {
        return try await request(
            url: "\(baseURLv1)/project/\(vcsType)/\(orgName)/\(repoName)/\(buildNum)/cancel",
            method: "POST"
        )
    }
    
    /// Get all recent builds across followed projects
    func getRecentBuilds(limit: Int = 30) async throws -> [Build] {
        return try await request(
            url: "\(baseURLv1)/recent-builds?limit=\(limit)&shallow=true",
            method: "GET"
        )
    }
    
    // MARK: - API v2 Endpoints
    
    /// Get jobs for a workflow (to check for pending approvals)
    func getWorkflowJobs(workflowId: String) async throws -> [WorkflowJob] {
        let response: WorkflowJobsResponse = try await request(
            url: "\(baseURLv2)/workflow/\(workflowId)/job",
            method: "GET"
        )
        return response.items
    }

    /// Get workflow details, including the owning pipeline ID.
    func getWorkflow(workflowId: String) async throws -> WorkflowDetails {
        try await request(
            url: "\(baseURLv2)/workflow/\(workflowId)",
            method: "GET"
        )
    }

    /// Get pipeline details, including the trigger actor.
    func getPipeline(pipelineId: String) async throws -> PipelineDetails {
        try await request(
            url: "\(baseURLv2)/pipeline/\(pipelineId)",
            method: "GET"
        )
    }
    
    /// Approve a pending approval job
    func approveJob(workflowId: String, approvalRequestId: String) async throws {
        let _: EmptyResponse = try await request(
            url: "\(baseURLv2)/workflow/\(workflowId)/approve/\(approvalRequestId)",
            method: "POST"
        )
    }
    
    /// Trigger a new pipeline for a branch, optionally passing pipeline parameters.
    func triggerPipeline(
        vcsType: String,
        orgName: String,
        repoName: String,
        branch: String,
        parameters: [String: String]?
    ) async throws -> TriggeredPipeline {
        let payload = TriggerPipelineRequest(
            branch: branch,
            parameters: (parameters?.isEmpty == false) ? parameters : nil
        )
        let body = try JSONEncoder().encode(payload)
        return try await request(
            url: "\(baseURLv2)/project/\(vcsType)/\(orgName)/\(repoName)/pipeline",
            method: "POST",
            body: body
        )
    }

    // MARK: - Generic Request

    private func request<T: Decodable>(
        url urlString: String,
        method: String,
        body: Data? = nil
    ) async throws -> T {
        guard let token = token else {
            throw CircleCIError.noToken
        }
        
        guard let url = URL(string: urlString) else {
            throw CircleCIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "Circle-Token")
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CircleCIError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw CircleCIError.unauthorized
        case 429:
            throw CircleCIError.rateLimited
        default:
            let message = String(data: data, encoding: .utf8)
            throw CircleCIError.httpError(httpResponse.statusCode, message)
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw CircleCIError.decodingError(error)
        }
    }
}

// MARK: - Empty Response (for endpoints that return no content)

struct EmptyResponse: Decodable {}
