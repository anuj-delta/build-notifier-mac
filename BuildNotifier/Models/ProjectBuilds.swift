import Foundation

/// One branch and the build shown for it.
struct BranchBuild: Identifiable {
    let branch: String
    let build: Build

    var id: String { branch }
}

/// A project's branches in display order, newest first.
struct ProjectBuilds: Identifiable {
    let project: WatchedProject
    let branches: [BranchBuild]

    var id: WatchedProject.ID { project.id }
}
