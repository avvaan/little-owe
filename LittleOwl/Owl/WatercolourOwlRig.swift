import SpriteKit

/// The owl as painted artwork: one sprite whose texture is swapped for each state, and
/// whose transform carries the motion.
///
/// **Adding a state is a data change, not a code change.** The rig looks for
/// `owl_<state>.png` in the bundle at launch and quietly falls back to the base pose
/// for anything missing, so the app is complete and shippable with only `owl_base`
/// present and improves the moment more artwork lands. `docs/ART_BRIEF.md` lists the
/// filenames.
///
/// Why texture swapping and not a cut-up puppet: the owl is a watercolour painting with
/// feather texture running across every edge. Cutting a head off the body leaves a seam
/// that no amount of rotation hides. Swapping whole frames keeps the painting intact;
/// what moves is the whole bird, which is how a paper puppet moves and reads correctly
/// at this scale.
///
/// Laid out with (0, 0) between the owl's feet, y up.
final class WatercolourOwlRig: OwlRig {

    // MARK: Frames

    /// A painted pose. `base` is guaranteed; the rest are optional until the artwork
    /// for them exists.
    private enum Frame: String, CaseIterable {
        case base      = "owl_base"
        case blink     = "owl_blink"
        case sleepy    = "owl_sleepy"
        case happy     = "owl_happy"
        case listen    = "owl_listen"
        case talkHalf  = "owl_talk_half"
        case talkWide  = "owl_talk_wide"
    }

    private var textures: [Frame: SKTexture] = [:]

    /// Falls back to the base pose, so a missing frame is a duller owl, never a broken one.
    private func texture(_ frame: Frame) -> SKTexture {
        textures[frame] ?? textures[.base]!
    }

    private func has(_ frame: Frame) -> Bool { textures[frame] != nil }

    // MARK: Nodes

    let node = SKNode()

    /// Everything that breathes, hops and leans. The ground shadow stays outside it.
    private let body = SKNode()
    private let sprite: SKSpriteNode

    private var state: OwlState = .idle
    private var currentFrame: Frame = .base
    private var mouthFrame: Frame = .base
    private var eyesClosedByState = false

    var standingHeight: CGFloat { RoomLayout.owlHeight }

    // MARK: Init

    init() {
        let base = SKTexture(imageNamed: Frame.base.rawValue)
        base.filteringMode = .linear
        sprite = SKSpriteNode(texture: base)

        textures[.base] = base
        for frame in Frame.allCases where frame != .base {
            guard Bundle.main.url(forResource: frame.rawValue, withExtension: "png") != nil else { continue }
            let texture = SKTexture(imageNamed: frame.rawValue)
            texture.filteringMode = .linear
            textures[frame] = texture
        }

        build()
        runIdle()
    }

    /// Which painted states the bundle actually has. Surfaced so the room can log it
    /// once at launch rather than leaving the gap to be discovered on device.
    var availableFrameNames: [String] {
        Frame.allCases.filter { textures[$0] != nil }.map(\.rawValue)
    }

    // MARK: OwlRig

    func enter(_ newState: OwlState) {
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
        guard state == .speaking || mouthFrame != .base else {
            show(.base)
            mouthFrame = .base
            return
        }

        // Two thresholds with a gap between them: a single cut-off makes the beak
        // stutter between frames on every wobble of the envelope.
        let wanted: Frame
        switch openness {
        case ..<0.22:  wanted = .base
        case ..<0.62:  wanted = has(.talkHalf) ? .talkHalf : .base
        default:       wanted = has(.talkWide) ? .talkWide : (has(.talkHalf) ? .talkHalf : .base)
        }

        guard wanted != mouthFrame else { return }
        mouthFrame = wanted
        show(wanted)
    }

    func play(_ accent: OwlAccent) {
        switch accent {
        case .blink:    blink()
        case .headTilt: headTilt()
        case .yawn:     yawn()
        case .nudge:    nudge()
        }
    }

    // MARK: Sustained states

    private func runIdle() {
        show(.base)
        eyesClosedByState = false

        body.run(.repeatForever(.sequence([
            .scaleY(to: 1.022, duration: 1.7),
            .scaleY(to: 1.000, duration: 1.7)
        ])), withKey: Key.breathe)

        // `wait(forDuration:withRange:)` re-rolls on every repeat, so the blinks never
        // settle into a rhythm a child can predict.
        node.run(.repeatForever(.sequence([
            .wait(forDuration: 4.2, withRange: 4.0),
            blinkAction()
        ])), withKey: Key.blink)

        node.run(.repeatForever(.sequence([
            .wait(forDuration: 11.0, withRange: 9.0),
            headTiltAction()
        ])), withKey: Key.tilt)
    }

    private func runListening() {
        show(has(.listen) ? .listen : .base)
        eyesClosedByState = false

        // Leans in and grows a little: the owl is visibly paying attention.
        body.run(.group([
            .scale(to: 1.035, duration: 0.25),
            .rotate(toAngle: 0.018, duration: 0.25, shortestUnitArc: true)
        ]))

        body.run(.sequence([
            .wait(forDuration: 0.25),
            .repeatForever(.sequence([
                .scaleY(to: 1.055, duration: 1.1),
                .scaleY(to: 1.035, duration: 1.1)
            ]))
        ]), withKey: Key.breathe)

        if !has(.listen) {
            node.run(.repeatForever(.sequence([
                .wait(forDuration: 3.0, withRange: 2.4),
                blinkAction()
            ])), withKey: Key.blink)
        }
    }

    private func runThinking() {
        show(has(.blink) ? .blink : .base)
        eyesClosedByState = has(.blink)

        body.run(.repeatForever(.sequence([
            .rotate(toAngle:  0.022, duration: 1.2, shortestUnitArc: true),
            .rotate(toAngle: -0.022, duration: 1.2, shortestUnitArc: true)
        ])), withKey: Key.sway)

        body.run(.repeatForever(.sequence([
            .scaleY(to: 1.02, duration: 1.4),
            .scaleY(to: 1.00, duration: 1.4)
        ])), withKey: Key.breathe)
    }

    private func runSpeaking() {
        show(.base)
        mouthFrame = .base
        eyesClosedByState = false

        // A small bob keeps the owl alive between syllables. The beak itself is driven
        // by `setMouthOpenness` from the audio envelope.
        body.run(.repeatForever(.sequence([
            .moveTo(y: 5, duration: 0.42),
            .moveTo(y: 0, duration: 0.42)
        ])), withKey: Key.sway)

        // Only blink here when there is no talking artwork — otherwise the blink frame
        // would fight the beak frames for the same sprite.
        if !has(.talkHalf) && !has(.talkWide) {
            node.run(.repeatForever(.sequence([
                .wait(forDuration: 3.4, withRange: 2.6),
                blinkAction()
            ])), withKey: Key.blink)
        }
    }

    private func runSleepy() {
        show(has(.sleepy) ? .sleepy : (has(.blink) ? .blink : .base))
        eyesClosedByState = true

        body.run(.group([
            .rotate(toAngle: 0.035, duration: 1.1, shortestUnitArc: true),
            .scaleY(to: 0.975, duration: 1.1)
        ]))

        // Slow, deep breathing.
        body.run(.sequence([
            .wait(forDuration: 1.1),
            .repeatForever(.sequence([
                .scaleY(to: 1.000, duration: 2.6),
                .scaleY(to: 0.975, duration: 2.6)
            ]))
        ]), withKey: Key.breathe)
    }

    // MARK: One-shots

    private func playHappy() {
        let restoreTo = state
        let restoreFrame = currentFrame
        body.removeAction(forKey: Key.breathe)
        node.removeAction(forKey: Key.restore)

        if has(.happy) { show(.happy) }

        let hop = SKAction.sequence([
            .group([.moveBy(x: 0, y: 30, duration: 0.16), .scaleY(to: 1.05, duration: 0.16)]),
            .group([.moveBy(x: 0, y: -30, duration: 0.14), .scaleY(to: 0.96, duration: 0.14)]),
            .scaleY(to: 1.0, duration: 0.12)
        ])
        let sequence = SKAction.sequence([hop, hop])
        body.run(sequence, withKey: Key.happy)

        // Restoring from `node`, one hop off the main queue: `enter` clears every action
        // on these nodes, and an action must not tear down the action it runs inside.
        node.run(.sequence([
            .wait(forDuration: sequence.duration),
            .run { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.show(restoreFrame)
                    self.state = .happy          // force `enter` to do real work
                    self.enter(restoreTo)
                }
            }
        ]), withKey: Key.restore)
    }

    private func blink() { node.run(blinkAction()) }
    private func headTilt() { node.run(headTiltAction()) }

    private func yawn() {
        guard has(.talkWide) else { return }
        let restore = currentFrame
        node.run(.sequence([
            .run { [weak self] in self?.show(.talkWide) },
            .wait(forDuration: 0.9),
            .run { [weak self] in self?.show(restore) }
        ]))
    }

    /// A quick squash. The instant answer to being touched, small enough that it does
    /// not disturb whatever the owl was already doing.
    private func nudge() {
        node.removeAction(forKey: Key.nudge)
        node.setScale(1)
        node.run(.sequence([
            .scale(to: 1.05, duration: 0.07),
            .scale(to: 0.985, duration: 0.06),
            .scale(to: 1.00, duration: 0.09)
        ]), withKey: Key.nudge)
    }

    private func blinkAction() -> SKAction {
        guard has(.blink) else { return .wait(forDuration: 0) }
        return .customAction(withDuration: 0.13) { [weak self] _, elapsed in
            guard let self, !self.eyesClosedByState else { return }
            self.show(elapsed < 0.11 ? .blink : .base)
        }
    }

    /// The whole bird leans, rather than a cut-out head turning. At these angles it
    /// reads as a head tilt and leaves the painting intact.
    private func headTiltAction() -> SKAction {
        let angle: CGFloat = 0.035
        return .run(.sequence([
            .rotate(toAngle:  angle, duration: 0.35, shortestUnitArc: true),
            .wait(forDuration: 0.9),
            .rotate(toAngle: -angle * 0.6, duration: 0.40, shortestUnitArc: true),
            .wait(forDuration: 0.6),
            .rotate(toAngle: 0, duration: 0.35, shortestUnitArc: true)
        ]), onChildWithName: "//\(Self.bodyNodeName)")
    }

    // MARK: Internals

    private func show(_ frame: Frame) {
        currentFrame = frame
        sprite.texture = texture(frame)
    }

    private func stopEverything() {
        node.removeAllActions()
        body.removeAllActions()
    }

    private func resetPose() {
        node.setScale(1)
        body.removeAllActions()
        body.setScale(1)
        body.zRotation = 0
        body.position = .zero
        mouthFrame = .base
    }

    private func build() {
        // Soft contact shadow. Sits on `node`, not on `body`, so it stays on the stump
        // while the owl hops.
        let shadow = SKSpriteNode(texture: GradientTexture.radialGlow(SKColor(white: 0.10, alpha: 1)))
        shadow.size = CGSize(width: RoomLayout.owlHeight * 0.62, height: RoomLayout.owlHeight * 0.17)
        shadow.position = CGPoint(x: 0, y: 6)
        shadow.alpha = 0.30
        shadow.zPosition = -1
        node.addChild(shadow)

        // Anchored at the feet so every pose stands on the same spot, whatever its
        // artwork does above the ankles.
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        let aspect = sprite.size.width / sprite.size.height
        sprite.size = CGSize(width: RoomLayout.owlHeight * aspect, height: RoomLayout.owlHeight)

        body.name = Self.bodyNodeName
        body.addChild(sprite)
        node.addChild(body)
    }

    private static let bodyNodeName = "owl.body"

    private enum Key {
        static let breathe = "owl.breathe"
        static let sway    = "owl.sway"
        static let blink   = "owl.blink"
        static let tilt    = "owl.tilt"
        static let happy   = "owl.happy"
        static let restore = "owl.happy.restore"
        static let nudge   = "owl.nudge"
    }
}
