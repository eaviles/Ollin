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
    // The status colors are the system semantics (AppKit dynamic colors), so
    // they adapt per appearance: dark resolves to the values the design speced
    // (#30D158 / #FF9F0A-ish / #FF453A) and light gets the correct, less
    // fluorescent variants — hard-coding the dark hexes had light mode showing
    // dark-palette neon.
    public static let green = SwiftUI.Color(nsColor: .systemGreen)
    public static let amber = SwiftUI.Color(nsColor: .systemOrange)
    public static let red = SwiftUI.Color(nsColor: .systemRed)

    /// The brand accent: the slider tint, the frame counter, the ring spinner,
    /// the `@Param` mention in the empty state. One token so they can't drift.
    public static let accent = SwiftUI.Color.purple

    /// The inspector surface width — the live host's docked sidebar and the
    /// detached panel share it, keeping the two a true 1:1.
    public static let sidebarWidth: CGFloat = 296

    /// Shared opacity for the host chrome's frosted tints — the live host's sidebar
    /// scrim and reload toast, and the standalone stats panel — so they read as one
    /// translucency. The tint's alpha over the material blur: higher is more opaque.
    public static let chromeTintOpacity: Double = 0.55

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

    /// The hairline separator color from the design tokens (`--sep`): dark
    /// `rgba(255,255,255,0.085)`, light `rgba(0,0,0,0.09)`. The card-internal
    /// rules use it; exposed so the live host draws the same window-chrome
    /// hairlines (under the title bar, at the sidebar's edge).
    public static func separator(_ scheme: ColorScheme) -> SwiftUI.Color {
        Palette.resolve(scheme).separator
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
/// and the detached panel's header. The compiling pulse rides the symbol-effect
/// system (`isActive:` starts and stops it per state change), so it works on
/// every compile — a hand-rolled `repeatForever` keyed on local state only
/// fired the first time, leaving later compiles a static dimmed dot.
public struct StatusChip: View {
    let status: InspectorStatus

    public init(status: InspectorStatus) { self.status = status }

    public var body: some View {
        HStack(spacing: 6) {
            SwiftUI.Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(status.tint)
                .shadow(color: status.tint.opacity(0.6), radius: 3.5)
                .symbolEffect(.pulse, options: .repeating, isActive: status.pulses)
            Text(status.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(status.labelColor)
        }
    }
}

// MARK: - Monitor card

/// Identity for the card header: the source filename and its folder. The folder
/// is optional (its line is dropped when nil), as is the leading `icon`: pass
/// `nil` to omit it (e.g. the standalone panel names the app, not a file).
///
/// `Equatable` so the card's identity block, factored into its own view, is
/// skipped by SwiftUI on every `FrameStats` tick that leaves the identity
/// unchanged (the common case between sketch reloads).
public struct MonitorIdentity: Equatable {
    var name: String
    var folder: String?
    var icon: String?
    public init(name: String, folder: String? = nil, icon: String? = "doc") {
        self.name = name
        self.folder = folder
        self.icon = icon
    }
}

/// The centerpiece: a card with three tiers, an identity row (filename · path,
/// with a Frame counter cell on the right; just the one cell, a second squeezed
/// the identity block illegibly), the big centered timecode clock, and a
/// four-up FPS · CPU · Canvas · Geometry stat strip. Driven by a live
/// `FrameStats`, so it updates a few times a second as the sketch runs.
///
/// Each tier is its own `View` so a tick only re-renders the readouts that
/// changed: the static identity block stays put while the clock and strip
/// advance, instead of the whole card re-evaluating behind one boundary.
public struct MonitorCardView: View {
    let identity: MonitorIdentity
    let stats: FrameStats
    let clockSize: CGFloat

    @SwiftUI.Environment(\.colorScheme) private var scheme

    public init(identity: MonitorIdentity, stats: FrameStats, clockSize: CGFloat = 30) {
        self.identity = identity
        self.stats = stats
        self.clockSize = clockSize
    }

    private var palette: OllinInspector.Palette { .resolve(scheme) }

    public var body: some View {
        VStack(spacing: 0) {
            MonitorIdentityRow(identity: identity, frameCount: stats.frameCount)
            Hairline(palette: palette)
            MonitorClockRow(time: stats.time, clockSize: clockSize)
            Hairline(palette: palette)
            MonitorStatStrip(stats: stats)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// The static identity block: icon · filename over the optional folder line, with
/// the (often truncated) path shown in full on hover. Its own view so the live
/// `FrameStats` tick re-renders the readouts around it without redrawing this;
/// `MonitorIdentity` is `Equatable`, so SwiftUI skips it when it hasn't changed.
private struct IdentityBlock: View {
    let identity: MonitorIdentity

    @SwiftUI.Environment(\.colorScheme) private var scheme
    private var palette: OllinInspector.Palette { .resolve(scheme) }

    /// The full path, shown as a tooltip on the (often truncated) block.
    private var fullPath: String {
        if let folder = identity.folder { return "\(folder)/\(identity.name)" }
        return identity.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let icon = identity.icon {
                    SwiftUI.Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textTertiary)
                }
                Text(identity.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            if let folder = identity.folder {
                Text(folder)
                    .font(.system(size: 10.5))
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
    }
}

/// The card's top tier: the static `IdentityBlock` beside a live Frame counter
/// cell. Only the frame count ticks, so the identity block is left alone.
private struct MonitorIdentityRow: View {
    let identity: MonitorIdentity
    let frameCount: Int

    @SwiftUI.Environment(\.colorScheme) private var scheme
    private var palette: OllinInspector.Palette { .resolve(scheme) }

    var body: some View {
        HStack(spacing: 0) {
            IdentityBlock(identity: identity)

            HStack(spacing: 0) {
                Hairline(palette: palette, axis: .vertical)
                MonitorCell(value: "\(frameCount)", label: "Frame",
                            valueColor: OllinInspector.accent, palette: palette)
                    // A width floor so the identity row doesn't shift each time
                    // the running frame count gains a digit.
                    .frame(minWidth: 56)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A centered value-over-label cell (a monospaced readout above tiny caps),
/// used for the header's Frame counter.
private struct MonitorCell: View {
    let value: String
    let label: String
    let valueColor: SwiftUI.Color
    let palette: OllinInspector.Palette

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.3)
                .textCase(.uppercase)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
    }
}

/// The big centered timecode clock.
private struct MonitorClockRow: View {
    let time: Double
    let clockSize: CGFloat

    @SwiftUI.Environment(\.colorScheme) private var scheme
    private var palette: OllinInspector.Palette { .resolve(scheme) }

    var body: some View {
        Text(OllinInspector.timecode(time))
            .font(.system(size: clockSize, weight: .medium, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(palette.readout)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }
}

/// The four-up FPS · CPU · Canvas · Geometry strip. Every cell ticks with the
/// live `FrameStats`, so it reads the object directly rather than threading nine
/// scalars through; per-property observation still re-renders only on a change.
private struct MonitorStatStrip: View {
    let stats: FrameStats

    @SwiftUI.Environment(\.colorScheme) private var scheme
    private var palette: OllinInspector.Palette { .resolve(scheme) }

    private var canvasLabel: String {
        let w = Int(stats.canvasWidth.rounded()), h = Int(stats.canvasHeight.rounded())
        guard w > 0, h > 0 else { return "—" }
        return w == h ? "\(w)²" : "\(w)×\(h)"
    }

    /// Geometry readout, naming each path in use (e.g. `5 sdf`, `31k tri`,
    /// `12k pts` (3D point cloud), `1M particles`), space-joined when a sketch
    /// mixes them (the full breakdown rides the cell's tooltip). Naming the path
    /// rather than showing a bare number keeps a text/shape-heavy *or* a point-cloud
    /// / particle sketch from reading as "0" when it's clearly drawing.
    private var geometryLabel: String {
        func compact(_ n: Int) -> String {
            n >= 1_000_000 ? "\(n / 1_000_000)M" : n >= 1000 ? "\(n / 1000)k" : "\(n)"
        }
        var parts: [String] = []
        if stats.sdfCount > 0 { parts.append("\(compact(stats.sdfCount)) sdf") }
        if stats.vertexCount > 0 { parts.append("\(compact(stats.vertexCount)) tri") }
        if stats.pointCount > 0 { parts.append("\(compact(stats.pointCount)) pts") }
        if stats.particleCount > 0 { parts.append("\(compact(stats.particleCount)) particles") }
        return parts.isEmpty ? "0" : parts.joined(separator: " ")
    }

    /// The Geometry cell's tooltip: the decoder for the compact value, so it
    /// always spells out every path, zeros included.
    private var geometryDetail: String {
        func line(_ n: Int, _ one: String, _ many: String) -> String {
            n == 1 ? "1 \(one)" : "\(n) \(many)"
        }
        let parts = [
            line(stats.sdfCount, "instanced SDF shape", "instanced SDF shapes"),
            line(stats.vertexCount, "tessellated triangle vertex", "tessellated triangle vertices"),
            line(stats.pointCount, "3D point-cloud splat", "3D point-cloud splats"),
            line(stats.particleCount, "GPU particle", "GPU particles"),
        ]
        return "Geometry this frame: " + parts.joined(separator: " + ")
    }

    var body: some View {
        HStack(spacing: 0) {
            statCell(value: stats.hasData ? String(format: "%.0f", stats.fps) : "—",
                     label: "FPS", valueColor: OllinInspector.green)
            Hairline(palette: palette, axis: .vertical)
            statCell(value: stats.hasData ? String(format: "%.1f ms", stats.frameTimeMS) : "—",
                     label: "CPU", valueColor: .primary)
            Hairline(palette: palette, axis: .vertical)
            statCell(value: canvasLabel, label: "Canvas", valueColor: .primary)
            Hairline(palette: palette, axis: .vertical)
            statCell(value: stats.hasData ? geometryLabel : "—",
                     label: "Geometry", valueColor: .primary)
                .help(geometryDetail)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Stat-strip cell: content-sized (`maxWidth: .infinity`, even padding) so a
    /// short value doesn't strand in an oversized column.
    private func statCell(value: String, label: String, valueColor: SwiftUI.Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.3)
                .textCase(.uppercase)
                .foregroundStyle(palette.textTertiary)
        }
        .lineLimit(1)
        // Shrink rather than clip when a value outgrows its quarter-column;
        // no fixedSize here, or the scale factor can never engage.
        .minimumScaleFactor(0.8)
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

    @SwiftUI.Environment(\.colorScheme) private var scheme

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
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
            Text("Add \(Text("@Param").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(OllinInspector.accent)) knobs to your sketch to tune them live.")
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
/// a user edit is written into the live `Param` and reported to `onChange`.
///
/// The row is not the param's only writer — a MIDI/OSC binding, a smoothing
/// glide, or the sketch itself may drive the same knob — so it also *follows*:
/// a ~10 Hz pull (the stats cadence) reflects the live value back into the
/// thumb and pill, paused while the user is dragging or typing.
private struct ParamSliderRow: View {
    let handle: ParamHandle
    let palette: OllinInspector.Palette
    let onChange: (Double) -> Void

    @State private var value: Double
    /// The last value this row knows the param to hold — seeded at init, updated
    /// by every sync pull and user edit. `onChange(of: value)` compares against
    /// it to tell a sync echo (skip) from a real user edit (write + record).
    @State private var lastKnown: Double
    /// True while the slider thumb is held; parks the sync pull.
    @State private var isDragging = false
    /// True while the value pill has keyboard focus; parks the sync pull.
    @FocusState private var isTyping: Bool

    init(handle: ParamHandle, palette: OllinInspector.Palette, onChange: @escaping (Double) -> Void) {
        self.handle = handle
        self.palette = palette
        self.onChange = onChange
        let current = handle.param.wrappedValue
        _value = State(initialValue: current)
        _lastKnown = State(initialValue: current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(handle.label)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                TextField("", value: $value, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.plain)
                    .focused($isTyping)
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
            Slider(value: $value, in: handle.param.range) { isDragging = $0 }
                .controlSize(.small)
                .tint(OllinInspector.accent)
                // The native slider carries internal vertical inset; trim it so the
                // track-to-separator gap matches the pill's top gap (balanced row).
                // The -3 is tied to AppKit's private metrics — re-verify the row
                // spacing on each macOS major.
                .padding(.vertical, -3)
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 11)
        .onChange(of: value) { _, newValue in
            guard newValue != lastKnown else { return }   // the sync pull's own echo
            // A typed value can land outside the range (the slider can't).
            // Clamp here so the pill, the param, and the host's persisted
            // record all agree — the param clamps internally anyway, but a raw
            // out-of-range value displayed or recorded would lie about what
            // the sketch actually runs with.
            let range = handle.param.range
            let clamped = Swift.min(Swift.max(newValue, range.lowerBound), range.upperBound)
            if clamped != newValue { value = clamped }   // snap the pill back into range
            lastKnown = clamped
            handle.param.wrappedValue = clamped
            onChange(clamped)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !isDragging, !isTyping else { continue }
                let live = handle.param.wrappedValue
                if live != value {
                    lastKnown = live
                    value = live
                }
            }
        }
    }
}
