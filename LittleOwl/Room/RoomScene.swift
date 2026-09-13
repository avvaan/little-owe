import SpriteKit

/// The one screen the child ever sees.
///
/// The scene owns the room, the owl and the routing from a tap to a mode. Modes
/// themselves are not here yet; `handle(_:)` is the single place they will be hooked up.
final class RoomScene: SKScene {

    // MARK: Contents

    private let owl = OwlNode()
    private var props: [RoomObject] = []
    private var windowNode: WindowNode!
    private var lightSpill: SKShapeNode!
    private var ambientWash: SKSpriteNode!
    private var debugOverlay: DebugOverlay?

    private var timeWatcher = TimeOfDayWatcher()

    /// Most specific target first: with padded tap targets the boxes overlap, and a
    /// smaller box always means a more deliberate aim.
    private var tappables: [any Tappable] = []

    /// Which prop the owl is currently attending to. Modes replace this in later
    /// deliverables; today it only decides whether tapping the owl sends it home.
    private(set) var activeMode: RoomObjectID?

    /// Hook for the mode layer. Left unset, the scene falls back to the placeholder
    /// behaviour below so the room is explorable on its own.
    var onModeRequested: ((RoomObjectID) -> Void)?

    // MARK: Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = Palette.roofNear
        scaleMode = .aspectFill

        SoundKit.shared.configureSession()
        SoundKit.shared.preload(SoundKit.Effect.allCases.map(\.rawValue))

        buildRoom()
        applyTimeOfDay(timeWatcher.current, animated: false)
    }

    private func buildRoom() {
        addChild(RoomBuilder.makeShell())
        addChild(RoomBuilder.makeRug())
        addChild(RoomBuilder.makeShelf())
        addChild(RoomBuilder.makeSideTable())
        addChild(RoomBuilder.makePerch())

        let (windowObject, windowNode) = RoomBuilder.makeWindow(time: timeWatcher.current)
        self.windowNode = windowNode

        let book   = RoomBuilder.makeBook()
        let lamp   = RoomBuilder.makeLamp()
        let blocks = RoomBuilder.makeBlocks()

        props = [book, lamp, blocks, windowObject]
        props.forEach { addChild($0) }

        lightSpill = RoomBuilder.makeLightSpill()
        addChild(lightSpill)

        ambientWash = RoomBuilder.makeAmbientWash()
        addChild(ambientWash)

        owl.zPosition = RoomLayout.Z.owl
        addChild(owl)

        tappables = ((props as [any Tappable]) + [owl])
            .sorted { lhs, rhs in
                let a = lhs.hitAreaInParent
                let b = rhs.hitAreaInParent
                return a.width * a.height < b.width * b.height
            }

        if CommandLine.arguments.contains("-showTapTargets") {
            let overlay = DebugOverlay()
            overlay.zPosition = RoomLayout.Z.debug
            addChild(overlay)
            debugOverlay = overlay
        }
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)

        guard let target = tappables.first(where: { $0.containsPoint(inParent: point) }) else {
            // A tap on empty floor still wakes the owl. Nothing in this app is a dead zone
            // that silently ignores a child.
            owl.wake()
            return
        }

        target.acknowledgeTap()
        handle(target.tapID)
    }

    /// The single seam between "a child touched something" and "a mode runs".
    private func handle(_ id: RoomObjectID) {
        if id == .owl {
            if activeMode != nil {
                endActiveMode()
            }
            // Echo mode attaches here in deliverable 2.
            return
        }

        guard activeMode != id else { return }
        activeMode = id

        if let onModeRequested {
            owl.travel(to: RoomLayout.approachPoint(for: id)) { onModeRequested(id) }
            return
        }

        // Placeholder: the owl goes to the object and settles, so the routing and the
        // movement can be judged before any mode exists.
        owl.travel(to: RoomLayout.approachPoint(for: id)) { [weak self] in
            self?.owl.transition(to: .thinking)
        }
    }

    private func endActiveMode() {
        activeMode = nil
        owl.transition(to: .idle)
        owl.returnHome()
    }

    // MARK: Time of day

    /// Called by the SwiftUI host when the app returns to the foreground, where hours
    /// may have passed with the update loop stopped.
    func refreshTimeOfDay() {
        if let changed = timeWatcher.refresh() {
            applyTimeOfDay(changed, animated: true)
        }
    }

    private func applyTimeOfDay(_ time: TimeOfDay, animated: Bool) {
        windowNode?.setTime(time, animated: animated)

        let spill = WindowNode.spill(for: time)
        let wash  = Palette.ambientWash(for: time)
        let duration: TimeInterval = animated ? 1.4 : 0

        lightSpill.fillColor = spill.color
        lightSpill.run(.fadeAlpha(to: spill.alpha, duration: duration))

        ambientWash.color = wash.color
        ambientWash.blendMode = wash.blend
        ambientWash.run(.fadeAlpha(to: wash.alpha, duration: duration))
    }

    // MARK: Update

    override func update(_ currentTime: TimeInterval) {
        owl.update(currentTime: currentTime)

        if let changed = timeWatcher.poll(sceneTime: currentTime) {
            applyTimeOfDay(changed, animated: true)
        }

        debugOverlay?.refresh(with: tappables, sceneScale: sceneScaleForCurrentView())
    }

    /// How many device points one design point occupies right now. Used only to prove
    /// the 88 pt tap-target floor on the actual screen.
    private func sceneScaleForCurrentView() -> CGFloat {
        guard let view, size.width > 0, size.height > 0 else { return 1 }
        return max(view.bounds.width / size.width, view.bounds.height / size.height)
    }
}
