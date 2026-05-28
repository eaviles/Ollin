import SwiftUI
import Ollin

/// Sidebar inspector for the live host: sketch identity, reload status, live
/// FPS, the running sketch's `@Param` knobs as sliders, and the last compile
/// error when a reload fails.
struct InspectorPanel: View {
    let session: LiveSession

    var body: some View {
        Form {
            Section("Sketch") {
                LabeledContent("Name", value: session.title)
                LabeledContent("File", value: session.displayName)
            }
            Section("Live reload") {
                LabeledContent("Status", value: session.status.label)
                LabeledContent("Reloads", value: "\(session.reloadCount)")
            }
            Section("Performance") {
                LabeledContent("FPS", value: session.frameRate > 0
                    ? String(format: "%.0f", session.frameRate) : "—")
            }
            if !session.params.isEmpty {
                Section("Parameters") {
                    ForEach(session.params) { handle in
                        ParamSliderRow(handle: handle) { session.recordParam(handle.name, $0) }
                            // Recreate (resetting local state) when the underlying
                            // param instance changes — i.e. on reload.
                            .id(ObjectIdentifier(handle.param))
                    }
                }
            }
            if let error = session.errorMessage {
                Section("Last error") {
                    Text(error)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// One labelled slider for a `@Param`. Local `@State` drives smooth dragging and
/// the live readout; `onChange` pushes the value into the live sketch and records
/// it for persistence. The parent re-creates this view (fresh state) on reload.
private struct ParamSliderRow: View {
    let handle: ParamHandle
    let onChange: (Double) -> Void
    @State private var value: Double

    init(handle: ParamHandle, onChange: @escaping (Double) -> Void) {
        self.handle = handle
        self.onChange = onChange
        _value = State(initialValue: handle.param.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(handle.label).font(.callout)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(2)))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: $value, in: handle.param.range)
        }
        .onChange(of: value) { _, newValue in
            handle.param.wrappedValue = newValue
            onChange(newValue)
        }
    }
}
