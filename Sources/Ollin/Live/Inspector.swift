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

/// The centerpiece: a card of stacked tiers, an identity row (filename · path,
/// with a Frame counter cell on the right; just the one cell, a second squeezed
/// the identity block illegibly), the big centered timecode clock, one cell
/// grid (FPS · Canvas · a cell per drawing path in use · Draws · Passes ·
/// Batches, filling rows four at a time), and the CPU/GPU cost bars. Cells
/// carry facts, the bars carry time, and no number appears in two places.
/// Driven by a live `FrameStats`, so it updates a few times a second as the
/// sketch runs.
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
            Hairline(palette: palette)
            MonitorCostRow(stats: stats)
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

/// The cell grid: FPS and Canvas, one cell per drawing path the sketch uses
/// (SDF instances, triangle vertices, point splats, GPU particles), then the
/// Draws · Passes · Batches counts, each its own value-over-label cell so no
/// readout joins several numbers and truncates. Cells fill hairline-separated
/// rows four at a time, the last row taking the remainder (eight cells run
/// 4+4, seven run 4+3), so a path-heavy sketch grows a row rather than
/// squeezing. A path's cell stays once it has appeared: a simulation whose
/// particle count dips to zero for a frame must not reshuffle the grid. The
/// set clears when the frame counter restarts (a reload).
///
/// Every cell ticks with the live `FrameStats`, so it reads the object directly
/// rather than threading scalars through; per-property observation still
/// re-renders only on a change. No time appears here: milliseconds belong to
/// the cost bars below, so a number is never shown twice.
private struct MonitorStatStrip: View {
    let stats: FrameStats

    @SwiftUI.Environment(\.colorScheme) private var scheme
    private var palette: OllinInspector.Palette { .resolve(scheme) }

    /// The drawing paths whose cells have earned a place this run (see above).
    @State private var seenPaths: Set<GeometryPath> = []

    private enum GeometryPath: CaseIterable {
        case sdf, tri, pts, particles
    }

    private var canvasLabel: String {
        let w = Int(stats.canvasWidth.rounded()), h = Int(stats.canvasHeight.rounded())
        guard w > 0, h > 0 else { return noReadingYet }
        return w == h ? "\(w)²" : "\(w)×\(h)"
    }

    private func count(of path: GeometryPath) -> Int {
        switch path {
        case .sdf: stats.sdfCount
        case .tri: stats.vertexCount
        case .pts: stats.pointCount
        case .particles: stats.particleCount
        }
    }

    private func cell(for path: GeometryPath) -> FactCell {
        func detail(_ n: Int, _ one: String, _ many: String) -> String {
            (n == 1 ? "1 \(one)" : "\(n) \(many)") + " this frame."
        }
        let n = count(of: path)
        return switch path {
        case .sdf:
            FactCell(value: compactCount(n, hasData: stats.hasData), label: "SDF",
                     detail: detail(n, "instanced SDF shape", "instanced SDF shapes"))
        case .tri:
            FactCell(value: compactCount(n, hasData: stats.hasData), label: "Tri",
                     detail: detail(n, "tessellated triangle vertex", "tessellated triangle vertices"))
        case .pts:
            FactCell(value: compactCount(n, hasData: stats.hasData), label: "Pts",
                     detail: detail(n, "3D point-cloud splat", "3D point-cloud splats"))
        case .particles:
            FactCell(value: compactCount(n, hasData: stats.hasData), label: "Particles",
                     detail: detail(n, "GPU particle", "GPU particles"))
        }
    }

    private var drawDetail: String {
        let p = stats.profile
        var parts: [String] = []
        func add(_ n: Int, _ name: String) { if n > 0 { parts.append("\(n) \(name)") } }
        add(p.sdfInstances, "instanced SDF shapes")
        add(p.triangleVertices, "fill vertices")
        add(p.fringeVertices, "stroke vertices")
        add(p.meshVertices, "mesh vertices")
        add(p.glyphVertices, "glyph vertices")
        add(p.imageVertices, "image vertices")
        add(p.fieldQuads, "SDF fields")
        add(p.pointSplats, "point splats")
        add(p.particles, "particles")
        add(p.clipVertices, "clip vertices")
        add(p.computeDispatches, "compute dispatches")
        let body = parts.isEmpty ? "nothing" : parts.joined(separator: ", ")
        return "\(p.drawCalls) draw calls carrying \(body)."
    }

    private var passDetail: String {
        "\(stats.profile.passes) render passes: the canvas and the present, plus every "
            + "effects layer, filter, shadow map, and probe bake the frame asked for."
    }

    private var batchDetail: String {
        "\(stats.profile.batches) recorded runs. A run breaks whenever the pipeline, blend mode, "
            + "texture, or clip level changes, so many runs against few shapes means state is "
            + "changing per shape."
    }

    /// One submitted-work cell. The label follows the count into the singular,
    /// so a frame with one of something does not read "1 draws".
    private func countCell(_ count: Int, _ one: String, _ many: String,
                           detail: String) -> FactCell {
        FactCell(value: compactCount(count, hasData: stats.hasData),
                 label: count == 1 ? one : many, detail: detail)
    }

    /// The grid's cells for this tick: the two fixed facts, the active paths in
    /// a fixed order, then the three counts. With no path yet, one placeholder
    /// Geometry cell keeps the grid from reading as though the sketch draws
    /// nothing.
    private var cells: [FactCell] {
        var cells = [
            FactCell(value: stats.hasData ? String(format: "%.0f", stats.fps) : noReadingYet,
                     label: "FPS", valueColor: OllinInspector.green),
            FactCell(value: canvasLabel, label: "Canvas"),
        ]
        let active = GeometryPath.allCases.filter { seenPaths.contains($0) || count(of: $0) > 0 }
        if active.isEmpty {
            cells.append(FactCell(
                value: stats.hasData ? "0" : noReadingYet, label: "Geometry",
                detail: "Geometry this frame: nothing yet on any drawing path "
                    + "(SDF shapes, triangle vertices, point-cloud splats, GPU particles)."))
        } else {
            cells.append(contentsOf: active.map(cell(for:)))
        }
        cells.append(countCell(stats.profile.drawCalls, "Draw", "Draws", detail: drawDetail))
        cells.append(countCell(stats.profile.passes, "Pass", "Passes", detail: passDetail))
        cells.append(countCell(stats.profile.batches, "Batch", "Batches", detail: batchDetail))
        return cells
    }

    /// The cells filled into rows of four, the last row taking the remainder
    /// (eight cells run 4+4, seven run 4+3), each row sharing its width equally.
    private var rows: [[FactCell]] {
        let cells = cells
        return stride(from: 0, to: cells.count, by: 4).map {
            Array(cells[$0 ..< min($0 + 4, cells.count)])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            let rows = rows
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Hairline(palette: palette) }
                HStack(spacing: 0) {
                    ForEach(row) { cell in
                        if cell.id != row.first?.id {
                            Hairline(palette: palette, axis: .vertical)
                        }
                        MonitorFactCell(cell: cell, palette: palette)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: stats.frameCount) { previous, current in
            if current < previous { seenPaths.removeAll() }
            let active = GeometryPath.allCases.filter { count(of: $0) > 0 }
            if !seenPaths.isSuperset(of: active) { seenPaths.formUnion(active) }
        }
    }
}

/// A count shortened past a thousand (31k, 1M) so a busy frame keeps its cell.
private func compactCount(_ n: Int, hasData: Bool) -> String {
    guard hasData else { return noReadingYet }
    if n >= 1_000_000 { return "\(n / 1_000_000)M" }
    if n >= 1_000 { return "\(n / 1_000)k" }
    return "\(n)"
}

/// One fact for the cell rows: a value over its label, an optional accent
/// color, and an optional hover explanation. Identified by the label, which is
/// unique across the card.
private struct FactCell: Identifiable {
    let value: String
    let label: String
    var valueColor: SwiftUI.Color = .primary
    var detail: String?
    var id: String { label }
}

/// The shared cell: a monospaced value over tiny caps, evenly sharing its row
/// (`maxWidth: .infinity`, even padding) so a short value doesn't strand in an
/// oversized column. Both the fact strip and the counts row are built from it.
private struct MonitorFactCell: View {
    let cell: FactCell
    let palette: OllinInspector.Palette

    var body: some View {
        let content = VStack(spacing: 3) {
            Text(cell.value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(cell.valueColor)
            Text(cell.label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.3)
                .textCase(.uppercase)
                .foregroundStyle(palette.textTertiary)
        }
        .lineLimit(1)
        // Shrink rather than clip when a value outgrows its column;
        // no fixedSize here, or the scale factor can never engage.
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity)
        if let detail = cell.detail {
            content.help(detail)
        } else {
            content
        }
    }
}

// MARK: - Cost row

/// The "no reading yet" placeholder the card already shows before the first
/// frame. Spelled as an escape so the source carries no em dash while the UI
/// keeps the glyph the rest of the card uses.
private let noReadingYet = "\u{2014}"

/// The profiler tier of the card: two bars answering "which side is the frame
/// waiting on". This is the one place milliseconds appear on the card, so the
/// cell grid above never repeats a number the bars already carry.
///
/// The bars are drawn against the same scale, the frame's own period, so their
/// lengths can be compared by eye: the longer one is the bottleneck, and a short
/// pair means the sketch has headroom. They are deliberately *not* stacked into
/// one bar, since the CPU builds frame N while the GPU is still drawing N-1, and
/// a stack would read as though the two times added up.
private struct MonitorCostRow: View {
    let stats: FrameStats

    @SwiftUI.Environment(\.colorScheme) private var scheme
    private var palette: OllinInspector.Palette { .resolve(scheme) }

    /// The frame period the bars are scaled against. It never rounds below the
    /// numbers it has to hold, so a bar cannot overflow its track.
    private var budgetMS: Double {
        let period = stats.fps > 0 ? 1000 / stats.fps : 16.7
        return max(period, stats.profile.cpuMS, stats.profile.gpuMS, 1)
    }

    private func ms(_ value: Double) -> String {
        stats.hasData ? String(format: "%.1f", value) : noReadingYet
    }

    private var cpuDetail: String {
        let p = stats.profile
        return String(format: """
            CPU: %.2f ms drawing (your sketch, including tessellation) \
            + %.2f ms encoding the GPU commands.
            Waiting for the display: %.2f ms, which is headroom rather than work.
            """, p.cpuDrawMS, p.cpuEncodeMS, p.waitMS)
    }

    private var gpuDetail: String {
        String(format: """
            GPU: %.2f ms of a %.1f ms frame. Measured from the device's own \
            timestamps, one frame behind, so it lags a sudden change by a frame.
            """, stats.profile.gpuMS, budgetMS)
    }

    var body: some View {
        VStack(spacing: 7) {
            costBar(icon: "cpu", value: stats.profile.cpuMS,
                    tint: OllinInspector.accent, label: "CPU")
                .help(cpuDetail)
            costBar(icon: "memorychip", value: stats.profile.gpuMS,
                    tint: OllinInspector.green, label: "GPU")
                .help(gpuDetail)
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 10)
    }

    /// One labeled bar: icon and name, a track filled to the share of the frame
    /// this side took, and the number in milliseconds.
    private func costBar(icon: String, value: Double,
                         tint: SwiftUI.Color, label: String) -> some View {
        HStack(spacing: 6) {
            SwiftUI.Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 13)
                .accessibilityHidden(true)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 24, alignment: .leading)
            GeometryReader { geo in
                let fraction = stats.hasData ? min(1, max(0, value / budgetMS)) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.fieldFill)
                    Capsule().fill(tint).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 5)
            Text(ms(value))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 30, alignment: .trailing)
            Text("ms")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
    }

}

// MARK: - Parameters

/// The parameter groups: for each group a header over a card of control rows,
/// or an empty state when the sketch declares no `@Param` knobs. The control in
/// each row follows the parameter's type (slider, stepper, toggle, menu, color
/// well); `@Param(group:)` names a section, and knobs without one lead under
/// the default "Parameters" header. `onChange` reports edits (as the param's
/// persistable `ParamStored`) so a host can carry them across reloads; the row
/// writes the value into the live `Param` regardless, so a standalone panel
/// can leave it a no-op and still tune live.
public struct ParametersListView: View {
    let params: [ParamHandle]
    let onChange: (String, ParamStored) -> Void

    @SwiftUI.Environment(\.colorScheme) private var scheme

    /// The rows whose show-rule currently fails, seeded at init and re-polled by
    /// the body's task, so a rule flipping mid-run moves the list.
    @State private var hiddenIDs: Set<String>

    public init(params: [ParamHandle], onChange: @escaping (String, ParamStored) -> Void = { _, _ in }) {
        self.params = params
        self.onChange = onChange
        _hiddenIDs = State(initialValue: Self.hiddenIDs(in: params))
    }

    private var palette: OllinInspector.Palette { .resolve(scheme) }

    /// The ids of the rows whose `show(when:_:)` rule currently fails.
    package nonisolated static func hiddenIDs(in params: [ParamHandle]) -> Set<String> {
        Set(params.lazy.filter { !$0.isShown }.map(\.id))
    }

    /// The handles split into sections with the hidden rows left out: the
    /// ungrouped knobs first (under the default header), then each named group
    /// in order of first declaration. A group whose rows are all hidden drops
    /// its whole card. Package-visible so tests can drive the split without a view.
    package nonisolated static func visibleSections(of params: [ParamHandle], hiding hidden: Set<String>)
        -> [(title: String, handles: [ParamHandle])] {
        var order: [String?] = []
        var byGroup: [String?: [ParamHandle]] = [:]
        for handle in params where !hidden.contains(handle.id) {
            if byGroup[handle.group] == nil { order.append(handle.group) }
            byGroup[handle.group, default: []].append(handle)
        }
        if let i = order.firstIndex(of: nil), i != 0 {
            order.remove(at: i)
            order.insert(nil, at: 0)
        }
        return order.map { ($0 ?? "Parameters", byGroup[$0]!) }
    }

    private var sections: [(title: String, handles: [ParamHandle])] {
        Self.visibleSections(of: params, hiding: hiddenIDs)
    }

    public var body: some View {
        if params.isEmpty {
            section(title: "Parameters") { emptyState }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(sections, id: \.title) { group in
                    section(title: group.title) { card(for: group.handles) }
                }
            }
            // The visibility poll, on the rows' own 100ms sync-pull cadence.
            // Keyed on the handle identities so a reload's fresh params restart
            // it (the old task would keep reading the swapped-out sketch's knobs).
            .task(id: params.map { ObjectIdentifier($0.param) }) {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    let hidden = Self.hiddenIDs(in: params)
                    if hidden != hiddenIDs { hiddenIDs = hidden }
                }
            }
        }
    }

    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 4)
                .padding(.bottom, 7)

            content()
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private func card(for handles: [ParamHandle]) -> some View {
        // If any row in the card carries an icon, every row reserves the icon
        // gutter so the labels stay aligned down the card.
        let gutter = handles.contains { $0.icon != nil }
        return VStack(spacing: 0) {
            ForEach(Array(handles.enumerated()), id: \.element.id) { index, handle in
                if index > 0 { Hairline(palette: palette) }
                ParamRow(handle: handle, palette: palette, iconGutter: gutter,
                         onChange: { onChange(handle.name, $0) })
                    .id(ObjectIdentifier(handle.param))   // reset state on reload
            }
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

/// One parameter row, dispatched on the control kind the value type implies.
private struct ParamRow: View {
    let handle: ParamHandle
    let palette: OllinInspector.Palette
    let iconGutter: Bool
    let onChange: (ParamStored) -> Void

    var body: some View {
        switch handle.control {
        case .slider(let control):
            SliderParamRow(handle: handle, control: control, palette: palette,
                           iconGutter: iconGutter, onChange: onChange)
        case .stepper(let control):
            StepperParamRow(handle: handle, control: control, palette: palette,
                            iconGutter: iconGutter, onChange: onChange)
        case .toggle(let control):
            ToggleParamRow(handle: handle, control: control, palette: palette,
                           iconGutter: iconGutter, onChange: onChange)
        case .menu(let control):
            MenuParamRow(handle: handle, control: control, palette: palette,
                         iconGutter: iconGutter, onChange: onChange)
        case .colorWell(let control):
            ColorParamRow(handle: handle, control: control, palette: palette,
                          iconGutter: iconGutter, onChange: onChange)
        case .vector(let control):
            VectorParamRow(handle: handle, control: control, palette: palette,
                           iconGutter: iconGutter, onChange: onChange)
        case .vector3(let control):
            Vector3ParamRow(handle: handle, control: control, palette: palette,
                            iconGutter: iconGutter, onChange: onChange)
        case .rectangle(let control):
            RectangleParamRow(handle: handle, control: control, palette: palette,
                              iconGutter: iconGutter, onChange: onChange)
        case .insets(let control):
            InsetsParamRow(handle: handle, control: control, palette: palette,
                           iconGutter: iconGutter, onChange: onChange)
        case .range(let control):
            RangeParamRow(handle: handle, control: control, palette: palette,
                          iconGutter: iconGutter, onChange: onChange)
        case .text(let control):
            TextParamRow(handle: handle, control: control, palette: palette,
                         iconGutter: iconGutter, onChange: onChange)
        }
    }
}

/// Whole numbers over a wide (pixel-sized) range, decimals over a narrow one.
private func paramFieldDigits(for range: ClosedRange<Double>) -> Int {
    range.upperBound - range.lowerBound > 20 ? 0 : 2
}

/// The leading label of a row: the optional SF Symbol icon (or its reserved
/// gutter, so labels align down a card that mixes both) and the display name.
private struct ParamRowLabel: View {
    let handle: ParamHandle
    let palette: OllinInspector.Palette
    let iconGutter: Bool

    var body: some View {
        HStack(spacing: 7) {
            if let icon = handle.icon {
                SwiftUI.Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 18)
            } else if iconGutter {
                SwiftUI.Color.clear.frame(width: 18, height: 1)
            }
            Text(handle.label)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
    }
}

/// An editable mono value pill that also *scrubs*: drag horizontally across it
/// to change the value (hold Option for a fine adjust, Shift for a coarse one),
/// or click once to type. The pill shows the resize cursor so the drag invites
/// itself; a value committed by typing is clamped by the row.
///
/// While the field is being scrubbed or has keyboard focus it flips
/// `isInteracting` so the owning row parks its sync pull.
private struct ScrubbableField: View {
    @Binding var value: Double
    let fractionDigits: Int
    /// Value change per dragged point at normal speed.
    let perPoint: Double
    /// Snap scrubbed values to multiples of this (from `snapOrigin`), if given.
    let snap: Double?
    let snapOrigin: Double
    let range: ClosedRange<Double>
    @Binding var isInteracting: Bool
    let palette: OllinInspector.Palette
    /// A tiny leading tag inside the pill (the "x"/"y" of a vector field).
    var prefix: String? = nil

    /// The value under the pointer when the scrub began; nil while not scrubbing.
    @State private var scrubBase: Double?
    @FocusState private var isTyping: Bool

    var body: some View {
        HStack(spacing: 4) {
            if let prefix {
                Text(prefix)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    // Pinned, or the paired-pill row's tight HStack compresses
                    // this (the only flexible child) to zero width and the tag
                    // silently vanishes; the fields hold their floor either way.
                    .fixedSize()
            }
            TextField("", value: $value, format: .number.precision(.fractionLength(fractionDigits)))
                .textFieldStyle(.plain)
                .focused($isTyping)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 12, design: .monospaced))
                // Hug the number (don't stretch across the row) so the pill is
                // compact and content-sized, matching the design's value field.
                .fixedSize(horizontal: true, vertical: false)
                // A floor so short values stay ~uniform; the prefixed (paired)
                // pills take a smaller one since the tag shares their row.
                .frame(minWidth: prefix == nil ? 42 : 34, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(palette.fieldFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
            .strokeBorder(palette.fieldStroke, lineWidth: 0.5))
        .overlay { if !isTyping { scrubSurface } }
        .onChange(of: isTyping) { _, typing in isInteracting = typing || scrubBase != nil }
    }

    /// The transparent layer that owns the drag. It sits over the text field
    /// until the field has focus, so a plain click falls through to typing (the
    /// tap gesture hands focus over) while any horizontal drag scrubs.
    private var scrubSurface: some View {
        SwiftUI.Color.clear
            .contentShape(SwiftUI.Rectangle())
            .pointerStyle(.columnResize)
            .onTapGesture { isTyping = true }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { drag in
                        if scrubBase == nil {
                            scrubBase = value
                            isInteracting = true
                        }
                        guard let base = scrubBase else { return }
                        // Option refines the drag, Shift accelerates it.
                        let flags = NSEvent.modifierFlags
                        let gain = flags.contains(.option) ? 0.1 : flags.contains(.shift) ? 10.0 : 1.0
                        var v = base + drag.translation.width * perPoint * gain
                        if let snap, snap > 0 {
                            v = snapOrigin + ((v - snapOrigin) / snap).rounded() * snap
                        }
                        value = Swift.min(Swift.max(v, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        scrubBase = nil
                        isInteracting = isTyping
                    }
            )
    }
}

/// The XY pad: a square area mapped to a `Vector2` param's two ranges, with
/// the top-left corner at both lower bounds (matching the canvas's top-left
/// origin). Drag anywhere and the dot jumps to the pointer; a crosshair tracks
/// the dot so its alignment reads against the pad edges.
private struct ParamXYPad: View {
    @Binding var x: Double
    @Binding var y: Double
    let xRange: ClosedRange<Double>
    let yRange: ClosedRange<Double>
    @Binding var isInteracting: Bool
    let palette: OllinInspector.Palette

    private static let dotRadius: CGFloat = 6
    /// The dot's travel keeps this far off every edge, so it never clips.
    private static let inset: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let dot = dotPosition(in: geo.size)
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.fieldFill)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(palette.fieldStroke, lineWidth: 0.5)
                // The crosshair through the dot, clipped to the pad.
                SwiftUI.Path { path in
                    path.move(to: CGPoint(x: dot.x, y: 0))
                    path.addLine(to: CGPoint(x: dot.x, y: geo.size.height))
                    path.move(to: CGPoint(x: 0, y: dot.y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: dot.y))
                }
                .stroke(palette.separator, lineWidth: 1)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                SwiftUI.Circle()
                    .fill(OllinInspector.accent)
                    .overlay(SwiftUI.Circle().strokeBorder(SwiftUI.Color.white.opacity(0.85), lineWidth: 1))
                    .frame(width: Self.dotRadius * 2, height: Self.dotRadius * 2)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .position(dot)
            }
            .contentShape(SwiftUI.Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isInteracting = true
                        setValue(for: drag.location, in: geo.size)
                    }
                    .onEnded { _ in isInteracting = false }
            )
        }
        .frame(height: 116)
    }

    private func travel(_ size: CGSize) -> CGSize {
        CGSize(width: max(size.width - Self.inset * 2, 1),
               height: max(size.height - Self.inset * 2, 1))
    }

    private func dotPosition(in size: CGSize) -> CGPoint {
        let area = travel(size)
        let tx = (x - xRange.lowerBound) / max(xRange.upperBound - xRange.lowerBound, .ulpOfOne)
        let ty = (y - yRange.lowerBound) / max(yRange.upperBound - yRange.lowerBound, .ulpOfOne)
        return CGPoint(x: Self.inset + CGFloat(tx) * area.width,
                       y: Self.inset + CGFloat(ty) * area.height)
    }

    private func setValue(for location: CGPoint, in size: CGSize) {
        let area = travel(size)
        let tx = Double((location.x - Self.inset) / area.width)
        let ty = Double((location.y - Self.inset) / area.height)
        let clampedX = Swift.min(Swift.max(tx, 0), 1)
        let clampedY = Swift.min(Swift.max(ty, 0), 1)
        x = xRange.lowerBound + clampedX * (xRange.upperBound - xRange.lowerBound)
        y = yRange.lowerBound + clampedY * (yRange.upperBound - yRange.lowerBound)
    }
}

/// The two-thumb slider: a track over the outer bounds with a tinted span
/// between the min and max thumbs. A drag grabs the nearest thumb and keeps it
/// for the whole gesture, stopping at the other thumb rather than crossing it.
private struct ParamRangeSlider: View {
    @Binding var lower: Double
    @Binding var upper: Double
    let outer: ClosedRange<Double>
    @Binding var isInteracting: Bool
    let palette: OllinInspector.Palette

    private enum Thumb { case lower, upper }
    /// The thumb grabbed at the start of the current drag, held so a fast drag
    /// past the other thumb never swaps hands mid-gesture.
    @State private var activeThumb: Thumb?

    private static let thumbRadius: CGFloat = 6.5
    private static let trackHeight: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let lowerX = position(of: lower, width: width)
            let upperX = position(of: upper, width: width)
            let midY = geo.size.height / 2
            ZStack {
                Capsule()
                    .fill(palette.fieldFill)
                    .overlay(Capsule().strokeBorder(palette.fieldStroke, lineWidth: 0.5))
                    .frame(height: Self.trackHeight)
                Capsule()
                    .fill(OllinInspector.accent)
                    .frame(width: max(upperX - lowerX, Self.trackHeight), height: Self.trackHeight)
                    .position(x: (lowerX + upperX) / 2, y: midY)
                thumb.position(x: lowerX, y: midY)
                thumb.position(x: upperX, y: midY)
            }
            .contentShape(SwiftUI.Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isInteracting = true
                        if activeThumb == nil {
                            activeThumb = abs(drag.startLocation.x - lowerX) <=
                                abs(drag.startLocation.x - upperX) ? .lower : .upper
                        }
                        let value = self.value(at: drag.location.x, width: width)
                        switch activeThumb {
                        case .lower: lower = Swift.min(value, upper)
                        case .upper: upper = Swift.max(value, lower)
                        case nil: break
                        }
                    }
                    .onEnded { _ in
                        activeThumb = nil
                        isInteracting = false
                    }
            )
        }
        .frame(height: 20)
    }

    private var thumb: some View {
        SwiftUI.Circle()
            .fill(SwiftUI.Color.white)
            .frame(width: Self.thumbRadius * 2, height: Self.thumbRadius * 2)
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
    }

    private func position(of value: Double, width: CGFloat) -> CGFloat {
        let span = max(outer.upperBound - outer.lowerBound, .ulpOfOne)
        let travel = width - Self.thumbRadius * 2
        return Self.thumbRadius + CGFloat((value - outer.lowerBound) / span) * travel
    }

    private func value(at x: CGFloat, width: CGFloat) -> Double {
        let travel = max(width - Self.thumbRadius * 2, 1)
        let t = Double((x - Self.thumbRadius) / travel)
        return outer.lowerBound + Swift.min(Swift.max(t, 0), 1) * (outer.upperBound - outer.lowerBound)
    }
}

/// A labeled slider: icon + label and the scrubbable value pill on top, a thin
/// tinted slider below. Local state drives smooth dragging and the readout; a
/// user edit is written into the live `Param` and reported to `onChange`.
///
/// The row is not the param's only writer (a MIDI/OSC binding, a smoothing
/// glide, or the sketch itself may drive the same knob) so it also *follows*:
/// a ~10 Hz pull (the stats cadence) reflects the live value back into the
/// thumb and pill, paused while the user is dragging, scrubbing, or typing.
private struct SliderParamRow: View {
    let handle: ParamHandle
    let control: ParamControl.Slider
    let palette: OllinInspector.Palette
    let iconGutter: Bool
    let onChange: (ParamStored) -> Void

    @State private var value: Double
    /// The last value this row knows the param to hold: seeded at init, updated
    /// by every sync pull and user edit. `onChange(of: value)` compares against
    /// it to tell a sync echo (skip) from a real user edit (write + record).
    @State private var lastKnown: Double
    /// True while the slider thumb is held; parks the sync pull.
    @State private var isDragging = false
    /// True while the value pill is scrubbed or typed in; parks the sync pull.
    @State private var isEditingField = false

    init(handle: ParamHandle, control: ParamControl.Slider, palette: OllinInspector.Palette,
         iconGutter: Bool, onChange: @escaping (ParamStored) -> Void) {
        self.handle = handle
        self.control = control
        self.palette = palette
        self.iconGutter = iconGutter
        self.onChange = onChange
        let current = control.get()
        _value = State(initialValue: current)
        _lastKnown = State(initialValue: current)
    }

    var body: some View {
        layout
        .onChange(of: value) { _, newValue in
            guard newValue != lastKnown else { return }   // the sync pull's own echo
            // A typed value can land outside the range (the slider and scrub
            // can't); the param also snaps to any step. Write, then read back
            // the value the param actually holds, so the pill, the param, and
            // the host's persisted record all agree.
            control.set(newValue)
            let actual = control.get()
            if actual != newValue { value = actual }
            lastKnown = actual
            onChange(.number(actual))
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !isDragging, !isEditingField else { continue }
                let live = control.get()
                if live != value {
                    lastKnown = live
                    value = live
                }
            }
        }
    }

    /// `.slider` is the two-line row (label + pill over the track); `.field`
    /// drops the track and reads as a single-line control row.
    @ViewBuilder private var layout: some View {
        if control.style == .field {
            ControlRow(handle: handle, palette: palette, iconGutter: iconGutter) {
                valueField
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ParamRowLabel(handle: handle, palette: palette, iconGutter: iconGutter)
                    Spacer()
                    valueField
                }
                slider
                    .controlSize(.small)
                    .tint(OllinInspector.accent)
                    // The native slider carries internal vertical inset; trim it so the
                    // track-to-separator gap matches the pill's top gap (balanced row).
                    // The -3 is tied to AppKit's private metrics; re-verify the row
                    // spacing on each macOS major.
                    .padding(.vertical, -3)
            }
            .padding(.horizontal, 12)
            .padding(.top, 11)
            .padding(.bottom, 11)
        }
    }

    private var valueField: some View {
        ScrubbableField(
            value: $value, fractionDigits: 2,
            perPoint: (control.range.upperBound - control.range.lowerBound) / 250,
            snap: control.step, snapOrigin: control.range.lowerBound,
            range: control.range, isInteracting: $isEditingField, palette: palette)
    }

    @ViewBuilder private var slider: some View {
        if let step = control.step, step > 0 {
            Slider(value: $value, in: control.range, step: step) { isDragging = $0 }
        } else {
            Slider(value: $value, in: control.range) { isDragging = $0 }
        }
    }
}

/// Shared chrome for the single-line rows (stepper, toggle, menu, color): the
/// leading label, a spacer, and the trailing control.
private struct ControlRow<Control: View>: View {
    let handle: ParamHandle
    let palette: OllinInspector.Palette
    let iconGutter: Bool
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack {
            ParamRowLabel(handle: handle, palette: palette, iconGutter: iconGutter)
            // A floor on the gap so a wide control never crowds the label.
            Spacer(minLength: 16)
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 38)
    }
}

/// An `Int` row: a scrubbable value cell between minus/plus buttons.
private struct StepperParamRow: View {
    let handle: ParamHandle
    let control: ParamControl.Stepper
    let palette: OllinInspector.Palette
    let iconGutter: Bool
    let onChange: (ParamStored) -> Void

    @State private var value: Double
    @State private var lastKnown: Double
    @State private var isEditingField = false

    init(handle: ParamHandle, control: ParamControl.Stepper, palette: OllinInspector.Palette,
         iconGutter: Bool, onChange: @escaping (ParamStored) -> Void) {
        self.handle = handle
        self.control = control
        self.palette = palette
        self.iconGutter = iconGutter
        self.onChange = onChange
        let current = Double(control.get())
        _value = State(initialValue: current)
        _lastKnown = State(initialValue: current)
    }

    private var doubleRange: ClosedRange<Double> {
        Double(control.range.lowerBound)...Double(control.range.upperBound)
    }

    var body: some View {
        ControlRow(handle: handle, palette: palette, iconGutter: iconGutter) {
            HStack(spacing: 2) {
                stepButton("minus", by: -control.step, disabled: Int(value) <= control.range.lowerBound)
                ScrubbableField(
                    value: $value, fractionDigits: 0,
                    perPoint: Double(control.step) / 8,   // ~8 points of drag per step
                    snap: Double(control.step), snapOrigin: Double(control.range.lowerBound),
                    range: doubleRange, isInteracting: $isEditingField, palette: palette)
                stepButton("plus", by: control.step, disabled: Int(value) >= control.range.upperBound)
            }
        }
        .onChange(of: value) { _, newValue in
            guard newValue != lastKnown else { return }
            control.set(Int(newValue.rounded()))
            let actual = Double(control.get())
            if actual != newValue { value = actual }
            lastKnown = actual
            onChange(.number(actual))
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !isEditingField else { continue }
                let live = Double(control.get())
                if live != value {
                    lastKnown = live
                    value = live
                }
            }
        }
    }

    private func stepButton(_ symbol: String, by delta: Int, disabled: Bool) -> some View {
        Button {
            value = Swift.min(Swift.max(value + Double(delta), doubleRange.lowerBound),
                              doubleRange.upperBound)
        } label: {
            SwiftUI.Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(disabled ? palette.textTertiary : .secondary)
                .frame(width: 20, height: 20)
                .background(palette.fieldFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(palette.fieldStroke, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// A `Bool` row: an on/off switch.
private struct ToggleParamRow: View {
    let handle: ParamHandle
    let control: ParamControl.Toggle
    let palette: OllinInspector.Palette
    let iconGutter: Bool
    let onChange: (ParamStored) -> Void

    @State private var isOn: Bool

    init(handle: ParamHandle, control: ParamControl.Toggle, palette: OllinInspector.Palette,
         iconGutter: Bool, onChange: @escaping (ParamStored) -> Void) {
        self.handle = handle
        self.control = control
        self.palette = palette
        self.iconGutter = iconGutter
        self.onChange = onChange
        _isOn = State(initialValue: control.get())
    }

    var body: some View {
        ControlRow(handle: handle, palette: palette, iconGutter: iconGutter) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(OllinInspector.accent)
        }
        .onChange(of: isOn) { _, newValue in
            guard newValue != control.get() else { return }
            control.set(newValue)
            onChange(.boolean(newValue))
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                let live = control.get()
                if live != isOn { isOn = live }
            }
        }
    }
}

/// An enum row: a pop-up menu over the type's cases.
private struct MenuParamRow: View {
    let handle: ParamHandle
    let control: ParamControl.Menu
    let palette: OllinInspector.Palette
    let iconGutter: Bool
    let onChange: (ParamStored) -> Void

    @State private var selection: Int

    init(handle: ParamHandle, control: ParamControl.Menu, palette: OllinInspector.Palette,
         iconGutter: Bool, onChange: @escaping (ParamStored) -> Void) {
        self.handle = handle
        self.control = control
        self.palette = palette
        self.iconGutter = iconGutter
        self.onChange = onChange
        _selection = State(initialValue: control.get())
    }

    var body: some View {
        layout
        .onChange(of: selection) { _, newValue in
            guard newValue != control.get() else { return }
            control.set(newValue)
            // Report what the param now holds (the case name, not the index).
            onChange(handle.param.stored)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                let live = control.get()
                if live != selection { selection = live }
            }
        }
    }

    /// `.menu` is a single-line row with a pop-up. `.segmented` stays on one
    /// line while the segments fit beside the label (the label pinned so it
    /// can't silently truncate), else wraps to a full-width control below it.
    @ViewBuilder private var layout: some View {
        if control.style == .segmented {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    ParamRowLabel(handle: handle, palette: palette, iconGutter: iconGutter)
                        .fixedSize()
                    Spacer(minLength: 16)
                    basePicker.pickerStyle(.segmented).fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    ParamRowLabel(handle: handle, palette: palette, iconGutter: iconGutter)
                    basePicker.pickerStyle(.segmented)
                        .frame(maxWidth: .infinity)
                }
                // Pinned leading: ViewThatFits centers a child narrower than
                // the row, which would strand the label off the label column.
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 38)
        } else {
            ControlRow(handle: handle, palette: palette, iconGutter: iconGutter) {
                basePicker.pickerStyle(.menu).fixedSize()
            }
        }
    }

    private var basePicker: some View {
        Picker("", selection: $selection) {
            ForEach(Array(control.options.enumerated()), id: \.offset) { index, name in
                Text(name).tag(index)
            }
        }
        .labelsHidden()
        .controlSize(.small)
    }
}

/// A `Color` row: the native color well (its panel includes the eyedropper).
private struct ColorParamRow: View {
    let handle: ParamHandle
    let control: ParamControl.ColorWell
    let palette: OllinInspector.Palette
    let iconGutter: Bool
    let onChange: (ParamStored) -> Void

    @State private var color: SwiftUI.Color
    /// What the param held when this row last wrote or pulled, so the sync pull
    /// can tell an external change from round-trip drift in the bridge.
    @State private var lastKnown: Color

    init(handle: ParamHandle, control: ParamControl.ColorWell, palette: OllinInspector.Palette,
         iconGutter: Bool, onChange: @escaping (ParamStored) -> Void) {
        self.handle = handle
        self.control = control
        self.palette = palette
        self.iconGutter = iconGutter
        self.onChange = onChange
        let current = control.get()
        _color = State(initialValue: ColorParamRow.swiftUIColor(current))
        _lastKnown = State(initialValue: current)
    }

    var body: some View {
        ControlRow(handle: handle, palette: palette, iconGutter: iconGutter) {
            ColorPicker("", selection: $color, supportsOpacity: true)
                .labelsHidden()
                .controlSize(.small)
        }
        .onChange(of: color) { _, newValue in
            guard let value = ColorParamRow.ollinColor(newValue) else { return }
            guard value != lastKnown else { return }
            control.set(value)
            lastKnown = value
            onChange(handle.param.stored)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                let live = control.get()
                if live != lastKnown {
                    lastKnown = live
                    color = ColorParamRow.swiftUIColor(live)
                }
            }
        }
    }

    private static func swiftUIColor(_ color: Color) -> SwiftUI.Color {
        SwiftUI.Color(.sRGB, red: color.red, green: color.green, blue: color.blue,
                      opacity: color.alpha)
    }

    private static func ollinColor(_ color: SwiftUI.Color) -> Color? {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return Color(red: converted.redComponent, green: converted.greenComponent,
                     blue: converted.blueComponent, alpha: converted.alphaComponent)
    }
}

/// A `Vector2` row: paired x/y scrubbable fields, each over its own range.
private struct VectorParamRow: View {
    let handle: ParamHandle
    let control: ParamControl.Vector
    let palette: OllinInspector.Palette
    let iconGutter: Bool
    let onChange: (ParamStored) -> Void

    @State private var x: Double
    @State private var y: Double
    @State private var lastKnown: Vector2
    @State private var isEditingX = false
    @State private var isEditingY = false

    init(handle: ParamHandle, control: ParamControl.Vector, palette: OllinInspector.Palette,
         iconGutter: Bool, onChange: @escaping (ParamStored) -> Void) {
        self.handle = handle
        self.control = control
        self.palette = palette
        self.iconGutter = iconGutter
        self.onChange = onChange
        let current = control.get()
        _x = State(initialValue: current.x)
        _y = State(initialValue: current.y)
        _lastKnown = State(initialValue: current)
    }

    /// True while the XY pad is being dragged; parks the sync pull.
    @State private var isPadding = false

    var body: some View {
        layout
        .onChange(of: x) { _, _ in push() }
        .onChange(of: y) { _, _ in push() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !isEditingX, !isEditingY, !isPadding else { continue }
                let live = control.get()
                if live != lastKnown {
                    lastKnown = live
                    x = live.x
                    y = live.y
                }
            }
        }
    }

    /// `.fields` is the single-line pair; `.pad` stacks the drag pad under it.
    @ViewBuilder private var layout: some View {
        if control.style == .pad {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ParamRowLabel(handle: handle, palette: palette, iconGutter: iconGutter)
                    Spacer(minLength: 16)
                    fields
                }
                ParamXYPad(x: $x, y: $y, xRange: control.xRange, yRange: control.yRange,
                           isInteracting: $isPadding, palette: palette)
            }
            .padding(.horizontal, 12)
            .padding(.top, 11)
            .padding(.bottom, 11)
        } else {
            ControlRow(handle: handle, palette: palette, iconGutter: iconGutter) {
                fields
            }
        }
    }

    private var fields: some View {
        HStack(spacing: 6) {
            ScrubbableField(
                value: $x, fractionDigits: paramFieldDigits(for: control.xRange),
                perPoint: (control.xRange.upperBound - control.xRange.lowerBound) / 250,
                snap: nil, snapOrigin: 0, range: control.xRange,
                isInteracting: $isEditingX, palette: palette, prefix: "x")
            ScrubbableField(
                value: $y, fractionDigits: paramFieldDigits(for: control.yRange),
                perPoint: (control.yRange.upperBound - control.yRange.lowerBound) / 250,
                snap: nil, snapOrigin: 0, range: control.yRange,
                isInteracting: $isEditingY, palette: palette, prefix: "y")
        }
    }

    /// Write the edited pair through the param, read back what it actually
    /// holds (clamped per axis), and reflect + report that.
    private func push() {
        let candidate = Vector2(x, y)
        guard candidate != lastKnown else { return }   // the sync pull's own echo
        control.set(candidate)
        let actual = control.get()
        if actual.x != x { x = actual.x }
        if actual.y != y { y = actual.y }
        lastKnown = actual
        onChange(.vector(x: actual.x, y: actual.y))
    }
}

/// A `Vector3` row: x/y/z scrubbable fields on their own line under the label
/// (three pills don't fit beside it at the sidebar width).
private struct Vector3ParamRow: View {
    let handle: ParamHandle
    let control: ParamControl.VectorXYZ
    let palette: OllinInspector.Palette
    let iconGutter: Bool
    let onChange: (ParamStored) -> Void

    @State private var x: Double
    @State private var y: Double
    @State private var z: Double
    @State private var lastKnown: Vector3
    @State private var isEditingX = false
    @State private var isEditingY = false
    @State private var isEditingZ = false

    init(handle: ParamHandle, control: ParamControl.VectorXYZ, palette: OllinInspector.Palette,
         iconGutter: Bool, onChange: @escaping (ParamStored) -> Void) {
        self.handle = handle
        self.control = control
        self.palette = palette
        self.iconGutter = iconGutter
        self.onChange = onChange
        let current = control.get()
        _x = State(initialValue: current.x)
        _y = State(initialValue: current.y)
        _z = State(initialValue: current.z)
        _lastKnown = State(initialValue: current)
    }

    var body: some View {
        // The first field pair shares the label's line (no orphaned label with
        // dead space beside it); the remainder sits right-aligned below.
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ParamRowLabel(handle: handle, palette: palette, iconGutter: iconGutter)
                Spacer(minLength: 16)
                ScrubbableField(
                    value: $x, fractionDigits: paramFieldDigits(for: control.xRange),
                    perPoint: (control.xRange.upperBound - control.xRange.lowerBound) / 250,
                    snap: nil, snapOrigin: 0, range: control.xRange,
                    isInteracting: $isEditingX, palette: palette, prefix: "x")
                ScrubbableField(
                    value: $y, fractionDigits: paramFieldDigits(for: control.yRange),
                    perPoint: (control.yRange.upperBound - control.yRange.lowerBound) / 250,
                    snap: nil, snapOrigin: 0, range: control.yRange,
                    isInteracting: $isEditingY, palette: palette, prefix: "y")
            }
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                ScrubbableField(
                    value: $z, fractionDigits: paramFieldDigits(for: control.zRange),
                    perPoint: (control.zRange.upperBound - control.zRange.lowerBound) / 250,
                    snap: nil, snapOrigin: 0, range: control.zRange,
                    isInteracting: $isEditingZ, palette: palette, prefix: "z")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 11)
        .onChange(of: x) { _, _ in push() }
        .onChange(of: y) { _, _ in push() }
        .onChange(of: z) { _, _ in push() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !isEditingX, !isEditingY, !isEditingZ else { continue }
                let live = control.get()
                if live != lastKnown {
                    lastKnown = live
                    x = live.x
                    y = live.y
                    z = live.z
                }
            }
        }
    }

    /// Write the edited triple through the param, read back what it actually
    /// holds (clamped per axis), and reflect + report that.
    private func push() {
        let candidate = Vector3(x, y, z)
        guard candidate != lastKnown else { return }   // the sync pull's own echo
        control.set(candidate)
        let actual = control.get()
        if actual.x != x { x = actual.x }
        if actual.y != y { y = actual.y }
        if actual.z != z { z = actual.z }
        lastKnown = actual
        onChange(.vector3(x: actual.x, y: actual.y, z: actual.z))
    }
}

/// A `Rectangle` row: x/y and w/h scrubbable field pairs on their own lines
/// under the label.
private struct RectangleParamRow: View {
    let handle: ParamHandle
    let control: ParamControl.RectangleFields
    let palette: OllinInspector.Palette
    let iconGutter: Bool
    let onChange: (ParamStored) -> Void

    @State private var x: Double
    @State private var y: Double
    @State private var w: Double
    @State private var h: Double
    @State private var lastKnown: Rectangle
    @State private var editing = [false, false, false, false]

    init(handle: ParamHandle, control: ParamControl.RectangleFields, palette: OllinInspector.Palette,
         iconGutter: Bool, onChange: @escaping (ParamStored) -> Void) {
        self.handle = handle
        self.control = control
        self.palette = palette
        self.iconGutter = iconGutter
        self.onChange = onChange
        let current = control.get()
        _x = State(initialValue: current.x)
        _y = State(initialValue: current.y)
        _w = State(initialValue: current.width)
        _h = State(initialValue: current.height)
        _lastKnown = State(initialValue: current)
    }

    var body: some View {
        // x/y ride the label's line, w/h sit right-aligned below (no orphaned
        // label line with dead space beside it).
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ParamRowLabel(handle: handle, palette: palette, iconGutter: iconGutter)
                Spacer(minLength: 16)
                field($x, range: control.xRange, editing: 0, prefix: "x")
                field($y, range: control.yRange, editing: 1, prefix: "y")
            }
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                field($w, range: control.widthRange, editing: 2, prefix: "w")
                field($h, range: control.heightRange, editing: 3, prefix: "h")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 11)
        .onChange(of: x) { _, _ in push() }
        .onChange(of: y) { _, _ in push() }
        .onChange(of: w) { _, _ in push() }
        .onChange(of: h) { _, _ in push() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !editing.contains(true) else { continue }
                let live = control.get()
                if live != lastKnown {
                    lastKnown = live
                    x = live.x
                    y = live.y
                    w = live.width
                    h = live.height
                }
            }
        }
    }

    private func field(_ value: Binding<Double>, range: ClosedRange<Double>,
                       editing index: Int, prefix: String) -> some View {
        ScrubbableField(
            value: value, fractionDigits: paramFieldDigits(for: range),
            perPoint: (range.upperBound - range.lowerBound) / 250,
            snap: nil, snapOrigin: 0, range: range,
            isInteracting: $editing[index], palette: palette, prefix: prefix)
    }

    /// Write the edited region through the param, read back what it actually
    /// holds (clamped per field), and reflect + report that.
    private func push() {
        let candidate = Rectangle(x: x, y: y, width: w, height: h)
        guard candidate != lastKnown else { return }   // the sync pull's own echo
        control.set(candidate)
        let actual = control.get()
        if actual.x != x { x = actual.x }
        if actual.y != y { y = actual.y }
        if actual.width != w { w = actual.width }
        if actual.height != h { h = actual.height }
        lastKnown = actual
        onChange(.rect(x: actual.x, y: actual.y, width: actual.width, height: actual.height))
    }
}

/// An `Insets` row: t/r and b/l scrubbable field pairs on their own lines
/// under the label, all sharing the one per-edge range.
private struct InsetsParamRow: View {
    let handle: ParamHandle
    let control: ParamControl.InsetsFields
    let palette: OllinInspector.Palette
    let iconGutter: Bool
    let onChange: (ParamStored) -> Void

    @State private var top: Double
    @State private var right: Double
    @State private var bottom: Double
    @State private var left: Double
    @State private var lastKnown: Insets
    @State private var editing = [false, false, false, false]

    init(handle: ParamHandle, control: ParamControl.InsetsFields, palette: OllinInspector.Palette,
         iconGutter: Bool, onChange: @escaping (ParamStored) -> Void) {
        self.handle = handle
        self.control = control
        self.palette = palette
        self.iconGutter = iconGutter
        self.onChange = onChange
        let current = control.get()
        _top = State(initialValue: current.top)
        _right = State(initialValue: current.right)
        _bottom = State(initialValue: current.bottom)
        _left = State(initialValue: current.left)
        _lastKnown = State(initialValue: current)
    }

    var body: some View {
        // t/r ride the label's line, b/l sit right-aligned below (no orphaned
        // label line with dead space beside it).
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ParamRowLabel(handle: handle, palette: palette, iconGutter: iconGutter)
                Spacer(minLength: 16)
                field($top, editing: 0, prefix: "t")
                field($right, editing: 1, prefix: "r")
            }
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                field($bottom, editing: 2, prefix: "b")
                field($left, editing: 3, prefix: "l")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 11)
        .onChange(of: top) { _, _ in push() }
        .onChange(of: right) { _, _ in push() }
        .onChange(of: bottom) { _, _ in push() }
        .onChange(of: left) { _, _ in push() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !editing.contains(true) else { continue }
                let live = control.get()
                if live != lastKnown {
                    lastKnown = live
                    top = live.top
                    right = live.right
                    bottom = live.bottom
                    left = live.left
                }
            }
        }
    }

    private func field(_ value: Binding<Double>, editing index: Int, prefix: String) -> some View {
        ScrubbableField(
            value: value, fractionDigits: paramFieldDigits(for: control.edgeRange),
            perPoint: (control.edgeRange.upperBound - control.edgeRange.lowerBound) / 250,
            snap: nil, snapOrigin: 0, range: control.edgeRange,
            isInteracting: $editing[index], palette: palette, prefix: prefix)
    }

    /// Write the edited insets through the param, read back what it actually
    /// holds (clamped per edge), and reflect + report that.
    private func push() {
        let candidate = Insets(top: top, right: right, bottom: bottom, left: left)
        guard candidate != lastKnown else { return }   // the sync pull's own echo
        control.set(candidate)
        let actual = control.get()
        if actual.top != top { top = actual.top }
        if actual.right != right { right = actual.right }
        if actual.bottom != bottom { bottom = actual.bottom }
        if actual.left != left { left = actual.left }
        lastKnown = actual
        onChange(.insets(top: actual.top, right: actual.right,
                         bottom: actual.bottom, left: actual.left))
    }
}

/// A `ClosedRange<Double>` row: paired min/max scrubbable fields. The param
/// keeps the pair ordered, so dragging the minimum past the maximum pushes
/// the maximum along.
private struct RangeParamRow: View {
    let handle: ParamHandle
    let control: ParamControl.RangeFields
    let palette: OllinInspector.Palette
    let iconGutter: Bool
    let onChange: (ParamStored) -> Void

    @State private var lower: Double
    @State private var upper: Double
    @State private var lastKnown: ClosedRange<Double>
    @State private var isEditingLower = false
    @State private var isEditingUpper = false

    init(handle: ParamHandle, control: ParamControl.RangeFields, palette: OllinInspector.Palette,
         iconGutter: Bool, onChange: @escaping (ParamStored) -> Void) {
        self.handle = handle
        self.control = control
        self.palette = palette
        self.iconGutter = iconGutter
        self.onChange = onChange
        let current = control.get()
        _lower = State(initialValue: current.lowerBound)
        _upper = State(initialValue: current.upperBound)
        _lastKnown = State(initialValue: current)
    }

    /// True while a slider thumb is held; parks the sync pull.
    @State private var isSliding = false

    var body: some View {
        layout
        .onChange(of: lower) { _, _ in push() }
        .onChange(of: upper) { _, _ in push() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !isEditingLower, !isEditingUpper, !isSliding else { continue }
                let live = control.get()
                if live != lastKnown {
                    lastKnown = live
                    lower = live.lowerBound
                    upper = live.upperBound
                }
            }
        }
    }

    /// `.slider` (the default) is the two-line row: fields over the two-thumb
    /// track; `.field` keeps just the single-line pair.
    @ViewBuilder private var layout: some View {
        if control.style == .field {
            ControlRow(handle: handle, palette: palette, iconGutter: iconGutter) {
                fields
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ParamRowLabel(handle: handle, palette: palette, iconGutter: iconGutter)
                    Spacer(minLength: 16)
                    fields
                }
                ParamRangeSlider(lower: $lower, upper: $upper, outer: control.outer,
                                 isInteracting: $isSliding, palette: palette)
            }
            .padding(.horizontal, 12)
            .padding(.top, 11)
            .padding(.bottom, 11)
        }
    }

    private var fields: some View {
        HStack(spacing: 6) {
            ScrubbableField(
                value: $lower, fractionDigits: paramFieldDigits(for: control.outer),
                perPoint: (control.outer.upperBound - control.outer.lowerBound) / 250,
                snap: nil, snapOrigin: 0, range: control.outer,
                isInteracting: $isEditingLower, palette: palette, prefix: "min")
            ScrubbableField(
                value: $upper, fractionDigits: paramFieldDigits(for: control.outer),
                perPoint: (control.outer.upperBound - control.outer.lowerBound) / 250,
                snap: nil, snapOrigin: 0, range: control.outer,
                isInteracting: $isEditingUpper, palette: palette, prefix: "max")
        }
    }

    /// Write the edited pair through the param, read back the ordered, clamped
    /// pair it actually holds, and reflect + report that.
    private func push() {
        guard lower != lastKnown.lowerBound || upper != lastKnown.upperBound else { return }
        control.set(Swift.min(lower, upper)...Swift.max(lower, upper))
        let actual = control.get()
        if actual.lowerBound != lower { lower = actual.lowerBound }
        if actual.upperBound != upper { upper = actual.upperBound }
        lastKnown = actual
        onChange(.range(lower: actual.lowerBound, upper: actual.upperBound))
    }
}

/// A `String` row: a free text field in the pill chrome. No scrubbing here;
/// the field commits on return or focus loss.
private struct TextParamRow: View {
    let handle: ParamHandle
    let control: ParamControl.TextBox
    let palette: OllinInspector.Palette
    let iconGutter: Bool
    let onChange: (ParamStored) -> Void

    @State private var text: String
    @FocusState private var isTyping: Bool

    init(handle: ParamHandle, control: ParamControl.TextBox, palette: OllinInspector.Palette,
         iconGutter: Bool, onChange: @escaping (ParamStored) -> Void) {
        self.handle = handle
        self.control = control
        self.palette = palette
        self.iconGutter = iconGutter
        self.onChange = onChange
        _text = State(initialValue: control.get())
    }

    var body: some View {
        ControlRow(handle: handle, palette: palette, iconGutter: iconGutter) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .focused($isTyping)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(maxWidth: 130, alignment: .trailing)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(palette.fieldFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(palette.fieldStroke, lineWidth: 0.5))
        }
        .onChange(of: text) { _, newValue in
            guard newValue != control.get() else { return }
            control.set(newValue)
            onChange(.text(newValue))
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !isTyping else { continue }
                let live = control.get()
                if live != text { text = live }
            }
        }
    }
}
