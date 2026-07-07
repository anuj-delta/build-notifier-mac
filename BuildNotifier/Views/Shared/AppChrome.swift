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
        light: NSColor(calibratedWhite: 0.90, alpha: 1),
        dark: NSColor(calibratedWhite: 0.24, alpha: 1)
    )

    static let text = dynamicColor(
        light: NSColor(calibratedWhite: 0.12, alpha: 1),
        dark: NSColor(calibratedWhite: 0.94, alpha: 1)
    )

    static let textMuted = dynamicColor(
        light: NSColor(calibratedWhite: 0.44, alpha: 1),
        dark: NSColor(calibratedWhite: 0.66, alpha: 1)
    )

    static let accent = Color(red: 0.15, green: 0.40, blue: 0.88)

    static let accentSoft = dynamicColor(
        light: NSColor(calibratedRed: 0.15, green: 0.40, blue: 0.88, alpha: 0.08),
        dark: NSColor(calibratedRed: 0.15, green: 0.40, blue: 0.88, alpha: 0.20)
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
        light: NSColor(calibratedRed: 0.15, green: 0.40, blue: 0.88, alpha: 0.28),
        dark: NSColor(calibratedRed: 0.33, green: 0.56, blue: 0.98, alpha: 0.45)
    )

    static let warning = dynamicColor(
        light: NSColor(calibratedRed: 0.78, green: 0.45, blue: 0.05, alpha: 1),
        dark: NSColor(calibratedRed: 0.93, green: 0.67, blue: 0.28, alpha: 1)
    )

    static let radiusSmall: CGFloat = 6
    static let radiusMedium: CGFloat = 8
    static let radiusLarge: CGFloat = 10
}
