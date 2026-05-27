import SwiftUI
import Ollin
import OllinRuntime

/// Sidebar of examples + a detail pane that compiles and embeds the selected
/// sketch. Loading happens off the main thread (each compile is ~1s) and is
/// cached, so re-selecting an example is instant.
struct GalleryView: View {
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
            .frame(minWidth: 230)
        } detail: {
            detailPane
        }
        .task(id: selection) { loadSelected() }
    }

    @ViewBuilder private var detailPane: some View {
        switch detail {
        case .empty:
            ContentUnavailableViewCompat(
                "Pick an example", systemImage: "sidebar.left",
                description: "Select a sketch from the list to run it here.")
        case .loading(let name):
            ProgressView("Compiling \(name)…")
        case .loaded(let id, let sketch):
            SketchView(sketch).id(id)   // .id recreates (and tears down) on switch
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

    /// Load the current selection: cached → instant; otherwise compile off the
    /// main thread and update the detail state when it lands (ignoring the result
    /// if the selection changed meanwhile).
    private func loadSelected() {
        guard let id = selection, let example = examples.first(where: { $0.id == id }) else {
            detail = .empty
            return
        }
        if let cached = cache[id] {
            detail = .loaded(id, cached)
            return
        }
        detail = .loading(example.name)
        let path = example.sketchPath
        DispatchQueue.global(qos: .userInitiated).async {
            let result = SketchLoader(sketchPath: path).load()
            DispatchQueue.main.async {
                guard selection == id else { return }   // user moved on while compiling
                switch result {
                case .success(let sketch):
                    cache[id] = sketch
                    detail = .loaded(id, sketch)
                case .failure(let error):
                    detail = .failed(String(describing: error))
                }
            }
        }
    }
}

/// `ContentUnavailableView` is macOS 14+, but its labeled init varies across SDKs;
/// this is a tiny, dependency-free placeholder for the empty state.
private struct ContentUnavailableViewCompat: View {
    let title: String
    let systemImage: String
    let description: String

    init(_ title: String, systemImage: String, description: String) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(description).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
