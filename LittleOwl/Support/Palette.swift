import SpriteKit

/// What little colour the code still owns.
///
/// The room, the owl and the props are painted artwork now (`LittleOwl/Resources/Art`),
/// so the long list of vector-shape colours this file used to hold is gone. What is
/// left is light the code applies *over* the painting.
enum Palette {

    /// Behind the scene, visible only in the sliver `.aspectFill` may leave while the
    /// room texture loads. Matches the darkest wood in the painting.
    static let roomShadow = SKColor(hex: 0x2A211C)

    /// The bloom that answers a tap on a prop painted into the room.
    static let tapGlow = SKColor(hex: 0xFFE6B0)

    /// Warm or cool wash laid over the whole room, so the time of day is felt and not
    /// only seen through the glass.
    ///
    /// Kept gentle on purpose: the painting already carries its own light — a lit lamp,
    /// a warm floor — and a heavy tint fights it. A fuller day/night would need the
    /// room repainted at each time of day; see `docs/ART_BRIEF.md`.
    ///
    /// **Every entry uses a blend where `alpha` means the same thing: none of it at 0,
    /// all of it at 1.** Night used `.multiplyX2` and did not, which is how it came to
    /// black the room out between 21:00 and 05:00. SpriteKit premultiplies a node's
    /// colour by its alpha, so under any multiply blend a *low* alpha is a *dark*
    /// source — and the room times a nearly-black source is a nearly-black room. The
    /// number that reads as "barely there" was the one doing the most damage. Fading
    /// between times of day animates this node's alpha, which under a multiply blend
    /// would also have dipped through black on the way. See `PaletteTests`.
    static func ambientWash(for time: TimeOfDay) -> (color: SKColor, alpha: CGFloat, blend: SKBlendMode) {
        switch time {
        case .morning: return (SKColor(hex: 0xFFD9A0), 0.10, .add)
        case .day:     return (SKColor(hex: 0xEAF2FF), 0.09, .add)
        case .evening: return (SKColor(hex: 0xC98A5A), 0.07, .add)
        // Deep blue laid over the painting rather than multiplied into it. The room is
        // painted for night already, so this only has to cool it — the lamp stays the
        // warmest thing in the room.
        case .night:   return (SKColor(hex: 0x3A4778), 0.30, .alpha)
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
