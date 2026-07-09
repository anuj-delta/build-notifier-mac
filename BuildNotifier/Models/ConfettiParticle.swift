import CoreGraphics
import Foundation

enum ConfettiShape: Int, CaseIterable {
    case rectangle
    case circle
    case triangle
}

/// A single confetti piece. State is described in closed form (no per-frame
/// accumulation) so a piece's position/angle/opacity at any time `t` is a pure
/// function of its spawn parameters. This keeps the simulation deterministic and
/// unit-testable, and lets the Canvas simply evaluate every piece each frame.
///
/// Coordinates are normalized (0...1) relative to the canvas and scaled at draw time.
struct ConfettiParticle {
    var x0: Double
    var y0: Double
    var vx: Double
    var vy: Double
    var rotation0: Double
    var angularVelocity: Double
    var size: Double
    var colorIndex: Int
    var shape: ConfettiShape
    var spawnDelay: Double
    var lifetime: Double

    /// Normalized gravity (units per second squared).
    static let gravity: Double = 0.35

    private static let fadeInDuration: Double = 0.2
    private static let fadeOutDuration: Double = 0.8

    func localTime(at t: Double) -> Double {
        max(0, t - spawnDelay)
    }

    func position(at t: Double) -> CGPoint {
        let tau = localTime(at: t)
        let x = x0 + vx * tau
        let y = y0 + vy * tau + 0.5 * Self.gravity * tau * tau
        return CGPoint(x: x, y: y)
    }

    func angle(at t: Double) -> Double {
        rotation0 + angularVelocity * localTime(at: t)
    }

    func opacity(at t: Double) -> Double {
        if t < spawnDelay { return 0 }
        let tau = localTime(at: t)
        if tau >= lifetime { return 0 }

        if tau < Self.fadeInDuration {
            return tau / Self.fadeInDuration
        }
        let fadeOutStart = lifetime - Self.fadeOutDuration
        if tau > fadeOutStart {
            return max(0, (lifetime - tau) / Self.fadeOutDuration)
        }
        return 1
    }

    static func spawnBurst(count: Int, seed: UInt64) -> [ConfettiParticle] {
        var rng = SeededGenerator(seed: seed)
        var particles: [ConfettiParticle] = []
        particles.reserveCapacity(count)

        for _ in 0..<count {
            let particle = ConfettiParticle(
                x0: Double.random(in: -0.05...1.05, using: &rng),
                y0: Double.random(in: (-0.2)...(-0.02), using: &rng),
                vx: Double.random(in: -0.12...0.12, using: &rng),
                vy: Double.random(in: 0.12...0.4, using: &rng),
                rotation0: Double.random(in: 0...(2 * .pi), using: &rng),
                angularVelocity: Double.random(in: -6...6, using: &rng),
                size: Double.random(in: 7...14, using: &rng),
                colorIndex: Int.random(in: 0...9, using: &rng),
                shape: ConfettiShape.allCases.randomElement(using: &rng) ?? .rectangle,
                spawnDelay: Double.random(in: 0...0.7, using: &rng),
                lifetime: Double.random(in: 3.4...4.6, using: &rng)
            )
            particles.append(particle)
        }
        return particles
    }
}

/// Deterministic RNG (SplitMix64) so seeded bursts reproduce exactly in tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
