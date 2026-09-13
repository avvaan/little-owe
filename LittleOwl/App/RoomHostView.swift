import SwiftUI
import SpriteKit

/// The whole child-facing app is one SpriteKit scene with no chrome around it.
///
/// SwiftUI appears again only for the parent settings screen, behind the parental gate,
/// in deliverable 7.
struct RoomHostView: View {

    @Environment(\.scenePhase) private var scenePhase

    /// Built once and kept for the life of the app. Rebuilding the scene would restart
    /// the owl mid-sentence.
    @State private var scene: RoomScene = {
        let scene = RoomScene(size: RoomLayout.designSize)
        scene.scaleMode = .aspectFill
        return scene
    }()

    var body: some View {
        SpriteView(scene: scene, options: [.ignoresSiblingOrder])
            .ignoresSafeArea()
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .onChange(of: scenePhase) { _, phase in
                // Hours can pass while backgrounded; the window must not still show
                // last night's moon.
                if phase == .active { scene.refreshTimeOfDay() }
            }
    }
}
