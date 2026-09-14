import SpriteKit

/// The one screen the child ever sees.
///
/// The scene owns the room, the owl and the routing from a tap to a mode. `handle(_:)`
/// is the single place a mode is hooked up, and the only place that knows a tap on the
/// book means Stories.
final class RoomScene: SKScene {

    // MARK: Contents

    private let owl = OwlNode(rig: WatercolourOwlRig(character: ParentSettings.shared.character))

    /// Only built when there is a second character's artwork to offer. Nil is the
    /// ordinary state of a build whose second set of paintings has not landed.
    private var characterPicker: CharacterPicker?
    private var props: [RoomObject] = []
    private var windowNode: WindowNode!
    /// Shown in the book's place when a parent takes the book out of the room.
    private var bookPatch: SKSpriteNode!
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
    private var wordGames: WordGameMode?
    private var why: WhyMode?
    private var wonder: WonderMode?

    /// Every mode that dims the room behind it. The scene routes taps through whichever
    /// one is running rather than knowing what each of them is.
    private var roomModes: [any RoomMode] {
        // Written out rather than `[story, spokenSets].compactMap`, which infers `[Any]`
        // from two differently-typed optionals.
        var modes: [any RoomMode] = []
        if let story { modes.append(story) }
        if let spokenSets { modes.append(spokenSets) }
        if let wordGames { modes.append(wordGames) }
        if let why { modes.append(why) }
        if let wonder { modes.append(wonder) }
        return modes
    }

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

    /// The parent's choices. The child-facing app reads them and never writes them.
    let settings: ParentSettings

    /// So the settings screen can list what is actually in the pack.
    var contentPack: ContentPack? { pack }

    init(size: CGSize, settings: ParentSettings = .shared) {
        self.settings = settings
        super.init(size: size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

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
        applySettings()
    }

    // MARK: Parent settings

    /// Pushes the parent's choices into the room. Called at launch and every time the
    /// settings screen closes, so a change lands without restarting anything.
    ///
    /// A prop turned off is taken out of the room and out of hit-testing, and any mode
    /// running behind it is sent home — a child must not be left inside a story whose
    /// book has just vanished from the shelf.
    func applySettings() {
        for prop in props {
            let visible = settings.isVisible(prop.id)
            if !visible, activeMode == prop.id { endActiveMode() }
            prop.isAvailable = visible
        }

        // The book is painted into the wall, so taking it out of the room means putting
        // a piece of wall over it. The blocks are their own sprites and simply go.
        //
        // The lamp and the window stay painted where they are: both are light sources and
        // their glow is part of the picture, so they cannot be cloned over. Turning them
        // off stops the mode and takes them out of hit-testing, and a tap there falls
        // through to waking the owl rather than into nothing.
        bookPatch.isHidden = settings.isVisible(.book)

        voice?.volume = settings.voiceVolume

        let captions = settings.captionsEnabled
        story?.captionsEnabled = captions
        spokenSets?.captionsEnabled = captions
        wordGames?.captionsEnabled = captions
        why?.captionsEnabled = captions
        wonder?.captionsEnabled = captions
    }

    /// "Reset owl": stop whatever is happening and put the owl back on its perch.
    ///
    /// There is nothing else to reset. No progress, no history, no saved state about the
    /// child — the app has never had any. This is a way out of a mode for a parent whose
    /// child has wandered off mid-story, and nothing more.
    func resetOwl() {
        echo.cancel()
        roomModes.forEach { $0.leave() }
        activeMode = nil
        SoundKit.shared.stopAllLoops()
        owl.transition(to: .idle)
        owl.returnHome()
        applySettings()
    }

    private func buildRoom() {
        addChild(RoomBuilder.makeRoom())

        let (windowObject, windowNode) = RoomBuilder.makeWindow(time: timeWatcher.current)
        self.windowNode = windowNode

        props = [RoomBuilder.makeBook(), RoomBuilder.makeLamp(), RoomBuilder.makeBlocks(), windowObject]
        // The basket is the only prop that is not in the painting, so it is the only one
        // that can be missing. A build without its artwork simply has no corner.
        if let basket = RoomBuilder.makeBasket() { props.append(basket) }
        props.forEach { addChild($0) }

        bookPatch = RoomBuilder.makeBookPatch()
        addChild(bookPatch)

        ambientWash = RoomBuilder.makeAmbientWash()
        addChild(ambientWash)

        owl.zPosition = RoomLayout.Z.owl
        addChild(owl)

        buildCharacterPicker()

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

            let wordGames = WordGameMode(scene: self, owl: owl, pack: pack, voice: voice)
            wordGames.onLeave = { [weak self] in self?.activeMode = nil }

            let why = WhyMode(scene: self, owl: owl, pack: pack, voice: voice)
            why.onLeave = { [weak self] in self?.activeMode = nil }

            let wonder = WonderMode(scene: self, owl: owl, pack: pack, voice: voice)
            wonder.onLeave = { [weak self] in self?.activeMode = nil }

            self.pack = pack
            self.voice = voice
            self.story = story
            self.spokenSets = spokenSets
            self.wordGames = wordGames
            self.why = why
            self.wonder = wonder
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

        // Before the room's own props: it sits in a corner nothing else claims, and a
        // child reaching for a corner should not have to be accurate.
        if let picker = characterPicker, picker.containsPoint(inParent: point) {
            picker.acknowledgeTap()
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
    /// The badge in the corner, offering whichever animal is not on the perch.
    ///
    /// Built only when a second character's paintings are actually in the bundle, so a
    /// build with one animal has no corner badge at all rather than a badge that offers
    /// nothing.
    private func buildCharacterPicker() {
        let others = Character.available.filter { $0 != owl.character }
        guard let other = others.first else { return }

        let picker = CharacterPicker(offering: other)
        picker.onPick = { [weak self] character in self?.change(to: character) }
        addChild(picker)
        characterPicker = picker
    }

    /// Swaps who lives here.
    ///
    /// Everything except the paintings stays: the same node, the same modes holding the
    /// same reference to it, the same pose. A child who swaps while the owl is halfway
    /// through a story gets the puppy halfway through the same story.
    private func change(to character: Character) {
        guard character != owl.character, character.isAvailable else { return }

        ParentSettings.shared.character = character
        owl.wear(WatercolourOwlRig(character: character))
        owl.transition(to: .happy)
        characterPicker?.nowOnThePerch(character)
    }

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

        if id == .blocks, let wordGames, wordGames.canBegin {
            wordGames.begin()
            return
        }

        if id == .window, let why, why.canBegin {
            why.begin()
            return
        }

        if id == .basket, let wonder, wonder.canBegin {
            wonder.begin()
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
