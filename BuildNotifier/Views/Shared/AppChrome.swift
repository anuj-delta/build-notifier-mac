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

    static let radiusSmall: CGFloat = 6
    static let radiusMedium: CGFloat = 8
    static let radiusLarge: CGFloat = 10
}
