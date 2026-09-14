import Foundation

/// The only thing this app stores.
///
/// No history, no logs, nothing about what a child said or tapped or how long they
/// played — just the handful of choices a parent makes behind the gate. Deliverable 7
/// builds the gate and the screen; this is the store underneath it, and Prayers is its
/// first reader.
final class ParentSettings {

    static let shared = ParentSettings()

    private let defaults: UserDefaults

    /// Injectable so tests get their own suite rather than the simulator's.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let enabledSpokenSets = "parent.enabledSpokenSets"
    }

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
}
