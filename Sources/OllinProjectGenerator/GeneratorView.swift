import SwiftUI
import AppKit
import Ollin
import OllinProjects
import OllinRuntime

/// The generator window: what to make on the left, the starting point running in
/// the middle, and everything about the new project on the right.
///
/// The preview is the thing worth the trouble. A template is a whole small
/// sketch, so the honest way to show one is to run it: the source the generator
/// would write is compiled and instantiated exactly as the gallery compiles an
/// example, which means what you watch is what you get, and a template that
/// stopped compiling shows up here rather than in someone's new project.
struct GeneratorView: View {
    // The shipped sidebar widths: the same 240 the gallery's list uses and the
    // 296 the inspector uses, so all three windows line up.
    static let templatesWidth: Double = 240
    static let optionsWidth: Double = 296
    static let stageSide: Double = 560

    /// The folder chosen last time. Sketches pile up in one place, so being
    /// asked where to put them on every launch is the wrong default.
    @AppStorage("generator.destination") private var destinationPath = ""

    @State private var kind: ProjectKind = .macSketch
    @State private var source: StartingPoint = .templates
    @State private var template: ProjectTemplate = .blank
    @State private var example: ExampleSource.Example?
    @State private var examples: [ExampleSource.Example] = []
    @State private var exampleFilter = ""
    @State private var name = ""
    @State private var chosen: Set<String> = []
    @State private var canvas: CanvasChoice = .default
    @State private var threeD = ThreeDRecipe.realistic
    @State private var hoveredRule: String?

    enum StartingPoint: String, CaseIterable, Identifiable {
        case templates, examples
        var id: String { rawValue }
        var title: String { self == .templates ? "Templates" : "Examples" }
    }

    /// The example actually in play: whichever tab is showing decides, so a
    /// selection survives a look at the other one.
    private var chosenExample: ExampleSource.Example? {
        source == .examples ? example : nil
    }

    private var destination: URL {
        destinationPath.isEmpty ? Self.defaultDestination : URL(fileURLWithPath: destinationPath)
    }

    @State private var preview: PreviewState = .idle
    @State private var previewCache: [String: Sketch] = [:]
    @State private var previewTask: Task<Void, Never>?
    @State private var outcome: Outcome?
    @State private var stats = FrameStats()

    enum PreviewState {
        case idle
        case compiling(String)
        case running(Sketch)
        case failed(String)
    }

    enum Outcome {
        case made(GeneratedProject)
        case refused(String)
    }

    var body: some View {
        HStack(spacing: 0) {
            starting
            Divider()
            stage
            Divider()
            options
        }
        .frame(height: Self.stageSide)
        .task(id: previewKey) { await showPreview() }
        .task {
            examples = ExampleSource.discover(in: Self.frameworkRoot().appendingPathComponent("Examples"))
            // `ollin generate --template 3d` opens on that starting point, so a
            // window can be opened straight onto the thing being worked on.
            if let wanted = Self.launchArgument("--template"), let found = ProjectTemplate.named(wanted) {
                template = found
            }
            if let wanted = Self.launchArgument("--kind"), let found = ProjectKind.named(wanted) {
                kind = found
            }
            if let wanted = Self.launchArgument("--from"),
               let found = examples.first(where: { $0.path.lowercased() == wanted.lowercased() }) {
                source = .examples
                example = found
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
        }
    }

    /// What the preview is showing, so switching source or selection rebuilds it.
    private var previewKey: String {
        if source == .examples { return example?.path ?? "no-example" }
        guard template.id == ProjectTemplate.threeD.id else { return template.id }
        // A 3D change is a different sketch, so it needs a different key or the
        // cache would hand back the previous combination.
        return template.id + "-" + threeD.chosen.sorted().joined(separator: "-")
    }

    /// The next dated serial in the destination, offered until the name is
    /// touched. Recomputed whenever the destination changes or one is made, so
    /// the number is never one somebody just used.
    private func suggestName() {
        name = ProjectNaming.nextSerial(
            in: destination,
            year: Calendar.current.component(.year, from: Date())
        )
    }

    // MARK: - Left: what to make, and where to start

    private var starting: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What to make")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

            Picker("", selection: $kind) {
                ForEach(ProjectKind.all) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()
            .padding(.horizontal, 12)

            // A kind that is not ready is still offered, and says what it waits
            // on. Naming it is the point: it is the map of where this goes.
            Group {
                if let waiting = kind.waitingOn {
                    Label(waiting, systemImage: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Text(kind.summary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .fixedSize(horizontal: false, vertical: true)

            Picker("", selection: $source) {
                ForEach(StartingPoint.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .onChange(of: source) { _, new in
                // Land on something the first time this tab is opened, and keep
                // whatever was chosen after that: which of the two is in play is
                // decided by `source` alone, not by clearing the other.
                if new == .examples, example == nil { example = examples.first }
            }

            if source == .templates {
                templateList
            } else {
                exampleList
            }
        }
        .frame(width: Self.templatesWidth)
        .background(SidebarVibrancy())
    }

    private var templateList: some View {
        List(ProjectTemplate.fitting(kind), selection: Binding(
            get: { template.id },
            set: { id in if let found = id.flatMap(ProjectTemplate.named) { template = found } }
        )) { option in
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title).font(.system(size: 12, weight: .medium))
                Text(option.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 3)
            .tag(option.id)
        }
        .listStyle(.sidebar)
    }

    /// Every example, filterable. Long enough that a filter is the only way to
    /// find one, and the group is shown because a name alone rarely places it.
    private var exampleList: some View {
        VStack(spacing: 0) {
            List(filteredExamples, selection: Binding(
                get: { example?.path },
                set: { path in example = examples.first { $0.path == path } }
            )) { option in
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.name).font(.system(size: 12, weight: .medium))
                    Text(option.group)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(option.path)
            }
            .listStyle(.sidebar)

            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                TextField("Filter", text: $exampleFilter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    private var filteredExamples: [ExampleSource.Example] {
        guard !exampleFilter.isEmpty else { return examples }
        return examples.filter { $0.path.localizedCaseInsensitiveContains(exampleFilter) }
    }

    // MARK: - Middle: the starting point, actually running

    private var stage: some View {
        ZStack {
            // Qualified: the framework has a `Color` of its own, as it does an
            // `Image` and an `Environment`.
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
            case .failed(let message):
                // A template that stopped compiling is a real defect, so it is
                // shown rather than swallowed.
                ScrollView {
                    Text(message)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                        .padding(12)
                }
            }
        }
        .frame(width: Self.stageSide, height: Self.stageSide)
    }

    // MARK: - Right: everything about the new project

    private var options: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                field("Name") {
                    TextField("", text: $name).textFieldStyle(.roundedBorder)
                }

                field("Where") {
                    HStack(spacing: 6) {
                        Text(destination.lastPathComponent)
                            .font(.system(size: 11))
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

                if template.id == ProjectTemplate.threeD.id && chosenExample == nil {
                    threeDOptions
                    Divider()
                }

                // Split by what a tick actually does: the first group makes a
                // folder to put material in, the second links a library.
                field("Material") {
                    toggles(Capability.all.filter { $0.module == nil })
                }
                field("Libraries") {
                    toggles(Capability.satellites)
                }

                Divider()
                summary
            }
            .padding(14)
        }
        .frame(width: Self.optionsWidth)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button(action: create) {
                    Text("Create").frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(!kind.isAvailable || name.trimmingCharacters(in: .whitespaces).isEmpty)

                if !kind.isAvailable {
                    Text("Nothing to create yet for this kind.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(.bar)
        }
    }

    /// What is about to be written, and what happened once it was.
    @ViewBuilder private var summary: some View {
        switch outcome {
        case .made(let project):
            VStack(alignment: .leading, spacing: 6) {
                Label("Made \(project.root.lastPathComponent)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
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
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case nil:
            if let plan = try? ProjectGenerator.plan(request()) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Will write \(plan.files.count) file\(plan.files.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                    ForEach(plan.files, id: \.path) { file in
                        Text(file.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The 3D pieces, with whatever cannot be combined greyed out and carrying
    /// the reason.
    ///
    /// This is the one part of the framework where the choices genuinely do not
    /// all stack, and the rule is never obvious from the call itself: a matcap
    /// silently swallows your lighting, traced reflections silently do nothing
    /// without an environment. Saying so here is cheaper than rendering to find
    /// out, which is what the reference page otherwise asks of you.
    @ViewBuilder private var threeDOptions: some View {
        ForEach(ThreeDOption.Slot.allCases, id: \.self) { slot in
            field(slot.title) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(ThreeDOption.inSlot(slot)) { option in
                        threeDRow(option, slot: slot)
                    }
                }
            }
        }
        // What the rule *is*, for whichever row is under the pointer, so the
        // reason is readable rather than only a tooltip.
        if let note = hoveredRule {
            Text(note)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, -6)
        }
    }

    private func threeDRow(_ option: ThreeDOption, slot: ThreeDOption.Slot) -> some View {
        let objection = threeD.objection(to: option)
        let chosen = threeD.chosen.contains(option.id)
        return Button {
            switch slot {
            case .geometry: threeD.geometry = option
            case .finish: threeD.finish = option
            case .extra:
                if chosen { threeD.extras.remove(option.id) } else { threeD.extras.insert(option.id) }
            }
            // Changing one choice can invalidate another, so the recipe tidies
            // itself rather than sitting in a state the generator would refuse.
            threeD.settle()
            outcome = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol(chosen: chosen, slot: slot, blocked: objection != nil))
                    .foregroundStyle(objection != nil
                                     ? AnyShapeStyle(.tertiary)
                                     : (chosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)))
                Text(option.title)
                    .font(.system(size: 11))
                    .foregroundStyle(objection != nil ? .tertiary : .primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(objection != nil)
        .help(objection ?? option.summary)
        .onHover { inside in
            hoveredRule = inside ? (objection ?? option.summary) : nil
        }
    }

    private func symbol(chosen: Bool, slot: ThreeDOption.Slot, blocked: Bool) -> String {
        if blocked { return "slash.circle" }
        if slot == .extra { return chosen ? "checkmark.square.fill" : "square" }
        return chosen ? "largecircle.fill.circle" : "circle"
    }

    /// A column of checkboxes. One a template needs itself is ticked and locked,
    /// since unticking it would leave the code that uses it with no import.
    private func toggles(_ capabilities: [Capability]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(capabilities) { capability in
                Toggle(isOn: binding(for: capability)) {
                    Text(capability.title).font(.system(size: 11))
                }
                .toggleStyle(.checkbox)
                .disabled(template.requires.contains(capability.id))
                .help(capability.summary)
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func binding(for capability: Capability) -> Binding<Bool> {
        Binding(
            get: { chosen.contains(capability.id) || template.requires.contains(capability.id) },
            set: { on in
                if on { chosen.insert(capability.id) } else { chosen.remove(capability.id) }
            }
        )
    }

    // MARK: - Doing the thing

    private func request() -> ProjectRequest {
        ProjectRequest(
            name: name,
            kind: kind,
            template: template,
            example: chosenExample,
            capabilities: Capability.all.filter { chosen.contains($0.id) },
            canvas: canvas,
            threeD: threeD,
            destination: destination,
            framework: .localPath(Self.frameworkRoot())
        )
    }

    private func create() {
        do {
            let project = try ProjectGenerator.plan(request())
            try ProjectGenerator.write(project)
            outcome = .made(project)
            // The serial just used is taken, so offer the next one.
            suggestName()
        } catch let error as ProjectGeneratorError {
            outcome = .refused(error.description)
        } catch {
            outcome = .refused("\(error)")
        }
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
            // A different folder has its own count.
            suggestName()
        }
    }

    /// Compile the template into the very source the generator would write, then
    /// run it. Cached per template, so moving back and forth is instant.
    private func showPreview() async {
        outcome = nil
        let key = previewKey
        if let cached = previewCache[key] {
            preview = .running(cached)
            return
        }
        preview = .compiling(chosenExample?.name ?? template.title)

        // Named after the starting point so the class inside is a fresh type
        // each time, which keeps repeated loads from colliding in the runtime.
        let previewRequest = ProjectRequest(
            name: "Preview\(key.filter(\.isLetter).capitalized)",
            kind: .singleFile,
            template: template,
            example: chosenExample,
            threeD: threeD,
            destination: URL(fileURLWithPath: NSTemporaryDirectory()),
            framework: .localPath(Self.frameworkRoot())
        )
        let source = ProjectGenerator.sketchSource(previewRequest)
        // An example loads its material relative to its own folder, so the
        // preview compiles as if it still lived there.
        let path = (chosenExample?.directory ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("ollin-preview-\(key.replacingOccurrences(of: "/", with: "-")).swift").path

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
            case .failure(let error):
                preview = .failed(String(describing: error))
            }
        case .failure(let error):
            preview = .failed(String(describing: error))
        }
    }

    // MARK: - Where things are

    /// A value passed on the command line, for opening the window already set
    /// to something.
    static func launchArgument(_ name: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static var defaultDestination: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    /// The folder this binary was built in, so a generated manifest points at the
    /// framework already on this machine.
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
