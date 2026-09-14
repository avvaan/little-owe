import SpriteKit
import UIKit

/// SpriteKit has no gradient primitive, so we bake one small texture at scene build
/// time. It stays modest in size because everything stretches it.
enum GradientTexture {

    /// Soft round glow, opaque in the middle and fully transparent at the rim. Used for
    /// the owl's contact shadow and for the bloom that answers a tap on a painted prop.
    static func radialGlow(_ color: SKColor, diameter: CGFloat = 256) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let colors = [
                color.withAlphaComponent(1.0).cgColor,
                color.withAlphaComponent(0.45).cgColor,
                color.withAlphaComponent(0.0).cgColor
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0.0, 0.45, 1.0]
            ) else { return }
            let centre = CGPoint(x: diameter / 2, y: diameter / 2)
            cg.drawRadialGradient(
                gradient,
                startCenter: centre, startRadius: 0,
                endCenter: centre, endRadius: diameter / 2,
                options: []
            )
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    /// The opposite: clear in the middle, dark at the rim.
    ///
    /// A mode needs the child's eye in the middle of the screen, and the old way of
    /// getting it was a black sheet over the whole room. That reads as a dimmed screen
    /// rather than as an owl in its house — the room, which is most of the charm, simply
    /// went away whenever anything happened in it. A vignette does the same job by
    /// darkening the corners and leaving the room lit.
    static func vignette(_ color: SKColor = .black, diameter: CGFloat = 512) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let colors = [
                color.withAlphaComponent(0.0).cgColor,
                color.withAlphaComponent(0.0).cgColor,
                color.withAlphaComponent(0.55).cgColor,
                color.withAlphaComponent(0.92).cgColor
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                // Clear across the middle half, then falling away quickly.
                locations: [0.0, 0.42, 0.78, 1.0]
            ) else { return }
            let centre = CGPoint(x: diameter / 2, y: diameter / 2)
            cg.drawRadialGradient(
                gradient,
                startCenter: centre, startRadius: 0,
                endCenter: centre, endRadius: diameter / 2,
                options: [.drawsAfterEndLocation]
            )
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }
}
