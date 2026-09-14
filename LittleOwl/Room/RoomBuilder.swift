import SpriteKit

/// Assembles the room from the painted artwork in `LittleOwl/Resources/Art`.
///
/// The room, the shelf, the book, the lamp, the table, the stump and the rug are all
/// one painting. Only the things that have to move independently are separate sprites:
/// the window's sky (it follows the clock), the three letter blocks, and the owl.
///
/// Every coordinate lives in `RoomLayout` and was measured off the painting, not
/// invented. `tools/compose_room.py` re-renders this same arrangement outside the app
/// so a layout change can be reviewed without a Mac.
enum RoomBuilder {

    // MARK: Room

    static func makeRoom() -> SKSpriteNode {
        let room = ArtTexture.sprite("room_bg")
        room.size = RoomLayout.designSize
        room.position = CGPoint(x: RoomLayout.designSize.width / 2,
                                y: RoomLayout.designSize.height / 2)
        room.zPosition = RoomLayout.Z.room
        return room
    }

    // MARK: Props

    /// The book and the lamp are painted into the room and cannot move, so they answer
    /// a tap with a bloom of light rather than a squash.
    static func makeBook() -> RoomObject {
        let object = RoomObject(
            id: .book,
            content: nil,
            localBounds: CGRect(origin: .zero, size: RoomLayout.bookSize)
                .offsetBy(dx: -RoomLayout.bookSize.width / 2, dy: -RoomLayout.bookSize.height / 2),
            feedback: .glow(size: CGSize(width: RoomLayout.bookSize.width * 2.1,
                                         height: RoomLayout.bookSize.height * 2.1))
        )
        object.position = RoomLayout.bookCentre
        object.zPosition = RoomLayout.Z.props
        return object
    }

    /// The piece of wall that replaces the book when a parent takes it out.
    ///
    /// Cloned from the painting itself by `tools/export_art.py`, which searches for the
    /// offset whose wall best continues the wall around the book — the planking here runs
    /// diagonally, so a fixed sideways or upward offset would break the grain.
    static func makeBookPatch() -> SKSpriteNode {
        let patch = ArtTexture.sprite("patch_book")
        patch.size = RoomLayout.bookPatchSize
        patch.position = RoomLayout.bookPatchCentre
        patch.zPosition = RoomLayout.Z.patch
        patch.isHidden = true
        return patch
    }

    static func makeLamp() -> RoomObject {
        let object = RoomObject(
            id: .lamp,
            content: nil,
            localBounds: CGRect(origin: .zero, size: RoomLayout.lampSize)
                .offsetBy(dx: -RoomLayout.lampSize.width / 2, dy: -RoomLayout.lampSize.height / 2),
            feedback: .glow(size: CGSize(width: RoomLayout.lampSize.width * 2.2,
                                         height: RoomLayout.lampSize.height * 2.2))
        )
        object.position = RoomLayout.lampCentre
        object.zPosition = RoomLayout.Z.props
        return object
    }

    /// Three separate sprites, positioned as they sit in the painting. Separate so a
    /// later mode can lift or wobble one on its own.
    static func makeBlocks() -> RoomObject {
        let content = SKNode()
        for (index, centre) in RoomLayout.blockCentres.enumerated() {
            let block = ArtTexture.sprite("block_\(["a","b","c"][index])")
            let height = RoomLayout.blockHeight
            block.size = CGSize(width: height * block.size.width / block.size.height, height: height)
            // Positions are absolute in the painting; the group node sits at the middle
            // one, so each block is offset from there.
            block.position = CGPoint(x: centre.x - RoomLayout.blocksTapCentre.x,
                                     y: centre.y - RoomLayout.blocksTapCentre.y)
            content.addChild(block)
        }

        let object = RoomObject(
            id: .blocks,
            content: content,
            localBounds: CGRect(origin: .zero, size: RoomLayout.blocksTapSize)
                .offsetBy(dx: -RoomLayout.blocksTapSize.width / 2,
                          dy: -RoomLayout.blocksTapSize.height / 2),
            feedback: .squash
        )
        object.position = RoomLayout.blocksTapCentre
        object.zPosition = RoomLayout.Z.props
        return object
    }

    /// The basket in the near corner: the one prop that is not in the painting.
    ///
    /// Nil when its painting is not in the bundle, and the room is then built without it
    /// — the same rule the second character follows. A missing texture is drawn by
    /// SpriteKit as a red cross, and one of those has already reached a child's iPad
    /// once; see `ArtTexture`.
    static func makeBasket() -> RoomObject? {
        guard let texture = ArtTexture.texture(named: "corner_basket") else { return nil }

        let sprite = SKSpriteNode(texture: texture)
        let height = RoomLayout.basketSize.height
        sprite.size = CGSize(width: height * sprite.size.width / sprite.size.height,
                             height: height)

        let object = RoomObject(
            id: .basket,
            content: sprite,
            localBounds: CGRect(origin: .zero, size: RoomLayout.basketSize)
                .offsetBy(dx: -RoomLayout.basketSize.width / 2,
                          dy: -RoomLayout.basketSize.height / 2),
            feedback: .squash
        )
        object.position = RoomLayout.basketCentre
        object.zPosition = RoomLayout.Z.props
        return object
    }

    static func makeWindow(time: TimeOfDay) -> (object: RoomObject, window: WindowNode) {
        let window = WindowNode(radius: RoomLayout.glassRadius, time: time)
        let bounds = CGRect(origin: .zero, size: RoomLayout.windowTapSize)
            .offsetBy(dx: -RoomLayout.windowTapSize.width / 2,
                      dy: -RoomLayout.windowTapSize.height / 2)
        // The frame is painted into the room; only the glass is ours, so a squash would
        // slide the sky out from under its own woodwork. Glow instead.
        let object = RoomObject(
            id: .window,
            content: window,
            localBounds: bounds,
            feedback: .glow(size: CGSize(width: RoomLayout.windowTapSize.width * 1.9,
                                         height: RoomLayout.windowTapSize.height * 1.9))
        )
        object.position = RoomLayout.windowCentre
        object.zPosition = RoomLayout.Z.props
        return (object, window)
    }

    // MARK: Light

    /// Whole-room tint for the time of day. Gentle: the painting carries its own light.
    static func makeAmbientWash() -> SKSpriteNode {
        let wash = SKSpriteNode(color: .clear, size: RoomLayout.designSize)
        wash.position = CGPoint(x: RoomLayout.designSize.width / 2,
                                y: RoomLayout.designSize.height / 2)
        wash.alpha = 0
        wash.zPosition = RoomLayout.Z.ambientWash
        return wash
    }
}
