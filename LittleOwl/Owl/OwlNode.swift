import SpriteKit

/// The owl in the room: behaviour, movement and the idle clock.
///
/// It knows nothing about how the character is drawn — everything visual goes through
/// `OwlRig`. To move to the final artwork, change the one line in `init` that builds
/// the rig.
final class OwlNode: SKNode, Tappable {

    private let rig: OwlRig

    private(set) var state: OwlState = .idle

    /// Where the owl returns to when a mode ends.
    var homePosition: CGPoint = RoomLayout.owlHome

    /// True while a hop or flight is in progress; taps are still acknowledged, but a
    /// second journey is not started on top of the first.
    private(set) var isTravelling = false

    // MARK: Idle clock

    /// Purely decorative. Nothing is gated behind it and any tap wakes the owl.
    var sleepyAfter: TimeInterval = 75
    private var lastInteraction: TimeInterval = 0

    // MARK: Init

    init(rig: OwlRig = WatercolourOwlRig()) {
        self.rig = rig
        super.init()
        name = RoomObjectID.owl.rawValue
        position = homePosition
        addChild(rig.node)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    // MARK: State

    /// One-shot states (`happy`) play over the current state and are not recorded;
    /// the rig ignores a sustained state it is already in.
    func transition(to newState: OwlState) {
        if newState.isSustained { state = newState }
        rig.enter(newState)
    }

    func setMouthOpenness(_ openness: CGFloat) {
        rig.setMouthOpenness(openness)
    }

    func play(_ accent: OwlAccent) {
        rig.play(accent)
    }

    // MARK: Tappable

    var tapID: RoomObjectID { .owl }

    var localHitArea: CGRect {
        // Generous: the whole standing silhouette plus padding. Comfortably past the
        // 88 pt floor at every supported screen size.
        CGRect(x: -130, y: -20, width: 260, height: rig.standingHeight + 40)
    }

    var hitAreaInParent: CGRect {
        localHitArea.offsetBy(dx: position.x, dy: position.y)
    }

    func containsPoint(inParent point: CGPoint) -> Bool {
        localHitArea.contains(CGPoint(x: point.x - position.x, y: point.y - position.y))
    }

    func acknowledgeTap() {
        SoundKit.shared.play(.tap, volumeScale: 0.9)
        wake()
        // A nudge, not a bounce: the tap has to be answered instantly, but the owl may
        // be about to start listening, and a full happy bounce would stamp on that.
        // Praise uses `.happy` explicitly.
        play(.nudge)
    }

    // MARK: Mouth

    /// Opens and closes the beak on a fixed rhythm for the length of a sound that is
    /// played outside the audio engine — the giggles, which come from `SoundKit` and so
    /// produce no envelope to follow.
    func wiggleMouth(for duration: TimeInterval, pulsesPerSecond: Double = 8) {
        guard duration > 0 else { return }
        stopMouthWiggle()
        run(.sequence([
            .customAction(withDuration: duration) { [weak self] _, elapsed in
                let phase = Double(elapsed) * pulsesPerSecond * .pi
                self?.setMouthOpenness(CGFloat(abs(sin(phase))) * 0.8)
            },
            .run { [weak self] in self?.setMouthOpenness(0) }
        ]), withKey: Key.mouth)
    }

    func stopMouthWiggle() {
        removeAction(forKey: Key.mouth)
        setMouthOpenness(0)
    }

    // MARK: Idle clock

    /// Called from the scene's update loop.
    func update(currentTime: TimeInterval) {
        // Only resting counts towards the sleepy idle. Anything else — a mode, a hop,
        // the sleepy pose itself — keeps resetting the clock.
        guard state == .idle, !isTravelling else {
            lastInteraction = currentTime
            return
        }
        guard lastInteraction != 0 else {
            lastInteraction = currentTime
            return
        }
        if currentTime - lastInteraction >= sleepyAfter {
            transition(to: .sleepy)
        }
    }

    /// Resets the idle clock and brings the owl out of the sleepy pose.
    func wake() {
        lastInteraction = 0
        if state == .sleepy {
            SoundKit.shared.play(.wake, volumeScale: 0.8)
            transition(to: .idle)
        }
    }

    // MARK: Movement

    /// Moves the owl to a point in the scene, hopping for short trips and flying for
    /// anything high up. Completion runs after the owl lands.
    ///
    /// A journey already in progress is abandoned rather than queued: a child who taps
    /// the owl mid-hop has to be obeyed now, not after the animation finishes.
    func travel(to destination: CGPoint, completion: (() -> Void)? = nil) {
        wake()
        cancelTravel()

        let delta = CGPoint(x: destination.x - position.x, y: destination.y - position.y)
        let distance = (delta.x * delta.x + delta.y * delta.y).squareRoot()

        guard distance > 4 else {
            completion?()
            return
        }

        isTravelling = true

        let journey: SKAction = abs(delta.y) > 120
            ? flightAction(to: destination, delta: delta, distance: distance)
            : hopAction(to: destination, distance: distance)

        run(.sequence([
            journey,
            // Only the pose is reset here: an action must not remove the action it is
            // running inside, and the sequence is finishing anyway.
            .run { [weak self] in
                guard let self else { return }
                self.isTravelling = false
                self.resetTravelPose()
                completion?()
            }
        ]), withKey: Key.travel)
    }

    /// Abandons a journey in progress. Safe only from outside the travel action itself.
    private func cancelTravel() {
        isTravelling = false
        removeAction(forKey: Key.travel)
        removeAction(forKey: Key.steps)
        resetTravelPose()
    }

    /// Puts the rig back on its feet, level and unoffset.
    private func resetTravelPose() {
        rig.node.removeAction(forKey: Key.bob)
        rig.node.position = .zero
        rig.node.zRotation = 0
    }

    func returnHome(completion: (() -> Void)? = nil) {
        travel(to: homePosition, completion: completion)
    }

    private func hopAction(to destination: CGPoint, distance: CGFloat) -> SKAction {
        let hopCount = max(1, Int((distance / 165).rounded()))
        let perHop = 0.34
        let total = perHop * Double(hopCount)

        // Body arcs while the node slides; the shadow stays on the ground because it
        // lives on `OwlNode`, not inside the hopping group.
        let arc = SKAction.sequence([
            .moveBy(x: 0, y: 46, duration: perHop * 0.45),
            .moveBy(x: 0, y: -46, duration: perHop * 0.55)
        ])
        arc.timingMode = .easeOut
        rig.node.run(.repeat(arc, count: hopCount), withKey: Key.bob)

        let hopSound = SKAction.sequence([
            .run { SoundKit.shared.play(.hop, volumeScale: 0.7) },
            .wait(forDuration: perHop)
        ])
        run(.repeat(hopSound, count: hopCount), withKey: Key.steps)

        let slide = SKAction.move(to: destination, duration: total)
        slide.timingMode = .linear
        return slide
    }

    private func flightAction(to destination: CGPoint, delta: CGPoint, distance: CGFloat) -> SKAction {
        let duration = TimeInterval(min(max(distance / 420, 0.55), 1.3))

        // A single lifted arc, relative to the current position.
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addQuadCurve(
            to: CGPoint(x: delta.x, y: delta.y),
            control: CGPoint(x: delta.x * 0.5, y: max(delta.y, 0) + 150)
        )

        let follow = SKAction.follow(path, asOffset: true, orientToPath: false, duration: duration)
        follow.timingMode = .easeInEaseOut

        // A little banking, so the flight reads as flight and not as a slide.
        let bank = SKAction.sequence([
            .rotate(toAngle: delta.x > 0 ? -0.12 : 0.12, duration: duration * 0.3, shortestUnitArc: true),
            .wait(forDuration: duration * 0.4),
            .rotate(toAngle: 0, duration: duration * 0.3, shortestUnitArc: true)
        ])
        rig.node.run(bank, withKey: Key.bob)

        SoundKit.shared.play(.hop, volumeScale: 0.6)
        return follow
    }

    private enum Key {
        static let travel = "owl.travel"
        static let steps  = "owl.steps"
        static let bob    = "owl.bob"
        static let mouth  = "owl.mouth"
    }
}
