// Dragging a shape in the window and having the file change.
//
// The framework says which shape the pointer is over and which line drew it
// (`SourcePick`); the rewriter turns a distance into new numbers in the text
// (`SourceEdit`). This is what joins them: it holds the drag, writes the file,
// and lets the watcher do what it already does with any other save.
//
// Nothing here reaches into the sketch's memory to move anything. The file is
// the only thing that changes, which is why the shape stays where the drag
// left it after a reload, and why undo is the editor's own undo.

import AppKit
import Foundation
import Observation
import Ollin
import OllinRuntime
import SwiftUI

/// What the dragger needs from the session around it: the sketch running right
/// now, and the file it was compiled from. A protocol so the headless
/// `--dragtest` can drive the whole controller without a window.
@MainActor
protocol ShapeDragHost: AnyObject {
    var currentSketch: Sketch? { get }
    var sourcePath: String { get }
}

extension LiveSession: ShapeDragHost {}

/// The live host's shape dragger: hold Command to see what the pointer is
/// over, drag to move it, and the numbers in the `.swift` file change.
@MainActor
@Observable
final class ShapeDragController: ShapeDragging {

    /// The shape under the pointer, as a closed outline in canvas points.
    private(set) var outline: [Vector2] = []
    /// `Sketch.swift:42`, the place the shape was written.
    private(set) var label: String?
    /// How far the shape has been dragged so far, in canvas points.
    private(set) var offset = Vector2.zero
    private(set) var isDragging = false
    /// Why the last drag could not be written, in one sentence.
    private(set) var note: String?

    @ObservationIgnored private let session: any ShapeDragHost
    @ObservationIgnored private var pick: SourcePick?
    @ObservationIgnored private var start = Vector2.zero
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
        show(sketch.sourcePick(at: canvasPoint))
    }

    func dragBegan(at canvasPoint: Vector2) -> Bool {
        guard let sketch = session.currentSketch else { return false }
        guard sketch.tracksSourceSites else { arm(true); return false }
        guard let found = sketch.sourcePick(at: canvasPoint) else {
            clear()
            return false                      // nothing here: leave the click alone
        }
        show(found)
        pick = found
        start = canvasPoint
        offset = .zero
        isDragging = true
        return true
    }

    func dragMoved(to canvasPoint: Vector2) {
        guard isDragging else { return }
        offset = canvasPoint - start
    }

    func dragEnded() {
        isDragging = false
        defer { offset = .zero; pick = nil }
        guard let pick, offset.length > 0.01 else { return }
        // The outline follows the shape to where the drag left it, so the
        // moment between the save and the reload does not read as a snap back.
        if write(pick, moved: pick.numbersDelta(forCanvasDelta: offset)) {
            let step = offset
            outline = outline.map { $0 + step }
        }
    }

    // MARK: Writing it down

    /// Put the new numbers in the file, and say whether anything changed. The
    /// watcher sees the save and reloads the sketch, which is the same path any
    /// other edit takes.
    @discardableResult
    private func write(_ pick: SourcePick, moved delta: Vector2) -> Bool {
        let path = session.sourcePath
        let name = (path as NSString).lastPathComponent
        guard pick.site.fileName == name else {
            // A shape drawn from another file (a helper, or the framework's own
            // drawing) has numbers this host does not own.
            say("That shape is drawn in \(pick.site.fileName), not in \(name).")
            return false
        }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            say("Could not read \(name).")
            return false
        }
        do {
            let edited = try SourceEdit.moving(text, line: pick.site.line, column: pick.site.column,
                                               move: pick.site.move, by: delta)
            // A drag too small to change a whole number writes nothing at all.
            guard edited != text else { return false }
            try edited.write(toFile: path, atomically: true, encoding: .utf8)
            print("OllinLive: moved the shape at \(name):\(pick.site.line) ✓")
            return true
        } catch let failure as SourceEdit.Failure {
            say(Self.sentence(for: failure, at: pick.site.line, in: name))
        } catch {
            say("Could not write \(name): \(error.localizedDescription)")
        }
        return false
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
        }
    }

    // MARK: State

    /// Turn per-shape recording on or off in the running sketch. Off is the
    /// resting state, so a sketch nobody is editing pays nothing for this.
    private func arm(_ on: Bool) {
        session.currentSketch?.tracksSourceSites = on
    }

    private func show(_ found: SourcePick?) {
        guard let found else { clear(); return }
        outline = found.outline
        label = "\(found.site.fileName):\(found.site.line)"
    }

    private func clear() {
        outline = []
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
/// it stands, and, while it is being dragged, a second outline where it would
/// land. A SwiftUI sibling of the canvas, never drawn into it, so it cannot
/// reach an export.
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
                let points = controller.outline.map {
                    CGPoint(x: $0.x * scale.width, y: $0.y * scale.height)
                }
                // Where the shape stands. It goes dashed and faint under a drag,
                // so the solid one is always the one that will be written.
                outline(points)
                    .stroke(OllinInspector.accent.opacity(controller.isDragging ? 0.35 : 0.9),
                            style: StrokeStyle(lineWidth: 1.5,
                                               dash: controller.isDragging ? [4, 3] : []))
                if controller.isDragging {
                    outline(points)
                        .stroke(OllinInspector.accent, lineWidth: 1.5)
                        .offset(x: controller.offset.x * scale.width,
                                y: controller.offset.y * scale.height)
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

    private func outline(_ points: [CGPoint]) -> SwiftUI.Path {
        SwiftUI.Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
    }
}
