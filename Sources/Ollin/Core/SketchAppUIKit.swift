#if !os(macOS)

import SwiftUI
import UIKit

// The app a sketch runs as on a phone or a tablet, so `@main` on the sketch is
// the whole program there too. On the desk `Sketch.main()` opens a window; here
// the system owns the launch and wants a SwiftUI `App`, so this is that app,
// written once in the framework instead of once in every project. A project is
// then its manifest and one sketch file, the same file the desk runs.

public extension Sketch {
    /// The entry point `@main` reaches on a phone or a tablet:
    ///
    /// ```swift
    /// @main
    /// final class Rings: Sketch {
    ///     override func draw() { /* ... */ }
    /// }
    /// ```
    ///
    /// `@main` calls this inherited `main()` with `Self` bound to the concrete
    /// subclass, so `Self()` builds that sketch and `OllinApp.run` starts the
    /// app around it: the canvas full screen, and the sketch's `@Param`s a tap
    /// away when it declares any. It is the same declaration the desk's
    /// `main()` reads, which is why one file runs in both places.
    @MainActor
    static func main() {
        OllinApp.run(Self())
    }
}

public extension OllinApp {
    /// Start an app around `sketch` and run it; does not return.
    ///
    /// The canvas takes the whole screen, edges included, with the status bar
    /// and the home indicator hidden, because a piece has no chrome to leave
    /// room for. A sketch that declares `@Param`s has them a keystroke away,
    /// Command-/ with a keyboard: a panel beside the canvas on a tablet or a
    /// Mac, a sheet on a phone. A development build also shows a small button
    /// in the top corner that opens them, whatever the sketch declares, since
    /// a phone has no keyboard; a release build never does, so what is handed
    /// to somebody else carries no tuning control over the art. A checkpoint
    /// the sketch declares in its `installation` is kept, and a piece that
    /// declares an installation keeps the screen awake unless it turns
    /// `keepsDisplayAwake` off.
    ///
    /// Call this yourself, from a `static func main()` of your own, to set the
    /// sketch up before it runs (an extension attached, a value given); `@main`
    /// on the sketch calls it for you otherwise.
    @MainActor
    static func run(_ sketch: Sketch) {
        // The run's `--param` values go on before anything reads the sketch,
        // as on the desk, so a launch argument from Xcode's scheme is honored.
        sketch.applyCommandLineValues()
        hostedSketch = sketch
        SketchTouchApp.main()
    }

    /// The instance handed to `run`, read back once SwiftUI makes the app
    /// (SwiftUI builds the `App` itself, so the sketch is passed out of band).
    @MainActor
    fileprivate static var hostedSketch: Sketch?
}

/// The app `OllinApp.run` starts on a phone or a tablet: one window holding
/// the sketch.
struct SketchTouchApp: App {
    // `Scene` is spelled out, because the framework has a 3D scene of its own
    // and the bare name is then two types.
    var body: some SwiftUI.Scene {
        WindowGroup {
            if let sketch = OllinApp.hostedSketch {
                SketchTouchHost(sketch: sketch)
            }
        }
    }
}

/// The sketch full screen, and its parameters when it has any.
struct SketchTouchHost: View {
    let sketch: Sketch
    /// Read once: what a sketch declares is fixed for its run, and the list
    /// itself follows each parameter's show rule as the run goes on.
    private let parameters: [ParamHandle]
    @State private var showsParameters = false

    init(sketch: Sketch) {
        self.sketch = sketch
        self.parameters = sketch.parameters()
    }

    /// Whether the button that opens them is drawn: in a build made to work on
    /// (Xcode's Run), never in one archived to hand out. The framework is
    /// compiled with the app, under the app's configuration, so this follows
    /// the app's build. It does not follow the sketch's `installation`, since
    /// a checkpoint alone is one and a phone has no keyboard for the shortcut.
    /// The shortcut works either way.
    private static var showsButton: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SketchView(sketch, onRunner: { [sketch] runner in
                // The app owns the launch, so nothing else reads what the sketch
                // declares: its checkpoint starts here, and a piece meant to run
                // unattended keeps the screen from sleeping under it unless it
                // says otherwise.
                let installation = Installation.resolved(for: sketch)
                runner.beginInstallation(installation)
                if installation.runsUnattended && installation.keepsDisplayAwake {
                    UIApplication.shared.isIdleTimerDisabled = true
                }
            })
            .ignoresSafeArea()
            .background(.black)

            if !parameters.isEmpty {
                // Kept in the tree when it is not shown, invisible and out of
                // the touch path, because a keyboard shortcut belongs to a
                // control that is there.
                Button {
                    showsParameters.toggle()
                } label: {
                    SwiftUI.Image(systemName: "slider.horizontal.3")
                        .font(.body.weight(.semibold))
                        .padding(6)
                }
                .buttonStyle(.glass)
                .keyboardShortcut("/", modifiers: .command)
                .accessibilityLabel("Parameters")
                .padding()
                .opacity(Self.showsButton ? 1 : 0)
                .allowsHitTesting(Self.showsButton)
                .accessibilityHidden(!Self.showsButton)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .inspector(isPresented: $showsParameters) {
            ScrollView {
                ParametersListView(parameters: parameters, sketchName: sketch.title)
                    .padding()
            }
            .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

#endif
