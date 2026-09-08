import SwiftUI
import Ollin

/// The inspector's "Controls" card: one row per host action with the control
/// that reaches it, a Learn button that waits for the next control to
/// arrive, and the OSC port. The fixed OSC address shows in place of a
/// binding for an action nothing has been learned for, since it answers
/// there whenever the port is open.
struct ControlsCardView: View {
    let controls: PerformanceControls

    @SwiftUI.Environment(\.colorScheme) private var scheme
    @State private var portDraft = ""
    @FocusState private var editingPort: Bool

    private var palette: OllinInspector.Palette { .resolve(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Controls")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 4)
                .padding(.bottom, 7)

            VStack(spacing: 0) {
                ForEach(PerformanceControls.Action.allCases) { action in
                    row(for: action)
                    Divider().opacity(0.5)
                }
                portRow
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .onAppear { portDraft = controls.oscPort > 0 ? String(controls.oscPort) : "" }
    }

    private func row(for action: PerformanceControls.Action) -> some View {
        let bound = controls.map[action]
        let learning = controls.learning == action
        return HStack(spacing: 7) {
            SwiftUI.Circle()
                .fill(controls.lastFired == action ? OllinInspector.accent : .clear)
                .frame(width: 5, height: 5)
            Text(action.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(learning ? "listening…" : (bound?.label ?? action.address))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(learning ? OllinInspector.amber : (bound == nil ? palette.textTertiary : .secondary))
                .lineLimit(1)
                .truncationMode(.head)
            smallButton(learning ? "xmark" : "dot.radiowaves.left.and.right",
                        help: learning ? "Stop listening" : "Learn: the next control to arrive is this action's",
                        tint: learning ? OllinInspector.amber : nil) {
                controls.learn(action)
            }
            if bound != nil {
                smallButton("minus", help: "Forget this control") { controls.clear(action) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var portRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text("OSC port")
                    .font(.system(size: 12.5, weight: .medium))
                Spacer(minLength: 6)
                TextField("off", text: $portDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .focused($editingPort)
                    .onSubmit(commitPort)
                    .frame(width: 58)
                    .padding(.vertical, 3)
                    .background(palette.fieldFill,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(palette.fieldStroke, lineWidth: 0.5))
                    .onChange(of: editingPort) { _, isEditing in
                        if !isEditing { commitPort() }
                    }
                    .onExitCommand { editingPort = false }
                    .help("The UDP port the host answers OSC on; empty is off")
            }
            HStack(spacing: 6) {
                Text(controls.oscStatus)
                Text("·")
                Text(controls.isListeningToMIDI
                     ? "MIDI: \(controls.midiSourceCount) source\(controls.midiSourceCount == 1 ? "" : "s")"
                     : "MIDI unavailable")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func commitPort() {
        let trimmed = portDraft.trimmingCharacters(in: .whitespaces)
        let port = Int(trimmed) ?? 0
        let clamped = min(max(0, port), 65535)
        controls.oscPort = clamped
        portDraft = clamped > 0 ? String(clamped) : ""
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
