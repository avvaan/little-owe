import SpriteKit

/// Draws every tap target and its size in real device points.
///
/// Off unless the app is launched with `-showTapTargets`. It exists to make the
/// 88 x 88 pt rule checkable on hardware rather than asserted in a comment; it is not
/// reachable from anything a child or parent can touch.
final class DebugOverlay: SKNode {

    private var boxes: [RoomObjectID: SKShapeNode] = [:]
    private var labels: [RoomObjectID: SKLabelNode] = [:]

    func refresh(with tappables: [any Tappable], sceneScale: CGFloat) {
        for tappable in tappables {
            let rect = tappable.hitAreaInParent
            let id = tappable.tapID

            let devicePoints = CGSize(width: rect.width * sceneScale, height: rect.height * sceneScale)
            let passes = min(devicePoints.width, devicePoints.height) >= 88

            let box = boxes[id] ?? {
                let node = SKShapeNode()
                node.fillColor = .clear
                node.lineWidth = 3
                addChild(node)
                boxes[id] = node
                return node
            }()

            box.path = CGPath(rect: rect, transform: nil)
            box.strokeColor = passes ? SKColor.green : SKColor.red

            let label = labels[id] ?? {
                let node = SKLabelNode(fontNamed: "Menlo")
                node.fontSize = 20
                node.fontColor = passes ? SKColor.green : SKColor.red
                node.horizontalAlignmentMode = .center
                addChild(node)
                labels[id] = node
                return node
            }()

            label.text = String(
                format: "%@ %.0f x %.0f pt",
                id.rawValue,
                devicePoints.width,
                devicePoints.height
            )
            label.fontColor = passes ? SKColor.green : SKColor.red
            label.position = CGPoint(x: rect.midX, y: rect.maxY + 8)
        }
    }
}
