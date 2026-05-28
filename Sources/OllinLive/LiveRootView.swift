import SwiftUI
import Ollin

/// The live host's window: the sketch renders in the detail pane; the sidebar
/// inspector shows reload status. The sketch's `SketchRunner` is created here
/// (the detail view owns the `MTKView`) and handed to the session so the
/// watcher can drive hot-swaps.
struct LiveRootView: View {
    let session: LiveSession

    var body: some View {
        NavigationSplitView {
            InspectorPanel(session: session)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 380)
        } detail: {
            detail.navigationTitle(session.title)
        }
        .task { session.start() }
    }

    // Lightweight until the first compile lands: a plain SwiftUI placeholder, not
    // a Metal view (mounting an MTKView at launch kept the window from surfacing).
    // Once `sketch` is set, the SketchView mounts and creates the runner.
    @ViewBuilder private var detail: some View {
        if let sketch = session.sketch {
            SketchView(sketch) { runner in session.attach(runner) }
        } else if let error = session.errorMessage {
            ContentUnavailableView {
                Label("Compile error", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        } else {
            ProgressView("Compiling \(session.displayName)…")
        }
    }
}
