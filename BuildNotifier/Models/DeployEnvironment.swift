import Foundation

/// A non-production environment that CircleCI workflows deploy a branch to. The menubar
/// shows a small badge for the branch currently live on each environment. Adding a new
/// environment is a matter of adding a case and its deploy workflow names here.
enum DeployEnvironment: String, CaseIterable {
    case devnet
    case sigma

    /// Workflow names that deploy to this environment. `devnet-manual-deploy` and
    /// `sigma-manual-deploy` deploy any branch on demand; `build-and-deploy` continuously
    /// deploys non-production branches to devnet.
    var deployWorkflows: Set<String> {
        switch self {
        case .devnet: return ["devnet-manual-deploy", "build-and-deploy"]
        case .sigma: return ["sigma-manual-deploy"]
        }
    }

    var label: String { rawValue }

    /// Whether a build deploys to this environment. `build-and-deploy` also runs on
    /// production branches for prod, so those are excluded via `productionBranches`.
    func isDeploy(_ build: Build, productionBranches: [String]) -> Bool {
        guard let workflow = build.workflows?.workflowName?.lowercased(),
              deployWorkflows.contains(workflow) else {
            return false
        }
        if workflow == "build-and-deploy",
           ProductionBranchMatcher.isProduction(branch: build.branch, patterns: productionBranches) {
            return false
        }
        return true
    }

    /// Unique deploy workflows for a project's builds, newest first. Callers probe these
    /// against the v2 workflow status and take the newest one that reads `success`.
    func deployWorkflowsNewestFirst(
        builds: [Build],
        productionBranches: [String]
    ) -> [(workflowId: String, branch: String)] {
        var latestByWorkflow: [String: Build] = [:]
        for build in builds where isDeploy(build, productionBranches: productionBranches) {
            guard let workflowId = build.workflows?.workflowId else { continue }
            if let existing = latestByWorkflow[workflowId],
               (existing.activityDate ?? .distantPast) >= (build.activityDate ?? .distantPast) {
                continue
            }
            latestByWorkflow[workflowId] = build
        }
        return latestByWorkflow
            .sorted { ($0.value.activityDate ?? .distantPast) > ($1.value.activityDate ?? .distantPast) }
            .compactMap { workflowId, build in
                build.branch.map { (workflowId: workflowId, branch: $0) }
            }
    }
}
