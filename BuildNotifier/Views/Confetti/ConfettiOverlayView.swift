import SwiftUI

/// What a confetti burst is celebrating, which sets the banner headline. A
/// production deploy and a non-production deploy (devnet, sigma, ...) read
/// differently to the user, and each environment names itself in the banner.
enum CelebrationKind: Equatable {
    case production
    case deploy(DeployEnvironment)

    var headline: String {
        switch self {
        case .production: return "Shipped to production"
        case .deploy(let env): return "Deployed to \(env.label)"
        }
    }
}

/// One thing being celebrated. `title` is the headline subject (branch for a
/// deploy, project slug for production); `subtitle` is the supporting line (the
/// repo for a deploy), shown muted below the titles.
struct CelebrationSubject: Equatable {
    let title: String
    let subtitle: String?
}

@MainActor
@Observable
final class ConfettiOverlayModel {
    var subjects: [CelebrationSubject] = []
    var isDismissing = false
    var headline: String = CelebrationKind.production.headline
    private var resolvedKind: CelebrationKind?

    /// Titles across all coalesced bursts, joined for the primary line.
    var titleLine: String {
        subjects.map(\.title).joined(separator: ", ")
    }

    /// Distinct subtitles (repos) across all coalesced bursts, joined for the
    /// supporting line. Empty when nothing carried a subtitle.
    var subtitleLine: String {
        var seen: Set<String> = []
        let ordered = subjects.compactMap(\.subtitle).filter { seen.insert($0).inserted }
        return ordered.joined(separator: ", ")
    }

    func addSubject(title: String, subtitle: String? = nil) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let trimmedSubtitle = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSubtitle = (trimmedSubtitle?.isEmpty ?? true) ? nil : trimmedSubtitle
        let subject = CelebrationSubject(title: trimmedTitle, subtitle: resolvedSubtitle)
        guard !subjects.contains(subject) else { return }
        subjects.append(subject)
    }

    /// Sets the banner headline for this burst. When bursts coalesce into one
    /// overlay, a production deploy wins over any deploy, and the first deploy
    /// environment resolved wins over later ones so the headline stays stable.
    func applyKind(_ kind: CelebrationKind) {
        if resolvedKind == .production { return }
        if case .deploy = resolvedKind, case .deploy = kind { return }
        resolvedKind = kind
        headline = kind.headline
    }

    func reset() {
        subjects = []
        isDismissing = false
        resolvedKind = nil
        headline = CelebrationKind.production.headline
    }
}

struct ConfettiOverlayView: View {
    @Bindable var model: ConfettiOverlayModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var particles = ConfettiParticle.spawnBurst(
        count: 200,
        seed: UInt64.random(in: 0...UInt64.max)
    )
    @State private var bannerVisible = false

    private static let palette: [Color] = [
        Color(red: 0.98, green: 0.30, blue: 0.36),
        Color(red: 1.00, green: 0.72, blue: 0.20),
        Color(red: 0.30, green: 0.78, blue: 0.45),
        Color(red: 0.26, green: 0.60, blue: 1.00),
        Color(red: 0.72, green: 0.42, blue: 0.98),
        Color(red: 1.00, green: 0.48, blue: 0.72),
        Color(red: 0.20, green: 0.82, blue: 0.80),
        Color(red: 1.00, green: 0.85, blue: 0.35),
        Color(red: 0.55, green: 0.85, blue: 0.30),
        Color(red: 0.98, green: 0.58, blue: 0.25),
    ]

    var body: some View {
        ZStack {
            if !reduceMotion {
                confettiCanvas
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                    .opacity(model.isDismissing ? 0 : 1)
                    .animation(.easeOut(duration: 0.4), value: model.isDismissing)
            }

            banner
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.25)
                                       : .spring(response: 0.5, dampingFraction: 0.7)) {
                bannerVisible = true
            }
        }
    }

    private var confettiCanvas: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                for particle in particles {
                    let opacity = particle.opacity(at: t)
                    guard opacity > 0 else { continue }

                    let normalized = particle.position(at: t)
                    let center = CGPoint(x: normalized.x * size.width,
                                         y: normalized.y * size.height)
                    guard center.y - particle.size < size.height else { continue }

                    let path = Self.path(for: particle.shape, size: particle.size)
                    let transform = CGAffineTransform(rotationAngle: particle.angle(at: t))
                        .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
                    let color = Self.palette[particle.colorIndex % Self.palette.count]
                    context.fill(path.applying(transform), with: .color(color.opacity(opacity)))
                }
            }
        }
    }

    private var banner: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(AppChrome.success)

            VStack(spacing: 7) {
                Text(model.headline.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(AppChrome.textSecondary)

                Text(model.titleLine)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(AppChrome.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)

                if !model.subtitleLine.isEmpty {
                    Text(model.subtitleLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppChrome.textMuted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thickMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AppChrome.glassStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 30, y: 14)
        .scaleEffect(bannerVisible && !model.isDismissing ? 1 : 0.9)
        .opacity(bannerVisible && !model.isDismissing ? 1 : 0)
        .animation(.easeOut(duration: 0.4), value: model.isDismissing)
        .frame(maxWidth: 420)
    }

    private static func path(for shape: ConfettiShape, size: Double) -> Path {
        let half = size / 2
        let rect = CGRect(x: -half, y: -half, width: size, height: size)
        switch shape {
        case .rectangle:
            return Path(CGRect(x: -half, y: -half * 0.6, width: size, height: size * 0.6))
        case .circle:
            return Path(ellipseIn: rect)
        case .triangle:
            var path = Path()
            path.move(to: CGPoint(x: 0, y: -half))
            path.addLine(to: CGPoint(x: half, y: half))
            path.addLine(to: CGPoint(x: -half, y: half))
            path.closeSubpath()
            return path
        }
    }
}
