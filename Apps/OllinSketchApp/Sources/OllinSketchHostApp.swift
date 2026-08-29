import SwiftUI
import Ollin

/// **Ollin Sketch**: one sketch, running as an app on the phone and the tablet.
///
/// On the desk a sketch is its own program, and `Sketch.main()` opens the
/// window for it. An app cannot work that way: the system owns the launch, so
/// the app declares the entry point and puts the sketch inside a `SketchView`,
/// which is the same view the desk hosts use. Everything else is the sketch.
///
/// The canvas takes the whole screen, edges included, because a piece has no
/// chrome to leave room for.
@main
struct OllinSketchHostApp: App {
    // `Scene` is spelled out, because the framework has a 3D scene of its own
    // and the bare name is then two types.
    var body: some SwiftUI.Scene {
        WindowGroup {
            SketchView(TouchRings())
                .ignoresSafeArea()
                .background(.black)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}
