import SpriteKit
import UIKit

/// Builds the attic out of vector primitives.
///
/// Everything here is placeholder art. It is structured the way the final room will be
/// — shell, furniture, props, light — so replacing a shape with a sprite is a local
/// change rather than a rewrite.
enum RoomBuilder {

    // MARK: Shell

    /// The whole static shell — roof planes, gable wall, beams, floor — baked into one
    /// texture.
    ///
    /// It was fifteen-odd shape nodes; none of it ever moves, and shapes cannot be
    /// clipped or gradient-filled reliably. One `CoreGraphics` pass at launch buys
    /// proper perspective on the floorboards and a sloped ceiling that reads as a
    /// ceiling rather than as a hole.
    static func makeShell() -> SKSpriteNode {
        let design = RoomLayout.designSize
        let pixelSize = CGSize(width: design.width / 2, height: design.height / 2)

        let image = UIGraphicsImageRenderer(size: pixelSize).image { context in
            let cg = context.cgContext
            // Flip into SpriteKit's space so every number below is a scene coordinate.
            cg.translateBy(x: 0, y: pixelSize.height)
            cg.scaleBy(x: 0.5, y: -0.5)

            drawRoofPlanes(in: cg)
            drawWall(in: cg)
            drawBeams(in: cg)
            drawFloor(in: cg)
        }

        let shell = SKSpriteNode(texture: SKTexture(image: image))
        shell.size = design
        shell.position = CGPoint(x: design.width / 2, y: design.height / 2)
        shell.zPosition = RoomLayout.Z.wall
        return shell
    }

    /// The underside of the roof, coming towards the viewer from the gable. Two
    /// triangles, darkest nearest the camera.
    private static func drawRoofPlanes(in cg: CGContext) {
        let width = RoomLayout.designSize.width
        let ridge = CGPoint(x: RoomLayout.ridgeX, y: RoomLayout.ridgeHeight)

        for edgeX in [CGFloat(0), width] {
            cg.saveGState()

            let triangle = CGMutablePath()
            triangle.move(to: CGPoint(x: edgeX, y: RoomLayout.eaveHeight))
            triangle.addLine(to: ridge)
            triangle.addLine(to: CGPoint(x: edgeX, y: RoomLayout.ridgeHeight))
            triangle.closeSubpath()
            cg.addPath(triangle)
            cg.clip()

            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [Palette.roofNear.cgColor, Palette.roofFar.cgColor] as CFArray,
                locations: nil
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: RoomLayout.ridgeHeight),
                    end: CGPoint(x: 0, y: RoomLayout.eaveHeight),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }

            // Plank seams running with the slope.
            cg.setStrokeColor(Palette.roofSeam.cgColor)
            cg.setLineWidth(3)
            var offset: CGFloat = 0
            while offset < RoomLayout.ridgeHeight - RoomLayout.eaveHeight + 40 {
                cg.move(to: CGPoint(x: edgeX, y: RoomLayout.eaveHeight + offset))
                cg.addLine(to: CGPoint(x: ridge.x, y: ridge.y + offset))
                cg.strokePath()
                offset += 44
            }

            cg.restoreGState()
        }
    }

    private static func drawWall(in cg: CGContext) {
        cg.saveGState()
        cg.addPath(RoomLayout.wallPath)
        cg.clip()

        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [Palette.wallUpper.cgColor, Palette.wallLower.cgColor] as CFArray,
            locations: nil
        ) {
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: RoomLayout.ridgeHeight),
                end: CGPoint(x: 0, y: RoomLayout.floorLine),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        cg.restoreGState()
    }

    private static func drawBeams(in cg: CGContext) {
        let width = RoomLayout.designSize.width

        cg.saveGState()
        // Ridge beam along the join of the two roof planes.
        cg.setStrokeColor(Palette.rafter.cgColor)
        cg.setLineWidth(26)
        cg.setLineCap(.round)
        cg.move(to: CGPoint(x: 0, y: RoomLayout.eaveHeight - 4))
        cg.addLine(to: CGPoint(x: RoomLayout.ridgeX, y: RoomLayout.ridgeHeight - 4))
        cg.addLine(to: CGPoint(x: width, y: RoomLayout.eaveHeight - 4))
        cg.strokePath()

        // Two cross-beams on the gable wall. They give the attic depth without adding
        // clutter at child eye level.
        cg.saveGState()
        cg.addPath(RoomLayout.wallPath)
        cg.clip()
        for (y, alpha) in [(CGFloat(690), CGFloat(0.9)), (CGFloat(620), CGFloat(0.45))] {
            cg.setFillColor(Palette.rafter.withAlphaComponent(alpha).cgColor)
            cg.fill(CGRect(x: 0, y: y, width: width, height: 16))
        }
        cg.restoreGState()
        cg.restoreGState()
    }

    /// Boards running away from the viewer: bands that get shorter towards the wall,
    /// which is what sells a flat elevation as a floor.
    private static func drawFloor(in cg: CGContext) {
        let width = RoomLayout.designSize.width
        let bandCount = 7

        // Band heights grow towards the bottom of the screen (nearest the child).
        let weights = (0..<bandCount).map { CGFloat(1) + CGFloat($0) * 0.6 }
        let weightTotal = weights.reduce(0, +)

        var y = RoomLayout.floorLine
        for (index, weight) in weights.enumerated() {
            let height = RoomLayout.floorLine * weight / weightTotal
            let bandRect = CGRect(x: 0, y: y - height, width: width, height: height)

            cg.setFillColor((index % 2 == 0 ? Palette.floorPlank : Palette.floorPlankAlt).cgColor)
            cg.fill(bandRect)

            // Board ends, staggered row to row and wider as they come forward.
            cg.setStrokeColor(Palette.floorSeam.cgColor)
            cg.setLineWidth(2)
            let spacing = 210 + CGFloat(index) * 46
            var x = CGFloat(index) * 73 - spacing
            while x < width + spacing {
                cg.move(to: CGPoint(x: x, y: bandRect.minY))
                cg.addLine(to: CGPoint(x: x, y: bandRect.maxY))
                x += spacing
            }
            cg.strokePath()

            // The seam between rows.
            cg.setStrokeColor(Palette.floorSeam.withAlphaComponent(0.8).cgColor)
            cg.setLineWidth(3)
            cg.move(to: CGPoint(x: 0, y: bandRect.minY))
            cg.addLine(to: CGPoint(x: width, y: bandRect.minY))
            cg.strokePath()

            y -= height
        }

        // Skirting where the floor meets the wall.
        cg.setFillColor(Palette.woodDark.cgColor)
        cg.fill(CGRect(x: 0, y: RoomLayout.floorLine - 14, width: width, height: 20))
    }

    static func makeRug() -> SKNode {
        let rug = SKNode()
        rug.position = RoomLayout.rugCentre
        rug.zPosition = RoomLayout.Z.rug

        let outer = SKShapeNode(ellipseOf: RoomLayout.rugSize)
        outer.fillColor = Palette.rug
        outer.strokeColor = Palette.rugTrim
        outer.lineWidth = 8
        rug.addChild(outer)

        let inner = SKShapeNode(ellipseOf: CGSize(width: RoomLayout.rugSize.width * 0.7,
                                                 height: RoomLayout.rugSize.height * 0.66))
        inner.fillColor = Palette.rugInner
        inner.strokeColor = Palette.rugTrim
        inner.lineWidth = 5
        rug.addChild(inner)

        return rug
    }

    /// Low stump the owl stands on, so it sits above the floor line and reads as the
    /// centre of the room.
    static func makePerch() -> SKNode {
        let perch = SKNode()
        perch.position = RoomLayout.perchCentre
        perch.zPosition = RoomLayout.Z.perch

        let trunk = SKShapeNode(rect: CGRect(x: -86, y: -46, width: 172, height: 92), cornerRadius: 12)
        trunk.fillColor = Palette.woodDark
        trunk.strokeColor = .clear
        perch.addChild(trunk)

        let top = SKShapeNode(ellipseOf: CGSize(width: 176, height: 46))
        top.fillColor = Palette.wood
        top.strokeColor = Palette.woodLight
        top.lineWidth = 3
        top.position = CGPoint(x: 0, y: 46)
        perch.addChild(top)

        let rings = SKShapeNode(ellipseOf: CGSize(width: 96, height: 24))
        rings.fillColor = .clear
        rings.strokeColor = Palette.woodLight
        rings.lineWidth = 2
        rings.alpha = 0.7
        rings.position = CGPoint(x: 0, y: 46)
        perch.addChild(rings)

        return perch
    }

    // MARK: Furniture (not tappable)

    static func makeShelf() -> SKNode {
        let shelf = SKNode()
        shelf.zPosition = RoomLayout.Z.furniture

        let plank = SKShapeNode(rect: RoomLayout.shelfRect, cornerRadius: 4)
        plank.fillColor = Palette.wood
        plank.strokeColor = Palette.woodDark
        plank.lineWidth = 2
        shelf.addChild(plank)

        for x in [RoomLayout.shelfRect.minX + 34, RoomLayout.shelfRect.maxX - 34] {
            let bracket = SKShapeNode(path: {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: x - 14, y: RoomLayout.shelfRect.minY))
                path.addLine(to: CGPoint(x: x + 14, y: RoomLayout.shelfRect.minY))
                path.addLine(to: CGPoint(x: x + 14, y: RoomLayout.shelfRect.minY - 46))
                path.closeSubpath()
                return path
            }())
            bracket.fillColor = Palette.woodDark
            bracket.strokeColor = .clear
            shelf.addChild(bracket)
        }
        return shelf
    }

    static func makeSideTable() -> SKNode {
        let table = SKNode()
        table.zPosition = RoomLayout.Z.furniture

        let top = SKShapeNode(rect: RoomLayout.tableTopRect, cornerRadius: 5)
        top.fillColor = Palette.wood
        top.strokeColor = Palette.woodDark
        top.lineWidth = 2
        table.addChild(top)

        for x in [RoomLayout.tableTopRect.minX + 22, RoomLayout.tableTopRect.maxX - 34] {
            let leg = SKShapeNode(rect: CGRect(x: x, y: RoomLayout.floorLine - 10,
                                               width: 16,
                                               height: RoomLayout.tableTopRect.minY - RoomLayout.floorLine + 10))
            leg.fillColor = Palette.woodDark
            leg.strokeColor = .clear
            table.addChild(leg)
        }
        return table
    }

    // MARK: Props (tappable)

    static func makeBook() -> RoomObject {
        let content = SKNode()

        let spineAngle: CGFloat = 0.06
        for side in [CGFloat(-1), CGFloat(1)] {
            let page = SKShapeNode(rect: CGRect(x: 0, y: -34, width: 74, height: 68), cornerRadius: 3)
            page.fillColor = side < 0 ? Palette.bookPage : Palette.bookPageShade
            page.strokeColor = Palette.woodDark
            page.lineWidth = 2
            page.position = CGPoint(x: side < 0 ? -74 : 0, y: 4)
            page.zRotation = spineAngle * side
            content.addChild(page)
        }

        let cover = SKShapeNode(rect: CGRect(x: -80, y: -44, width: 160, height: 18), cornerRadius: 5)
        cover.fillColor = Palette.bookCover
        cover.strokeColor = .clear
        content.addChild(cover)

        // Ribbon marker: a spot of colour that draws a toddler's eye to the book.
        let ribbon = SKShapeNode(rect: CGRect(x: -4, y: -56, width: 9, height: 52))
        ribbon.fillColor = Palette.rug
        ribbon.strokeColor = .clear
        content.addChild(ribbon)

        let object = RoomObject(id: .book, content: content, localBounds: CGRect(x: -84, y: -58, width: 168, height: 106))
        object.position = RoomLayout.bookAnchor
        object.zPosition = RoomLayout.Z.props
        return object
    }

    static func makeLamp() -> RoomObject {
        let content = SKNode()

        let base = SKShapeNode(ellipseOf: CGSize(width: 86, height: 22))
        base.fillColor = Palette.lampBase
        base.strokeColor = .clear
        content.addChild(base)

        let stem = SKShapeNode(rect: CGRect(x: -6, y: 0, width: 12, height: 74))
        stem.fillColor = Palette.lampBase
        stem.strokeColor = .clear
        content.addChild(stem)

        let shade = SKShapeNode(path: {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -62, y: 74))
            path.addLine(to: CGPoint(x: 62, y: 74))
            path.addLine(to: CGPoint(x: 40, y: 146))
            path.addLine(to: CGPoint(x: -40, y: 146))
            path.closeSubpath()
            return path
        }())
        shade.fillColor = Palette.lampShade
        shade.strokeColor = Palette.woodDark
        shade.lineWidth = 2
        content.addChild(shade)

        let glow = SKSpriteNode(texture: GradientTexture.radialGlow(Palette.lampGlow))
        glow.size = CGSize(width: 260, height: 260)
        glow.position = CGPoint(x: 0, y: 84)
        glow.blendMode = .add
        glow.alpha = 0.30
        glow.zPosition = -1
        // A slow flicker, the only thing in the room that moves on its own besides the owl.
        glow.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.22, duration: 2.3),
            .fadeAlpha(to: 0.34, duration: 1.9)
        ])))
        content.addChild(glow)

        let object = RoomObject(id: .lamp, content: content, localBounds: CGRect(x: -66, y: -14, width: 132, height: 170))
        object.position = RoomLayout.lampAnchor
        object.zPosition = RoomLayout.Z.props
        return object
    }

    static func makeBlocks() -> RoomObject {
        let content = SKNode()

        // Letters on a wooden toy are decoration, not interface — the child is never
        // asked to read them.
        let letters = ["A", "B", "C"]
        let placements: [(CGFloat, CGFloat, CGFloat)] = [(-92, 0, -0.06), (0, -4, 0.04), (88, 2, -0.10)]

        for (index, placement) in placements.enumerated() {
            let (x, y, rotation) = placement
            let block = SKNode()
            block.position = CGPoint(x: x, y: y)
            block.zRotation = rotation

            let face = SKShapeNode(rect: CGRect(x: -42, y: -42, width: 84, height: 84), cornerRadius: 10)
            face.fillColor = Palette.blockFaces[index % Palette.blockFaces.count]
            face.strokeColor = Palette.blockEdge
            face.lineWidth = 3
            block.addChild(face)

            let label = SKLabelNode(text: letters[index])
            label.fontName = "AvenirNext-Heavy"
            label.fontSize = 46
            label.fontColor = Palette.blockEdge
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            block.addChild(label)

            content.addChild(block)
        }

        let object = RoomObject(id: .blocks, content: content, localBounds: CGRect(x: -138, y: -50, width: 276, height: 100))
        object.position = RoomLayout.blocksAnchor
        object.zPosition = RoomLayout.Z.props
        return object
    }

    static func makeWindow(time: TimeOfDay) -> (object: RoomObject, window: WindowNode) {
        let window = WindowNode(radius: RoomLayout.windowRadius, time: time)
        let bounds = CGRect(x: -RoomLayout.windowRadius - 14,
                            y: -RoomLayout.windowRadius - 20,
                            width: RoomLayout.windowRadius * 2 + 28,
                            height: RoomLayout.windowRadius * 2 + 34)
        let object = RoomObject(id: .window, content: window, localBounds: bounds)
        object.position = RoomLayout.windowCentre
        object.zPosition = RoomLayout.Z.windowFrame
        return (object, window)
    }

    // MARK: Light

    /// The shaft of light the window throws onto the floor. Recoloured whenever the
    /// time of day changes.
    static func makeLightSpill() -> SKShapeNode {
        let centre = RoomLayout.windowCentre
        let radius = RoomLayout.windowRadius

        let path = CGMutablePath()
        path.move(to: CGPoint(x: centre.x - radius * 0.9, y: centre.y - radius * 0.2))
        path.addLine(to: CGPoint(x: centre.x + radius * 0.9, y: centre.y - radius * 0.2))
        path.addLine(to: CGPoint(x: centre.x + radius * 0.2, y: RoomLayout.floorLine - 190))
        path.addLine(to: CGPoint(x: centre.x - radius * 3.1, y: RoomLayout.floorLine - 190))
        path.closeSubpath()

        let spill = SKShapeNode(path: path)
        spill.strokeColor = .clear
        spill.blendMode = .add
        spill.alpha = 0
        spill.zPosition = RoomLayout.Z.lightSpill
        return spill
    }

    /// Whole-room tint, so the time of day is felt and not only seen through the glass.
    static func makeAmbientWash() -> SKSpriteNode {
        let wash = SKSpriteNode(color: .clear, size: RoomLayout.designSize)
        wash.position = CGPoint(x: RoomLayout.designSize.width / 2, y: RoomLayout.designSize.height / 2)
        wash.alpha = 0
        wash.zPosition = RoomLayout.Z.ambientWash
        return wash
    }
}
