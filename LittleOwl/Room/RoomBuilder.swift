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
        let room = SKSpriteNode(imageNamed: "room_bg")
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
            let block = SKSpriteNode(imageNamed: "block_\(["a","b","c"][index])")
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
