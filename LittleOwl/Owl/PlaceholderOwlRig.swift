import SpriteKit

/// The owl, drawn from vector primitives.
///
/// This exists so the whole app can be built, felt and tuned before any artwork lands.
/// It implements `OwlRig` exactly, so the final Rive character replaces it without the
/// behaviour code noticing. `docs/ART_BRIEF.md` lists what the artist has to deliver to
/// make that swap.
///
/// Laid out with (0, 0) between the owl's feet, y up.
final class PlaceholderOwlRig: OwlRig {

    // MARK: Geometry

    private enum G {
        static let bodyCentre   = CGPoint(x: 0, y: 122)
        static let bodySize     = CGSize(width: 196, height: 226)
        static let bellySize    = CGSize(width: 130, height: 156)
        static let neckY: CGFloat = 214
        static let headCentre   = CGPoint(x: 0, y: 42)    // head space
        static let headRadius: CGFloat = 88
        static let eyeOffset    = CGPoint(x: 37, y: 50)   // head space, mirrored on x
        static let eyeRadius: CGFloat = 30
        static let beakY: CGFloat = 8                     // head space
        static let totalHeight: CGFloat = 344
    }

    private enum Key {
        static let breathe = "owl.breathe"
        static let sway    = "owl.sway"
        static let blink   = "owl.blink"
        static let tilt    = "owl.tilt"
        static let happy   = "owl.happy"
        static let restore = "owl.happy.restore"
        static let lid     = "owl.lid"
    }

    private enum Lid {
        /// Parked above the eye, clipped away by the crop node.
        static let open: CGFloat = 34
        /// Fully covering the eye.
        static let closed: CGFloat = -32
    }

    private static let headNodeName = "owl.head"

    // MARK: Nodes

    let node = SKNode()

    private let bodyGroup = SKNode()
    private let headGroup = SKNode()
    private let earTuftLeft  = SKShapeNode()
    private let earTuftRight = SKShapeNode()
    private let beakLower = SKShapeNode()
    private var eyelids: [SKNode] = []

    private var state: OwlState = .idle
    private var eyesAreClosed = false

    var standingHeight: CGFloat { G.totalHeight }

    // MARK: Init

    init() {
        build()
        runIdle()
    }

    // MARK: OwlRig

    func enter(_ newState: OwlState) {
        // Happy is a one-shot: it plays over whatever is current and restores it.
        if newState == .happy {
            playHappy()
            return
        }

        guard newState != state else { return }
        state = newState

        stopEverything()
        resetPose()

        switch newState {
        case .idle:      runIdle()
        case .listening: runListening()
        case .thinking:  runThinking()
        case .speaking:  runSpeaking()
        case .sleepy:    runSleepy()
        case .happy:     break // handled above
        }
    }

    func setMouthOpenness(_ openness: CGFloat) {
        let clamped = min(max(openness, 0), 1)
        beakLower.position.y = G.beakY - clamped * 15
        beakLower.yScale = 1 + clamped * 0.35
    }

    func play(_ accent: OwlAccent) {
        switch accent {
        case .blink:    node.run(blinkAction())
        case .headTilt: node.run(.run(headTiltSequence(), onChildWithName: "//\(Self.headNodeName)"))
        case .yawn:     node.run(yawnAction())
        }
    }

    // MARK: Sustained states

    private func runIdle() {
        setEyesClosed(false)

        bodyGroup.run(.repeatForever(.sequence([
            .scaleY(to: 1.035, duration: 1.7),
            .scaleY(to: 1.000, duration: 1.7)
        ])), withKey: Key.breathe)

        // `wait(forDuration:withRange:)` re-rolls on every repeat, so blinks never settle
        // into a rhythm a child can predict.
        node.run(.repeatForever(.sequence([
            .wait(forDuration: 4.2, withRange: 4.0),
            blinkAction()
        ])), withKey: Key.blink)

        node.run(.repeatForever(.sequence([
            .wait(forDuration: 11.0, withRange: 9.0),
            .run(headTiltSequence(), onChildWithName: "//\(Self.headNodeName)")
        ])), withKey: Key.tilt)
    }

    private func runListening() {
        setEyesClosed(false)

        // Tufts up and out, head forward: the owl is visibly paying attention.
        earTuftLeft.run(.group([.scaleY(to: 1.4, duration: 0.22), .rotate(toAngle: -0.34, duration: 0.22)]))
        earTuftRight.run(.group([.scaleY(to: 1.4, duration: 0.22), .rotate(toAngle: 0.34, duration: 0.22)]))
        headGroup.run(.group([
            .rotate(toAngle: 0.05, duration: 0.25, shortestUnitArc: true),
            .moveTo(y: G.neckY + 8, duration: 0.25)
        ]))
        bodyGroup.run(.scaleX(to: 1.03, duration: 0.25))

        bodyGroup.run(.sequence([
            .wait(forDuration: 0.25),
            .repeatForever(.sequence([
                .scaleY(to: 1.055, duration: 1.1),
                .scaleY(to: 1.000, duration: 1.1)
            ]))
        ]), withKey: Key.breathe)

        node.run(.repeatForever(.sequence([
            .wait(forDuration: 3.0, withRange: 2.4),
            blinkAction()
        ])), withKey: Key.blink)
    }

    private func runThinking() {
        setEyesClosed(true)

        headGroup.run(.repeatForever(.sequence([
            .rotate(toAngle:  0.07, duration: 1.2, shortestUnitArc: true),
            .rotate(toAngle: -0.07, duration: 1.2, shortestUnitArc: true)
        ])), withKey: Key.sway)

        bodyGroup.run(.repeatForever(.sequence([
            .scaleY(to: 1.03, duration: 1.4),
            .scaleY(to: 1.00, duration: 1.4)
        ])), withKey: Key.breathe)
    }

    private func runSpeaking() {
        setEyesClosed(false)

        // A small bob keeps the owl alive between syllables. The beak itself is driven
        // by `setMouthOpenness` from the audio envelope.
        headGroup.run(.repeatForever(.sequence([
            .moveTo(y: G.neckY + 5, duration: 0.42),
            .moveTo(y: G.neckY - 2, duration: 0.42)
        ])), withKey: Key.sway)

        node.run(.repeatForever(.sequence([
            .wait(forDuration: 3.4, withRange: 2.6),
            blinkAction()
        ])), withKey: Key.blink)
    }

    private func runSleepy() {
        setEyesClosed(true)

        headGroup.run(.group([
            .rotate(toAngle: 0.2, duration: 1.1, shortestUnitArc: true),
            .moveTo(y: G.neckY - 16, duration: 1.1)
        ]))

        // Slow, deep breathing.
        bodyGroup.run(.sequence([
            .scaleY(to: 0.96, duration: 1.1),
            .repeatForever(.sequence([
                .scaleY(to: 1.00, duration: 2.6),
                .scaleY(to: 0.96, duration: 2.6)
            ]))
        ]), withKey: Key.breathe)

        node.run(.sequence([.wait(forDuration: 0.5), yawnAction()]))
    }

    // MARK: One-shots

    private func playHappy() {
        let restoreTo = state
        bodyGroup.removeAction(forKey: Key.breathe)
        node.removeAction(forKey: Key.restore)

        let hop = SKAction.sequence([
            .group([.moveBy(x: 0, y: 34, duration: 0.16), .scaleY(to: 1.06, duration: 0.16)]),
            .group([.moveBy(x: 0, y: -34, duration: 0.14), .scaleY(to: 0.94, duration: 0.14)]),
            .scaleY(to: 1.0, duration: 0.12)
        ])
        let sequence = SKAction.sequence([hop, hop])
        bodyGroup.run(sequence, withKey: Key.happy)

        setMouthOpenness(0.5)

        // Restoring from `node` rather than from inside the bounce, and one hop off the
        // main queue on top: `enter` clears every action on these nodes, and an action
        // must not tear down the action it is running inside.
        node.run(.sequence([
            .wait(forDuration: sequence.duration),
            .run { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.setMouthOpenness(0)
                    self.state = .happy      // force `enter` to do real work
                    self.enter(restoreTo)
                }
            }
        ]), withKey: Key.restore)
    }

    private func blinkAction() -> SKAction {
        .run { [weak self] in
            guard let self, !self.eyesAreClosed else { return }
            for lid in self.eyelids {
                lid.removeAction(forKey: Key.lid)
                lid.run(.sequence([
                    .moveTo(y: Lid.closed, duration: 0.06),
                    .wait(forDuration: 0.04),
                    .moveTo(y: Lid.open, duration: 0.09)
                ]), withKey: Key.lid)
            }
        }
    }

    /// Runs on the head node, not on `node` — see the `onChildWithName` call sites.
    private func headTiltSequence() -> SKAction {
        let angle: CGFloat = 0.11
        return .sequence([
            .rotate(toAngle:  angle, duration: 0.35, shortestUnitArc: true),
            .wait(forDuration: 0.9),
            .rotate(toAngle: -angle * 0.6, duration: 0.40, shortestUnitArc: true),
            .wait(forDuration: 0.6),
            .rotate(toAngle: 0, duration: 0.35, shortestUnitArc: true)
        ])
    }

    private func yawnAction() -> SKAction {
        .customAction(withDuration: 1.4) { [weak self] _, elapsed in
            // Open slowly, close quickly — the shape of a real yawn.
            let t = elapsed / 1.4
            let openness: CGFloat = t < 0.6 ? (t / 0.6) : max(0, 1 - (t - 0.6) / 0.4)
            self?.setMouthOpenness(openness * 0.9)
        }
    }

    // MARK: Pose helpers

    private func setEyesClosed(_ closed: Bool) {
        eyesAreClosed = closed
        for lid in eyelids {
            lid.removeAction(forKey: Key.lid)
            lid.run(.moveTo(y: closed ? Lid.closed : Lid.open, duration: 0.18), withKey: Key.lid)
        }
    }

    private func stopEverything() {
        node.removeAllActions()
        bodyGroup.removeAllActions()
        headGroup.removeAllActions()
        earTuftLeft.removeAllActions()
        earTuftRight.removeAllActions()
    }

    private func resetPose() {
        headGroup.zRotation = 0
        headGroup.position = CGPoint(x: 0, y: G.neckY)
        bodyGroup.zRotation = 0
        bodyGroup.setScale(1.0)
        bodyGroup.position = .zero
        earTuftLeft.yScale = 1
        earTuftRight.yScale = 1
        earTuftLeft.zRotation = -0.16
        earTuftRight.zRotation = 0.16
        setMouthOpenness(0)
    }
}

// MARK: - Construction
//
// Plain vector primitives. None of this survives the art hand-off; it is here so the
// timing and the feel of the character can be judged now.

private extension PlaceholderOwlRig {

    func build() {
        buildGroundShadow()

        node.addChild(bodyGroup)
        buildFeet()
        buildTail()
        buildBody()
        buildWings()

        headGroup.name = PlaceholderOwlRig.headNodeName
        headGroup.position = CGPoint(x: 0, y: G.neckY)
        headGroup.zPosition = 4
        bodyGroup.addChild(headGroup)

        buildEarTufts()
        buildHead()
        buildEyes()
        buildBeak()
    }

    /// Sits on `node`, not on `bodyGroup`, so it stays put while the owl hops.
    func buildGroundShadow() {
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 200, height: 44))
        shadow.fillColor = SKColor(white: 0, alpha: 0.20)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: 8)
        shadow.zPosition = -6
        node.addChild(shadow)
    }

    func buildFeet() {
        for x in [CGFloat(-42), CGFloat(42)] {
            let foot = SKShapeNode(ellipseOf: CGSize(width: 58, height: 26))
            foot.fillColor = Palette.owlFoot
            foot.strokeColor = Palette.owlBeakShade
            foot.lineWidth = 2
            foot.position = CGPoint(x: x, y: 14)
            foot.zPosition = -1
            bodyGroup.addChild(foot)
        }
    }

    func buildTail() {
        let tail = SKShapeNode(path: {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -36, y: 0))
            path.addLine(to: CGPoint(x: 36, y: 0))
            path.addLine(to: CGPoint(x: 0, y: -58))
            path.closeSubpath()
            return path
        }())
        tail.fillColor = Palette.owlBodyShade
        tail.strokeColor = .clear
        tail.position = CGPoint(x: 8, y: 74)
        tail.zRotation = -0.18
        tail.zPosition = -2
        bodyGroup.addChild(tail)
    }

    func buildBody() {
        let body = SKShapeNode(ellipseOf: G.bodySize)
        body.fillColor = Palette.owlBody
        body.strokeColor = Palette.owlBodyShade
        body.lineWidth = 3
        body.position = G.bodyCentre
        body.zPosition = 0
        bodyGroup.addChild(body)

        let belly = SKShapeNode(ellipseOf: G.bellySize)
        belly.fillColor = Palette.owlBelly
        belly.strokeColor = .clear
        belly.position = CGPoint(x: 0, y: G.bodyCentre.y - 14)
        belly.zPosition = 1
        bodyGroup.addChild(belly)
    }

    func buildWings() {
        for side in [CGFloat(-1), CGFloat(1)] {
            let wing = SKShapeNode(ellipseOf: CGSize(width: 56, height: 164))
            wing.fillColor = Palette.owlBodyShade
            wing.strokeColor = .clear
            wing.position = CGPoint(x: 92 * side, y: 132)
            wing.zRotation = 0.12 * side
            wing.zPosition = 2
            bodyGroup.addChild(wing)
        }
    }

    func buildEarTufts() {
        let tuftPath: CGPath = {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -17, y: 0))
            path.addLine(to: CGPoint(x: 17, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 64))
            path.closeSubpath()
            return path
        }()

        for (tuft, side) in [(earTuftLeft, CGFloat(-1)), (earTuftRight, CGFloat(1))] {
            tuft.path = tuftPath
            tuft.fillColor = Palette.owlBodyShade
            tuft.strokeColor = .clear
            tuft.position = CGPoint(x: 54 * side, y: G.headCentre.y + G.headRadius - 26)
            tuft.zRotation = 0.16 * side
            tuft.zPosition = -1   // behind the head, so only the tips show
            headGroup.addChild(tuft)
        }
    }

    func buildHead() {
        let head = SKShapeNode(circleOfRadius: G.headRadius)
        head.fillColor = Palette.owlBody
        head.strokeColor = Palette.owlBodyShade
        head.lineWidth = 3
        head.position = G.headCentre
        head.zPosition = 0
        headGroup.addChild(head)

        // Pale facial disc, the thing that makes a circle read as an owl.
        let face = SKShapeNode(ellipseOf: CGSize(width: 148, height: 118))
        face.fillColor = Palette.owlFace
        face.strokeColor = .clear
        face.position = CGPoint(x: 0, y: G.headCentre.y + 4)
        face.zPosition = 1
        headGroup.addChild(face)
    }

    func buildEyes() {
        for side in [CGFloat(-1), CGFloat(1)] {
            let eye = SKCropNode()
            eye.position = CGPoint(x: G.eyeOffset.x * side, y: G.eyeOffset.y)
            eye.zPosition = 2

            let mask = SKSpriteNode(texture: GradientTexture.solidCircle(diameter: G.eyeRadius * 2))
            mask.size = CGSize(width: G.eyeRadius * 2, height: G.eyeRadius * 2)
            eye.maskNode = mask

            let white = SKShapeNode(circleOfRadius: G.eyeRadius)
            white.fillColor = Palette.owlEyeWhite
            white.strokeColor = .clear
            eye.addChild(white)

            let pupil = SKShapeNode(circleOfRadius: 15)
            pupil.fillColor = Palette.owlPupil
            pupil.strokeColor = .clear
            pupil.position = CGPoint(x: 2 * side, y: -1)
            eye.addChild(pupil)

            let glint = SKShapeNode(circleOfRadius: 5)
            glint.fillColor = SKColor(white: 1, alpha: 0.9)
            glint.strokeColor = .clear
            glint.position = CGPoint(x: 2 * side + 6, y: 6)
            eye.addChild(glint)

            // Feather-coloured lid. Parked above the eye where the crop node hides it.
            let lid = SKShapeNode(rect: CGRect(x: -34, y: 0, width: 68, height: 72))
            lid.fillColor = Palette.owlBody
            lid.strokeColor = .clear
            lid.position = CGPoint(x: 0, y: Lid.open)
            lid.zPosition = 1
            eye.addChild(lid)
            eyelids.append(lid)

            // Rim drawn outside the crop node so it is never clipped.
            let rim = SKShapeNode(circleOfRadius: G.eyeRadius)
            rim.fillColor = .clear
            rim.strokeColor = Palette.owlBodyShade
            rim.lineWidth = 3
            rim.position = eye.position
            rim.zPosition = 3

            headGroup.addChild(eye)
            headGroup.addChild(rim)
        }
    }

    func buildBeak() {
        let upper = SKShapeNode(path: {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -22, y: 16))
            path.addLine(to: CGPoint(x: 22, y: 16))
            path.addLine(to: CGPoint(x: 0, y: -10))
            path.closeSubpath()
            return path
        }())
        upper.fillColor = Palette.owlBeak
        upper.strokeColor = .clear
        upper.position = CGPoint(x: 0, y: G.beakY)
        upper.zPosition = 4
        headGroup.addChild(upper)

        beakLower.path = {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -16, y: 0))
            path.addLine(to: CGPoint(x: 16, y: 0))
            path.addLine(to: CGPoint(x: 0, y: -28))
            path.closeSubpath()
            return path
        }()
        beakLower.fillColor = Palette.owlBeakShade
        beakLower.strokeColor = .clear
        beakLower.position = CGPoint(x: 0, y: G.beakY)
        beakLower.zPosition = 3   // behind the upper beak, so the jaw slides out of it
        headGroup.addChild(beakLower)
    }
}
