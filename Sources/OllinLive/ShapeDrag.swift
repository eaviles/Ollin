// Dragging a shape in the window and having the file change.
//
// The framework says which shape the pointer is over, which line drew it, and
// where its handles are (`SourcePick`); the rewriter turns a distance into new
// numbers in the text (`SourceEdit`). This is what joins them: it holds the
// drag, writes the file, and lets the watcher do what it already does with any
// other save.
//
// Nothing here reaches into the sketch's memory to move anything. The file is
// the only thing that changes, which is why the shape stays where the drag
// left it after a reload, and why undo is the editor's own undo. The one
// exception is a coordinate written as a knob's name, which turns that knob
// instead: there is no number on the line to write, and the knob is where the
// value lives.

import AppKit
import Foundation
import Observation
import Ollin
import OllinRuntime
import SwiftUI

/// What the dragger needs from the session around it: the sketch running right
/// now, the file it was compiled from, and somewhere to record a knob it turns.
/// A protocol so the headless `--dragtest` can drive the whole controller
/// without a window.
@MainActor
protocol ShapeDragHost: AnyObject {
    var currentSketch: Sketch? { get }
    var sourcePath: String { get }
    func recordParam(_ name: String, _ value: ParamStored)
}

extension LiveSession: ShapeDragHost {}

/// The live host's shape dragger: hold Command to see what the pointer is
/// over, drag the shape to move it, a corner to resize it, or the knob above it
/// to turn it, and the numbers in the `.swift` file change.
@MainActor
@Observable
final class ShapeDragController: ShapeDragging {

    /// Which of the three things a press started.
    enum Gesture: Equatable {
        case move
        case resize(SourceHandle)
        case turn(SourceHandle)
    }

    /// The shape under the pointer, as a closed outline in canvas points.
    private(set) var outline: [Vector2] = []
    /// Where the drag would leave the shape, while one is under way.
    private(set) var preview: [Vector2] = []
    /// What can be taken hold of on that shape, in canvas points.
    private(set) var handles: [SourceHandle] = []
    /// The handle under the pointer right now, if any.
    private(set) var handleUnderPointer: SourceHandle?
    /// `Sketch.swift:42`, the place the shape was written.
    private(set) var label: String?
    /// How far the shape has been dragged so far, in canvas points.
    private(set) var offset = Vector2.zero
    private(set) var isDragging = false
    /// Why the last drag could not be written, in one sentence.
    private(set) var note: String?

    /// How near a handle the pointer has to be, in canvas points.
    static let grabRadius = 11.0

    @ObservationIgnored private let session: any ShapeDragHost
    @ObservationIgnored private var pick: SourcePick?
    @ObservationIgnored private var hovered: SourcePick?
    @ObservationIgnored private var gesture = Gesture.move
    @ObservationIgnored private var start = Vector2.zero
    @ObservationIgnored private var factor = Vector2(1, 1)
    @ObservationIgnored private var angle = 0.0
    @ObservationIgnored private var noteHide: Task<Void, Never>?

    init(session: any ShapeDragHost) {
        self.session = session
    }

    // MARK: What the canvas tells it

    func modifierChanged(held: Bool, at canvasPoint: Vector2?) {
        arm(held || isDragging)
        guard held else {
            if !isDragging { clear() }
            return
        }
        if let canvasPoint { pointerHovered(at: canvasPoint) }
    }

    func pointerHovered(at canvasPoint: Vector2) {
        guard let sketch = session.currentSketch else { return }
        // A reload brings a new sketch that is not recording yet; arming it
        // here means the next frame answers, which is the next few
        // milliseconds.
        guard sketch.tracksSourceSites else { arm(true); return }
        // A handle stands outside the shape it belongs to, so the pointer over
        // one finds nothing underneath. Keep the shape that put it there.
        if let hovered, let handle = hovered.handle(at: canvasPoint, within: Self.grabRadius) {
            handleUnderPointer = handle
            return
        }
        handleUnderPointer = nil
        show(sketch.sourcePick(at: canvasPoint))
    }

    func dragBegan(at canvasPoint: Vector2) -> Bool {
        guard let sketch = session.currentSketch else { return false }
        guard sketch.tracksSourceSites else { arm(true); return false }
        // A handle of the shape already outlined takes the press first.
        if let hovered, let handle = hovered.handle(at: canvasPoint, within: Self.grabRadius) {
            begin(hovered, handle.kind == .resize ? .resize(handle) : .turn(handle), at: canvasPoint)
            return true
        }
        guard let found = sketch.sourcePick(at: canvasPoint) else {
            clear()
            return false                      // nothing here: leave the click alone
        }
        begin(found, .move, at: canvasPoint)
        return true
    }

    func dragMoved(to canvasPoint: Vector2) {
        guard isDragging, let pick else { return }
        offset = canvasPoint - start
        switch gesture {
        case .move:
            preview = outline.map { $0 + offset }
        case .resize(let handle):
            factor = pick.sizeFactor(for: handle, canvasDelta: offset) ?? Vector2(1, 1)
            preview = pick.resized(by: factor)
        case .turn:
            angle = pick.turnAngle(from: start, to: canvasPoint)
            preview = pick.turned(by: angle)
        }
    }

    func dragEnded() {
        isDragging = false
        let landed = preview
        defer { offset = .zero; preview = []; factor = Vector2(1, 1); angle = 0; pick = nil }
        guard let pick else { return }
        let wrote: Bool
        switch gesture {
        case .move:
            guard offset.length > 0.01 else { return }
            wrote = writeMove(pick, by: pick.numbersDelta(forCanvasDelta: offset))
        case .resize:
            guard abs(factor.x - 1) > 1e-4 || abs(factor.y - 1) > 1e-4 else { return }
            let size = factor
            wrote = write(pick) {
                try SourceEdit.resizing($0, line: pick.site.line, column: pick.site.column,
                                        move: pick.site.move, by: size)
            }
        case .turn:
            guard abs(angle) > 1e-4 else { return }
            let turn = angle
            wrote = write(pick) {
                try SourceEdit.turning($0, line: pick.site.line, column: pick.site.column,
                                       move: pick.site.move, by: turn)
            }
        }
        // The outline follows the shape to where the drag left it, so the
        // moment between the save and the reload does not read as a snap back.
        if wrote, !landed.isEmpty {
            outline = landed
            hovered = nil
            handles = []
        }
    }

    // MARK: Writing it down

    /// Put the new text in the file, and say whether anything changed. The
    /// watcher sees the save and reloads the sketch, which is the same path any
    /// other edit takes.
    @discardableResult
    private func write(_ pick: SourcePick, _ change: (String) throws -> String) -> Bool {
        guard let source = read(pick) else { return false }
        do {
            let edited = try change(source.text)
            // A drag too small to change a whole number writes nothing at all.
            guard edited != source.text else { return false }
            try edited.write(toFile: source.path, atomically: true, encoding: .utf8)
            print("OllinLive: changed the shape at \(source.name):\(pick.site.line) ✓")
            return true
        } catch let failure as SourceEdit.Failure {
            say(Self.sentence(for: failure, at: pick.site.line, in: source.name))
        } catch {
            say("Could not write \(source.name): \(error.localizedDescription)")
        }
        return false
    }

    /// A move, which is the one gesture that has somewhere else to go: a
    /// coordinate written as a knob's name turns that knob instead of being
    /// refused, which costs no recompile.
    private func writeMove(_ pick: SourcePick, by delta: Vector2) -> Bool {
        guard let source = read(pick) else { return false }
        do {
            let plan = try SourceEdit.planningMove(source.text, line: pick.site.line,
                                                   column: pick.site.column,
                                                   move: pick.site.move, by: delta)
            if let refused = plan.refused {
                say(Self.sentence(for: .computed(argument: refused), at: pick.site.line,
                                  in: source.name))
                return false
            }
            // Every name has to be a knob before any of them turns, so a drag
            // that cannot be carried out whole changes nothing at all.
            if let missed = plan.names.first(where: { knob($0, pick: pick) == nil }) {
                say(Self.sentence(for: .computed(argument: missed.name), at: pick.site.line,
                                  in: source.name))
                return false
            }
            for named in plan.names { turnKnob(named, pick: pick) }
            guard plan.text != source.text else { return !plan.names.isEmpty }
            try plan.text.write(toFile: source.path, atomically: true, encoding: .utf8)
            print("OllinLive: moved the shape at \(source.name):\(pick.site.line) ✓")
            return true
        } catch let failure as SourceEdit.Failure {
            say(Self.sentence(for: failure, at: pick.site.line, in: source.name))
        } catch {
            say("Could not write \(source.name): \(error.localizedDescription)")
        }
        return false
    }

    /// The file the shape was written in, when this host owns it.
    private func read(_ pick: SourcePick) -> (path: String, name: String, text: String)? {
        let path = session.sourcePath
        let name = (path as NSString).lastPathComponent
        guard pick.site.fileName == name else {
            // A shape drawn from another file (a helper, or the framework's own
            // drawing) has numbers this host does not own.
            say("That shape is drawn in \(pick.site.fileName), not in \(name).")
            return nil
        }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            say("Could not read \(name).")
            return nil
        }
        return (path, name, text)
    }

    // MARK: A coordinate that is a knob

    /// The `Param<Double>` a coordinate names, when the value it holds is the
    /// one the frame drew with. The equality is what keeps a local variable
    /// that shadows a knob's name from moving the wrong thing.
    private func knob(_ named: SourceEdit.MovePlan.Named,
                      pick: SourcePick) -> (ParamHandle, ParamControl.Slider)? {
        guard let sketch = session.currentSketch, let placedAt = pick.placedAt else { return nil }
        guard let handle = sketch.parameters().first(where: { $0.name == named.name }) else { return nil }
        guard case .slider(let slider) = handle.control else { return nil }
        let drawn = named.isAcross ? placedAt.x : placedAt.y
        guard abs(slider.read() - drawn) <= 1e-6 * Swift.max(1, abs(drawn)) else { return nil }
        return (handle, slider)
    }

    /// Turn it by the drag, the way the inspector row does, and remember the
    /// new value so the next reload keeps it.
    private func turnKnob(_ named: SourceEdit.MovePlan.Named, pick: SourcePick) {
        guard let (handle, slider) = knob(named, pick: pick) else { return }
        slider.write(slider.read() + named.delta)
        session.recordParam(handle.name, handle.param.stored)
        print("OllinLive: turned \(handle.name) to "
            + SourceEdit.written(slider.read(), fractionDigits: 2) + " ✓")
    }

    /// What to tell someone whose drag went nowhere. Each one names the thing
    /// standing where a number would have to be, because that is the only way
    /// to see why the shape did not move.
    static func sentence(for failure: SourceEdit.Failure, at line: Int, in file: String) -> String {
        switch failure {
        case .computed(let argument), .notAPoint(let argument):
            return "\(file):\(line) places this shape with \(argument), so there is no number to move."
        case .callNotFound:
            return "\(file):\(line) has changed since that frame was drawn."
        case .missingArgument:
            return "\(file):\(line) does not carry the numbers this shape needs."
        case .nothingToSize:
            return "\(file):\(line) does not say how big this shape is."
        case .nothingToTurn:
            return "\(file):\(line) does not say which way this shape faces."
        }
    }

    // MARK: State

    /// Turn per-shape recording on or off in the running sketch. Off is the
    /// resting state, so a sketch nobody is editing pays nothing for this.
    private func arm(_ on: Bool) {
        session.currentSketch?.tracksSourceSites = on
    }

    private func begin(_ found: SourcePick, _ gesture: Gesture, at canvasPoint: Vector2) {
        show(found)
        pick = found
        self.gesture = gesture
        start = canvasPoint
        offset = .zero
        factor = Vector2(1, 1)
        angle = 0
        preview = found.outline
        isDragging = true
    }

    private func show(_ found: SourcePick?) {
        guard let found else { clear(); return }
        hovered = found
        outline = found.outline
        handles = found.handles
        label = "\(found.site.fileName):\(found.site.line)"
    }

    private func clear() {
        hovered = nil
        outline = []
        handles = []
        handleUnderPointer = nil
        label = nil
    }

    private func say(_ message: String) {
        note = message
        FileHandle.standardError.write(Data("OllinLive: \(message)\n".utf8))
        noteHide?.cancel()
        noteHide = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.note = nil
        }
    }
}

/// What a Command-drag looks like: the shape under the pointer outlined where
/// it stands, its handles on the corners and above it, and, while it is being
/// dragged, a second outline where it would land. A SwiftUI sibling of the
/// canvas, never drawn into it, so it cannot reach an export.
struct ShapeDragOverlay: View {
    let controller: ShapeDragController
    /// The sketch's own size, which the outline is measured in.
    let canvas: CGSize
    /// The size the canvas is shown at, which may be smaller.
    let display: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !controller.outline.isEmpty {
                let scale = CGSize(width: display.width / max(canvas.width, 1),
                                   height: display.height / max(canvas.height, 1))
                let points = controller.outline.map { on(screen: $0, scale) }
                // Where the shape stands. It goes dashed and faint under a drag,
                // so the solid one is always the one that will be written.
                outline(points)
                    .stroke(OllinInspector.accent.opacity(controller.isDragging ? 0.35 : 0.9),
                            style: StrokeStyle(lineWidth: 1.5,
                                               dash: controller.isDragging ? [4, 3] : []))
                if controller.isDragging {
                    outline(controller.preview.map { on(screen: $0, scale) })
                        .stroke(OllinInspector.accent, lineWidth: 1.5)
                }
                if !controller.isDragging {
                    ForEach(Array(controller.handles.enumerated()), id: \.offset) { _, handle in
                        grip(handle, at: on(screen: handle.position, scale))
                    }
                }
                if let label = controller.label, let corner = points.first {
                    Text(label)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.thinMaterial, in: .rect(cornerRadius: 5))
                        .offset(x: corner.x, y: max(0, corner.y - 24))
                }
            }
            if let note = controller.note {
                Text(note)
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: .capsule)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 18)
                    .transition(.opacity)
            }
        }
        .frame(width: display.width, height: display.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.15), value: controller.note)
        .allowsHitTesting(false)
    }

    /// A corner grip is a small square; the one that turns the shape is a
    /// circle standing clear above it, so the two never read as the same thing.
    @ViewBuilder
    private func grip(_ handle: SourceHandle, at point: CGPoint) -> some View {
        let under = controller.handleUnderPointer == handle
        let side = under ? 11.0 : 8.0
        Group {
            if handle.kind == .resize {
                Rectangle()
                    .fill(.background)
                    .frame(width: side, height: side)
                    .overlay(Rectangle().stroke(OllinInspector.accent, lineWidth: 1.5))
            } else {
                Circle()
                    .fill(.background)
                    .frame(width: side + 2, height: side + 2)
                    .overlay(Circle().stroke(OllinInspector.accent, lineWidth: 1.5))
            }
        }
        .position(point)
    }

    private func on(screen point: Vector2, _ scale: CGSize) -> CGPoint {
        CGPoint(x: point.x * scale.width, y: point.y * scale.height)
    }

    private func outline(_ points: [CGPoint]) -> SwiftUI.Path {
        SwiftUI.Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
    }
}
