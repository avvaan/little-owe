import SwiftUI
import Speech
import AVFoundation

/// Everything a parent can change, and nothing else.
///
/// Five things, which is the whole list the brief asks for: what is in the room, what is
/// on the lamp, captions, the owl's volume, and a reset. There is no account, no history,
/// no usage report and no "what your child said today", because none of that was ever
/// collected — see `ParentSettings`.
///
/// The screen also tells a parent the truth about the microphone, because a quiet owl
/// with no explanation is the most likely support question this app will ever get.
struct ParentSettingsView: View {

    @ObservedObject var settings: ParentSettings

    /// Nil if the content pack failed to load, which is a broken build rather than a
    /// state to design around — the lamp section simply does not appear.
    var pack: ContentPack?

    /// True when the app has tried the microphone and could not use it.
    var microphoneUnavailable: Bool

    var onReset: () -> Void
    var onDone: () -> Void

    @State private var showingResetConfirmation = false

    #if LITTLE_OWL_AI
    @State private var typedKey = ""
    @State private var keyIsStored = BrainKey.isSet
    #endif

    var body: some View {
        NavigationStack {
            Form {
                roomSection
                if let pack, !pack.spokenSets.isEmpty { lampSection(pack) }
                voiceSection
                microphoneSection
                #if LITTLE_OWL_AI
                brainSection
                #endif
                resetSection
                aboutSection
            }
            .navigationTitle("Grown-up settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }

    // MARK: The room

    private var roomSection: some View {
        Section {
            ForEach(RoomObjectID.allCases.filter { $0 != .owl }, id: \.self) { object in
                Toggle(isOn: Binding(
                    get: { settings.isVisible(object) },
                    set: { settings.setVisible(object, $0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(object.parentName)
                        Text(object.modeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !settings.isVisible(object), let note = staysInThePicture(object) {
                            Text(note)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("In the room")
        } footer: {
            Text("Turning one off takes it out of the room and your child cannot open it any more. The owl itself is always there — tapping it is how your child talks to it, and how they come back from anything.")
        }
    }

    /// The lamp and the window are painted into the room *and* light it, so they cannot
    /// simply be lifted out of the picture the way the book can. Saying so here is better
    /// than a parent turning one off and wondering why it is still on the wall.
    private func staysInThePicture(_ object: RoomObjectID) -> String? {
        switch object {
        case .lamp:
            return "Still painted on the table — it is what lights that corner of the room. It just doesn't do anything now."
        case .window:
            return "Still painted on the wall, and it stops following the time of day. It just doesn't do anything now."
        case .book, .blocks, .owl:
            return nil
        }
    }

    // MARK: The lamp

    private func lampSection(_ pack: ContentPack) -> some View {
        Section {
            ForEach(pack.spokenSets, id: \.id) { set in
                Toggle(isOn: Binding(
                    get: { settings.isEnabled(set) },
                    set: { settings.setEnabled(set, $0, in: pack) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(set.title)
                        Text(setSubtitle(set))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("On the lamp")
        } footer: {
            Text("Your child picks one of these by its picture — a sun, a moon, a bowl. They never see a title. Turn them all off and the lamp does nothing.")
        }
    }

    private func setSubtitle(_ set: SpokenSet) -> String {
        var parts: [String] = [set.kind == .prayer ? "Prayer" : "Rhyme"]
        if set.isPlaceholder {
            parts.append("placeholder text — send us your own")
        } else if let source = set.source {
            parts.append(source)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Voice

    private var voiceSection: some View {
        Section {
            Toggle("Show captions", isOn: Binding(
                get: { settings.captionsEnabled },
                set: { settings.captionsEnabled = $0 }
            ))

            VStack(alignment: .leading) {
                Text("Owl's voice")
                Slider(value: Binding(
                    get: { settings.voiceVolume },
                    set: { settings.voiceVolume = $0 }
                ), in: 0...1) {
                    Text("Owl's voice volume")
                } minimumValueLabel: {
                    Image(systemName: "speaker.fill")
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3.fill")
                }
            }
        } header: {
            Text("Sound and captions")
        } footer: {
            Text("Captions are the only words your child ever sees, and they only appear while the owl is speaking. The app never asks a child to read anything.")
        }
    }

    // MARK: The owl answering for itself

    #if LITTLE_OWL_AI
    /// Only in a build somebody deliberately made. There is no such section in the
    /// App Store build, because there is no such code in it.
    private var brainSection: some View {
        Section {
            Toggle("Let the owl answer new questions", isOn: Binding(
                get: { settings.brainEnabled },
                set: { settings.brainEnabled = $0 }
            ))
            .disabled(!keyIsStored)

            if keyIsStored {
                LabeledContent("API key", value: "Stored on this iPad")
                Button("Remove the key", role: .destructive) {
                    BrainKey.set(nil)
                    keyIsStored = false
                    settings.brainEnabled = false
                    typedKey = ""
                }
            } else {
                SecureField("Anthropic API key", text: $typedKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save the key") {
                    if BrainKey.set(typedKey) {
                        keyIsStored = BrainKey.isSet
                        typedKey = ""
                    }
                }
                .disabled(typedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("When the owl does not know")
        } footer: {
            Text("""
                The owl knows about a hundred and thirty questions by heart. \
                Switched on, anything outside that goes to Anthropic's servers as \
                text — the question only, never your child's voice, never anything \
                about them, and nothing is kept between questions. Answers are \
                checked before they are spoken, and anything that does not come back \
                as one or two plain sentences becomes the owl's ordinary "I do not \
                know that one. Ask your grown-up." So does no signal at all.

                This is the only part of Little Owl that uses the network, it is \
                billed to your own account, and it is off until you turn it on.
                """)
        }
    }
    #endif

    // MARK: Microphone

    private var microphoneSection: some View {
        Section {
            LabeledContent("Microphone", value: microphoneStatus)
            LabeledContent("Speech recognition", value: recognitionStatus)
        } header: {
            Text("Listening")
        } footer: {
            Text("""
                 The owl uses the microphone only while your child is talking to it. \
                 Recognition runs entirely on this iPad — nothing your child says is \
                 recorded, saved or sent anywhere, and the app makes no network \
                 connections at all.

                 If either of these is off, everything still works. The owl waits a \
                 moment instead of listening, and games and questions offer cards to tap.
                 """)
        }
    }

    private var microphoneStatus: String {
        if microphoneUnavailable { return "Not available" }
        switch MicrophonePermission.status {
        case .granted: return "Allowed"
        case .denied: return "Not allowed"
        case .undetermined: return "Not asked yet"
        }
    }

    private var recognitionStatus: String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return "On, on this iPad"
        case .denied, .restricted: return "Not allowed"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Not available"
        }
    }

    // MARK: Reset

    private var resetSection: some View {
        Section {
            Button("Reset the owl", role: .destructive) {
                showingResetConfirmation = true
            }
            .confirmationDialog("Reset the owl?", isPresented: $showingResetConfirmation) {
                Button("Reset", role: .destructive) {
                    settings.resetToDefaults()
                    onReset()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Puts these settings back to how they started and sends the owl back to its perch. There is nothing else to clear.")
            }
        } footer: {
            Text("There is no history to erase. Nothing was ever kept about what your child said, asked or played — these settings are the only thing this app stores.")
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.shortVersion)
            LabeledContent("Ads", value: "None")
            LabeledContent("In-app purchases", value: "None")
            LabeledContent("Accounts", value: "None")
            LabeledContent("Network", value: "Never used")
        } header: {
            Text("About")
        }
    }
}

// MARK: - Small helpers

extension RoomObjectID {
    /// What a parent calls it. The child never sees any of these words.
    var parentName: String {
        switch self {
        case .owl:    return "The owl"
        case .book:   return "The book on the shelf"
        case .lamp:   return "The lamp"
        case .blocks: return "The letter blocks"
        case .window: return "The window"
        }
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
