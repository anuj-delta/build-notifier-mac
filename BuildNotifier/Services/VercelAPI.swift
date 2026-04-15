import Foundation
import BuildNotifierCore

// MARK: - API Errors

enum VercelError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int, String?)
    case decodingError(Error)
    case noToken
    case unauthorized
    case rateLimited
    case forbidden
    
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
            return "No Vercel token configured"
        case .unauthorized:
            return "Invalid Vercel token"
        case .rateLimited:
            return "Rate limited - please wait"
        case .forbidden:
            return "Access forbidden - check token permissions"
        }
    }
}

// MARK: - Vercel API Client

actor VercelAPI {
    static let shared = VercelAPI()
    
    private let baseURL = "https://api.vercel.com"
    
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
        self.token = try? KeychainService.shared.getVercelToken()
    }
    
    func hasToken() -> Bool {
        return token != nil && !(token?.isEmpty ?? true)
    }
    
    // MARK: - API Endpoints
    
    /// Validate token by fetching user info
    func validateToken() async throws -> VercelUser {
        return try await request(
            url: "\(baseURL)/v2/user",
            method: "GET"
        )
    }
    
    /// Get all teams for the authenticated user
    func getTeams() async throws -> [VercelTeam] {
        let response: VercelTeamsResponse = try await request(
            url: "\(baseURL)/v2/teams",
            method: "GET"
        )
        return response.teams
    }
    
    /// Get projects for a team (or personal account if teamId is nil)
    func getProjects(teamId: String?) async throws -> [VercelProject] {
        var url = "\(baseURL)/v9/projects?limit=100"
        if let teamId = teamId {
            url += "&teamId=\(teamId)"
        }
        let response: VercelProjectsResponse = try await request(
            url: url,
            method: "GET"
        )
        return response.projects.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    /// Get recent deployments for a project
    func getDeployments(
        projectId: String,
        teamId: String?,
        limit: Int = 20
    ) async throws -> [VercelDeployment] {
        var url = "\(baseURL)/v6/deployments?projectId=\(projectId)&limit=\(limit)"
        if let teamId = teamId {
            url += "&teamId=\(teamId)"
        }
        let response: VercelDeploymentsResponse = try await request(
            url: url,
            method: "GET"
        )
        return response.deployments
    }
    
    /// Get a single deployment by ID
    func getDeployment(id: String, teamId: String?) async throws -> VercelDeployment {
        var url = "\(baseURL)/v13/deployments/\(id)"
        if let teamId = teamId {
            url += "?teamId=\(teamId)"
        }
        return try await request(url: url, method: "GET")
    }
    
    // MARK: - Generic Request
    
    private func request<T: Decodable>(
        url urlString: String,
        method: String,
        body: Data? = nil
    ) async throws -> T {
        guard let token = token, !token.isEmpty else {
            throw VercelError.noToken
        }
        
        guard let url = URL(string: urlString) else {
            throw VercelError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VercelError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw VercelError.unauthorized
        case 403:
            throw VercelError.forbidden
        case 429:
            throw VercelError.rateLimited
        default:
            let message = String(data: data, encoding: .utf8)
            throw VercelError.httpError(httpResponse.statusCode, message)
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw VercelError.decodingError(error)
        }
    }
}

// MARK: - Vercel User

struct VercelUser: Codable {
    let user: VercelUserInfo
}

struct VercelUserInfo: Codable {
    let id: String
    let email: String?
    let name: String?
    let username: String?
}
