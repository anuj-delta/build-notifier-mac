import SwiftUI

/// Provider-agnostic status bucket shared by CircleCI and Vercel rows so both
/// render the same inline affordances. Running and queued are kept distinct for
/// labels/accessibility but both count as in-progress for the shimmer + arc.
enum RowStatus {
    case success
    case running
    case queued
    case failed
    case onHold
    case canceled
    case neutral

    init(_ status: BuildStatus) {
        switch status {
        case .success, .fixed:
            self = .success
        case .running, .notRunning:
            self = .running
        case .queued, .scheduled:
            self = .queued
        case .failed, .timedout, .infrastructureFail:
            self = .failed
        case .onHold:
            self = .onHold
        case .canceled:
            self = .canceled
        case .retried, .noTests, .notRun, .unknown:
            self = .neutral
        }
    }

    init(_ status: VercelDeploymentStatus) {
        switch status {
        case .ready:
            self = .success
        case .building, .initializing:
            self = .running
        case .queued:
            self = .queued
        case .error:
            self = .failed
        case .canceled:
            self = .canceled
        case .unknown:
            self = .neutral
        }
    }

    /// Running and queued are both "in progress" - they shimmer + show the arc
    /// instead of a static glyph.
    var isInProgress: Bool { self == .running || self == .queued }

    /// SF Symbol for the trailing glyph, or nil when the state needs no glyph
    /// (in-progress is conveyed by the shimmer + arc instead).
    var glyphSymbol: String? {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .onHold: return "pause.circle.fill"
        case .canceled: return "slash.circle"
        case .running, .queued, .neutral: return nil
        }
    }

    var glyphColor: Color {
        switch self {
        case .success: return AppChrome.success
        case .failed: return AppChrome.danger
        case .onHold: return AppChrome.warning
        case .canceled, .running, .queued, .neutral: return AppChrome.textMuted
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .success: return "Succeeded"
        case .running: return "Running"
        case .queued: return "Queued"
        case .failed: return "Failed"
        case .onHold: return "On hold"
        case .canceled: return "Canceled"
        case .neutral: return "Unknown status"
        }
    }
}

/// Leading status affordance for a build/deployment row. Renders nothing for
/// in-progress (the shimmering label + arc carry that) or neutral states.
struct StatusGlyph: View {
    let status: RowStatus

    var body: some View {
        if let symbol = status.glyphSymbol {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(status.glyphColor)
                .help(status.accessibilityLabel)
                .accessibilityLabel(status.accessibilityLabel)
        }
    }
}

/// Small native indeterminate spinner for in-progress rows.
struct RunningSpinner: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .scaleEffect(0.72)
            .frame(width: 13, height: 13)
    }
}

#Preview("Row statuses") {
    let cases: [(String, RowStatus)] = [
        ("success", .success), ("running", .running), ("queued", .queued),
        ("failed", .failed), ("onHold", .onHold), ("canceled", .canceled), ("neutral", .neutral)
    ]
    return VStack(alignment: .leading, spacing: 12) {
        ForEach(cases, id: \.0) { name, status in
            HStack(spacing: 8) {
                Text("feat/\(name)-branch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppChrome.text)
                    .shimmering(active: status.isInProgress)
                if status.isInProgress {
                    RunningSpinner()
                } else {
                    StatusGlyph(status: status)
                }
            }
        }
    }
    .padding(24)
    .frame(width: 260)
}
