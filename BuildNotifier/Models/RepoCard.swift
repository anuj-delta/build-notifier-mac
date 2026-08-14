import Foundation

/// One repository, with everything both providers report about it. A card exists for a watched
/// CircleCI project, for a watched Vercel project, or for the two of them linked by repository.
struct RepoCard: Identifiable {
    /// The CircleCI project id (`gh/org/repo`), or `vercel:<projectId>` with no CircleCI side.
    let id: String
    let title: String
    let circleCI: WatchedProject?
    let vercel: [WatchedVercelProject]
    let branches: [BranchActivity]
}

/// One branch, with the build and the deployments shown for it. Either side can be empty: a
/// branch can have a build and no deployment, or a deployment and no build.
struct BranchActivity: Identifiable {
    let branch: String
    let build: Build?
    let span: WorkflowSpan?
    let deployments: [BranchDeployment]

    var id: String { branch }
}

/// The newest deployment of one branch on one Vercel project and target.
struct BranchDeployment: Identifiable {
    let project: WatchedVercelProject
    let deployment: VercelDeployment

    var id: String { deployment.uid }
}

/// When a workflow started and, once every job it has reported is done, when it stopped.
///
/// The v1.1 builds endpoint is job-level, so a workflow spans the earliest job start to
/// the latest job stop. Reading either timestamp off one job gives the wrong answer: the
/// newest job of a long workflow starts seconds before the workflow ends.
struct WorkflowSpan: Equatable {
    let started: Date?
    let stopped: Date?

    init(jobs: [Build]) {
        started = jobs.compactMap(\.startedDate).min()
        stopped = jobs.allSatisfy(\.buildStatus.isTerminal) ? jobs.compactMap(\.stoppedDate).max() : nil
    }

    /// `inProgress` decides which end of the span to show, because the v2 workflow status
    /// knows about jobs that have not been created yet and the job list does not.
    func label(inProgress: Bool) -> String {
        if inProgress {
            guard let started else { return "queued" }
            return "running \(Self.elapsed(since: started))"
        }
        guard let stamp = stopped ?? started else { return "unknown" }
        return "\(Self.elapsed(since: stamp)) ago"
    }

    private static func elapsed(since date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86400))d"
    }
}
