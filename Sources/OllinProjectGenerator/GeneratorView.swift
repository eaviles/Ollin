import SwiftUI
import AppKit
import Ollin
import OllinProjects
import OllinRuntime

/// The generator window: what to start from on the left, that thing running in
/// the middle, and the project it will become on the right.
///
/// The window does two jobs that compete for the same space. Choosing a
/// starting point wants breadth (ten templates and some 350 examples, watched
/// running); describing the project wants a short form (for most people a name
/// and a folder). So the middle column takes the slack, the inspector holds only
/// what is always needed, and the two things that are neither (the 3D chain and
/// the rest of the wiring) move to where they belong: the chain under the stage
/// it governs, the wiring behind one row that still reports its state.
struct GeneratorView: View {
    static let sidebarWidth: Double = 260
    static let inspectorWidth: Double = 320

    /// The folder chosen last time. Sketches pile up in one place, so being
    /// asked where to put them on every launch is the wrong default.
    @AppStorage("generator.destination") private var destinationPath = ""
    @AppStorage("generator.sidebarShown") private var sidebarShown = true
    @AppStorage("generator.inspectorShown") private var inspectorShown = true

    @SwiftUI.Environment(\.colorScheme) private var colorScheme

    @State private var kind: ProjectKind = .macSketch
    @State private var template: ProjectTemplate = .blank
    @State private var example: ExampleSource.Example?
    @State private var examples: [ExampleSource.Example] = []
    @State private var filterText = ""
    @State private var expanded: Set<String> = ["templates"]

    /// Empty until typed into: the dated serial is a *suggestion*, shown in the
    /// field's placeholder, so it is never a value someone has to clear.
    @State private var typedName = ""
    @State private var suggestedName = ""

    @State private var chosen: Set<String> = []
    @State private var canvas: CanvasChoice = .default
    @State private var threeD = ThreeDRecipe.realistic
    @State private var hovered: ThreeDOption?
    @State private var wiringExpanded = false
    /// The package the chosen folder already sits in, if any. Found when the
    /// folder changes rather than on every keystroke.
    @State private var host: PackageHost?

    @State private var preview: PreviewState = .idle
    @State private var previewCache: [String: Sketch] = [:]
    @State private var lastBuild: BuildOutcome = .none
    @State private var outcome: Outcome?
    @State private var stats = FrameStats()

    enum PreviewState {
        case idle
        case compiling(String)
        case running(Sketch)
        case failed(String)
    }

    /// How the showing preview arrived, which is the honest thing to report
    /// beside the frame rate.
    enum BuildOutcome: Equatable {
        case none
        case built(seconds: Double)
        case cached
    }

    enum Outcome {
        case made(GeneratedProject)
        case refused(String)
    }

    // MARK: - Window

    var body: some View {
        HStack(spacing: 0) {
            if sidebarShown {
                sourceList
                    .frame(width: Self.sidebarWidth)
                    .background(sidebarBackground)
                    .overlay(alignment: .trailing) { hairline }
            }
            stageColumn
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            if inspectorShown {
                inspector
                    .frame(width: Self.inspectorWidth)
                    .background(sidebarBackground)
                    .overlay(alignment: .leading) { hairline }
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        // A hairline under the title bar: the system separator does not read
        // against the custom gradient.
        .overlay(alignment: .top) {
            SwiftUI.Rectangle().fill(OllinInspector.separator(colorScheme)).frame(height: 0.5)
        }
        .navigationTitle("New project")
        .background(WindowCustomizer { window in
            window.titlebarSeparatorStyle = .none
        })
        .background(TitlebarAccessory(attribute: .leading) { leadingChrome })
        .background(TitlebarAccessory(attribute: .trailing) { trailingChrome })
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("New project").font(.system(size: 13.5, weight: .semibold))
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .toolbarBackground(OllinInspector.titleBarGradient(colorScheme), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .task(id: previewKey) { await showPreview() }
        .task { await load() }
    }

    private var hairline: some View {
        SwiftUI.Rectangle().fill(OllinInspector.separator(colorScheme)).frame(width: 0.5)
    }

    private var sidebarBackground: some View {
        ZStack {
            SidebarVibrancy()
            (colorScheme == .dark
                ? SwiftUI.Color(red: 0x23 / 255, green: 0x23 / 255, blue: 0x25 / 255)
                : SwiftUI.Color(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF5 / 255))
                .opacity(OllinInspector.chromeTintOpacity)
        }
    }

    // MARK: - Title bar

    /// The kind menu scopes the whole window rather than the sidebar, so it
    /// lives up here. The kinds that are not ready sit under a divider with
    /// what each waits on: a roadmap in a menu reads as a roadmap, where a
    /// roadmap in the main flow reads as a control that does not work.
    private var leadingChrome: some View {
        HStack(spacing: 10) {
            SwiftUI.Rectangle().fill(OllinInspector.separator(colorScheme)).frame(width: 1, height: 22)

            Button { sidebarShown.toggle() } label: {
                SwiftUI.Image(systemName: "sidebar.left").font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(sidebarShown ? "Hide starting points" : "Show starting points")

            Menu {
                ForEach(offeredKinds) { option in
                    Button { kind = option } label: {
                        Text(option.title)
                        Text(option.summary)
                    }
                }
                Divider()
                Section("Not ready yet") {
                    ForEach(ProjectKind.all.filter { !$0.isAvailable }) { option in
                        Button {} label: {
                            Label(option.title, systemImage: "clock")
                            Text(option.waitingOn ?? "")
                        }
                        .disabled(true)
                    }
                }
            } label: {
                Text(kind.title).font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.leading, 8)
        .frame(maxHeight: .infinity)
    }

    /// Joining a package is offered only where there is one to join, since it
    /// is the only kind whose availability depends on where you are pointing.
    ///
    /// An extension package is left out for a different reason: this window
    /// previews a starting point by *running* it, and a library has nothing to
    /// run. Offering it here would show a template list and a run button for
    /// something that is neither, so it stays on the command line
    /// (`ollin new <name> --kind extension`) until the stage can show source
    /// rather than a frame.
    private var offeredKinds: [ProjectKind] {
        ProjectKind.available.filter {
            $0.id != ProjectKind.extensionPackage.id
                && ($0.id != ProjectKind.inPackage.id || host?.linksOllin == true)
        }
    }

    private var trailingChrome: some View {
        HStack(spacing: 12) {
            statusChip
            Button { inspectorShown.toggle() } label: {
                SwiftUI.Image(systemName: "sidebar.right").font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(inspectorShown ? "Hide inspector" : "Show inspector")
        }
        .padding(.leading, 12)
        .padding(.trailing, 22)
        .frame(maxHeight: .infinity)
    }

    private var statusChip: some View {
        let (text, color): (String, SwiftUI.Color) = switch preview {
        case .running: ("Running", OllinInspector.green)
        case .compiling: ("Building", OllinInspector.amber)
        case .failed: ("Compile error", OllinInspector.red)
        case .idle: ("Idle", OllinInspector.amber)
        }
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 11.5)).foregroundStyle(color)
        }
    }

    // MARK: - Left: one sectioned source list

    /// Ten curated starting points and 350 cataloged ones are not two modes:
    /// they are a short list and a long one, and the question is the same in
    /// both cases. So one list, with the examples grouped the way the folders
    /// already group them, and one filter over both.
    private var sourceList: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroller in
                List(selection: Binding(
                    get: { selectionID },
                    set: { select($0) }
                )) {
                    ForEach(rows) { row in
                        row.view(colorScheme: colorScheme)
                            .tag(row.id)
                            .id(row.id)
                            .listRowSeparator(.hidden)
                            .onTapGesture { tap(row) }
                    }
                }
                // A selection set from anywhere but a click (restored, or passed
                // on the command line) is off-screen in a list this long unless
                // it is scrolled to.
                .onChange(of: selectionID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.2)) { scroller.scrollTo(id, anchor: .center) }
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 22)
            // Purple is the identity color the other windows already use for
            // their own drawing, so it marks selection here. It is applied where
            // it means something rather than to the whole view, which would tint
            // every neutral native control along with it.
            .tint(OllinInspector.accent)

            filterBar
        }
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            SwiftUI.Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Filter", text: $filterText)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
            if filterText.isEmpty {
                Text("10 templates, ~\(examples.count) examples")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                Button { filterText = "" } label: {
                    SwiftUI.Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .top) {
            SwiftUI.Rectangle().fill(OllinInspector.separator(colorScheme)).frame(height: 0.5)
        }
    }

    /// One row of the source list. A flat array computed from the catalogs plus
    /// what is expanded, which is how the gallery's tree sidebar works too.
    enum Row: Identifiable {
        case header(id: String, title: String, detail: String, expanded: Bool, depth: Int)
        case template(ProjectTemplate)
        case example(ExampleSource.Example)
        case empty(String)

        var id: String {
            switch self {
            case .header(let id, _, _, _, _): "header:" + id
            case .template(let t): "template:" + t.id
            case .example(let e): "example:" + e.path
            case .empty(let text): "empty:" + text
            }
        }

        @ViewBuilder
        func view(colorScheme: ColorScheme) -> some View {
            switch self {
            case .header(_, let title, let detail, let expanded, let depth):
                HStack(spacing: 5) {
                    SwiftUI.Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    Text(title)
                        .font(.system(size: depth == 0 ? 12 : 11.5,
                                      weight: depth == 0 ? .semibold : .medium))
                    Spacer(minLength: 4)
                    if !detail.isEmpty {
                        Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, Double(depth) * 12)
                .contentShape(SwiftUI.Rectangle())
            case .template(let template):
                VStack(alignment: .leading, spacing: 1) {
                    Text(template.title).font(.system(size: 12, weight: .medium))
                    Text(template.summary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.leading, 15)
            case .example(let example):
                Text(example.name)
                    .font(.system(size: 11.5))
                    .padding(.leading, 27)
            case .empty(let text):
                Text(text)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 15)
            }
        }
    }

    /// The catalog's own two levels: a top-level category (`3D`, `Patterns`),
    /// and under the deeper ones a group (`3D/Depth`). Flattening these threw
    /// away the only structure the catalog has.
    struct Category: Identifiable {
        let name: String
        /// Examples filed directly under the category.
        let direct: [ExampleSource.Example]
        /// One level deeper, in catalog order.
        let groups: [(name: String, examples: [ExampleSource.Example])]
        var id: String { name }
        var count: Int { direct.count + groups.reduce(0) { $0 + $1.examples.count } }
    }

    private var exampleCategories: [Category] {
        var order: [String] = []
        var byCategory: [String: [ExampleSource.Example]] = [:]
        for example in matchingExamples {
            let category = String(example.group.split(separator: "/").first ?? "")
            if byCategory[category] == nil { order.append(category) }
            byCategory[category, default: []].append(example)
        }
        return order.map { name in
            let all = byCategory[name] ?? []
            let direct = all.filter { $0.group == name }
            var groupOrder: [String] = []
            var byGroup: [String: [ExampleSource.Example]] = [:]
            for example in all where example.group != name {
                if byGroup[example.group] == nil { groupOrder.append(example.group) }
                byGroup[example.group, default: []].append(example)
            }
            return Category(name: name, direct: direct,
                            groups: groupOrder.map { ($0, byGroup[$0] ?? []) })
        }
    }

    /// Filtering matches names *and* group names together, so typing "depth"
    /// finds the group as well as the sketches inside it.
    private var matchingExamples: [ExampleSource.Example] {
        guard !filterText.isEmpty else { return examples }
        return examples.filter { $0.path.localizedCaseInsensitiveContains(filterText) }
    }

    private var matchingTemplates: [ProjectTemplate] {
        let fitting = ProjectTemplate.fitting(kind)
        guard !filterText.isEmpty else { return fitting }
        return fitting.filter {
            $0.title.localizedCaseInsensitiveContains(filterText)
                || $0.summary.localizedCaseInsensitiveContains(filterText)
        }
    }

    private var filtering: Bool { !filterText.isEmpty }

    private var rows: [Row] {
        var out: [Row] = []
        let templates = matchingTemplates
        // While filtering, a group with no matches is reported rather than
        // hidden, so the list never looks like it lost something.
        let templatesOpen = filtering ? !templates.isEmpty : expanded.contains("templates")

        out.append(.header(id: "templates", title: "Templates",
                           detail: filtering && templates.isEmpty ? "no matches" : "\(templates.count)",
                           expanded: templatesOpen, depth: 0))
        if templatesOpen { out += templates.map(Row.template) }

        let categories = exampleCategories
        let examplesOpen = filtering ? !categories.isEmpty : expanded.contains("examples")
        out.append(.header(id: "examples",
                           title: filtering ? "Examples matching \u{201C}\(filterText)\u{201D}" : "Examples",
                           detail: categories.isEmpty ? "no matches" : "\(categories.count) groups",
                           expanded: examplesOpen, depth: 0))
        if examplesOpen {
            for category in categories {
                let open = filtering || expanded.contains("category:" + category.name)
                out.append(.header(id: "category:" + category.name, title: category.name,
                                   detail: "\(category.count)", expanded: open, depth: 1))
                guard open else { continue }
                out += category.direct.map(Row.example)
                for group in category.groups {
                    let groupOpen = filtering || expanded.contains("group:" + group.name)
                    out.append(.header(id: "group:" + group.name,
                                       title: group.name.replacingOccurrences(of: "/", with: " / "),
                                       detail: "\(group.examples.count)",
                                       expanded: groupOpen, depth: 2))
                    if groupOpen { out += group.examples.map(Row.example) }
                }
            }
        }
        return out
    }

    private var selectionID: String? {
        example.map { "example:" + $0.path } ?? "template:" + template.id
    }

    private func select(_ id: String?) {
        guard let id else { return }
        if let path = id.dropPrefix("example:"), let found = examples.first(where: { $0.path == path }) {
            example = found
        } else if let templateID = id.dropPrefix("template:"), let found = ProjectTemplate.named(templateID) {
            template = found
            example = nil
        }
        outcome = nil
    }

    private func tap(_ row: Row) {
        if case .header(let id, _, _, _, _) = row {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        } else {
            select(row.id)
        }
    }

    // MARK: - Middle: the thing running, and what governs it

    private var stageColumn: some View {
        VStack(spacing: 0) {
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            statusLine
            if template.id == ProjectTemplate.threeD.id && example == nil {
                SwiftUI.Rectangle().fill(OllinInspector.separator(colorScheme)).frame(height: 0.5)
                ThreeDStrip(recipe: $threeD, hovered: $hovered)
                    .tint(OllinInspector.accent)
                    .onChange(of: threeD) { _, _ in outcome = nil }
            }
        }
    }

    private var stage: some View {
        ZStack {
            SwiftUI.Color.black
            switch preview {
            case .idle:
                ProgressView().controlSize(.small)
            case .compiling(let title):
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Building \(title)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            case .running(let sketch):
                SketchView(sketch, stats: stats, showsInspectorPanel: false)
                    .aspectRatio(sketchAspect(sketch), contentMode: .fit)
            case .failed(let message):
                // A starting point that stopped compiling is a real defect, so
                // it is shown rather than swallowed.
                ScrollView {
                    Text(message)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(OllinInspector.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
        }
    }

    private func sketchAspect(_ sketch: Sketch) -> Double {
        let size = sketch.canvasSize
        return size.height > 0 ? Double(size.width) / Double(size.height) : 1
    }

    /// What is on the stage and how it got there, in one quiet line.
    private var statusLine: some View {
        let name = example?.name ?? template.title
        var parts: [String] = [name]
        switch preview {
        case .running:
            parts.append("running")
            if stats.fps > 0 { parts.append("\(Int(stats.fps.rounded())) fps") }
            if stats.canvasWidth > 0 {
                parts.append("\(Int(stats.canvasWidth)) \u{00D7} \(Int(stats.canvasHeight))")
            }
            switch lastBuild {
            case .built(let seconds): parts.append(String(format: "built in %.1fs", seconds))
            case .cached: parts.append("from cache")
            case .none: break
            }
        case .compiling: parts.append("building")
        case .failed: parts.append("compile error")
        case .idle: parts.append("waiting")
        }
        return HStack {
            Text(parts.joined(separator: " \u{00B7} "))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Spacer()
            if let example {
                Text(example.path).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }

    // MARK: - Right: the project it will become

    private var inspector: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("Name") {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("", text: $typedName, prompt: Text(suggestedName))
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: typedName) { _, _ in outcome = nil }
                            Text("Next serial in \(destination.lastPathComponent). Type to name it.")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    field("Where") {
                        HStack(spacing: 6) {
                            Text(destination.lastPathComponent)
                                .font(.system(size: 11.5))
                                .lineLimit(1)
                                .truncationMode(.head)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Choose") { chooseDestination() }
                                .controlSize(.small)
                        }
                    }

                    field("Canvas") {
                        Picker("", selection: $canvas) {
                            ForEach(CanvasChoice.all) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .labelsHidden()
                    }

                    wiring
                    Divider()
                    fileList
                }
                .padding(16)
            }
            createBar
        }
    }

    /// One row that still reports its state, because for most starting points
    /// every box under it is optional: a template brings the libraries its own
    /// code needs, and an example brings what it imports.
    private var wiring: some View {
        DisclosureGroup(isExpanded: $wiringExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                capabilityGroup("Material", Capability.all.filter { $0.module == nil })
                capabilityGroup("Libraries", Capability.satellites)
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 6) {
                Text("Wire in")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.6)
                Spacer(minLength: 4)
                Text(wiringSummary).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    private var wiringSummary: String {
        let brought = broughtCapabilities.count
        let asked = chosen.subtracting(broughtCapabilities.map(\.id)).count
        if brought == 0 && asked == 0 { return "nothing yet" }
        var parts: [String] = []
        if brought > 0 {
            parts.append("\(brought) from \(example == nil ? "template" : "example")")
        }
        if asked > 0 { parts.append("\(asked) added") }
        return parts.joined(separator: ", ")
    }

    /// What the starting point brings on its own, which is ticked and locked
    /// rather than removed: nothing here is taken away, it is only quieter.
    private var broughtCapabilities: [Capability] {
        if let example {
            return Capability.satellites.filter { example.modules.contains($0.module ?? "") }
        }
        return Capability.all.filter { template.requires.contains($0.id) }
    }

    private func capabilityGroup(_ title: String, _ capabilities: [Capability]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            ForEach(capabilities) { capability in
                let brought = broughtCapabilities.contains(capability)
                Toggle(isOn: Binding(
                    get: { chosen.contains(capability.id) || brought },
                    set: { on in
                        if on { chosen.insert(capability.id) } else { chosen.remove(capability.id) }
                        outcome = nil
                    }
                )) {
                    HStack(spacing: 5) {
                        Text(capability.title).font(.system(size: 11))
                        if brought {
                            Text(example == nil ? "the template needs it" : "the example imports it")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(brought)
                .help(capability.summary)
            }
        }
    }

    /// The thing worth seeing, so it sits above the fold with the guarantee
    /// printed under it rather than left in the docs.
    @ViewBuilder private var fileList: some View {
        switch outcome {
        case .made(let project):
            VStack(alignment: .leading, spacing: 8) {
                Label("Made \(project.root.lastPathComponent)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(OllinInspector.green)
                ForEach(project.nextSteps, id: \.self) { step in
                    Text(step)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([project.root])
                    }
                    .controlSize(.small)
                    Button("Copy command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(project.runCommand, forType: .string)
                    }
                    .controlSize(.small)
                }
            }
        case .refused(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(OllinInspector.amber)
                .fixedSize(horizontal: false, vertical: true)
        case nil:
            if let plan = try? ProjectGenerator.plan(request()) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Will write \(plan.files.count) file\(plan.files.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(0.6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(plan.root.lastPathComponent + "/")
                            .font(.system(size: 10, design: .monospaced))
                        ForEach(plan.files, id: \.path) { file in
                            Text("  " + file.path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(plan.edits, id: \.file) { edit in
                        HStack(alignment: .top, spacing: 6) {
                            SwiftUI.Image(systemName: "pencil")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                            Text(edit.summary)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(alignment: .top, spacing: 6) {
                        Circle().fill(OllinInspector.green).frame(width: 6, height: 6).padding(.top, 4)
                        Text(guarantee)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var guarantee: String {
        if kind.id == ProjectKind.inPackage.id {
            return "The sketch folder is new. The only file changed is the manifest, and only to list it."
        }
        return example == nil
            ? "Nothing is written until you press Create, and Create refuses rather than overwriting."
            : "Copied from the example and declared, so it runs before you change a line. The header comment travels with it."
    }

    private var createBar: some View {
        VStack(spacing: 8) {
            Button(action: create) {
                Text("Create").frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(OllinInspector.accent)
            .disabled(!kind.isAvailable)

            if let waiting = kind.waitingOn {
                Text("Nothing to create yet: \(waiting)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.bar)
        .overlay(alignment: .top) {
            SwiftUI.Rectangle().fill(OllinInspector.separator(colorScheme)).frame(height: 0.5)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)
            content()
        }
    }

    // MARK: - Doing the thing

    private var effectiveName: String { typedName.isEmpty ? suggestedName : typedName }

    private func request() -> ProjectRequest {
        ProjectRequest(
            name: effectiveName,
            kind: kind,
            template: template,
            example: example,
            capabilities: Capability.all.filter { chosen.contains($0.id) },
            canvas: canvas,
            threeD: threeD,
            packageHost: host,
            destination: destination,
            framework: .localPath(Self.frameworkRoot())
        )
    }

    private func create() {
        do {
            let project = try ProjectGenerator.plan(request())
            try ProjectGenerator.write(project)
            outcome = .made(project)
            typedName = ""
            suggestName()          // the serial just used is taken
        } catch let error as ProjectGeneratorError {
            outcome = .refused(error.description)
        } catch {
            outcome = .refused("\(error)")
        }
    }

    private var destination: URL {
        destinationPath.isEmpty ? Self.defaultDestination : URL(fileURLWithPath: destinationPath)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = destination
        if panel.runModal() == .OK, let url = panel.url {
            destinationPath = url.path
            outcome = nil
            suggestName()
            findHost()
        }
    }

    /// A folder inside a package almost always wants a target in it rather than
    /// a package of its own, so that becomes the offer the moment one is found,
    /// and stops being the kind the moment it is not.
    private func findHost() {
        host = PackageHost.nearest(from: destination)
        if kind.id == ProjectKind.inPackage.id, host?.linksOllin != true {
            kind = .macSketch
        } else if kind.id == ProjectKind.macSketch.id, host?.linksOllin == true {
            kind = .inPackage
        }
    }

    private func suggestName() {
        suggestedName = ProjectNaming.nextSerial(
            in: destination,
            year: Calendar.current.component(.year, from: Date())
        )
    }

    // MARK: - The preview

    /// What the stage is showing. A 3D change is a different sketch, so the
    /// recipe rides the key or the cache would hand back the last combination.
    private var previewKey: String {
        if let example { return example.path }
        guard template.id == ProjectTemplate.threeD.id else { return template.id }
        return template.id + "-" + threeD.chosen.sorted().joined(separator: "-")
    }

    private func load() async {
        examples = ExampleSource.discover(in: Self.frameworkRoot().appendingPathComponent("Examples"))
        if let wanted = Self.launchArgument("--template"), let found = ProjectTemplate.named(wanted) {
            template = found
        }
        if let wanted = Self.launchArgument("--kind"), let found = ProjectKind.named(wanted) {
            kind = found
        }
        if let wanted = Self.launchArgument("--from"),
           let found = examples.first(where: { $0.path.lowercased() == wanted.lowercased() }) {
            example = found
            expanded.insert("examples")
            expanded.insert("category:" + String(found.group.split(separator: "/").first ?? ""))
            expanded.insert("group:" + found.group)
        }
        if let wanted = Self.launchArgument("--3d") {
            var recipe = ThreeDRecipe(geometry: .mesh, finish: .unlit, extras: [])
            for id in wanted.split(whereSeparator: { $0 == "," || $0 == " " }) {
                guard let option = ThreeDOption.named(String(id)) else { continue }
                switch option.slot {
                case .geometry: recipe.geometry = option
                case .finish: recipe.finish = option
                case .extra: recipe.extras.insert(option.id)
                }
            }
            recipe.settle()
            threeD = recipe
        }
        suggestName()
        findHost()
    }

    /// Compile the very source the generator would write, then run it. What you
    /// watch is what you get, and a starting point that stopped compiling shows
    /// up here rather than in someone's new project.
    private func showPreview() async {
        outcome = nil
        let key = previewKey
        if let cached = previewCache[key] {
            preview = .running(cached)
            lastBuild = .cached
            return
        }
        preview = .compiling(example?.name ?? template.title)

        let previewRequest = ProjectRequest(
            name: "Preview\(key.filter(\.isLetter).capitalized)",
            kind: .singleFile,
            template: template,
            example: example,
            threeD: threeD,
            destination: URL(fileURLWithPath: NSTemporaryDirectory()),
            framework: .localPath(Self.frameworkRoot())
        )
        let source = ProjectGenerator.sketchSource(previewRequest)
        // An example loads its material relative to its own folder, so the
        // preview compiles as if it still lived there.
        let path = (example?.directory ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("ollin-preview-\(key.replacingOccurrences(of: "/", with: "-")).swift").path

        let started = Date()
        let compiled = await Task.detached(priority: .userInitiated) {
            SketchLoader(sketchPath: path).compile(.source(source))
        }.value
        guard !Task.isCancelled else { return }

        switch compiled {
        case .success(let dylib):
            switch SketchLoader(sketchPath: path).instantiate(dylibPath: dylib) {
            case .success(let sketch):
                previewCache[key] = sketch
                preview = .running(sketch)
                lastBuild = .built(seconds: Date().timeIntervalSince(started))
            case .failure(let error):
                preview = .failed(String(describing: error))
            }
        case .failure(let error):
            preview = .failed(String(describing: error))
        }
    }

    // MARK: - Where things are

    static var defaultDestination: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    /// A value passed on the command line, for opening the window already set
    /// to something.
    static func launchArgument(_ name: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// The folder this binary was built in, so a generated manifest points at
    /// the framework already on this machine.
    static func frameworkRoot() -> URL {
        var directory = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        for _ in 0 ..< 8 {
            let manifest = directory.appendingPathComponent("Package.swift")
            if let text = try? String(contentsOf: manifest, encoding: .utf8),
               text.contains("name: \"Ollin\"") {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { break }
            directory = parent
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

private extension String {
    /// The remainder after `prefix`, or nil when it does not start with it.
    func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
