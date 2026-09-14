import SpriteKit

/// The one screen the child ever sees.
///
/// The scene owns the room, the owl and the routing from a tap to a mode. `handle(_:)`
/// is the single place a mode is hooked up, and the only place that knows a tap on the
/// book means Stories.
final class RoomScene: SKScene {

    // MARK: Contents

    private let owl = OwlNode()
    private var props: [RoomObject] = []
    private var windowNode: WindowNode!
    private var ambientWash: SKSpriteNode!
    private var debugOverlay: DebugOverlay?

    private var timeWatcher = TimeOfDayWatcher()

    /// Echo is the owl's own mode: it needs no content and the owl never leaves its
    /// perch for it, so unlike the props it does not set `activeMode`.
    private lazy var echo = EchoMode(owl: owl)

    /// The content pack and the modes that read from it. Nil means the pack could not
    /// be loaded, which is a broken build rather than a state to design around — the
    /// room still works and the book simply does nothing.
    private var pack: ContentPack?
    private var voice: OwlVoice?
    private var story: StoryMode?
    private var spokenSets: SpokenSetMode?

    /// Every mode that dims the room behind it. The scene routes taps through whichever
    /// one is running rather than knowing what each of them is.
    private var roomModes: [any RoomMode] { [story, spokenSets].compactMap { $0 } }

    /// Most specific target first: with padded tap targets the boxes overlap, and a
    /// smaller box always means a more deliberate aim.
    private var tappables: [any Tappable] = []

    /// Which prop the owl is currently attending to. Modes replace this in later
    /// deliverables; today it only decides whether tapping the owl sends it home.
    private(set) var activeMode: RoomObjectID?

    /// Set once the microphone turns out to be unavailable — denied, or the engine
    /// would not start. The child is never told; parent settings (deliverable 7) read
    /// this to explain the quiet owl.
    private(set) var isMicrophoneUnavailable = false

    /// Hook for the mode layer. Left unset, the scene falls back to the placeholder
    /// behaviour below so the room is explorable on its own.
    var onModeRequested: ((RoomObjectID) -> Void)?

    // MARK: Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = Palette.roomShadow
        scaleMode = .aspectFill

        AudioSession.shared.configure()
        AudioSession.shared.onAudioLost = { [weak self] in
            self?.echo.cancel()
            self?.roomModes.forEach { $0.leave() }
        }
        echo.onMicrophoneUnavailable = { [weak self] in self?.isMicrophoneUnavailable = true }
        SoundKit.shared.preload()

        loadContent()

        buildRoom()
        applyTimeOfDay(timeWatcher.current, animated: false)
    }

    private func buildRoom() {
        addChild(RoomBuilder.makeRoom())

        let (windowObject, windowNode) = RoomBuilder.makeWindow(time: timeWatcher.current)
        self.windowNode = windowNode

        props = [RoomBuilder.makeBook(), RoomBuilder.makeLamp(), RoomBuilder.makeBlocks(), windowObject]
        props.forEach { addChild($0) }

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

    // MARK: Content

    private func loadContent() {
        do {
            let pack = try ContentLoader.load()
            let voice = OwlVoice(pack: pack)
            let story = StoryMode(scene: self, owl: owl, pack: pack, voice: voice)
            story.onOfferAgain = { [weak self] offering in self?.offer(.book, offering) }
            story.onLeave = { [weak self] in self?.activeMode = nil }

            let spokenSets = SpokenSetMode(scene: self, owl: owl, pack: pack, voice: voice)
            spokenSets.onOfferAgain = { [weak self] offering in self?.offer(.lamp, offering) }
            spokenSets.onLeave = { [weak self] in self?.activeMode = nil }

            self.pack = pack
            self.voice = voice
            self.story = story
            self.spokenSets = spokenSets
        } catch {
            // Nothing to show a child, and nothing a child could do about it. The room
            // stays playable and Echo still works.
            assertionFailure("Content pack failed to load: \(error)")
        }
    }

    /// Lifts a prop above a mode's dimming and lets it glow, so "tap the book to hear it
    /// again" — or the lamp — is an offer the child can actually see.
    private func offer(_ id: RoomObjectID, _ offering: Bool) {
        guard let prop = props.first(where: { $0.id == id }) else { return }
        prop.zPosition = offering ? ModeLayer.offer : RoomLayout.Z.props
        prop.setOffering(offering)
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)

        // While a mode is on screen the room is behind a dimming layer. Only the owl and
        // — when the mode is offering one — the prop that means "again" are reachable;
        // anything else would be a tap on something the child cannot see.
        if let mode = roomModes.first(where: { $0.isRunning }) {
            if mode.handleTap(at: point) { return }

            if owl.containsPoint(inParent: point) {
                owl.acknowledgeTap()
                mode.leave()
                return
            }
            if let id = mode.againProp,
               let prop = props.first(where: { $0.id == id }),
               prop.containsPoint(inParent: point) {
                prop.acknowledgeTap()
                mode.againTapped()
                return
            }
            return
        }

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
            // While a prop mode is running, the owl is the way back to the room.
            // Otherwise it is Echo, which is always available.
            if activeMode != nil {
                endActiveMode()
            } else {
                echo.handleOwlTap()
            }
            return
        }

        guard activeMode != id else { return }
        echo.cancel()
        activeMode = id

        if id == .book, let story {
            story.begin()
            return
        }

        if id == .lamp, let spokenSets, spokenSets.canBegin {
            spokenSets.begin()
            return
        }

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
        echo.cancel()
        if let mode = roomModes.first(where: { $0.isRunning }) {
            mode.leave()
            return
        }
        owl.transition(to: .idle)
        owl.returnHome()
    }

    // MARK: App lifecycle

    /// Called by the SwiftUI host when the app leaves the foreground. Anything holding
    /// the microphone has to let go, and the recording has to be released.
    func handleAppBackgrounded() {
        echo.cancel()
        roomModes.forEach { $0.leave() }
        SoundKit.shared.stopAllLoops()
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

        let wash = Palette.ambientWash(for: time)
        ambientWash.color = wash.color
        ambientWash.blendMode = wash.blend
        ambientWash.run(.fadeAlpha(to: wash.alpha, duration: animated ? 1.4 : 0))
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
