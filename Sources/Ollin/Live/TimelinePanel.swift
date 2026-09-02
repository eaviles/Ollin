#if os(macOS)
import SwiftUI
import AppKit

// The parameter timeline: a floating, frosted panel with one lane per
// automated parameter. Keys are placed from the parameter rows' diamonds or the
// "+ Track" menu, dragged along their lane, and shaped by the curve that
// leaves them; the playhead scrubs the deterministic clock, so the picture
// follows the drag live. The tracks are the sketch's own `Automation`, and
// they round-trip to the same file `--automation` and every export read.
// Summoned by the live host (the Timeline chip, ⌘T); the gallery stays a
// showcase and does not carry it.

// MARK: - The panel view

/// The panel's root: transport, ruler, lanes, and the footer, over the same
/// frosted scrim the detached inspector wears.
struct TimelinePanelRoot: View {
    let model: TimelineModel

    @SwiftUI.Environment(\.colorScheme) private var scheme

    private var panelScrim: SwiftUI.Color {
        scheme == .dark
            ? SwiftUI.Color(red: 44 / 255, green: 42 / 255, blue: 48 / 255).opacity(OllinInspector.chromeTintOpacity)
            : SwiftUI.Color(red: 246 / 255, green: 246 / 255, blue: 248 / 255).opacity(OllinInspector.chromeTintOpacity)
    }

    var body: some View {
        TimelinePanelView(model: model)
            .background(panelScrim)
            .background(.regularMaterial)
    }
}

struct TimelinePanelView: View {
    let model: TimelineModel

    @SwiftUI.Environment(\.colorScheme) private var scheme

    static let labelWidth: CGFloat = 132
    static let rulerHeight: CGFloat = 24
    static let laneHeight: CGFloat = 34

    var body: some View {
        // Reading the edit counter here is what re-draws the lanes on every
        // key placed or moved: the automation itself lives on the sketch and
        // is not observable on its own. The playhead read keeps the track
        // list fresh across a reload swap, riding the clock tick.
        let _ = model.editCount
        let _ = model.playhead
        let palette = OllinInspector.Palette.resolve(scheme)
        let scale = TimelineModel.Scale(contentDuration: model.contentDuration)
        VStack(spacing: 0) {
            TimelineTransportRow(model: model, palette: palette)
            Hairline(palette: palette)
            HStack(spacing: 0) {
                SwiftUI.Color.clear.frame(width: Self.labelWidth, height: Self.rulerHeight)
                TimelineRulerView(model: model, scale: scale, palette: palette)
                    .frame(height: Self.rulerHeight)
            }
            Hairline(palette: palette)
            if model.automation.tracks.isEmpty {
                emptyLanes(palette)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(model.automation.tracks, id: \.name) { track in
                            HStack(spacing: 0) {
                                TimelineLaneLabel(model: model, track: track, palette: palette)
                                    .frame(width: Self.labelWidth, height: Self.laneHeight)
                                TimelineLaneView(model: model, track: track,
                                                 scale: scale, palette: palette)
                                    .frame(height: Self.laneHeight)
                            }
                            Hairline(palette: palette)
                        }
                    }
                }
            }
            Hairline(palette: palette)
            TimelineFooterRow(model: model, palette: palette)
        }
    }

    private func emptyLanes(_ palette: OllinInspector.Palette) -> some View {
        VStack(spacing: 6) {
            Text("No tracks yet")
                .font(.system(size: 12, weight: .medium))
            Text("Click a parameter's diamond in the inspector, or add a track below, to place a key at the playhead.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }
}

// MARK: - Transport

private struct TimelineTransportRow: View {
    let model: TimelineModel
    let palette: OllinInspector.Palette

    /// The last loop region the ruler was given, so the loop button can bring
    /// it back after being switched off.
    @State private var rememberedRegion: ClosedRange<Double>?

    var body: some View {
        HStack(spacing: 5) {
            TransportButton(systemName: "backward.end") { model.toStart() }
                .help("To the start")
            TransportButton(systemName: "backward.frame") { model.step(byFrames: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .help("Back one frame")
            TransportButton(systemName: model.isPaused ? "play.fill" : "pause.fill",
                            prominent: true) { model.togglePlay() }
                .keyboardShortcut(.space, modifiers: [])
                .help(model.isPaused ? "Play" : "Pause")
            TransportButton(systemName: "forward.frame") { model.step(byFrames: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .help("Forward one frame")
            TransportButton(systemName: "forward.end") { model.toEnd() }
                .help("To the last key")
            TransportButton(systemName: "repeat", active: model.loopRegion != nil) {
                toggleLoop()
            }
            .help("Loop the region (option-drag the ruler to choose one)")
            Spacer(minLength: 12)
            Text("frame \(Int((model.playhead * SketchRunner.clockStepRate).rounded()))")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(OllinInspector.timecode(model.playhead))
                .font(.system(size: 21, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(palette.readout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func toggleLoop() {
        if let region = model.loopRegion {
            rememberedRegion = region
            model.loopRegion = nil
        } else if let remembered = rememberedRegion {
            model.loopRegion = remembered
        } else if model.contentDuration > 0 {
            model.loopRegion = 0...model.contentDuration
        }
    }
}

private struct TransportButton: View {
    let systemName: String
    var prominent = false
    var active = false
    let action: () -> Void

    @SwiftUI.Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = OllinInspector.Palette.resolve(scheme)
        Button(action: action) {
            SwiftUI.Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .semibold))
                .frame(width: prominent ? 40 : 30, height: 25)
                .contentShape(SwiftUI.Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? SwiftUI.Color.white
                         : active ? OllinInspector.accent : .primary)
        .background(prominent ? OllinInspector.accent
                    : active ? OllinInspector.accent.opacity(0.22) : palette.fieldFill,
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(prominent || active ? SwiftUI.Color.clear : palette.fieldStroke,
                          lineWidth: 0.5))
    }
}

// MARK: - Ruler

private struct TimelineRulerView: View {
    let model: TimelineModel
    let scale: TimelineModel.Scale
    let palette: OllinInspector.Palette

    private enum DragMode { case scrub, region(anchor: Double) }
    @State private var dragMode: DragMode?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .contentShape(SwiftUI.Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragMode == nil {
                        dragMode = NSEvent.modifierFlags.contains(.option)
                            ? .region(anchor: scale.time(at: value.startLocation.x, width: width))
                            : .scrub
                    }
                    let time = scale.time(at: value.location.x, width: width)
                    switch dragMode {
                    case .scrub:
                        model.scrub(to: time)
                    case .region(let anchor):
                        let low = min(anchor, time), high = max(anchor, time)
                        if high - low > 0.05 { model.loopRegion = low...high }
                    case nil:
                        break
                    }
                }
                .onEnded { _ in dragMode = nil })
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let width = size.width
        // The loop region first, under everything.
        if let region = model.loopRegion {
            let x0 = scale.x(of: region.lowerBound, width: width)
            let x1 = scale.x(of: region.upperBound, width: width)
            context.fill(SwiftUI.Path(CGRect(x: x0, y: 0, width: x1 - x0, height: size.height)),
                         with: .color(OllinInspector.accent.opacity(0.16)))
            for edge in [x0, x1] {
                context.fill(SwiftUI.Path(CGRect(x: edge - 0.5, y: 0, width: 1, height: size.height)),
                             with: .color(OllinInspector.accent))
            }
        }
        // Ticks: a labeled major each `majorTick`, a short minor at the half.
        let major = scale.majorTick
        var time = 0.0
        while time <= scale.span + 0.0001 {
            let x = scale.x(of: time, width: width)
            context.fill(SwiftUI.Path(CGRect(x: x, y: size.height - 9, width: 0.5, height: 9)),
                         with: .color(palette.textTertiary))
            let half = time + major / 2
            if half < scale.span {
                let hx = scale.x(of: half, width: width)
                context.fill(SwiftUI.Path(CGRect(x: hx, y: size.height - 5, width: 0.5, height: 5)),
                             with: .color(palette.fieldStroke))
            }
            let label = major < 1 ? String(format: "%.1fs", time) : "\(Int(time))s"
            let anchored = time >= scale.span - 0.0001
            context.draw(Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(palette.textTertiary),
                at: CGPoint(x: anchored ? x - 3 : x + 3, y: size.height - 11),
                anchor: anchored ? .bottomTrailing : .bottomLeading)
            time += major
        }
        drawPlayhead(&context, size: size, capped: true)
    }

    private func drawPlayhead(_ context: inout GraphicsContext, size: CGSize, capped: Bool) {
        let x = scale.x(of: model.playhead, width: size.width)
        context.fill(SwiftUI.Path(CGRect(x: x - 0.5, y: 0, width: 1, height: size.height)),
                     with: .color(OllinInspector.accent))
        if capped {
            let cap = CGRect(x: x - 4.5, y: 0, width: 9, height: 9)
            context.fill(SwiftUI.Path(roundedRect: cap, cornerRadius: 2),
                         with: .color(OllinInspector.accent))
        }
    }
}

// MARK: - Lanes

private struct TimelineLaneLabel: View {
    let model: TimelineModel
    let track: Automation.Track
    let palette: OllinInspector.Palette

    var body: some View {
        HStack(spacing: 7) {
            SwiftUI.Image(systemName: "diamond.fill")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(OllinInspector.accent)
            Text(ParamHandle.humanize(track.name))
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if let value = liveValue {
                Text(value)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .contentShape(SwiftUI.Rectangle())
        .contextMenu {
            Button("Remove Track") { model.removeTrack(named: track.name) }
        }
    }

    /// The number the parameter holds right now, for the trailing readout.
    private var liveValue: String? {
        guard let stored = model.sketch?.parameters()
            .first(where: { $0.name == track.name })?.param.stored else { return nil }
        switch stored {
        case .number(let value): return String(format: "%.2f", value)
        case .boolean(let value): return value ? "on" : "off"
        case .option(let name): return name
        default: return nil
        }
    }
}

private struct TimelineLaneView: View {
    let model: TimelineModel
    let track: Automation.Track
    let scale: TimelineModel.Scale
    let palette: OllinInspector.Palette

    /// What a drag on the lane took hold of, decided once at its first change.
    private enum Grab {
        case key(Int)
        case handleOut       // the selected key's own handle
        case handleIn        // the next key's arriving handle
        case scrub
    }
    @State private var grab: Grab?

    private static let handleColor = SwiftUI.Color(red: 0xE8 / 255, green: 0xC6 / 255,
                                                   blue: 0xFB / 255)
    private static let pad: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let plot = TimelineModel.plot(track, span: scale.span)
            Canvas { context, size in
                draw(in: &context, size: size, plot: plot)
            }
            .contentShape(SwiftUI.Rectangle())
            .gesture(SpatialTapGesture(count: 2).onEnded { value in
                if let index = keyIndex(at: value.location, width: width, plot: plot) {
                    model.removeKey(track: track.name, at: index)
                }
            })
            .gesture(SpatialTapGesture().onEnded { value in
                if let index = keyIndex(at: value.location, width: width, plot: plot) {
                    model.selection = .init(track: track.name, index: index)
                } else {
                    model.selection = nil
                }
            })
            .gesture(DragGesture(minimumDistance: 3)
                .onChanged { value in
                    if grab == nil { grab = target(at: value.startLocation, width: width, plot: plot) }
                    let time = scale.time(at: value.location.x, width: width)
                    switch grab {
                    case .key(let index):
                        let landed = model.moveKey(track: track.name, at: index, to: time)
                        grab = .key(landed)
                    case .handleOut, .handleIn:
                        dragHandle(to: value.location, width: width,
                                   height: geo.size.height, plot: plot)
                    case .scrub:
                        model.scrub(to: time)
                    case nil:
                        break
                    }
                }
                .onEnded { _ in grab = nil })
        }
        .allowsHitTesting(!track.isWorkedOut)
    }

    // MARK: Geometry

    private func keyPoint(_ index: Int, width: CGFloat, height: CGFloat,
                          plot: TimelineModel.LanePlot?) -> CGPoint {
        let x = scale.x(of: track.keys[index].time, width: width)
        guard let plot, plot.keyHeights.indices.contains(index) else {
            return CGPoint(x: x, y: height / 2)
        }
        let inner = height - Self.pad * 2
        return CGPoint(x: x, y: Self.pad + (1 - plot.keyHeights[index]) * inner)
    }

    private func keyIndex(at point: CGPoint, width: CGFloat,
                          plot: TimelineModel.LanePlot?) -> Int? {
        let height = TimelinePanelView.laneHeight
        var best: (index: Int, distance: CGFloat)?
        for index in track.keys.indices {
            let keyPoint = keyPoint(index, width: width, height: height, plot: plot)
            let distance = hypot(keyPoint.x - point.x, keyPoint.y - point.y)
            if distance <= 9, distance < (best?.distance ?? .infinity) {
                best = (index, distance)
            }
        }
        return best?.index
    }

    /// The bezier handle points for the selected key, in lane coordinates,
    /// when the selection sits on this track and its curve is a bezier with a
    /// key after it.
    private func handlePoints(width: CGFloat, height: CGFloat,
                              plot: TimelineModel.LanePlot?)
        -> (out: CGPoint, into: CGPoint, from: CGPoint, to: CGPoint)? {
        guard let selection = model.selection, selection.track == track.name,
              track.keys.indices.contains(selection.index),
              selection.index + 1 < track.keys.count,
              case .bezier(let x1, let y1, let x2, let y2)
                = track.keys[selection.index].curve else { return nil }
        let from = keyPoint(selection.index, width: width, height: height, plot: plot)
        let to = keyPoint(selection.index + 1, width: width, height: height, plot: plot)
        let dx = to.x - from.x, dy = to.y - from.y
        return (out: CGPoint(x: from.x + dx * x1, y: from.y + dy * y1),
                into: CGPoint(x: from.x + dx * x2, y: from.y + dy * y2),
                from: from, to: to)
    }

    private func target(at point: CGPoint, width: CGFloat,
                        plot: TimelineModel.LanePlot?) -> Grab {
        let height = TimelinePanelView.laneHeight
        if let handles = handlePoints(width: width, height: height, plot: plot) {
            if hypot(handles.out.x - point.x, handles.out.y - point.y) <= 8 { return .handleOut }
            if hypot(handles.into.x - point.x, handles.into.y - point.y) <= 8 { return .handleIn }
        }
        if let index = keyIndex(at: point, width: width, plot: plot) { return .key(index) }
        return .scrub
    }

    private func dragHandle(to point: CGPoint, width: CGFloat, height: CGFloat,
                            plot: TimelineModel.LanePlot?) {
        guard let selection = model.selection, selection.track == track.name,
              let handles = handlePoints(width: width, height: height, plot: plot),
              case .bezier(var x1, var y1, var x2, var y2)
                = track.keys[selection.index].curve else { return }
        let dx = handles.to.x - handles.from.x
        let dy = handles.to.y - handles.from.y
        guard dx > 0.5 else { return }
        let fractionX = min(max(0, (point.x - handles.from.x) / dx), 1)
        // A flat pair of keys has no height to measure the y against, so the
        // ease stays where it was and only the timing bends.
        let fractionY = abs(dy) > 0.5 ? (point.y - handles.from.y) / dy : nil
        switch grab {
        case .handleOut:
            x1 = fractionX
            if let fractionY { y1 = fractionY }
        case .handleIn:
            x2 = fractionX
            if let fractionY { y2 = fractionY }
        default:
            return
        }
        model.setCurve(track: track.name, at: selection.index,
                       .bezier(x1: x1, y1: y1, x2: x2, y2: y2))
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize,
                      plot: TimelineModel.LanePlot?) {
        let width = size.width
        if track.isWorkedOut {
            let source = track.formula?.source
                ?? track.parts.keys.sorted().joined(separator: ", ")
            context.draw(Text("rule: \(source)")
                .font(.system(size: 10, design: .monospaced).italic())
                .foregroundColor(palette.textTertiary),
                at: CGPoint(x: width - 10, y: size.height / 2), anchor: .trailing)
            drawPlayheadLine(&context, size: size)
            return
        }
        if let plot {
            var path = SwiftUI.Path()
            let inner = size.height - Self.pad * 2
            for (index, sample) in plot.samples.enumerated() {
                let x = width * CGFloat(index) / CGFloat(plot.samples.count - 1)
                let y = Self.pad + (1 - sample) * inner
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(OllinInspector.accent.opacity(0.45)),
                           lineWidth: 1.5)
        } else if case .color = track.keys.first?.value {
            // A color track draws itself: the band is the blend the parameter will
            // wear, sampled from the track rather than faded between stops.
            let bandHeight: CGFloat = 10
            let y = (size.height - bandHeight) / 2
            let stepWidth: CGFloat = 4
            var x: CGFloat = 0
            while x < width {
                let time = scale.time(at: x + stepWidth / 2, width: width)
                if case .color(let red, let green, let blue, let alpha)?
                    = track.value(at: time) {
                    context.fill(SwiftUI.Path(CGRect(x: x, y: y, width: stepWidth + 0.5,
                                             height: bandHeight)),
                                 with: .color(SwiftUI.Color(red: red, green: green,
                                                            blue: blue, opacity: alpha)))
                }
                x += stepWidth
            }
        }
        // The handle stems under the keys, over the curve.
        if let handles = handlePoints(width: width, height: size.height, plot: plot) {
            var stems = SwiftUI.Path()
            stems.move(to: handles.from)
            stems.addLine(to: handles.out)
            stems.move(to: handles.to)
            stems.addLine(to: handles.into)
            context.stroke(stems, with: .color(Self.handleColor.opacity(0.9)), lineWidth: 1)
            for dot in [handles.out, handles.into] {
                context.fill(SwiftUI.Path(ellipseIn: CGRect(x: dot.x - 2.5, y: dot.y - 2.5,
                                                    width: 5, height: 5)),
                             with: .color(Self.handleColor))
            }
        }
        for index in track.keys.indices {
            let point = keyPoint(index, width: width, height: size.height, plot: plot)
            let selected = model.selection == .init(track: track.name, index: index)
            if selected {
                context.fill(diamond(at: point, radius: 6.5), with: .color(.white))
            }
            context.fill(diamond(at: point, radius: 4.5),
                         with: .color(OllinInspector.accent))
            context.stroke(diamond(at: point, radius: 4.5),
                           with: .color(.white.opacity(0.5)), lineWidth: 0.5)
        }
        drawPlayheadLine(&context, size: size)
    }

    private func diamond(at center: CGPoint, radius: CGFloat) -> SwiftUI.Path {
        var path = SwiftUI.Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
        path.closeSubpath()
        return path
    }

    private func drawPlayheadLine(_ context: inout GraphicsContext, size: CGSize) {
        let x = scale.x(of: model.playhead, width: size.width)
        context.fill(SwiftUI.Path(CGRect(x: x - 0.5, y: 0, width: 1, height: size.height)),
                     with: .color(OllinInspector.accent.opacity(0.9)))
    }
}

// MARK: - Footer

private struct TimelineFooterRow: View {
    let model: TimelineModel
    let palette: OllinInspector.Palette

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                let addable = model.addableParameters()
                if addable.isEmpty {
                    Text("Every parameter has a track")
                } else {
                    ForEach(addable) { handle in
                        Button(handle.label) { model.addTrack(named: handle.name) }
                    }
                }
            } label: {
                Label("Track", systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            if let selection = model.selection,
               let track = model.automation.track(named: selection.track),
               track.keys.indices.contains(selection.index) {
                selectionCluster(selection, key: track.keys[selection.index])
            }
            Spacer(minLength: 12)
            Text(fileLabel)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(saveTint)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func selectionCluster(_ selection: TimelineModel.KeySelection,
                                  key: Automation.Key) -> some View {
        HStack(spacing: 6) {
            Text(String(format: "%.2fs", key.time))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
            Menu {
                ForEach(TimelineFooterRow.curveChoices, id: \.name) { choice in
                    Button(choice.name) {
                        model.setCurve(track: selection.track, at: selection.index,
                                       choice.curve)
                    }
                }
            } label: {
                Text(curveName(key.curve))
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("The curve that leaves this key")
            Button {
                model.removeKey(track: selection.track, at: selection.index)
            } label: {
                SwiftUI.Image(systemName: "trash")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove this key")
        }
    }

    static let curveChoices: [(name: String, curve: Automation.Curve)] = [
        ("Hold", .hold),
        ("Linear", .linear),
        ("Ease In", .easeIn),
        ("Ease Out", .easeOut),
        ("Ease In Out", .easeInOut),
        ("Bezier", .bezier(x1: 0.42, y1: 0, x2: 0.58, y2: 1)),
    ]

    private func curveName(_ curve: Automation.Curve) -> String {
        switch curve {
        case .hold: return "Hold"
        case .linear: return "Linear"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .easeInOut: return "Ease In Out"
        case .bezier: return "Bezier"
        }
    }

    private var fileLabel: String {
        guard let url = model.fileURL else { return "kept in memory this run" }
        let name = url.lastPathComponent
        switch model.saveState {
        case .saved: return "\(name) \u{00B7} saved"
        case .unsaved: return "\(name) \u{00B7} editing"
        case .failed: return "\(name) \u{00B7} write failed"
        }
    }

    private var saveTint: SwiftUI.Color {
        if case .failed = model.saveState { return OllinInspector.red }
        return palette.textTertiary
    }
}

// MARK: - The floating panel

/// Owns the floating timeline `NSPanel`, shown and hidden in step with the
/// host's "Show Timeline" toggle. The panel resizes (lanes want width), keeps
/// its frame across launches, and hands the toggle back when closed.
@MainActor
package final class TimelinePanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var host: NSHostingController<TimelinePanelRoot>?
    private weak var model: TimelineModel?

    package override init() {}

    package func sync(visible: Bool, model: TimelineModel) {
        guard visible else {
            self.model?.endFollowingClock()
            panel?.orderOut(nil)
            return
        }
        self.model = model
        let root = TimelinePanelRoot(model: model)
        if let host {
            host.rootView = root
        } else {
            buildPanel(root)
        }
        panel?.orderFront(nil)
        model.beginFollowingClock()
    }

    package func close() {
        model?.endFollowingClock()
        panel?.orderOut(nil)
    }

    private func buildPanel(_ rootView: TimelinePanelRoot) {
        let host = NSHostingController(rootView: rootView)
        host.sizingOptions = []       // the panel is sized by hand and by the user
        self.host = host

        let panel = NSPanel(contentViewController: host)
        // Activating (unlike the stats panel): the lanes take drags and the
        // transport takes the space bar, so the panel must become key.
        panel.styleMask = [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView]
        panel.title = "Timeline"
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .line
        panel.titleVisibility = .visible
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false   // the lanes own the drags
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.contentMinSize = NSSize(width: 520, height: 220)
        panel.identifier = NSUserInterfaceItemIdentifier(OllinHUD.timelinePanelID)
        panel.delegate = self
        self.panel = panel

        let autosaveName = "ollin.timelinePanel.frame"
        if !panel.setFrameUsingName(autosaveName) {
            panel.setContentSize(NSSize(width: 680, height: 300))
            positionBelowSketch(panel)
        }
        panel.setFrameAutosaveName(autosaveName)
    }

    /// Default placement: under the sketch window's lower edge, left-aligned
    /// (moving up over it when the screen has no room), and the screen's
    /// bottom-right as a fallback.
    private func positionBelowSketch(_ panel: NSPanel) {
        let size = panel.frame.size
        let gap: CGFloat = 12
        guard let sketch = NSApp.windows.first(where: {
            $0 !== panel && $0.isVisible && !($0 is NSPanel) && $0.styleMask.contains(.titled)
        }) else {
            if let area = NSScreen.main?.visibleFrame {
                panel.setFrameOrigin(CGPoint(x: area.maxX - size.width - 16,
                                             y: area.minY + 16))
            }
            return
        }
        let frame = sketch.frame
        let area = (sketch.screen ?? NSScreen.main)?.visibleFrame
        var y = frame.minY - gap - size.height
        if let area, y < area.minY { y = area.minY + 8 }
        panel.setFrameOrigin(CGPoint(x: frame.minX, y: y))
    }

    /// The user clicked the panel's close button: keep the menu toggle in
    /// sync, so the host does not re-summon it.
    package func windowWillClose(_ notification: Notification) {
        model?.endFollowingClock()
        UserDefaults.standard.set(false, forKey: OllinHUD.showTimelineKey)
    }
}

#endif
