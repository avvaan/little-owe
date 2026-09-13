import SpriteKit
import UIKit

/// SpriteKit has no gradient primitive, so we bake small textures once at scene
/// build time. Sizes stay modest because everything is stretched by the sprite.
enum GradientTexture {

    /// Colours run top to bottom, `colors.first` at the top.
    static func vertical(_ colors: [SKColor], size: CGSize = CGSize(width: 8, height: 256)) -> SKTexture {
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors.map(\.cgColor) as CFArray,
                locations: nil
            ) else { return }
            cg.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    /// Soft round glow, opaque in the middle and fully transparent at the rim.
    /// Used for the sun, the moon halo and the lamp.
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

    /// Hard-edged white disc. Used as an `SKCropNode` mask — shape nodes are unreliable
    /// as masks on some GPUs, and this costs one small texture.
    static func solidCircle(diameter: CGFloat) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
        return SKTexture(image: image)
    }
}
