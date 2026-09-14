import Foundation
import Combine

/// The only thing this app stores.
///
/// No history, no logs, nothing about what a child said or tapped or how long they
/// played — just the handful of choices a parent makes behind the gate. Five keys in
/// `UserDefaults`, all of them written from one screen, and a fresh install starts with
/// every one of them unset.
///
/// The one thing that is not a preference is the API key a `LITTLE_OWL_AI` build can
/// hold, and it deliberately does not live here: see `BrainKey`.
///
/// It is an `ObservableObject` because the settings screen is SwiftUI, and every setter
/// writes straight through to `UserDefaults` so a parent closing the app mid-change does
/// not lose it.
final class ParentSettings: ObservableObject {

    static let shared = ParentSettings()

    private let defaults: UserDefaults

    /// Injectable so tests get their own suite rather than the simulator's.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let enabledSpokenSets = "parent.enabledSpokenSets"
        static let hiddenObjects = "parent.hiddenObjects"
        static let captions = "parent.captions"
        static let voiceVolume = "parent.voiceVolume"
        static let brain = "parent.brain"
        static let brainProvider = "parent.brainProvider"
        static let character = "parent.character"
    }

    // MARK: What is in the room

    /// Props the parent has taken out of the room. Stored as the hidden set rather than
    /// the visible one so that a prop added in a later version is **on** by default
    /// instead of silently missing for everyone who already opened settings once.
    ///
    /// The owl is not in here and cannot be: it is the app.
    var hiddenObjects: Set<RoomObjectID> {
        get {
            let raw = defaults.array(forKey: Key.hiddenObjects) as? [String] ?? []
            return Set(raw.compactMap(RoomObjectID.init(rawValue:)).filter { $0 != .owl })
        }
        set {
            objectWillChange.send()
            let cleaned = newValue.filter { $0 != .owl }
            defaults.set(cleaned.map(\.rawValue).sorted(), forKey: Key.hiddenObjects)
        }
    }

    func isVisible(_ id: RoomObjectID) -> Bool {
        id == .owl || !hiddenObjects.contains(id)
    }

    func setVisible(_ id: RoomObjectID, _ visible: Bool) {
        guard id != .owl else { return }
        var hidden = hiddenObjects
        if visible { hidden.remove(id) } else { hidden.insert(id) }
        hiddenObjects = hidden
    }

    // MARK: What is on the lamp

    /// Which prayer and rhyme sets are on the lamp.
    ///
    /// Nil until a parent has chosen, and nil means all of them: a family that never
    /// opens settings still gets the whole pack. An empty set is a real choice — the
    /// parent turned everything off — and the lamp then does nothing.
    var enabledSpokenSetIDs: Set<String>? {
        get {
            guard let ids = defaults.array(forKey: Key.enabledSpokenSets) as? [String] else { return nil }
            return Set(ids)
        }
        set {
            objectWillChange.send()
            guard let newValue else {
                defaults.removeObject(forKey: Key.enabledSpokenSets)
                return
            }
            defaults.set(newValue.sorted(), forKey: Key.enabledSpokenSets)
        }
    }

    /// The sets the lamp offers, **in pack order**. The order comes from the pack rather
    /// than from the parent's selection, so the cards do not move around between
    /// sessions — a child learns where the moon one is.
    func spokenSets(from pack: ContentPack) -> [SpokenSet] {
        guard let enabled = enabledSpokenSetIDs else { return pack.spokenSets }
        return pack.spokenSets.filter { enabled.contains($0.id) }
    }

    func isEnabled(_ set: SpokenSet) -> Bool {
        enabledSpokenSetIDs?.contains(set.id) ?? true
    }

    /// Turning one on or off for the first time has to write out the whole current
    /// selection, because "nil" means everything and there is no way back to it.
    func setEnabled(_ set: SpokenSet, _ enabled: Bool, in pack: ContentPack) {
        var ids = enabledSpokenSetIDs ?? Set(pack.spokenSets.map(\.id))
        if enabled { ids.insert(set.id) } else { ids.remove(set.id) }
        enabledSpokenSetIDs = ids
    }

    // MARK: Captions and volume

    /// Captions are the only text a child ever sees, and they are optional.
    var captionsEnabled: Bool {
        get { defaults.object(forKey: Key.captions) as? Bool ?? true }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Key.captions)
        }
    }

    /// 0...1. The owl's voice only — the sound effects have their own soft level and sit
    /// well under it either way.
    var voiceVolume: Double {
        get {
            guard let stored = defaults.object(forKey: Key.voiceVolume) as? Double else { return 1 }
            return min(max(stored, 0), 1)
        }
        set {
            objectWillChange.send()
            defaults.set(min(max(newValue, 0), 1), forKey: Key.voiceVolume)
        }
    }

    // MARK: Who lives in the attic

    /// The owl unless somebody chose otherwise.
    ///
    /// The one setting here a **child** sets rather than a parent: it is changed by
    /// tapping the badge in the corner of the room, not from this screen. It is kept
    /// here anyway because it is a preference that has to survive the app closing, and
    /// this is where preferences live. A character whose paintings are not in the
    /// bundle falls back to the owl rather than leaving the room empty.
    var character: Character {
        get {
            guard let raw = defaults.string(forKey: Key.character),
                  let character = Character(rawValue: raw),
                  character.isAvailable else { return .fallback }
            return character
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: Key.character)
        }
    }

    // MARK: The owl answering for itself

    /// Whether the owl may ask a model when the question bank has no answer.
    ///
    /// Off until a parent turns it on, and in a build without `LITTLE_OWL_AI` there is
    /// nothing for it to turn on — the code it would reach is not compiled. So this
    /// setting is inert in every build but the one somebody deliberately made, which is
    /// why it can sit here in the ordinary settings rather than behind a second door.
    var brainEnabled: Bool {
        get { defaults.object(forKey: Key.brain) as? Bool ?? false }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Key.brain)
        }
    }

    /// Which service the owl asks. Claude unless a parent chose otherwise; an
    /// unrecognised stored value falls back to it rather than breaking the screen.
    var brainProvider: BrainProvider {
        get {
            guard let raw = defaults.string(forKey: Key.brainProvider),
                  let provider = BrainProvider(rawValue: raw) else { return .anthropic }
            return provider
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: Key.brainProvider)
        }
    }

    // MARK: Reset

    /// Puts every setting back to its default.
    ///
    /// Note what this does **not** do, because it is the whole point: there is no child
    /// data to clear. Nothing was ever kept about what the child said, asked, answered or
    /// played, so a reset has nothing to erase but these five preferences — and,
    /// in a build that has one, the parent's own API key.
    func resetToDefaults() {
        objectWillChange.send()
        for key in [Key.enabledSpokenSets, Key.hiddenObjects, Key.captions,
                    Key.voiceVolume, Key.brain, Key.brainProvider, Key.character] {
            defaults.removeObject(forKey: key)
        }
        #if LITTLE_OWL_AI
        // The one stored thing that is not a preference. A parent resetting the app has
        // asked for their keys to be gone, not for them to be quietly kept - and that
        // means every provider's, not just the one currently selected.
        BrainKey.removeAll()
        #endif
    }
}
