import SwiftUI

enum AppChrome {
    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let bestAppearance = appearance.bestMatch(from: [.darkAqua, .aqua])
            return bestAppearance == .darkAqua ? dark : light
        })
    }

    static let window = dynamicColor(
        light: NSColor(calibratedWhite: 0.965, alpha: 1),
        dark: NSColor(calibratedWhite: 0.118, alpha: 1)
    )

    static let surface = dynamicColor(
        light: NSColor(calibratedWhite: 0.995, alpha: 1),
        dark: NSColor(calibratedWhite: 0.155, alpha: 1)
    )

    static let surfaceMuted = dynamicColor(
        light: NSColor(calibratedWhite: 0.972, alpha: 1),
        dark: NSColor(calibratedWhite: 0.182, alpha: 1)
    )

    static let border = dynamicColor(
        light: NSColor(calibratedWhite: 0.86, alpha: 1),
        dark: NSColor(calibratedWhite: 0.28, alpha: 1)
    )

    static let separator = dynamicColor(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.07),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.09)
    )

    /// Hairline for the outer edge of translucent surfaces. Kept lighter than
    /// `border` so glass reads as a single crisp edge, not a stacked frame.
    static let glassStroke = dynamicColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.5),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.12)
    )

    /// Calm translucent fill for grouped cards layered over a glass surface.
    /// Legible without going fully opaque.
    static let glassPanel = dynamicColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.5),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.045)
    )

    static let text = dynamicColor(
        light: NSColor(calibratedWhite: 0.12, alpha: 1),
        dark: NSColor(calibratedWhite: 0.94, alpha: 1)
    )

    /// A defined weight between `text` and `textMuted` for supporting text (commit
    /// authors). A solid token rather than `text.opacity(...)` so it keeps its
    /// vibrancy over the translucent popover instead of thinning out.
    static let textSecondary = dynamicColor(
        light: NSColor(calibratedWhite: 0.34, alpha: 1),
        dark: NSColor(calibratedWhite: 0.78, alpha: 1)
    )

    static let textMuted = dynamicColor(
        light: NSColor(calibratedWhite: 0.44, alpha: 1),
        dark: NSColor(calibratedWhite: 0.66, alpha: 1)
    )

    static let accent = dynamicColor(
        light: NSColor(calibratedRed: 0.0, green: 0.48, blue: 1.0, alpha: 1),
        dark: NSColor(calibratedRed: 0.28, green: 0.60, blue: 1.0, alpha: 1)
    )

    static let accentSoft = dynamicColor(
        light: NSColor(calibratedRed: 0.0, green: 0.48, blue: 1.0, alpha: 0.10),
        dark: NSColor(calibratedRed: 0.30, green: 0.62, blue: 1.0, alpha: 0.18)
    )

    static let hover = dynamicColor(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.03),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.05)
    )

    static let rowHover = dynamicColor(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.05),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.07)
    )

    static let focus = dynamicColor(
        light: NSColor(calibratedRed: 0.0, green: 0.48, blue: 1.0, alpha: 0.30),
        dark: NSColor(calibratedRed: 0.30, green: 0.62, blue: 1.0, alpha: 0.50)
    )

    static let warning = dynamicColor(
        light: NSColor(calibratedRed: 0.78, green: 0.45, blue: 0.05, alpha: 1),
        dark: NSColor(calibratedRed: 0.93, green: 0.67, blue: 0.28, alpha: 1)
    )

    static let danger = dynamicColor(
        light: NSColor(calibratedRed: 0.86, green: 0.24, blue: 0.20, alpha: 1),
        dark: NSColor(calibratedRed: 0.98, green: 0.42, blue: 0.40, alpha: 1)
    )

    static let success = dynamicColor(
        light: NSColor(calibratedRed: 0.18, green: 0.63, blue: 0.26, alpha: 1),
        dark: NSColor(calibratedRed: 0.25, green: 0.72, blue: 0.31, alpha: 1)
    )

    static let successSoft = dynamicColor(
        light: NSColor(calibratedRed: 0.18, green: 0.63, blue: 0.26, alpha: 0.14),
        dark: NSColor(calibratedRed: 0.25, green: 0.72, blue: 0.31, alpha: 0.17)
    )

    /// Reserved for the devnet-deploy signal. Violet so it never reads as the blue PR
    /// pill or the green build status.
    static let deploy = dynamicColor(
        light: NSColor(calibratedRed: 0.42, green: 0.30, blue: 1.0, alpha: 1),
        dark: NSColor(calibratedRed: 0.61, green: 0.53, blue: 1.0, alpha: 1)
    )

    /// Soft fill paired with `deploy`, reserved for a deployed-row highlight background.
    static let deploySoft = dynamicColor(
        light: NSColor(calibratedRed: 0.42, green: 0.30, blue: 1.0, alpha: 0.12),
        dark: NSColor(calibratedRed: 0.61, green: 0.53, blue: 1.0, alpha: 0.18)
    )

    /// The sigma-deploy signal. Teal so it reads as its own environment, distinct from the
    /// violet devnet badge, the blue PR pill, and the green build status.
    static let sigmaDeploy = dynamicColor(
        light: NSColor(calibratedRed: 0.0, green: 0.58, blue: 0.53, alpha: 1),
        dark: NSColor(calibratedRed: 0.28, green: 0.82, blue: 0.75, alpha: 1)
    )

    static let radiusSmall: CGFloat = 6
    static let radiusMedium: CGFloat = 8
    static let radiusLarge: CGFloat = 10
    static let radiusCard: CGFloat = 12
    static let radiusWindow: CGFloat = 13
    static let radiusModal: CGFloat = 16
}

extension DeployEnvironment {
    /// Badge tint for the "currently deployed" indicator on a build row.
    var badgeColor: Color {
        switch self {
        case .devnet: return AppChrome.deploy
        case .sigma: return AppChrome.sigmaDeploy
        }
    }

    /// SF Symbol for the badge, so environments are distinguishable by shape and not
    /// color alone.
    var badgeIcon: String {
        switch self {
        case .devnet: return "hexagon.fill"
        case .sigma: return "diamond.fill"
        }
    }
}

/// Column widths shared by CircleCI and Vercel rows so the leading status glyph
/// and trailing timestamp line up across both providers - the alignment only
/// holds if both rows use the same values, so they live in one place.
enum RowLayout {
    static let statusColumnWidth: CGFloat = 14
    static let trailingColumnWidth: CGFloat = 62
}

/// Named animations so hover, state, and gesture-driven motion stay consistent
/// and interruptible across the app instead of re-declaring timings inline.
enum Motion {
    /// Instant-feeling feedback for hover in/out.
    static let hover: Animation = .easeOut(duration: 0.12)
    /// Discrete state flips (selection, visibility) that aren't gesture-driven.
    static let state: Animation = .easeInOut(duration: 0.16)
    /// Critically-damped spring for expand/collapse and overlays - settles without
    /// overshoot and can be grabbed/reversed mid-flight.
    static let spring: Animation = .spring(response: 0.28, dampingFraction: 0.92)
}

/// Shared text styles for the menu-bar surface. Large styles carry a small
/// negative tracking (letters read too far apart as size grows); body/caption
/// stay at the system default.
enum Typography {
    static let title = Font.system(size: 15, weight: .semibold)
    static let emptyTitle = Font.system(size: 18, weight: .semibold)
    static let sectionHeader = Font.system(size: 12, weight: .semibold)
    static let sectionSubtitle = Font.system(size: 11, weight: .regular)
    static let rowTitle = Font.system(size: 13, weight: .semibold)
    static let rowMeta = Font.system(size: 12, weight: .regular)
    static let rowAuthor = Font.system(size: 12, weight: .medium)

    /// Tracking for a given style. Negative for >=15pt display text, 0 elsewhere.
    static func tracking(forSize size: CGFloat) -> CGFloat {
        size >= 15 ? -0.3 : 0
    }
}

extension View {
    /// Applies a Typography style together with the tracking that matches its size.
    func typographyTracking(forSize size: CGFloat) -> some View {
        tracking(Typography.tracking(forSize: size))
    }
}
