import Foundation

/// Who lives in the attic.
///
/// The owl is the app and stays the default; the puppy is a second set of paintings and
/// nothing else. No behaviour changes with the character: the voice, the modes, the
/// idle repertoire and the room are the same code, because everything visual already
/// went through `OwlRig` before there was anything to choose between.
enum Character: String, CaseIterable, Identifiable {
    case owl
    case dog

    var id: String { rawValue }

    /// The prefix on every painting of this character — `owl_base`, `dog_blink`.
    var artPrefix: String { rawValue }

    /// For the settings screen and this file. The child never sees a word of it; they
    /// see the animal.
    var name: String {
        switch self {
        case .owl: return "The owl"
        case .dog: return "The puppy"
        }
    }

    /// Whether this character's paintings are in the bundle.
    ///
    /// A character whose artwork has not landed is not offered at all, rather than
    /// offered and then drawn as nothing. Only the base painting has to be there; every
    /// expression frame is optional for every character and the rig falls back to the
    /// base, which is the same bargain the owl has always had.
    var isAvailable: Bool { ArtTexture.exists("\(artPrefix)_base") }

    /// In `allCases` order, so the owl is always first and the room is never rearranged
    /// by which paintings happen to have arrived.
    static var available: [Character] { allCases.filter(\.isAvailable) }

    /// The one the room starts with, and the one it falls back to.
    static let fallback: Character = .owl
}
