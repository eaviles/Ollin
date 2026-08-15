import AppKit
import Observation
import SwiftUI

/// Lining a piece up with the wall it is thrown onto.
///
/// Host chrome, like the stats panel: it owns four handles over the running
/// picture and the file they are kept in, and never draws into the canvas or
/// reaches an export. Command-K opens it, you drag the corners onto whatever
/// the picture is meant to sit inside, and it is kept under the display so the
/// next launch opens already square.
///
/// The piece keeps running underneath the whole time, which is the point: you
/// are lining up the work itself, at its own brightness, not a test card.
@MainActor
@Observable
final class ProjectionCalibrator {

    /// What the run is fitted with. Every change is pushed straight at the
    /// runner, so the wall answers the drag as it happens.
    private(set) var projection: Installation.Projection
    /// Whether the handles are up.
    private(set) var isOpen = false
    /// Which corner the arrow keys move, clockwise from the top left.
    private(set) var selected = 0
    /// The display's size in points, as the overlay last measured it. Kept so a
    /// nudge can be a pixel rather than a fraction of a screen nobody named.
    var outputSize: CGSize = .zero

    /// The canvas, for working `Corners.fit` out: it is the picture's own
    /// proportions that decide where a fitted corner sits.
    private let canvas: Vector2
    /// Which display this is filed under.
    private let displayKey: String
    /// Whether the pointer goes back into hiding when the handles come down.
    private let hidesPointer: Bool

    private weak var runner: SketchRunner?
    private var keyMonitor: Any?

    init(projection: Installation.Projection, canvas: Vector2,
         displayKey: String, hidesPointer: Bool) {
        self.projection = projection
        self.canvas = canvas
        self.displayKey = displayKey
        self.hidesPointer = hidesPointer
    }

    /// The running sketch, as soon as the view has built one.
    func attach(_ runner: SketchRunner) {
        self.runner = runner
        runner.setProjection(projection)
    }

    // MARK: The handles

    func toggle() { isOpen ? close() : open() }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        NSCursor.unhide()
        ollinInstallationLog("lining up: drag the corners, arrows nudge, R squares up, Command-K when done")
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        save()
        if hidesPointer { NSCursor.hide() }
    }

    /// Where the four corners are now, in fractions of the display, ready to be
    /// drawn as handles.
    ///
    /// Read from the corners themselves rather than from the placement, which
    /// can be nothing: a hand dragging one corner past another makes a shape
    /// with no inside for a moment, and there is no map through it. The handles
    /// have to stay under the fingers holding them anyway.
    func corners(output: CGSize) -> [Vector2] {
        projection.corners.resolved(outputAspect: aspect(of: output),
                                    pictureAspect: pictureAspect)
    }

    /// The declaration worked out against a display of this size.
    func placement(output: CGSize) -> ProjectionPlacement? {
        guard output.width > 0, output.height > 0 else { return nil }
        return ProjectionPlacement(projection, canvas: canvas,
                                   output: Vector2(Double(output.width), Double(output.height)))
    }

    /// Put one corner somewhere else, in fractions of the display. A dragged
    /// corner is allowed a little way off the screen: a projector often has to
    /// throw part of its picture past the edge of what it is aimed at.
    func move(_ index: Int, to point: Vector2, output: CGSize) {
        let held = Vector2(min(max(point.x, -0.5), 1.5), min(max(point.y, -0.5), 1.5))
        selected = index
        apply(projection.corners.moving(index, to: held,
                                        outputAspect: aspect(of: output),
                                        pictureAspect: pictureAspect))
    }

    /// Move the chosen corner by a few points, for the last part of lining up
    /// that a hand on a trackpad cannot do.
    func nudge(by delta: Vector2) {
        guard outputSize.width > 0, outputSize.height > 0 else { return }
        let now = corners(output: outputSize)[selected]
        move(selected, to: Vector2(now.x + delta.x / Double(outputSize.width),
                                   now.y + delta.y / Double(outputSize.height)),
             output: outputSize)
    }

    /// Take the next corner, clockwise from the top left.
    func selectNext() { selected = (selected + 1) % 4 }

    /// Square the picture back up, as it opens before anybody drags anything.
    func reset() {
        apply(.fit)
        ollinInstallationLog("squared up")
    }

    private func apply(_ corners: Installation.Projection.Corners) {
        projection.corners = corners
        runner?.setProjection(projection)
    }

    /// Keep the corners under this display. Called as each drag ends, so a
    /// power cut in the middle of an evening's work loses nothing.
    func save() {
        ProjectionCalibration.save(projection.corners, forDisplay: displayKey,
                                   displaySize: outputSize)
    }

    private var pictureAspect: Double {
        let shows = projection.shows
        guard shows.height > 0, canvas.y > 0 else { return 1 }
        return (shows.width * canvas.x) / (shows.height * canvas.y)
    }

    private func aspect(of output: CGSize) -> Double {
        output.height > 0 ? Double(output.width / output.height) : 1
    }

    // MARK: The keys

    /// Watch for the keys the handles answer to.
    ///
    /// A local monitor rather than a menu command: this window has no menu bar
    /// to hang one on, since a piece on a wall is full screen. It reads the
    /// event before the canvas does, so Command-K works while the sketch holds
    /// the keyboard, and everything else is passed straight through unless the
    /// handles are actually up.
    func watchKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func stopWatchingKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Whether this key was one of ours, and so must not reach the sketch.
    private func handle(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        if command, event.charactersIgnoringModifiers?.lowercased() == "k" {
            toggle()
            return true
        }
        guard isOpen else { return false }
        let step = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
        switch Int(event.keyCode) {
        case 53:  close(); return true                       // escape
        case 48:  selectNext(); return true                  // tab
        case 123: nudge(by: Vector2(-step, 0)); return true  // left
        case 124: nudge(by: Vector2(step, 0)); return true   // right
        case 125: nudge(by: Vector2(0, step)); return true   // down
        case 126: nudge(by: Vector2(0, -step)); return true  // up
        default: break
        }
        if event.charactersIgnoringModifiers?.lowercased() == "r", !command {
            reset()
            return true
        }
        return false
    }
}

// MARK: - The overlay

/// The handles, the outline, and a grid that shows what the warp is doing.
///
/// Invisible and untouchable until the handles are up, so a piece nobody is
/// lining up keeps every click and every pixel to itself.
struct CalibrationOverlay: View {

    let calibrator: ProjectionCalibrator

    private static let space = "ollin.calibration"

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                if calibrator.isOpen {
                    guides(size: size)
                    ForEach(0..<4, id: \.self) { index in
                        handle(index, size: size)
                    }
                    // Along the bottom edge, where no handle ever sits, and deaf
                    // to the pointer: a caption that eats a drag is worse than
                    // no caption.
                    caption
                        .frame(width: size.width, height: size.height, alignment: .bottom)
                        .padding(.bottom, 28)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height)
            .coordinateSpace(name: CalibrationOverlay.space)
            .onAppear { calibrator.outputSize = size }
            .onChange(of: size) { _, new in calibrator.outputSize = new }
        }
        .allowsHitTesting(calibrator.isOpen)
    }

    /// The outline of where the picture lands, and a grid through it. A
    /// straight line across the canvas stays straight under this kind of warp,
    /// so each one is drawn from its two ends and nothing in between.
    private func guides(size: CGSize) -> some View {
        let placement = calibrator.placement(output: size)
        return Canvas { context, _ in
            guard let placement else { return }
            let steps = 8
            var grid = SwiftUI.Path()
            for step in 1..<steps {
                let t = Double(step) / Double(steps)
                grid.move(to: point(placement, t, 0, size))
                grid.addLine(to: point(placement, t, 1, size))
                grid.move(to: point(placement, 0, t, size))
                grid.addLine(to: point(placement, 1, t, size))
            }
            context.stroke(grid, with: .color(.white.opacity(0.28)), lineWidth: 1)

            var outline = SwiftUI.Path()
            outline.move(to: point(placement, 0, 0, size))
            outline.addLine(to: point(placement, 1, 0, size))
            outline.addLine(to: point(placement, 1, 1, size))
            outline.addLine(to: point(placement, 0, 1, size))
            outline.closeSubpath()
            context.stroke(outline, with: .color(.white.opacity(0.85)), lineWidth: 2)
        }
    }

    private func point(_ placement: ProjectionPlacement,
                       _ u: Double, _ v: Double, _ size: CGSize) -> CGPoint {
        let p = placement.homography.map(Vector2(u, v))
        return CGPoint(x: p.x * Double(size.width), y: p.y * Double(size.height))
    }

    private func handle(_ index: Int, size: CGSize) -> some View {
        let corners = calibrator.corners(output: size)
        let corner = corners[index]
        let chosen = calibrator.selected == index
        return SwiftUI.Circle()
            .strokeBorder(chosen ? SwiftUI.Color.white : SwiftUI.Color.white.opacity(0.7),
                          lineWidth: chosen ? 3 : 2)
            .background(SwiftUI.Circle().fill(SwiftUI.Color.black.opacity(0.45)))
            .frame(width: 34, height: 34)
            .position(x: corner.x * Double(size.width), y: corner.y * Double(size.height))
            .gesture(
                DragGesture(minimumDistance: 0,
                            coordinateSpace: .named(CalibrationOverlay.space))
                    .onChanged { value in
                        calibrator.move(index,
                                        to: Vector2(Double(value.location.x / size.width),
                                                    Double(value.location.y / size.height)),
                                        output: size)
                    }
                    .onEnded { _ in calibrator.save() }
            )
    }

    private var caption: some View {
        VStack(spacing: 5) {
            Text("Lining up")
                .font(.system(size: 15, weight: .semibold))
            Text("Drag a corner onto the wall. Arrow keys nudge the lit one, "
                 + "Shift for ten. Tab takes the next, R squares up, Command-K is done.")
                .font(.system(size: 12))
                .opacity(0.8)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }
}
