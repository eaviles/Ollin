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

    /// The gallery's mutable heart (selection, the stage, the compile cache) as
    /// one shared reference. See `GalleryModel` for why this must be a class
    /// and not a spread of view-struct `@State`.
    @State private var model: GalleryModel
    /// One `FrameStats` for the whole gallery: each loaded example's runner
    /// writes into it, and the inspector card reads it live.
    @State private var stats = FrameStats()
    @State private var filterText = ""

    init(examples: [Example]) {
        self.examples = examples
        _model = State(initialValue: GalleryModel(examples: examples))
    }

    @AppStorage(Self.examplesShownKey) private var examplesShown = true
    @AppStorage(Self.inspectorShownKey) private var inspectorShown = true
    /// Expanded sidebar nodes (categories and groups). Plain `@State` (seeded
    /// from and persisted to `UserDefaults` by hand) rather than `@AppStorage`:
    /// a defaults-backed value re-invalidates the whole window on every
    /// disclosure toggle, mid-animation. Empty = everything collapsed, the tidy
    /// first-launch view.
    @State private var expandedNodes = Self.loadExpandedNodes()

    @SwiftUI.Environment(\.colorScheme) private var colorScheme

    /// The stage's fixed size; every state (sketch, placeholder, error) fills
    /// exactly this, so the window never changes size as examples load.
    private var stageSize: CGSize { OllinApp.defaultWindowSize }

    private var selectedExample: Example? {
        model.running.flatMap { id in examples.first { $0.id == id } }
    }

    /// A scrim laid over the sidebar vibrancy so the panels read over a bright
    /// background (the `.behindWindow` material alone washes out over white).
    private var sidebarScrim: SwiftUI.Color {
        colorScheme == .dark
            ? SwiftUI.Color(red: 0x23 / 255, green: 0x23 / 255, blue: 0x25 / 255).opacity(OllinInspector.chromeTintOpacity)
            : SwiftUI.Color(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF5 / 255).opacity(OllinInspector.chromeTintOpacity)
    }

    var body: some View {
        @Bindable var model = model
        return HStack(spacing: 0) {
            if examplesShown {
                ExamplesSidebar(
                    tree: ExampleCatalog.tree(of: examples),
                    selection: $model.selection,
                    filterText: $filterText,
                    expandedNodes: $expandedNodes,
                    running: model.running,
                    restartRunning: { [model] in model.restartRunning() })
                .frame(width: Self.examplesSidebarWidth, height: stageSize.height)
                .background {
                    ZStack {
                        SidebarVibrancy()
                        sidebarScrim
                    }
                }
                .overlay(alignment: .trailing) {
                    SwiftUI.Rectangle().fill(OllinInspector.separator(for: colorScheme)).frame(width: 0.5)
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
                        SwiftUI.Rectangle().fill(OllinInspector.separator(for: colorScheme)).frame(width: 0.5)
                    }
            }
        }
        // A hairline under the title bar, framing the content off the gradient
        // bar (the system separator doesn't read against the custom gradient).
        .overlay(alignment: .top) {
            SwiftUI.Rectangle().fill(OllinInspector.separator(for: colorScheme)).frame(height: 0.5)
        }
        .navigationTitle(selectedExample?.name ?? "Ollin Examples")
        .background(WindowCustomizer { window in
            window.titlebarSeparatorStyle = .none
        })
        .background(TitleBarAccessory(attribute: .leading) {
            HStack(spacing: 10) {
                SwiftUI.Rectangle().fill(OllinInspector.separator(for: colorScheme)).frame(width: 1, height: 22)
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
        .background(TitleBarAccessory(attribute: .trailing) {
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
        .toolbarBackground(OllinInspector.titleBarGradient(for: colorScheme), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .task(id: model.runRequest) { await model.loadSelected() }
        .task { await model.runHarnessIfRequested() }
        // A selection landing on a leaf puts it on the stage; landing on a
        // folder changes nothing there, so browsing never blanks the canvas.
        .onChange(of: model.selection) { _, id in
            guard let id, let example = examples.first(where: { $0.id == id }) else { return }
            expand(around: example)   // a filter pick stays visible once the filter clears
            model.running = example.id
        }
        .onAppear {
            if let restored = model.restoreSelection() { expand(around: restored) }
        }
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
            switch model.detail {
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
        if case .loaded(let example, let sketch) = model.detail {
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
}

// MARK: - Gallery model

/// The gallery's mutable state and loading machinery, as one shared reference.
///
/// A class on purpose, not view-struct `@State`: escaping closures formed in
/// `body` (a sidebar row's action, the restart hook) capture the whole view
/// value, and `List` rows are lazily cached, so a stale closure can outlive
/// many selection changes off screen. A view value carrying the stage state
/// inline hands every one of those stale closures a strong reference to
/// whatever `Sketch` was loaded at capture time, keeping its audio playing
/// and its resources held long after the switch. Through a class reference
/// the closures share one object and pin nothing; `--cycletest` is the gate.
@MainActor @Observable
final class GalleryModel {
    let examples: [Example]

    /// The selected sidebar row: an example's id, or a folder row's id. Folder
    /// rows take part in selection so the arrow keys sweep the whole tree; the
    /// stage follows `running`, not this, so parking on a folder while browsing
    /// leaves the current example playing.
    var selection: String?
    /// The example on the stage. Set whenever the selection lands on a leaf.
    var running: Example.ID?
    /// Bumped to relaunch the running example as a fresh instance.
    private var runNonce = 0
    /// Compiled dylib path per example. The cache holds *artifacts*, never live
    /// `Sketch` instances: a cached instance would keep running out of sight
    /// (its audio engines, capture sessions, and players stay live), so sound
    /// from every visited example piles up, and so do their resources until the
    /// process falls over. A fresh instance per visit costs one `dlopen` +
    /// factory call (instant); the compile stays the only slow step.
    private var compiledDylibs: [Example.ID: String] = [:]
    private(set) var detail: DetailState = .empty

    enum DetailState {
        case empty
        case loading(String)
        case loaded(Example, Sketch)
        case failed(String)
    }

    /// The `.task(id:)` key: a fresh value reruns `loadSelected`, so the same
    /// example relaunches when only the nonce moves.
    struct RunRequest: Equatable {
        let id: Example.ID?
        let nonce: Int
    }

    var runRequest: RunRequest { RunRequest(id: running, nonce: runNonce) }

    init(examples: [Example]) {
        self.examples = examples
    }

    func restartRunning() {
        runNonce += 1
    }

    /// Re-select the example the last session left on the stage. Returns it so
    /// the view can re-open the folders around it.
    func restoreSelection() -> Example? {
        let stored = UserDefaults.standard.string(forKey: Self.storedSelectionKey) ?? ""
        guard selection == nil, !stored.isEmpty,
              let restored = examples.first(where: { $0.id == stored }) else { return nil }
        selection = restored.id
        running = restored.id
        return restored
    }

    static let storedSelectionKey = "ollin.gallery.selection"

    // MARK: Loading

    /// Load the running example: already compiled → instantiate fresh, instant;
    /// otherwise compile off the main actor (the slow `swiftc`) first. Driven by
    /// `.task(id: runRequest)`, which cancels this when the target changes, so
    /// a stale compile's result is dropped rather than racing the new one in.
    ///
    /// Every assignment to `detail` here drops the previous example's only strong
    /// reference: its view dismantles, the instance deallocates, and everything
    /// it was running (audio, capture, playback) stops with it. That release is
    /// the switch's off switch; never park an outgoing `Sketch` anywhere.
    func loadSelected() async {
        guard let id = running, let example = examples.first(where: { $0.id == id }) else {
            CrashReporter.setCurrentExample(nil)
            detail = .empty
            return
        }
        UserDefaults.standard.set(id, forKey: Self.storedSelectionKey)
        // Name the example for the crash reporter as soon as it's the selection, so
        // a fault while it loads or runs is attributed to it.
        CrashReporter.setCurrentExample(example.displayName)
        let path = example.sketchPath
        if let dylibPath = compiledDylibs[id] {
            instantiate(example, from: dylibPath)
            return
        }
        detail = .loading(example.name)
        let compiled = await Task.detached(priority: .userInitiated) {
            SketchLoader(sketchPath: path).compile()
        }.value
        guard !Task.isCancelled else { return }   // user moved on while compiling
        switch compiled {
        case .success(let dylibPath):
            compiledDylibs[id] = dylibPath
            instantiate(example, from: dylibPath)
        case .failure(let error):
            detail = .failed(String(describing: error))
        }
    }

    /// Build a fresh `Sketch` instance from an already compiled dylib and put it
    /// on the stage. `dlopen` + the factory are cheap, so this is the instant path.
    private func instantiate(_ example: Example, from dylibPath: String) {
        switch SketchLoader(sketchPath: example.sketchPath).instantiate(dylibPath: dylibPath) {
        case .success(let sketch):
            detail = .loaded(example, sketch)
        case .failure(let error):
            detail = .failed(String(describing: error))
        }
    }

    // MARK: Harness (--cycletest / --self-shot; see GalleryHarness)

    func runHarnessIfRequested() async {
        if let count = GalleryHarness.cycleCount {
            await runCycleTest(count: count)
        } else if let path = GalleryHarness.shotPath {
            try? await Task.sleep(for: .seconds(5))
            let ok = GalleryHarness.writeWindowShot(to: path)
            print("OllinExamples self-shot: \(ok ? "wrote" : "FAILED to write") \(path)")
            exit(ok ? 0 : 1)
        }
    }

    /// Visit `count` examples spread across the whole catalog through the real
    /// selection path, then require every instance but the last to have
    /// deallocated. See `GalleryHarness` for why this is the leak gate.
    private func runCycleTest(count: Int) async {
        let picks: [Example]
        if let filter = GalleryHarness.cycleFilter {
            picks = examples.filter { example in filter.contains { example.id.contains($0) } }
        } else {
            let step = max(1, examples.count / count)
            picks = stride(from: 0, to: examples.count, by: step).map { examples[$0] }
        }
        var visited: [GalleryHarness.WeakSketch] = []
        var failures: [String] = []
        let watchdog = GalleryHarness.Watchdog()
        watchdog.start()
        print("OllinExamples cycletest: visiting \(picks.count) of \(examples.count) examples…")
        for (index, example) in picks.enumerated() {
            watchdog.beat(example.displayName)
            selection = example.id
            running = example.id   // the view's onChange also does this; direct keeps it headless-safe
            if await waitForLoad(of: example.id) {
                if case .loaded(_, let sketch) = detail {
                    visited.append(GalleryHarness.WeakSketch(sketch, name: example.displayName))
                }
                // Let it render and start whatever it starts (audio, players).
                try? await Task.sleep(for: .milliseconds(700))
            } else {
                failures.append(example.displayName)
            }
            print("OllinExamples cycletest: [\(index + 1)/\(picks.count)] \(example.displayName)"
                  + (failures.last == example.displayName ? " FAILED TO LOAD" : ""))
        }
        // One more beat for the last teardown to settle, then the verdict.
        watchdog.finish()
        try? await Task.sleep(for: .seconds(1))
        let leaked = visited.dropLast().filter { $0.sketch != nil }.map(\.name)
        if !failures.isEmpty {
            print("OllinExamples cycletest: \(failures.count) failed to load: "
                  + failures.joined(separator: ", "))
        }
        if leaked.isEmpty {
            print("OllinExamples cycletest: PASS: \(visited.count) examples ran; every "
                  + "outgoing instance deallocated (its sound and resources stop with it)")
            if !GalleryHarness.cycleHold { exit(failures.isEmpty ? 0 : 1) }
        } else {
            print("OllinExamples cycletest: FAIL: \(leaked.count) instances stayed alive: "
                  + leaked.joined(separator: ", "))
            if !GalleryHarness.cycleHold { exit(1) }
        }
        print("OllinExamples cycletest: holding for inspection (pid \(ProcessInfo.processInfo.processIdentifier))")
    }

    /// Wait until the stage shows `id` loaded, or its load failed, or a timeout.
    private func waitForLoad(of id: Example.ID, timeout: Double = 60) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if case .loaded(let example, _) = detail, example.id == id { return true }
            if case .failed = detail { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
}

// MARK: - Examples sidebar

/// The example list: one outline in the navigator idiom. Folder rows (categories
/// and their groups) carry a chevron, an icon and a count; example rows sit
/// under them; a filter bar is pinned at the bottom. While a filter is typed,
/// the tree gives way to a flat match list with each row naming where it lives.
///
/// Every row is selectable, folders included, which is what lets the arrow keys
/// sweep the whole tree: up and down never stop at a folder, right opens one
/// (then steps inside), left closes one (or jumps to the parent), Return toggles
/// a folder and relaunches an example. Landing on an example runs it; landing on
/// a folder leaves the stage alone.
///
/// Deliberately a *flat* `List` over rows computed from the tree + the expanded
/// set, not `Section(isExpanded:)`/`DisclosureGroup`: the outline machinery
/// duplicated rows and orphaned row heights when toggled while scrolled (an
/// AppKit row-cache glitch), and a flat identified list has nothing to mis-cache.
private struct ExamplesSidebar: View {
    let tree: [ExampleCatalog.Category]
    @Binding var selection: String?
    @Binding var filterText: String
    @Binding var expandedNodes: Set<String>
    /// The example on the stage, marked in the list even when not selected.
    let running: Example.ID?
    /// Return on the running example: relaunch it as a fresh instance.
    let restartRunning: () -> Void

    @FocusState private var filterFocused: Bool

    /// One visible sidebar line, carrying everything navigation needs: what it
    /// shows, its parent row (the left-arrow target), and its depth.
    private struct Row: Identifiable {
        enum Kind {
            case folder(node: String, icon: String?, expanded: Bool, count: Int)
            case example(Example)
            case noMatches
        }

        let id: String
        let name: String
        let kind: Kind
        let parent: String?
        let depth: Int   // 0 category, 1 group or direct example, 2 grouped example

        var isFolder: Bool { if case .folder = kind { return true } else { return false } }
        var isExpanded: Bool {
            if case .folder(_, _, let expanded, _) = kind { return expanded } else { return false }
        }
        var isSelectable: Bool { if case .noMatches = kind { return false } else { return true } }
    }

    /// The curated icon per top-level category; unknown categories get a plain
    /// folder, so a new `Examples/` directory needs no code to appear.
    private static let categoryIcons: [String: String] = [
        "3D": "cube",
        "Audio": "waveform",
        "Basic": "circle",
        "Color": "paintpalette",
        "Compute": "cpu",
        "Data": "tablecells",
        "Effects": "sparkles",
        "Export": "square.and.arrow.up",
        "Images": "photo",
        "Input": "cursorarrow.click",
        "Installation": "display",
        "Integration": "link",
        "Live": "dot.radiowaves.left.and.right",
        "Motion": "wind",
        "Patterns": "square.grid.3x3",
        "Physics": "atom",
        "Randomness": "dice",
        "Recreations": "photo.artframe",
        "Rendering": "square.stack.3d.up",
        "Shaders": "fx",
        "Shapes": "square.on.circle",
        "Simulation": "circle.hexagongrid",
        "Text": "textformat",
        "Video": "film",
        "Vision": "eye",
    ]

    private var isFiltering: Bool {
        !filterText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The visible rows: the disclosure tree flattened by the expanded set, or
    /// the flat match list while filtering.
    private var rows: [Row] {
        if isFiltering { return matchRows }
        var rows: [Row] = []
        for category in tree {
            let categoryID = "category:\(category.name)"
            rows.append(Row(
                id: categoryID, name: category.name,
                kind: .folder(node: category.name,
                              icon: Self.categoryIcons[category.name] ?? "folder",
                              expanded: expandedNodes.contains(category.name),
                              count: category.count),
                parent: nil, depth: 0))
            guard expandedNodes.contains(category.name) else { continue }
            rows.append(contentsOf: category.direct.map {
                Row(id: $0.id, name: $0.name, kind: .example($0), parent: categoryID, depth: 1)
            })
            for group in category.groups {
                let node = "\(category.name)/\(group.name)"
                let groupID = "group:\(node)"
                let groupExpanded = expandedNodes.contains(node)
                rows.append(Row(
                    id: groupID, name: group.name,
                    kind: .folder(node: node, icon: nil, expanded: groupExpanded,
                                  count: group.examples.count),
                    parent: categoryID, depth: 1))
                if groupExpanded {
                    rows.append(contentsOf: group.examples.map {
                        Row(id: $0.id, name: $0.name, kind: .example($0), parent: groupID, depth: 2)
                    })
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
        if matches.isEmpty {
            return [Row(id: "no-matches", name: "", kind: .noMatches, parent: nil, depth: 0)]
        }
        return matches.map { Row(id: $0.id, name: $0.name, kind: .example($0), parent: nil, depth: 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroller in
                List(selection: $selection) {
                    ForEach(rows) { row in
                        SidebarRowView(
                            row: row,
                            isSelected: selection == row.id,
                            running: running,
                            showsContext: isFiltering,
                            toggle: { toggle(row, select: true) })
                        // The tag rides the row's top-level content (a nested tag
                        // doesn't reach the List); only the empty-state row is
                        // skipped by selection.
                        .tag(row.id)
                        .selectionDisabled(!row.isSelectable)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)   // the vibrancy panel shows through
                .environment(\.defaultMinListRowHeight, 25)
                // The identity purple marks selection, as in the sibling hosts.
                .tint(OllinInspector.accent)
                .onMoveCommand(perform: move)
                .onKeyPress(.return) { activateSelection() }
                // A selection set by keyboard fold-navigation (jump to parent,
                // step inside) can sit off screen; keep it visible. Deferred a
                // turn: scrolling inside the selection change re-enters the
                // list's own layout pass (AppKit warns, and will trap one day).
                .onChange(of: selection) { _, id in
                    guard let id else { return }
                    DispatchQueue.main.async { scroller.scrollTo(id) }
                }
            }
            FilterBar(text: $filterText, focused: $filterFocused, onSubmit: runFirstMatch)
        }
        .background {
            // The filter shortcut: an invisible button so the sidebar needs no
            // menu plumbing. Esc in the field clears it and hands the keys back.
            Button("") { filterFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .buttonStyle(.plain)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    // MARK: Keyboard

    /// Left and right drive the fold, the way every outline does it: right opens
    /// a folder and then steps into it; left closes one, or jumps to the parent.
    /// Up and down stay with the List, which now traverses every row.
    private func move(_ direction: MoveCommandDirection) {
        guard !isFiltering,
              let id = selection,
              let row = rows.first(where: { $0.id == id }) else { return }
        switch direction {
        case .left:
            if row.isFolder && row.isExpanded {
                toggle(row, select: false)
            } else if let parent = row.parent {
                selection = parent
            }
        case .right:
            guard row.isFolder else { return }
            if !row.isExpanded {
                toggle(row, select: false)
            } else if let child = rows.first(where: { $0.parent == row.id }) {
                selection = child.id
            }
        default:
            break
        }
    }

    /// Return: toggle a folder, relaunch the running example.
    private func activateSelection() -> KeyPress.Result {
        guard let id = selection, let row = rows.first(where: { $0.id == id }) else {
            return .ignored
        }
        switch row.kind {
        case .folder:
            toggle(row, select: false)
            return .handled
        case .example(let example):
            guard example.id == running else { return .ignored }
            restartRunning()
            return .handled
        case .noMatches:
            return .ignored
        }
    }

    /// Filter field Return: run the first match and hand focus to the list.
    private func runFirstMatch() {
        guard isFiltering,
              let first = rows.first(where: { if case .example = $0.kind { return true } else { return false } })
        else { return }
        selection = first.id
        filterFocused = false
    }

    private func toggle(_ row: Row, select: Bool) {
        guard case .folder(let node, _, _, _) = row.kind else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            if expandedNodes.contains(node) {
                expandedNodes.remove(node)
            } else {
                expandedNodes.insert(node)
            }
        }
        if select { selection = row.id }
    }

    // MARK: Rows

    /// A single sidebar line. Wrapped in one root container so every row is
    /// unary with a stable id.
    private struct SidebarRowView: View {
        let row: Row
        let isSelected: Bool
        let running: Example.ID?
        /// Filter mode: leaves show where they live under their name.
        let showsContext: Bool
        let toggle: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                switch row.kind {
                case .folder(_, let icon, let expanded, let count):
                    folder(icon: icon, expanded: expanded, count: count)
                case .example(let example):
                    leaf(example)
                case .noMatches:
                    Text("No matches")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }

        /// A folder row: chevron, icon (top level only), name, count. The whole
        /// row is the toggle, which also takes the selection with it.
        private func folder(icon: String?, expanded: Bool, count: Int) -> some View {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    SwiftUI.Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 12)
                    if let icon {
                        SwiftUI.Image(systemName: icon)
                            .font(.system(size: 12))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .frame(width: 18)
                    }
                    Text(row.name)
                        .font(.system(size: 13, weight: row.depth == 0 ? .medium : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(count)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? .secondary : .tertiary)
                }
                .padding(.leading, row.depth == 0 ? 0 : 20)
                .contentShape(SwiftUI.Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(row.name), \(count) examples")
        }

        @ViewBuilder private func leaf(_ example: Example) -> some View {
            let isRunning = example.id == running
            HStack(spacing: 6) {
                if showsContext {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(example.name)
                        Text(example.subgroup.map { "\(example.category) · \($0)" } ?? example.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(example.name)
                        .font(.system(size: 13, weight: isRunning ? .medium : .regular))
                        .lineLimit(1)
                        .foregroundStyle(isRunning && !isSelected
                            ? AnyShapeStyle(OllinInspector.accent)
                            : AnyShapeStyle(.primary))
                }
                if isRunning {
                    Spacer(minLength: 8)
                    PlayingGlyph(color: isSelected ? .white : OllinInspector.accent)
                }
            }
            .padding(.leading, showsContext ? 0 : (row.depth == 2 ? 44 : 26))
            .accessibilityLabel(isRunning ? "\(example.name), running" : example.name)
        }
    }

    /// The mark on the example that is playing: three level bars, the visual
    /// shorthand for "this one is making the sound you hear".
    private struct PlayingGlyph: View {
        let color: SwiftUI.Color

        var body: some View {
            HStack(alignment: .center, spacing: 2) {
                Capsule().frame(width: 2, height: 5)
                Capsule().frame(width: 2, height: 10)
                Capsule().frame(width: 2, height: 7)
            }
            .foregroundStyle(color)
            .accessibilityHidden(true)
        }
    }
}

/// The filter field pinned under the example list, advertising its shortcut.
private struct FilterBar: View {
    @Binding var text: String
    let focused: FocusState<Bool>.Binding
    /// Return in the field: run the first match.
    let onSubmit: () -> Void
    @SwiftUI.Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            SwiftUI.Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Filter", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused(focused)
                .onSubmit(onSubmit)
                .onExitCommand {
                    text = ""
                    focused.wrappedValue = false
                }
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
            } else if !focused.wrappedValue {
                Text("⌘F")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(colorScheme == .dark
                                ? SwiftUI.Color.white.opacity(0.08) : .black.opacity(0.06)))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(colorScheme == .dark ? SwiftUI.Color.white.opacity(0.07) : .black.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(OllinInspector.separator(for: colorScheme), lineWidth: 0.5))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            SwiftUI.Rectangle().fill(OllinInspector.separator(for: colorScheme)).frame(height: 0.5)
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
                        ParametersListView(parameters: sketch.parameters(), sketchName: example.name)
                    }
                }
                .padding(14)
            }
        }
    }
}
