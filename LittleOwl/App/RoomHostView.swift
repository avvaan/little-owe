import SwiftUI
import SpriteKit

/// The whole child-facing app is one SpriteKit scene with no chrome around it.
///
/// SwiftUI appears twice: here, for the small quiet corner that leads to the parental
/// gate, and behind that gate for the settings screen. A child sees neither.
struct RoomHostView: View {

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = ParentSettings.shared

    /// Built once and kept for the life of the app. Rebuilding the scene would restart
    /// the owl mid-sentence.
    @State private var scene: RoomScene = {
        let scene = RoomScene(size: RoomLayout.designSize)
        scene.scaleMode = .aspectFill
        return scene
    }()

    /// Enums with no associated values are Equatable and Hashable already, which is what
    /// `onChange` and `fullScreenCover(item:)` want.
    private enum ParentSheet: Int, Identifiable {
        case gate, settings
        var id: Int { rawValue }
    }

    @State private var parentSheet: ParentSheet?

    var body: some View {
        ZStack(alignment: .topLeading) {
            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()

            // The one way to the parent settings. It sits over the dark roof beam in the
            // corner, shows nothing until it is held, and is the only control in the app
            // that is deliberately hard for a small hand to use.
            GateCornerButton { parentSheet = .gate }
                .padding(.leading, 18)
                .padding(.top, 18)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .fullScreenCover(item: $parentSheet) { sheet in
            switch sheet {
            case .gate:
                ParentalGateView(
                    onPassed: { parentSheet = .settings },
                    onCancelled: { parentSheet = nil }
                )
            case .settings:
                ParentSettingsView(
                    settings: settings,
                    pack: scene.contentPack,
                    microphoneUnavailable: scene.isMicrophoneUnavailable,
                    onReset: {
                        scene.resetOwl()
                        parentSheet = nil
                    },
                    onDone: {
                        scene.applySettings()
                        parentSheet = nil
                    }
                )
            }
        }
        .onChange(of: parentSheet) { _, sheet in
            // The owl stops talking while a grown-up is in the settings, and picks the
            // room back up when they leave.
            if sheet != nil { scene.handleAppBackgrounded() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Hours can pass while backgrounded; the window must not still show
                // last night's moon.
                scene.refreshTimeOfDay()
            case .background:
                scene.handleAppBackgrounded()
            default:
                // Deliberately not `.inactive`: the microphone permission alert puts
                // the app there, and cancelling Echo underneath it would throw away
                // the very tap that asked for permission.
                break
            }
        }
    }
}
