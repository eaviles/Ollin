import SwiftUI

// The seed-navigation card shared by every inspector surface (the live host's
// sidebar, the performance host's panel, the gallery's inspector, and the
// standalone detached panel): it shows the running sketch's current variation
// seed and steps, randomizes, or jumps the sketch through its seed space. Each
// navigation restarts the sketch in place at the chosen seed via the active
// runner (the same route the host Camera menu takes), leaving `@Param` parameter
// values untouched. A sketch that pins its own seed in `setup()` simply
// reproduces that variation, so the card is inert for it by design.

/// A titled "Variation" section holding the seed readout and its controls:
/// previous/next steppers, a randomize roll, and a type-to-jump field. Reads
/// the live seed from `stats`; `onNavigate` reports each chosen seed so a host
/// session can persist it across reloads (the tuned-parameter precedent). Leave it
/// defaulted where no reload exists (the gallery, the detached panel).
public struct VariationCardView: View {
    let stats: FrameStats
    let onNavigate: (Int) -> Void

    @SwiftUI.Environment(\.colorScheme) private var scheme
    /// The seed chosen through the card, shown immediately (the stats mirror
    /// refreshes a few times a second, too slow for a button press to feel
    /// attached). Cleared whenever the sketch lands on a different seed of its
    /// own accord, so an external change wins the display back.
    @State private var chosen: Int?
    @State private var draft: String = ""
    @FocusState private var editing: Bool

    public init(stats: FrameStats, onNavigate: @escaping (Int) -> Void = { _ in }) {
        self.stats = stats
        self.onNavigate = onNavigate
    }

    private var palette: OllinInspector.Palette { .resolve(scheme) }
    private var current: Int? { chosen ?? stats.variation }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Variation")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 4)
                .padding(.bottom, 7)

            row
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .onAppear { syncDraft() }
        .onChange(of: stats.variation) { _, newValue in
            if let newValue, newValue != chosen { chosen = nil }
            syncDraft()
        }
    }

    private var row: some View {
        HStack(spacing: 7) {
            Text("Seed")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)

            stepButton("chevron.left", help: "Previous seed") { step(-1) }

            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .multilineTextAlignment(.center)
                .focused($editing)
                .onSubmit(commitDraft)
                .frame(width: 58)
                .padding(.vertical, 3)
                .background(palette.fieldFill,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(palette.fieldStroke, lineWidth: 0.5))
                .onChange(of: editing) { _, isEditing in
                    if !isEditing { commitDraft() }
                }
                .onExitCommand { editing = false }
                .help("Jump to a seed")

            stepButton("chevron.right", help: "Next seed") { step(+1) }
            stepButton("dice", help: "Random seed") { apply(Int.random(in: 1 ... 99_999)) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func stepButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SwiftUI.Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 20)
                .background(palette.fieldFill,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(palette.fieldStroke, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func step(_ delta: Int) {
        guard let current else { return }
        apply(current + delta)
    }

    private func commitDraft() {
        guard let seed = Int(draft.trimmingCharacters(in: .whitespaces)), seed != current else {
            syncDraft()   // not a number, or unchanged: show the live seed again
            return
        }
        apply(seed)
    }

    /// Restart the running sketch at `seed` and reflect it immediately.
    private func apply(_ seed: Int) {
        chosen = seed
        syncDraft()
        OllinActiveSketch.runner?.restart(variation: seed)
        onNavigate(seed)
    }

    /// Show the live seed, unless someone is typing a different one.
    ///
    /// A box that holds the keyboard but nothing typed still fills: the panel
    /// can open before the first frame has a seed to show, and the first text
    /// field in a fresh window is handed the keyboard by the system, so the
    /// seed arriving a moment later used to find the box "busy" and leave it
    /// empty until the keyboard moved on.
    private func syncDraft() {
        guard !editing || draft.isEmpty else { return }
        draft = current.map(String.init) ?? ""
    }
}
