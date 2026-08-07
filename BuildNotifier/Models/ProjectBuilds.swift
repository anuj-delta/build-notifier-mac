import Foundation

/// One branch, the build shown for it, and how long its workflow has been going.
struct BranchBuild: Identifiable {
    let branch: String
    let build: Build
    let span: WorkflowSpan

    var id: String { branch }
}

/// A project's branches in display order, newest first.
struct ProjectBuilds: Identifiable {
    let project: WatchedProject
    let branches: [BranchBuild]

    var id: WatchedProject.ID { project.id }
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
