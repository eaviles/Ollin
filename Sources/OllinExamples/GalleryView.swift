import SwiftUI
import Ollin
import OllinRuntime

/// Sidebar of examples + a detail pane that compiles and embeds the selected
/// sketch. Loading happens off the main thread (each compile is ~1s) and is
/// cached, so re-selecting an example is instant.
struct GalleryView: View {
    /// Fixed sidebar width. The detail pane is pinned to the sketch's square, so
    /// the window is exactly `square + sidebarWidth` wide and can't be resized;
    /// collapsing the sidebar narrows it to just the square.
    static let sidebarWidth: CGFloat = 230

    let examples: [Example]

    @State private var selection: Example.ID?
    @State private var cache: [Example.ID: Sketch] = [:]
    @State private var detail: DetailState = .empty

    private enum DetailState {
        case empty
        case loading(String)
        case loaded(Example.ID, Sketch)
        case failed(String)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(ExampleCatalog.categories(of: examples), id: \.self) { category in
                    Section(category) {
                        ForEach(examples.filter { $0.category == category }) { example in
                            Text(example.displayName).tag(example.id)
                        }
                    }
                }
            }
            .navigationTitle("Examples")
            .navigationSplitViewColumnWidth(Self.sidebarWidth)
        } detail: {
            detailPane
        }
        .task(id: selection) { await loadSelected() }
    }

    @ViewBuilder private var detailPane: some View {
        // Pin the detail pane to a fixed square so the sketch renders at its true
        // size (never stretched to fill the pane) and the window stays square.
        Group {
            switch detail {
            case .empty:
                ContentUnavailableView(
                    "Pick an example", systemImage: "sidebar.left",
                    description: Text("Select a sketch from the list to run it here."))
            case .loading(let name):
                ProgressView("Compiling \(name)…")
            case .loaded(let id, let sketch):
                SketchView(sketch).id(id)   // .id recreates (and tears down) on switch
                    .frame(width: OllinApp.windowSize(for: sketch).width,
                           height: OllinApp.windowSize(for: sketch).height)
            case .failed(let message):
                ScrollView {
                    Text(message)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
        .frame(width: OllinApp.defaultWindowSize.width, height: OllinApp.defaultWindowSize.height)
    }

    /// Load the current selection: cached → instant; otherwise compile off the
    /// main actor (the slow `swiftc`) and instantiate on the main actor. Driven by
    /// `.task(id: selection)`, which cancels this when the selection changes — so
    /// a stale compile's result is dropped rather than racing the new one in.
    @MainActor
    private func loadSelected() async {
        guard let id = selection, let example = examples.first(where: { $0.id == id }) else {
            CrashReporter.setCurrentExample(nil)
            detail = .empty
            return
        }
        // Name the example for the crash reporter as soon as it's the selection, so
        // a fault while it loads or runs is attributed to it.
        CrashReporter.setCurrentExample(example.displayName)
        if let cached = cache[id] {
            detail = .loaded(id, cached)
            return
        }
        detail = .loading(example.name)
        let path = example.sketchPath
        let compiled = await Task.detached(priority: .userInitiated) {
            SketchLoader(sketchPath: path).compile()
        }.value
        guard !Task.isCancelled else { return }   // user moved on while compiling
        switch compiled {
        case .success(let dylibPath):
            switch SketchLoader(sketchPath: path).instantiate(dylibPath: dylibPath) {
            case .success(let sketch):
                cache[id] = sketch
                detail = .loaded(id, sketch)
            case .failure(let error):
                detail = .failed(String(describing: error))
            }
        case .failure(let error):
            detail = .failed(String(describing: error))
        }
    }
}
