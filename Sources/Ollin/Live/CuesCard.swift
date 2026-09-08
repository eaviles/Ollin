import SwiftUI

/// The inspector's "Cues" card: one row per saved cue, pressed to call it over
/// the card's fade, a dot lit on the cue called last, a field to save the
/// parameters as they stand under a new name (or to update the cue of that
/// name), and the fade in seconds. The host hands over the cues and what to
/// do; the card holds nothing of its own but the drafts.
public struct CuesCardView: View {
    /// The defaults key the fade lives under, read by the card and by a host's
    /// own controls, so a program change fades the way a press on the card does.
    public static let fadeKey = "ollin.inspector.cueFade"

    /// The fade the card and the host's controls use, in seconds; 1 until set.
    public static func fade(in defaults: UserDefaults = .standard) -> Double {
        defaults.object(forKey: fadeKey) == nil ? 1 : max(0, defaults.double(forKey: fadeKey))
    }

    let cues: [Cue]
    /// The cue called last, asked each time the card draws so a cue the
    /// sketch calls itself lights up too.
    let currentCue: () -> String?
    let onCall: (CueRequest, Double) -> Void
    let onSave: (String) -> Void
    let onDelete: (String) -> Void

    public init(cues: [Cue], currentCue: @escaping () -> String?,
                onCall: @escaping (CueRequest, Double) -> Void,
                onSave: @escaping (String) -> Void,
                onDelete: @escaping (String) -> Void) {
        self.cues = cues
        self.currentCue = currentCue
        self.onCall = onCall
        self.onSave = onSave
        self.onDelete = onDelete
    }

    @SwiftUI.Environment(\.colorScheme) private var scheme
    @AppStorage(CuesCardView.fadeKey) private var fade = 1.0
    @State private var nameDraft = ""
    @State private var fadeDraft = ""
    @State private var lit: String?
    @FocusState private var editingName: Bool
    @FocusState private var editingFade: Bool

    private var palette: OllinInspector.Palette { .resolve(scheme) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Cues")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 4)
                .padding(.bottom, 7)

            VStack(spacing: 0) {
                ForEach(cues, id: \.name) { cue in
                    row(for: cue)
                    Divider().opacity(0.5)
                }
                saveRow
                fadeRow
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .onAppear { fadeDraft = Self.format(fade) }
        // The lit dot follows the cue called last, whoever called it, on the
        // rows' own poll cadence.
        .task(id: cues.map(\.name)) {
            lit = currentCue()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                let now = currentCue()
                if now != lit { lit = now }
            }
        }
    }

    private func row(for cue: Cue) -> some View {
        HStack(spacing: 7) {
            Button {
                onCall(.named(cue.name), fade)
            } label: {
                HStack(spacing: 7) {
                    SwiftUI.Circle()
                        .fill(lit == cue.name ? OllinInspector.accent : .clear)
                        .frame(width: 5, height: 5)
                    Text(cue.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text("\(cue.values.count)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                        .help("\(cue.values.count) parameter\(cue.values.count == 1 ? "" : "s") saved in this cue")
                }
                .contentShape(SwiftUI.Rectangle())
            }
            .buttonStyle(.plain)
            .help("Call this cue over the fade")
            smallButton("minus", help: "Delete this cue") { onDelete(cue.name) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    /// Whether the name typed is a cue already, so the button updates it.
    private var draftNamesExisting: Bool {
        let name = nameDraft.trimmingCharacters(in: .whitespaces)
        return cues.contains { $0.name == name }
    }

    private var saveRow: some View {
        HStack(spacing: 7) {
            TextField("Name a new cue", text: $nameDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($editingName)
                .onSubmit(commitSave)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(palette.fieldFill,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(palette.fieldStroke, lineWidth: 0.5))
                #if os(macOS)
                .onExitCommand { editingName = false }
                #endif
            smallButton(draftNamesExisting ? "arrow.down.to.line" : "plus",
                        help: draftNamesExisting
                            ? "Update this cue with the parameters as they stand"
                            : "Save the parameters as they stand as a new cue",
                        tint: draftNamesExisting ? OllinInspector.accent : nil) {
                commitSave()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var fadeRow: some View {
        HStack(spacing: 7) {
            Text("Fade")
                .font(.system(size: 12.5, weight: .medium))
            Spacer(minLength: 6)
            TextField("0", text: $fadeDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .multilineTextAlignment(.center)
                .focused($editingFade)
                .onSubmit(commitFade)
                .frame(width: 58)
                .padding(.vertical, 3)
                .background(palette.fieldFill,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(palette.fieldStroke, lineWidth: 0.5))
                .onChange(of: editingFade) { _, isEditing in
                    if !isEditing { commitFade() }
                }
                #if os(macOS)
                .onExitCommand { editingFade = false }
                #endif
                .help("Seconds a called cue takes to arrive; 0 is at once")
            Text("s")
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func commitSave() {
        let name = nameDraft.trimmingCharacters(in: .whitespaces)
        let chosen = name.isEmpty ? Self.freshName(among: cues.map(\.name)) : name
        onSave(chosen)
        nameDraft = ""
        editingName = false
    }

    private func commitFade() {
        let trimmed = fadeDraft.trimmingCharacters(in: .whitespaces)
        let value = max(0, Double(trimmed) ?? 0)
        fade = value
        fadeDraft = Self.format(value)
    }

    /// "Cue 1", "Cue 2", … the first not taken.
    static func freshName(among names: [String]) -> String {
        var n = names.count + 1
        while names.contains("Cue \(n)") { n += 1 }
        return "Cue \(n)"
    }

    private static func format(_ seconds: Double) -> String {
        seconds == seconds.rounded() ? String(Int(seconds)) : String(format: "%.2g", seconds)
    }

    private func smallButton(_ symbol: String, help: String, tint: SwiftUI.Color? = nil,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SwiftUI.Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 22, height: 20)
                .background(palette.fieldFill,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(palette.fieldStroke, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
