import SwiftUI
import Ollin
import OllinRuntime

/// The gallery window: the example list on the left, the running sketch in the
/// middle, and the inspector (monitor card + `@Param` knobs) docked on the
/// right. Both sidebars collapse, and the window hugs whatever remains: the
/// same fixed-size `HStack` + `.contentSize` recipe as the live host, under the
/// same tall gradient title bar. Loading happens off the main thread (each
/// compile is ~1s) and is cached, so re-selecting an example is instant.
struct GalleryView: View {
    /// Fixed example-list width. The stage is pinned to the sketch's square, so
    /// the window is exactly `examples + square + inspector` wide and can't be
    /// resized; collapsing a sidebar narrows it by that sidebar.
    static let examplesSidebarWidth: CGFloat = 240

    /// `@AppStorage` keys shared with the menu commands, so the menu, the
    /// title-bar buttons, and the persisted choice stay one state.
    static let examplesShownKey = "ollin.gallery.examplesShown"
    static let inspectorShownKey = "ollin.gallery.inspectorShown"

    let examples: [Example]

    @State private var selection: Example.ID?
    @State private var cache: [Example.ID: Sketch] = [:]
    @State private var detail: DetailState = .empty
    /// One `FrameStats` for the whole gallery: each loaded example's runner
    /// writes into it, and the inspector card reads it live.
    @State private var stats = FrameStats()
    @State private var filterText = ""

    @AppStorage(Self.examplesShownKey) private var examplesShown = true
    @AppStorage(Self.inspectorShownKey) private var inspectorShown = true
    /// Expanded sidebar nodes (categories and groups). Plain `@State` (seeded
    /// from and persisted to `UserDefaults` by hand) rather than `@AppStorage`:
    /// a defaults-backed value re-invalidates the whole window on every
    /// disclosure toggle, mid-animation. Empty = everything collapsed, the tidy
    /// first-launch view.
    @State private var expandedNodes = Self.loadExpandedNodes()
    /// The last selection, restored on launch (and its containers re-expanded).
    @AppStorage("ollin.gallery.selection") private var storedSelection = ""

    @SwiftUI.Environment(\.colorScheme) private var colorScheme

    private enum DetailState {
        case empty
        case loading(String)
        case loaded(Example, Sketch)
        case failed(String)
    }

    /// The stage's fixed size; every state (sketch, placeholder, error) fills
    /// exactly this, so the window never changes size as examples load.
    private var stageSize: CGSize { OllinApp.defaultWindowSize }

    private var selectedExample: Example? {
        selection.flatMap { id in examples.first { $0.id == id } }
    }

    /// A scrim laid over the sidebar vibrancy so the panels read over a bright
    /// background (the `.behindWindow` material alone washes out over white).
    private var sidebarScrim: SwiftUI.Color {
        colorScheme == .dark
            ? SwiftUI.Color(red: 0x23 / 255, green: 0x23 / 255, blue: 0x25 / 255).opacity(OllinInspector.chromeTintOpacity)
            : SwiftUI.Color(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF5 / 255).opacity(OllinInspector.chromeTintOpacity)
    }

    var body: some View {
        HStack(spacing: 0) {
            if examplesShown {
                ExamplesSidebar(
                    tree: ExampleCatalog.tree(of: examples),
                    selection: $selection,
                    filterText: $filterText,
                    expandedNodes: $expandedNodes)
                .frame(width: Self.examplesSidebarWidth, height: stageSize.height)
                .background {
                    ZStack {
                        SidebarVibrancy()
                        sidebarScrim
                    }
                }
                .overlay(alignment: .trailing) {
                    SwiftUI.Rectangle().fill(OllinInspector.separator(colorScheme)).frame(width: 0.5)
                }
            }
            stage
            if inspectorShown {
                InspectorSidebar(detail: inspectorContent, stats: stats)
                    .frame(width: OllinInspector.sidebarWidth, height: stageSize.height)
                    .background {
                        ZStack {
                            SidebarVibrancy()
                            sidebarScrim
                        }
                    }
                    .overlay(alignment: .leading) {
                        SwiftUI.Rectangle().fill(OllinInspector.separator(colorScheme)).frame(width: 0.5)
                    }
            }
        }
        // A hairline under the title bar, framing the content off the gradient
        // bar (the system separator doesn't read against the custom gradient).
        .overlay(alignment: .top) {
            SwiftUI.Rectangle().fill(OllinInspector.separator(colorScheme)).frame(height: 0.5)
        }
        .navigationTitle(selectedExample?.name ?? "Ollin Examples")
        .background(WindowCustomizer { window in
            window.titlebarSeparatorStyle = .none
        })
        .background(TitlebarAccessory(attribute: .leading) {
            HStack(spacing: 10) {
                SwiftUI.Rectangle().fill(OllinInspector.separator(colorScheme)).frame(width: 1, height: 22)
                Button { examplesShown.toggle() } label: {
                    SwiftUI.Image(systemName: "sidebar.left").font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(examplesShown ? "Hide Examples" : "Show Examples")
                .accessibilityLabel(examplesShown ? "Hide Examples" : "Show Examples")
            }
            .padding(.leading, 8)
            .frame(maxHeight: .infinity)
        })
        .background(TitlebarAccessory(attribute: .trailing) {
            Button { inspectorShown.toggle() } label: {
                SwiftUI.Image(systemName: "sidebar.right").font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(inspectorShown ? "Hide Inspector" : "Show Inspector")
            .accessibilityLabel(inspectorShown ? "Hide Inspector" : "Show Inspector")
            .padding(.leading, 12)
            .padding(.trailing, 22)
            .frame(maxHeight: .infinity)
        })
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(selectedExample?.name ?? "Ollin Examples")
                    .font(.system(size: 13.5, weight: .semibold))
            }
            .sharedBackgroundVisibility(.hidden)   // drop the glass capsule around the title
        }
        .toolbarBackground(OllinInspector.titleBarGradient(colorScheme), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .task(id: selection) { await loadSelected() }
        .onAppear(perform: restoreSelection)
        .onChange(of: expandedNodes) { _, nodes in
            UserDefaults.standard.set(nodes.sorted().joined(separator: "\n"),
                                      forKey: Self.expandedNodesKey)
        }
    }

    // MARK: Stage

    @ViewBuilder private var stage: some View {
        // Pin the stage to a fixed square so the sketch renders at its true size
        // (never stretched to fill the pane) and the window stays put.
        Group {
            switch detail {
            case .empty:
                ContentUnavailableView(
                    "Pick an example", systemImage: "sidebar.left",
                    description: Text("Select a sketch from the list to run it here."))
            case .loading(let name):
                ProgressView("Compiling \(name)…")
            case .loaded(let example, let sketch):
                // The gallery's inspector is the right sidebar, so the detached
                // panel stays off; the example list keeps the keyboard until the
                // viewer clicks the canvas, with the hint shown only for
                // sketches that actually read keys.
                SketchView(sketch, stats: stats,
                           showsInspectorPanel: false,
                           keyboardFocus: .onClick,
                           showsKeyboardHint: example.usesKeyboard)
                    .id(example.id)   // .id recreates (and tears down) on switch
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
        .frame(width: stageSize.width, height: stageSize.height)
    }

    /// What the inspector shows: the loaded example (card + knobs) or nothing.
    private var inspectorContent: InspectorSidebar.Content {
        if case .loaded(let example, let sketch) = detail {
            return .example(example, sketch)
        }
        return .idle
    }

    // MARK: Sidebar expansion

    static let expandedNodesKey = "ollin.gallery.expandedNodes"

    /// The persisted expanded-node set, newline-joined in defaults.
    private static func loadExpandedNodes() -> Set<String> {
        let stored = UserDefaults.standard.string(forKey: expandedNodesKey) ?? ""
        return Set(stored.split(separator: "\n").map(String.init))
    }

    /// Re-open the containers around `example` so its row is on screen (used
    /// when restoring the persisted selection).
    private func expand(around example: Example) {
        expandedNodes.insert(example.category)
        if let subgroup = example.subgroup {
            expandedNodes.insert("\(example.category)/\(subgroup)")
        }
    }

    private func restoreSelection() {
        guard selection == nil, !storedSelection.isEmpty,
              let restored = examples.first(where: { $0.id == storedSelection }) else { return }
        expand(around: restored)
        selection = restored.id
    }

    // MARK: Loading

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
        storedSelection = id
        // Name the example for the crash reporter as soon as it's the selection, so
        // a fault while it loads or runs is attributed to it.
        CrashReporter.setCurrentExample(example.displayName)
        if let cached = cache[id] {
            detail = .loaded(example, cached)
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
                detail = .loaded(example, sketch)
            case .failure(let error):
                detail = .failed(String(describing: error))
            }
        case .failure(let error):
            detail = .failed(String(describing: error))
        }
    }
}

// MARK: - Examples sidebar

/// The example list: categories and groups (3D topics, Recreations artists) as
/// collapsible header rows over their examples, with a filter bar pinned at the
/// bottom. While a filter is typed, the tree gives way to a flat match list with
/// each row naming where it lives.
///
/// Deliberately a *flat* `List` over rows computed from the tree + the expanded
/// set, not `Section(isExpanded:)`/`DisclosureGroup`: the outline machinery
/// duplicated rows and orphaned row heights when toggled while scrolled (an
/// AppKit row-cache glitch), and a flat identified list has nothing to mis-cache.
private struct ExamplesSidebar: View {
    let tree: [ExampleCatalog.Category]
    @Binding var selection: Example.ID?
    @Binding var filterText: String
    @Binding var expandedNodes: Set<String>

    /// One visible sidebar line. Headers and leaves share the enum so the whole
    /// sidebar is a single `ForEach` over stable string ids.
    private enum Row: Identifiable {
        case category(name: String, expanded: Bool)
        case group(id: String, name: String, expanded: Bool)
        case example(Example, indented: Bool)
        case noMatches

        var id: String {
            switch self {
            case .category(let name, _): "category:\(name)"
            case .group(let id, _, _): "group:\(id)"
            case .example(let example, _): example.id
            case .noMatches: "no-matches"
            }
        }

        /// Only leaves take part in the List selection; a leaf's row id *is*
        /// its example id, so the selected tag is the selected example.
        var isSelectable: Bool {
            if case .example = self { return true }
            return false
        }
    }

    private var isFiltering: Bool {
        !filterText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The visible rows: the disclosure tree flattened by the expanded set, or
    /// the flat match list while filtering.
    private var rows: [Row] {
        if isFiltering { return matchRows }
        var rows: [Row] = []
        for category in tree {
            let expanded = expandedNodes.contains(category.name)
            rows.append(.category(name: category.name, expanded: expanded))
            guard expanded else { continue }
            rows.append(contentsOf: category.direct.map { .example($0, indented: false) })
            for group in category.groups {
                let groupID = "\(category.name)/\(group.name)"
                let groupExpanded = expandedNodes.contains(groupID)
                rows.append(.group(id: groupID, name: group.name, expanded: groupExpanded))
                if groupExpanded {
                    rows.append(contentsOf: group.examples.map { .example($0, indented: true) })
                }
            }
        }
        return rows
    }

    private var matchRows: [Row] {
        let needle = filterText.trimmingCharacters(in: .whitespaces)
        let matches = tree.flatMap { category in
            (category.direct + category.groups.flatMap(\.examples)).filter { example in
                example.name.localizedCaseInsensitiveContains(needle)
                    || example.subgroup?.localizedCaseInsensitiveContains(needle) == true
                    || example.category.localizedCaseInsensitiveContains(needle)
            }
        }
        return matches.isEmpty ? [.noMatches] : matches.map { .example($0, indented: false) }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(rows) { row in
                    SidebarRowView(row: row, showsContext: isFiltering) { node in
                        withAnimation(.easeOut(duration: 0.15)) {
                            if expandedNodes.contains(node) {
                                expandedNodes.remove(node)
                            } else {
                                expandedNodes.insert(node)
                            }
                        }
                    }
                    // The tag rides the row's top-level content (a nested tag
                    // doesn't reach the List); headers and the empty-state row
                    // are skipped by selection (and by arrow-key navigation).
                    .tag(row.id)
                    .selectionDisabled(!row.isSelectable)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)   // the vibrancy panel shows through
            FilterBar(text: $filterText)
        }
    }

    /// A single sidebar line. Wrapped in one root container (and tagged only for
    /// leaves) so every row is unary with a stable id.
    private struct SidebarRowView: View {
        let row: Row
        /// Filter mode: leaves show where they live under their name.
        let showsContext: Bool
        let toggle: (String) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                switch row {
                case .category(let name, let expanded):
                    header(name, node: name, expanded: expanded)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                case .group(let id, let name, let expanded):
                    header(name, node: id, expanded: expanded)
                        .font(.system(size: 13))
                        .padding(.leading, 10)
                case .example(let example, let indented):
                    leaf(example, indented: indented)
                case .noMatches:
                    Text("No matches")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }

        /// A disclosure header: chevron + name, the whole row toggling its node.
        private func header(_ name: String, node: String, expanded: Bool) -> some View {
            Button { toggle(node) } label: {
                HStack(spacing: 5) {
                    SwiftUI.Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(name)
                    Spacer(minLength: 0)
                }
                .contentShape(SwiftUI.Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(name)")
        }

        @ViewBuilder private func leaf(_ example: Example, indented: Bool) -> some View {
            if showsContext {
                VStack(alignment: .leading, spacing: 1) {
                    Text(example.name)
                    Text(example.subgroup.map { "\(example.category) · \($0)" } ?? example.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(example.name)
                    .padding(.leading, indented ? 24 : 14)
            }
        }
    }
}

/// The filter field pinned under the example list.
private struct FilterBar: View {
    @Binding var text: String
    @SwiftUI.Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            SwiftUI.Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Filter", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    SwiftUI.Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(colorScheme == .dark ? SwiftUI.Color.white.opacity(0.07) : .black.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(OllinInspector.separator(colorScheme), lineWidth: 0.5))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            SwiftUI.Rectangle().fill(OllinInspector.separator(colorScheme)).frame(height: 0.5)
        }
    }
}

// MARK: - Inspector sidebar

/// The right sidebar: the shared monitor card (identity · timecode clock ·
/// performance strip) over the running example's `@Param` knobs, the same
/// views the live host's inspector uses, so the two never drift. Idle (nothing
/// running), it shows a quiet placeholder instead.
private struct InspectorSidebar: View {
    enum Content {
        case idle
        case example(Example, Sketch)
    }

    let detail: Content
    let stats: FrameStats

    var body: some View {
        switch detail {
        case .idle:
            VStack(spacing: 10) {
                SwiftUI.Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
                Text("Run an example to inspect it")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .example(let example, let sketch):
            ScrollView {
                GlassEffectContainer(spacing: 16) {
                    VStack(spacing: 16) {
                        MonitorCardView(
                            identity: MonitorIdentity(
                                name: example.name,
                                folder: example.subgroup.map { "\(example.category) · \($0)" }
                                    ?? example.category),
                            stats: stats)
                        VariationCardView(stats: stats)
                        ParametersListView(params: sketch.parameters())
                    }
                }
                .padding(14)
            }
        }
    }
}
