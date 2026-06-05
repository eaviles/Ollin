import SwiftUI

// Within the Ollin module the bare name `Color` is the framework's own color
// value type, so the explicit color declarations below say `SwiftUI.Color`.
// (Contextual `.white`/`.purple`/… still resolve against those typed positions,
// so they need no qualification.)

// The inspector surface shared by the live host's sidebar and the standalone
// "Show FPS" detached panel: a monitor card (identity · clock · stats) and a
// parameter list. Built once here so the docked sidebar and the floating panel
// render the same thing and can never drift. Colors follow the system
// appearance — no in-app theme switch — so semantic colors and `Material` do
// the light/dark work automatically; the few literal tokens below are the
// designed accents (the clock readout, the status colors).

// MARK: - Status

/// The lifecycle state shown as a small dot-and-label chip. The live host maps
/// its watcher state onto the first three; the detached panel (no watcher) uses
/// `.running`.
public enum InspectorStatus: Equatable, Sendable {
    case watching
    case compiling
    case error
    case running

    var label: String {
        switch self {
        case .watching: return "Watching"
        case .compiling: return "Compiling…"   // the only transient state takes the ellipsis
        case .error: return "Compile error"
        case .running: return "Running"
        }
    }

    var tint: SwiftUI.Color {
        switch self {
        case .watching, .running: return OllinInspector.green
        case .compiling: return OllinInspector.amber
        case .error: return OllinInspector.red
        }
    }

    /// The chip's text color: muted for the steady states, tinted for the alerts.
    var labelColor: SwiftUI.Color {
        switch self {
        case .watching, .running: return .secondary
        case .compiling: return OllinInspector.amber
        case .error: return OllinInspector.red
        }
    }

    var pulses: Bool { self == .compiling }
}

// MARK: - Tokens & helpers

/// Design tokens that aren't covered by semantic colors, plus the timecode
/// formatter. Resolved per `ColorScheme` so the card matches the spec in both
/// appearances.
public enum OllinInspector {
    public static let green = SwiftUI.Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)
    public static let amber = SwiftUI.Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255)
    public static let red = SwiftUI.Color(red: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255)

    /// The title-bar gradient from the design tokens (dark `#2B2B2D`→`#262628`,
    /// light `#E6E6E8`→`#EDEDEF`).
    public static func titleBarGradient(_ scheme: ColorScheme) -> LinearGradient {
        let top: SwiftUI.Color, bottom: SwiftUI.Color
        if scheme == .dark {
            top = SwiftUI.Color(red: 0x2B / 255, green: 0x2B / 255, blue: 0x2D / 255)
            bottom = SwiftUI.Color(red: 0x26 / 255, green: 0x26 / 255, blue: 0x28 / 255)
        } else {
            top = SwiftUI.Color(red: 0xE6 / 255, green: 0xE6 / 255, blue: 0xE8 / 255)
            bottom = SwiftUI.Color(red: 0xED / 255, green: 0xED / 255, blue: 0xEF / 255)
        }
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    /// `HH:MM:SS.x` — the clock hero. Tenths match the ~4 Hz stats refresh.
    public static func timecode(_ seconds: Double) -> String {
        let s = max(0, seconds)
        let h = Int(s) / 3600
        let m = (Int(s) / 60) % 60
        let sec = Int(s) % 60
        let tenths = Int((s - floor(s)) * 10)
        return String(format: "%02d:%02d:%02d.%d", h, m, sec, tenths)
    }

    struct Palette {
        let cardFill: SwiftUI.Color
        let cardStroke: SwiftUI.Color
        let fieldFill: SwiftUI.Color
        let fieldStroke: SwiftUI.Color
        let separator: SwiftUI.Color
        let textTertiary: SwiftUI.Color
        let readout: SwiftUI.Color

        static func resolve(_ scheme: ColorScheme) -> Palette {
            if scheme == .dark {
                return Palette(
                    cardFill: .white.opacity(0.055),
                    cardStroke: .white.opacity(0.07),
                    fieldFill: .white.opacity(0.08),
                    fieldStroke: .white.opacity(0.10),
                    separator: .white.opacity(0.085),
                    textTertiary: .white.opacity(0.34),
                    readout: SwiftUI.Color(red: 0xE8 / 255, green: 0xE2 / 255, blue: 0xF2 / 255))
            } else {
                return Palette(
                    cardFill: .white,
                    cardStroke: .black.opacity(0.07),
                    fieldFill: .black.opacity(0.045),
                    fieldStroke: .black.opacity(0.10),
                    separator: .black.opacity(0.09),
                    textTertiary: .black.opacity(0.32),
                    readout: SwiftUI.Color(red: 0x3A / 255, green: 0x2B / 255, blue: 0x4A / 255))
            }
        }
    }
}

/// A thin 0.5pt rule in the card's separator color.
private struct Hairline: View {
    let palette: OllinInspector.Palette
    var axis: Axis = .horizontal
    var body: some View {
        SwiftUI.Rectangle()
            .fill(palette.separator)
            .frame(width: axis == .vertical ? 0.5 : nil,
                   height: axis == .horizontal ? 0.5 : nil)
    }
}

// MARK: - Status chip

/// A dot-and-label status chip (`● Watching`). Used in the live host's toolbar
/// and the detached panel's header.
public struct StatusChip: View {
    let status: InspectorStatus
    @State private var dim = false

    public init(status: InspectorStatus) { self.status = status }

    public var body: some View {
        HStack(spacing: 6) {
            SwiftUI.Circle()
                .fill(status.tint)
                .frame(width: 7, height: 7)
                .shadow(color: status.tint.opacity(0.6), radius: 3.5)
                .opacity(status.pulses && dim ? 0.35 : 1)
                .animation(status.pulses ? Animation.easeInOut(duration: 1).repeatForever(autoreverses: true) : .default,
                           value: dim)
            Text(status.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(status.labelColor)
        }
        .onAppear { if status.pulses { dim = true } }
    }
}

// MARK: - Monitor card

/// Identity for the card header: the source filename and its folder. The
/// detached panel for a standalone sketch has no source file, so both are
/// optional — pass just a name (the sketch title) and the path line is dropped.
public struct MonitorIdentity {
    var name: String
    var folder: String?
    public init(name: String, folder: String? = nil) {
        self.name = name
        self.folder = folder
    }
}

/// The centerpiece: a card with three tiers — an identity row (filename · path,
/// with Frame and Reloads cells on the right), the big centered timecode clock,
/// and a four-up FPS · CPU · Canvas · Geometry stat strip. Driven by a live
/// `FrameStats`, so it updates a few times a second as the sketch runs.
public struct MonitorCardView: View {
    let identity: MonitorIdentity
    let stats: FrameStats
    let clockSize: CGFloat

    @Environment(\.colorScheme) private var scheme

    public init(identity: MonitorIdentity, stats: FrameStats, clockSize: CGFloat = 30) {
        self.identity = identity
        self.stats = stats
        self.clockSize = clockSize
    }

    private var palette: OllinInspector.Palette { .resolve(scheme) }

    private var canvasLabel: String {
        let w = Int(stats.canvasWidth.rounded()), h = Int(stats.canvasHeight.rounded())
        guard w > 0, h > 0 else { return "—" }
        return w == h ? "\(w)²" : "\(w)×\(h)"
    }

    /// The full path, shown as a tooltip on the (often truncated) identity block.
    private var fullPath: String {
        if let folder = identity.folder { return "\(folder)/\(identity.name)" }
        return identity.name
    }

    public var body: some View {
        VStack(spacing: 0) {
            identityRow
            Hairline(palette: palette)
            clockRow
            Hairline(palette: palette)
            statStrip
        }
        .background(palette.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(palette.cardStroke, lineWidth: 0.5))
    }

    private var identityRow: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    SwiftUI.Image(systemName: "doc")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textTertiary)
                    Text(identity.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                if let folder = identity.folder {
                    Text(folder)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.vertical, 9)
            .padding(.leading, 13)
            .padding(.trailing, 12)   // keep the path off the Frame-cell separator
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(fullPath)           // hover the truncated path to see it in full

            HStack(spacing: 0) {
                Hairline(palette: palette, axis: .vertical)
                cell(value: "\(stats.frameCount)", label: "Frame", valueColor: .purple)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A centered value-over-label cell, used by both the head cells and the
    /// stat strip. The value is monospaced (a readout); the label is tiny caps.
    private func cell(value: String, label: String, valueColor: SwiftUI.Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.3)
                .textCase(.uppercase)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
    }

    private var clockRow: some View {
        Text(OllinInspector.timecode(stats.time))
            .font(.system(size: clockSize, weight: .medium, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(palette.readout)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }

    private var statStrip: some View {
        HStack(spacing: 0) {
            statCell(value: stats.hasData ? String(format: "%.0f", stats.fps) : "—",
                     label: "FPS", valueColor: OllinInspector.green)
            Hairline(palette: palette, axis: .vertical)
            statCell(value: stats.hasData ? String(format: "%.1f ms", stats.frameTimeMS) : "—",
                     label: "CPU", valueColor: .primary)
            Hairline(palette: palette, axis: .vertical)
            statCell(value: canvasLabel, label: "Canvas", valueColor: .primary)
            Hairline(palette: palette, axis: .vertical)
            statCell(value: "\(stats.sdfCount) sdf", label: "Geometry", valueColor: .primary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Stat-strip cell: like `cell`, but content-sized (`maxWidth: .infinity`
    /// with even padding) so "60" doesn't strand in an oversized column.
    private func statCell(value: String, label: String, valueColor: SwiftUI.Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(0.3)
                .textCase(.uppercase)
                .foregroundStyle(palette.textTertiary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)   // shrink rather than clip "0.0 ms" in a tight column
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Parameters

/// The `PARAMETERS` group: a header over a card of slider rows (label · editable
/// value pill · thin tinted slider), or an empty state when the sketch declares
/// no `@Param` knobs. `onChange` reports edits so a host can persist them; the
/// row writes the value into the live `Param` regardless, so a standalone panel
/// can leave it a no-op and still tune live.
public struct ParametersListView: View {
    let params: [ParamHandle]
    let onChange: (String, Double) -> Void

    @Environment(\.colorScheme) private var scheme

    public init(params: [ParamHandle], onChange: @escaping (String, Double) -> Void = { _, _ in }) {
        self.params = params
        self.onChange = onChange
    }

    private var palette: OllinInspector.Palette { .resolve(scheme) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Parameters")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 4)
                .padding(.bottom, 7)

            Group {
                if params.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(params.enumerated()), id: \.element.id) { index, handle in
                            if index > 0 { Hairline(palette: palette) }
                            ParamSliderRow(handle: handle, palette: palette,
                                           onChange: { onChange(handle.name, $0) })
                                .id(ObjectIdentifier(handle.param))   // reset state on reload
                        }
                    }
                }
            }
            .background(palette.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(palette.cardStroke, lineWidth: 0.5))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            SwiftUI.Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 34, height: 34)
                .background(palette.fieldFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("No parameters")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.secondary)
            (Text("Add ") + Text("@Param").font(.system(size: 11.5, design: .monospaced)).foregroundColor(.purple)
                + Text(" knobs to your sketch to tune them live."))
                .font(.system(size: 11.5))
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
    }
}

/// One labelled slider: a label and an editable mono value pill on top, a thin
/// tinted slider below. Local state drives smooth dragging and the readout;
/// every change is written into the live `Param` and reported to `onChange`.
private struct ParamSliderRow: View {
    let handle: ParamHandle
    let palette: OllinInspector.Palette
    let onChange: (Double) -> Void

    @State private var value: Double

    init(handle: ParamHandle, palette: OllinInspector.Palette, onChange: @escaping (Double) -> Void) {
        self.handle = handle
        self.palette = palette
        self.onChange = onChange
        _value = State(initialValue: handle.param.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(handle.label)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                TextField("", value: $value, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 12, design: .monospaced))
                    // Hug the number (don't stretch across the row) so the pill is
                    // compact and content-sized, matching the design's value field.
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 42, alignment: .trailing)   // floor so short values stay ~uniform, like the design
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(palette.fieldFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(palette.fieldStroke, lineWidth: 0.5))
            }
            Slider(value: $value, in: handle.param.range)
                .controlSize(.small)
                .tint(.purple)
                // The native slider carries internal vertical inset; trim it so the
                // track-to-separator gap matches the pill's top gap (balanced row).
                .padding(.vertical, -3)
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 11)
        .onChange(of: value) { _, newValue in
            handle.param.wrappedValue = newValue
            onChange(newValue)
        }
    }
}
