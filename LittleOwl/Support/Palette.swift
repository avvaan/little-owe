import SpriteKit

/// Every colour in the room lives here so the whole scene can be re-tinted at once
/// when final art arrives. Values are deliberately warm and low-contrast: this is a
/// bedtime attic, not a toy shop.
enum Palette {

    // MARK: Room

    static let wallUpper        = SKColor(hex: 0x6E5A4E)
    static let wallLower        = SKColor(hex: 0x8A7263)
    /// The sloped ceiling coming towards the viewer: darker where it is nearest the
    /// camera, lighter where it meets the gable wall.
    static let roofNear         = SKColor(hex: 0x332720)
    static let roofFar          = SKColor(hex: 0x5C4938)
    static let roofSeam         = SKColor(hex: 0x241B16)
    static let rafter           = SKColor(hex: 0x4E3D33)
    static let floorPlank       = SKColor(hex: 0x7A5A41)
    static let floorPlankAlt    = SKColor(hex: 0x6E5039)
    static let floorSeam        = SKColor(hex: 0x5A4130)

    static let rug              = SKColor(hex: 0xB5635A)
    static let rugInner         = SKColor(hex: 0xC9786C)
    static let rugTrim          = SKColor(hex: 0xE2B08A)

    static let wood             = SKColor(hex: 0x8B6742)
    static let woodDark         = SKColor(hex: 0x6B4F32)
    static let woodLight        = SKColor(hex: 0xA9835A)

    // MARK: Props

    static let bookCover        = SKColor(hex: 0x3F7D6E)
    static let bookPage         = SKColor(hex: 0xF4E9D2)
    static let bookPageShade    = SKColor(hex: 0xDFD0B4)

    static let lampShade        = SKColor(hex: 0xE8B15C)
    static let lampShadeLit     = SKColor(hex: 0xFFD68C)
    static let lampBase         = SKColor(hex: 0x59636B)
    static let lampGlow         = SKColor(hex: 0xFFD79A)

    static let blockFaces: [SKColor] = [
        SKColor(hex: 0xD98E63),
        SKColor(hex: 0x7FA8A0),
        SKColor(hex: 0xE0C169)
    ]
    static let blockEdge        = SKColor(hex: 0x8A5C3E)

    // MARK: Owl (placeholder rig only — final values come from the artist)

    static let owlBody          = SKColor(hex: 0xA98259)
    static let owlBodyShade     = SKColor(hex: 0x8D6A45)
    static let owlBelly         = SKColor(hex: 0xE9D4B0)
    static let owlFace          = SKColor(hex: 0xF0DCBB)
    static let owlBeak          = SKColor(hex: 0xE0A24C)
    static let owlBeakShade     = SKColor(hex: 0xC5883A)
    static let owlEyeWhite      = SKColor(hex: 0xFFFCF4)
    static let owlPupil         = SKColor(hex: 0x2E2419)
    static let owlFoot          = SKColor(hex: 0xD9954A)

    // MARK: Sky (per time of day, top colour first)

    static let skyMorning       = [SKColor(hex: 0xFFD9A0), SKColor(hex: 0xFFF1D6), SKColor(hex: 0xE9F0DA)]
    static let skyDay           = [SKColor(hex: 0x7FB6E8), SKColor(hex: 0xAFD6F2), SKColor(hex: 0xDCEEF9)]
    static let skyEvening       = [SKColor(hex: 0x3B3A72), SKColor(hex: 0x8A5A86), SKColor(hex: 0xE39A6A)]
    static let skyNight         = [SKColor(hex: 0x141A38), SKColor(hex: 0x1E2A4E), SKColor(hex: 0x2B3A63)]

    static let sun              = SKColor(hex: 0xFFF3C4)
    static let cloud            = SKColor(white: 1.0, alpha: 0.92)
    static let moon             = SKColor(hex: 0xF6F1DC)
    static let star             = SKColor(hex: 0xFFFBE8)

    /// Warm/cool wash laid over the whole room so the time of day is felt, not just
    /// seen through the glass.
    static func ambientWash(for time: TimeOfDay) -> (color: SKColor, alpha: CGFloat, blend: SKBlendMode) {
        switch time {
        case .morning: return (SKColor(hex: 0xFFC978), 0.14, .add)
        case .day:     return (SKColor(hex: 0xFFF6E2), 0.06, .add)
        case .evening: return (SKColor(hex: 0xC97A5A), 0.12, .add)
        case .night:   return (SKColor(hex: 0x5C6BA8), 0.22, .multiplyX2)
        }
    }
}

extension SKColor {
    convenience init(hex: UInt32) {
        self.init(
            red:   CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue:  CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
