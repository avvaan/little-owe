import SpriteKit
import UIKit

/// Loading a painting out of the bundle, by name, whatever it was saved as.
///
/// This exists because of a bug that reached a child's iPad: the room appeared as a
/// giant red cross on white, which is what SpriteKit draws when a texture is missing.
/// Every painting in `Resources/Art` is a PNG except the room, which is a JPEG because
/// it is a full-screen photograph-like painting and a PNG of it is six times the size.
///
/// `SKSpriteNode(imageNamed:)` goes through `UIImage(named:)`, and for a loose file in
/// the bundle — rather than an entry in an asset catalogue — that **assumes `.png`**. So
/// every painting loaded and the one JPEG did not, silently, all the way through a
/// green build and an upload.
///
/// So: ask the bundle which file is actually there, and load that. No guessing, and a
/// missing painting fails loudly in a debug build instead of being drawn as a cross.
enum ArtTexture {

    /// The extensions the export script produces. Order is preference, not search cost.
    static let extensions = ["png", "jpg", "jpeg"]

    /// Where a painting lives, or nil if the bundle has no such painting.
    static func url(named name: String, in bundle: Bundle = .main) -> URL? {
        for ext in extensions {
            if let url = bundle.url(forResource: name, withExtension: ext) { return url }
        }
        return nil
    }

    static func exists(_ name: String, in bundle: Bundle = .main) -> Bool {
        url(named: name, in: bundle) != nil
    }

    /// Nil rather than a red cross. Callers that cannot do without the painting say so
    /// with `required(_:)`.
    static func texture(named name: String, in bundle: Bundle = .main) -> SKTexture? {
        guard let url = url(named: name, in: bundle),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    /// For the paintings the room cannot be assembled without.
    ///
    /// A debug build stops on the missing name, which is the thing that was wanted here
    /// and was not there. A release build carries on with an empty sprite: a room with a
    /// hole in it is bad, and a room that is a red cross is worse.
    static func required(_ name: String, in bundle: Bundle = .main) -> SKTexture? {
        let texture = texture(named: name, in: bundle)
        assert(texture != nil, "No painting called \(name) in the bundle")
        return texture
    }

    /// An `SKSpriteNode` for a painting that must be there.
    static func sprite(_ name: String, in bundle: Bundle = .main) -> SKSpriteNode {
        guard let texture = required(name, in: bundle) else { return SKSpriteNode() }
        return SKSpriteNode(texture: texture)
    }
}
