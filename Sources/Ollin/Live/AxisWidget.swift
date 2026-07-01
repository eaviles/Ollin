import SwiftUI
import simd

/// The orientation axis widget: a small interactive indicator parked bottom-center
/// over the canvas, showing which way the 3D scene faces, the way a modeling tool's
/// navigation puck does. A frosted disk holds a live-rotating tripod (red X, green
/// Y, blue Z); hovering a dot highlights it and clicking snaps the camera to look
/// down that axis. The icon buttons that fade in on hover reset the view and frame
/// an isometric angle. Projection (orthographic vs perspective) lives in the Camera
/// menu.
///
/// Host chrome (a SwiftUI sibling of the Metal view), so it never lands in an
/// export. It is mounted only when there is a 3D camera and the sketch or the menu
/// asked for it, so a 2D sketch never pays for its animation timeline. Actions are
/// routed through `OllinActiveSketch.runner`, the same weak hook the Camera menu
/// uses, so the widget needs no wiring to the running sketch.
struct AxisWidget: View {
    let cameraState: CameraOrientationState

    @SwiftUI.Environment(\.colorScheme) private var scheme
    @State private var hovering = false
    /// The pointer location within the puck (nil when the pointer is outside it),
    /// fed by one `onContinuousHover`. The hovered dot is computed from this each
    /// frame rather than via per-dot `.onHover`: the dots are `.position`-ed views
    /// rebuilt every frame by the timeline, and per-view hover tracking doesn't fire
    /// reliably for those, so we hit-test the pointer ourselves.
    @State private var pointer: CGPoint?
    @State private var hoveredControl: Control?
    @State private var isDragging = false
    /// The last drag translation forwarded, so a *cancelled* gesture can release the
    /// synthetic mouse press where it stood (a cancellation never calls `onEnded`).
    @State private var lastDragTranslation: CGSize = .zero
    /// Mirrors the drag's lifetime; a gesture the system cancels resets this without
    /// calling `onEnded`, which is the only signal a cancellation gives us.
    @GestureState private var dragActive = false
    /// The projection toggle, shared with the Camera menu (the runner reads it each
    /// frame and applies it to the rig).
    @AppStorage(OllinHUD.orthographicKey) private var orthographic = false
    /// Namespace for the projection toggle's sliding selection highlight.
    @Namespace private var projectionSelection

    private let puckSize: CGFloat = 78
    private let dotSize: CGFloat = 11

    var body: some View {
        // No TimelineView: the widget redraws when `cameraState.orientation` changes,
        // which the runner publishes once per rendered frame on the main queue. That
        // keeps it from freezing when the window is unfocused (SwiftUI pauses a
        // free-running timeline there, but honors a data update).
        HStack(spacing: 11) {
            // Left: the projection toggle (vertical, icons). Right: Reset / Isometric
            // (vertical). Both fade in on hover, like the puck's controls.
            projectionToggle
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
            puck
            VStack(spacing: 6) {
                iconButton(.reset)
                iconButton(.isometric)
            }
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.16)) { hovering = h } }
    }

    // MARK: Puck + tripod

    private var puck: some View {
        ZStack {
            SwiftUI.Circle().fill(.regularMaterial)
            SwiftUI.Circle().fill(scrim)
            SwiftUI.Circle().strokeBorder(hairline, lineWidth: 0.5)
            tripod
        }
        .frame(width: puckSize, height: puckSize)
        .clipShape(SwiftUI.Circle())
        .contentShape(SwiftUI.Circle())
    }

    private var tripod: some View {
        let reach = puckSize / 2 - dotSize / 2 - 7
        let axes = projectedAxes(reach: reach)
        let hovered = hoveredAxis(in: axes)
        return ZStack {
            // A connector line to every axis tip (negatives in the dots' own ghost
            // color), stopped at the dot's edge. The lines converge at the center
            // with no hub dot. Behind the dots and non-interactive.
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for a in axes {
                    // Constant line opacity too, no depth fade, to match the dots.
                    let color = a.isPositive ? a.color.opacity(0.55) : ghost.opacity(0.5)
                    let vx = a.point.x - c.x, vy = a.point.y - c.y
                    let len = max((vx * vx + vy * vy).squareRoot(), 0.001)
                    let stop = max(0, len - a.radius)
                    let end = CGPoint(x: c.x + vx / len * stop, y: c.y + vy / len * stop)
                    var path = SwiftUI.Path()
                    path.move(to: c)
                    path.addLine(to: end)
                    ctx.stroke(path, with: .color(color), lineWidth: 1.5)
                }
            }
            // Drawn far-to-near (sorted), so nearer dots sit on top.
            ForEach(axes, id: \.view) { dot($0, hovered: $0.view == hovered) }
        }
        .frame(width: puckSize, height: puckSize)
        .contentShape(SwiftUI.Circle())
        // One hover region over the whole puck reports the pointer; the hovered dot
        // is computed from it (see `pointer`).
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location): pointer = location
            case .ended: pointer = nil
            }
        }
        // A small press is a tap (snap to the dot under it); a larger move is a drag,
        // forwarded to the scene's camera so dragging on the puck orbits the view
        // (otherwise the puck swallows the drag the canvas needs to orbit).
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($dragActive) { _, state, _ in state = true }
                .onChanged { value in
                    let t = value.translation
                    if (t.width * t.width + t.height * t.height).squareRoot() > 4 {
                        OllinActiveSketch.runner?.widgetOrbit(began: !isDragging, ended: false, translation: t)
                        isDragging = true
                        lastDragTranslation = t
                    }
                }
                .onEnded { value in
                    if isDragging {
                        OllinActiveSketch.runner?.widgetOrbit(began: false, ended: true, translation: value.translation)
                        isDragging = false
                    } else if let view = nearestAxis(to: value.location, in: axes) {
                        snap(view)
                    }
                }
        )
        // A gesture the system cancels (window/session interruption) never calls
        // `onEnded`, which would leave the synthetic mouse press latched down,
        // freezing `cameraShowcase`'s idle logic and any `mouseIsPressed` polling.
        // `dragActive` resets on *any* end; defer one runloop turn so a normal end
        // (whose `onEnded` clears `isDragging`) is left alone, and only a true
        // cancellation releases the press here.
        .onChange(of: dragActive) { _, active in
            guard !active else { return }
            DispatchQueue.main.async {
                if isDragging {
                    OllinActiveSketch.runner?.widgetOrbit(began: false, ended: true,
                                                          translation: lastDragTranslation)
                    isDragging = false
                }
            }
        }
        .help(hovered?.rawValue.capitalized ?? "")
    }

    /// The dot under the pointer (nearest center within its radius), or nil.
    private func hoveredAxis(in axes: [ProjectedAxis]) -> CameraView? {
        guard let p = pointer else { return nil }
        return nearestAxis(to: p, in: axes)
    }

    /// The dot nearest `p` within its radius, or nil.
    private func nearestAxis(to p: CGPoint, in axes: [ProjectedAxis]) -> CameraView? {
        var best: (view: CameraView, dist: CGFloat)?
        for a in axes {
            let dx = p.x - a.point.x, dy = p.y - a.point.y
            let d = (dx * dx + dy * dy).squareRoot()
            if d <= a.radius + 5, best == nil || d < best!.dist { best = (a.view, d) }
        }
        return best?.view
    }

    private func dot(_ a: ProjectedAxis, hovered: Bool) -> some View {
        // Depth-dependent size and opacity (larger and bolder toward the front);
        // hover grows it slightly. The depth value is smooth, so both ramp smoothly.
        let size = a.radius * 2 * (hovered ? 1.3 : 1)
        let fill = a.isPositive
            ? a.color.opacity(hovered ? 1 : 0.55 + 0.45 * a.near)
            : negativeDot.opacity(hovered ? 1 : 0.5 + 0.5 * a.near)
        return SwiftUI.Circle().fill(fill)
            .frame(width: size, height: size)
            .position(a.point)
            .animation(.easeOut(duration: 0.1), value: hovered)
    }

    /// The six axis tips, projected from the live camera orientation into the puck
    /// and sorted far-to-near for correct overlap. `near` runs 0 (pointing away)
    /// to 1 (toward the viewer), dimming and shrinking the far dots; `radius` is the
    /// dot's drawn radius, used to stop its connector line at the edge.
    private func projectedAxes(reach: CGFloat) -> [ProjectedAxis] {
        let c = puckSize / 2
        // Each axis maps to the view that puts it toward the camera: +X is the
        // Right view (eye on +X), +Y is Top, +Z is Front, and the negatives flip.
        let defs: [(SIMD3<Float>, SwiftUI.Color, Bool, CameraView)] = [
            (SIMD3(1,  0,  0), axisRed,   true,  .right),
            (SIMD3(-1,  0,  0), axisRed,   false, .left),
            (SIMD3(0,  1,  0), axisGreen, true,  .top),
            (SIMD3(0, -1,  0), axisGreen, false, .bottom),
            (SIMD3(0,  0,  1), axisBlue,  true,  .front),
            (SIMD3(0,  0, -1), axisBlue,  false, .back),
        ]
        let r = cameraState.orientation
        return defs.map { axis, color, positive, view in
            let d = r * axis
            let near = Double((d.z + 1) / 2)
            let point = CGPoint(x: c + CGFloat(d.x) * reach, y: c - CGFloat(d.y) * reach)
            // Depth-dependent size: larger toward the front, smaller toward the back.
            // The source depth is smooth and the widget tracks the render loop, so
            // this ramps smoothly.
            let radius = dotSize * CGFloat(0.62 + 0.38 * near) / 2
            return ProjectedAxis(view: view, color: color, isPositive: positive,
                                 point: point, near: near, radius: radius)
        }
        .sorted { $0.near < $1.near }
    }

    private struct ProjectedAxis {
        let view: CameraView
        let color: SwiftUI.Color
        let isPositive: Bool
        let point: CGPoint
        let near: Double
        let radius: CGFloat
    }

    // MARK: Controls

    /// Reset and Isometric, the hover buttons stacked to the right of the puck, each
    /// an SF Symbol with a native tooltip.
    private enum Control: Equatable {
        case reset, isometric
        var view: CameraView { self == .reset ? .reset : .isometric }
        var icon: String { self == .reset ? "arrow.counterclockwise" : "cube" }
        var label: String { self == .reset ? "Reset" : "Isometric" }
    }

    private func iconButton(_ control: Control) -> some View {
        Button { snap(control.view) } label: {
            SwiftUI.Image(systemName: control.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hoveredControl == control ? labelStrong : label)
                .frame(width: 30, height: 30)
                .background {
                    SwiftUI.Circle().fill(.regularMaterial)
                    SwiftUI.Circle().fill(scrim)
                }
                .overlay(SwiftUI.Circle().strokeBorder(hairline, lineWidth: 0.5))
                .clipShape(SwiftUI.Circle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredControl = $0 ? control : (hoveredControl == control ? nil : hoveredControl) }
        .help(control.label)
    }

    /// The Orthographic / Perspective toggle, a vertical two-icon segmented control
    /// to the left of the puck, bound to the same setting the Camera menu flips (the
    /// runner reads it each frame and applies it to the rig).
    private var projectionToggle: some View {
        VStack(spacing: 0) {
            projectionOption("square", tooltip: "Orthographic", active: orthographic) { orthographic = true }
            projectionOption("perspective", tooltip: "Perspective", active: !orthographic) { orthographic = false }
        }
        .background {
            SwiftUI.RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.regularMaterial)
            SwiftUI.RoundedRectangle(cornerRadius: 9, style: .continuous).fill(scrim)
        }
        .overlay(SwiftUI.RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(hairline, lineWidth: 0.5))
        .clipShape(SwiftUI.RoundedRectangle(cornerRadius: 9, style: .continuous))
        // Slide the selection between the two segments on any change (widget or the
        // Camera menu), the way a native segmented control does.
        .animation(.snappy(duration: 0.22), value: orthographic)
    }

    private func projectionOption(_ icon: String, tooltip: String, active: Bool,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SwiftUI.Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? labelStrong : label)
                .frame(width: 30, height: 33)
                .background {
                    // One highlight shared by both segments via the matched geometry,
                    // so toggling slides it from one to the other instead of jumping.
                    if active {
                        SwiftUI.RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(activeFill)
                            .matchedGeometryEffect(id: "projSelection", in: projectionSelection)
                            .padding(2)
                    }
                }
                .contentShape(SwiftUI.Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // MARK: Actions

    private func snap(_ view: CameraView) {
        OllinActiveSketch.runner?.requestCameraView(view)
    }

    // MARK: Tokens (resolved per appearance, on the shared inspector tints)

    private var scrim: SwiftUI.Color {
        scheme == .dark
            ? SwiftUI.Color(red: 44 / 255, green: 42 / 255, blue: 48 / 255).opacity(OllinInspector.chromeTintOpacity)
            : SwiftUI.Color(red: 246 / 255, green: 246 / 255, blue: 248 / 255).opacity(OllinInspector.chromeTintOpacity)
    }
    private var hairline: SwiftUI.Color { scheme == .dark ? .white.opacity(0.10) : .black.opacity(0.10) }
    private var label: SwiftUI.Color { scheme == .dark ? .white.opacity(0.72) : .black.opacity(0.66) }
    private var labelStrong: SwiftUI.Color { scheme == .dark ? .white.opacity(0.95) : .black.opacity(0.90) }
    private var activeFill: SwiftUI.Color { scheme == .dark ? .white.opacity(0.14) : .black.opacity(0.08) }
    private var ghost: SwiftUI.Color { scheme == .dark ? .white.opacity(0.40) : .black.opacity(0.35) }
    private var negativeDot: SwiftUI.Color { scheme == .dark ? SwiftUI.Color(white: 0.52) : SwiftUI.Color(white: 0.45) }

    // The universal axis convention: X red, Y green, Z blue.
    private let axisRed = SwiftUI.Color(red: 1.00, green: 0.27, blue: 0.23)
    private let axisGreen = SwiftUI.Color(red: 0.19, green: 0.82, blue: 0.35)
    private let axisBlue = SwiftUI.Color(red: 0.04, green: 0.52, blue: 1.00)
}
