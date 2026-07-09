import Foundation

enum CelebrationSound: String, CaseIterable, Codable {
    case yeahBoy
    case isntThatAmazing
    case carHorn
    case what
    case fart
    case faah

    var fileName: String { rawValue }

    var displayName: String {
        switch self {
        case .yeahBoy: return "Yeah Boy!"
        case .isntThatAmazing: return "Isn't That Amazing"
        case .carHorn: return "Goofy Car Horn"
        case .what: return "What?!"
        case .fart: return "Fart"
        case .faah: return "Faah"
        }
    }

    static let successBucket: [CelebrationSound] = [.yeahBoy, .isntThatAmazing, .carHorn]
    static let failureBucket: [CelebrationSound] = [.what, .fart, .faah]

    static let defaultSuccess: CelebrationSound = .yeahBoy
    static let defaultFailure: CelebrationSound = .what
}
