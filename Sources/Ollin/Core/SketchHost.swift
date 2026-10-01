import Foundation
#if os(macOS)
import AppKit
#endif

/// What a running sketch asks of whatever is showing it. The live runner
/// answers; with nothing showing the sketch (an export, a test with no
/// runner) `Sketch.host` is nil and each ask does nothing.
@MainActor
protocol SketchHost: AnyObject {
    /// Draw one frame of a sketch that has stopped looping (`redraw()`).
    func sketchWantsFrame(_ sketch: Sketch)
    /// The sketch changed the pointer it wants over its canvas.
    func sketchPointerChanged(_ sketch: Sketch)
    /// Show the open panel for the sketch (`chooseFiles(...)`).
    func sketchWantsFiles(_ sketch: Sketch, extensions: [String], allowsMultiple: Bool)
}

// MARK: - The pointer

/// The shape of the pointer over a sketch's canvas, one of the system's own.
/// Set it with `pointerShape(_:)`.
public enum PointerShape: Sendable, CaseIterable {
    /// The ordinary arrow, which is what the canvas shows until a sketch asks
    /// for something else.
    case arrow
    /// Thin crossed lines, for picking an exact point.
    case crosshair
    /// A hand with a pointing finger, for something that can be clicked.
    case pointingHand
    /// An open hand, for something that can be grabbed and moved.
    case openHand
    /// A closed hand, for something being moved.
    case closedHand
    /// The text cursor.
    case iBeam
    /// A circle with a line through it, for something that cannot be done here.
    case notAllowed
    /// A magnifier with a plus sign.
    case zoomIn
    /// A magnifier with a minus sign.
    case zoomOut
    /// Arrows pointing left and right, for moving a vertical edge.
    case columnResize
    /// Arrows pointing up and down, for moving a horizontal edge.
    case rowResize
    /// The arrow with a small plus sign, for something that will be copied.
    case dragCopy
}

#if os(macOS)
extension PointerShape {
    /// The system cursor this shape names.
    var systemCursor: NSCursor {
        switch self {
        case .arrow: .arrow
        case .crosshair: .crosshair
        case .pointingHand: .pointingHand
        case .openHand: .openHand
        case .closedHand: .closedHand
        case .iBeam: .iBeam
        case .notAllowed: .operationNotAllowed
        case .zoomIn: .zoomIn
        case .zoomOut: .zoomOut
        case .columnResize: .columnResize
        case .rowResize: .rowResize
        case .dragCopy: .dragCopy
        }
    }
}
#endif

public extension Sketch {
    /// Give the pointer over the canvas one of the system's shapes.
    ///
    /// The shape holds until another call changes it, only over the canvas:
    /// the rest of the window, and a host's sidebar beside the canvas, keep the
    /// ordinary arrow. Setting a shape does not show a pointer that
    /// ``hidePointer()`` hid; the two are kept apart, so a sketch can choose
    /// the shape it will want while the pointer is hidden.
    ///
    /// ```swift
    /// override func draw() {
    ///     pointerShape(hovered == nil ? .crosshair : .openHand)
    /// }
    /// ```
    ///
    /// On a phone or a tablet there is no pointer to shape, and the call does
    /// nothing; in an export it does nothing either.
    func pointerShape(_ shape: PointerShape) {
        guard shape != requestedPointer else { return }
        requestedPointer = shape
        host?.sketchPointerChanged(self)
    }

    /// Hide the pointer while it is over the canvas, for a sketch that draws
    /// its own (a brush outline, a reticle) at `mouse`. It comes back over
    /// the rest of the window, and with ``showPointer()``.
    ///
    /// An installation that hides the pointer (`Installation.hidesPointer`)
    /// hides it over the whole screen whatever the sketch asks; this one is
    /// only the sketch's own and never undoes that.
    func hidePointer() {
        guard !hidesPointerOverCanvas else { return }
        hidesPointerOverCanvas = true
        host?.sketchPointerChanged(self)
    }

    /// Show the pointer that ``hidePointer()`` hid, in the shape
    /// ``pointerShape(_:)`` last set.
    func showPointer() {
        guard hidesPointerOverCanvas else { return }
        hidesPointerOverCanvas = false
        host?.sketchPointerChanged(self)
    }
}

// MARK: - The open panel

public extension Sketch {
    /// Show the system's open panel so the person running the sketch can pick
    /// a file, and carry on drawing while it is open.
    ///
    /// The call returns at once and the frames keep coming. When the panel
    /// closes on a pick, the paths join ``chosenFiles()`` as `String` paths and
    /// ``filesChosen()`` fires; a panel closed without a pick adds nothing.
    /// The usual caller is an input hook:
    ///
    /// ```swift
    /// override func keyPressed() {
    ///     if key == "o" { chooseFiles(withExtensions: ["png", "jpg", "heic"]) }
    /// }
    /// override func filesChosen() {
    ///     for path in chosenFiles() { photo = (try? loadImage(path)) ?? photo }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - extensions: the file extensions the panel offers, without the dot
    ///     (`"png"`, `"csv"`). Empty, the default, offers every file.
    ///   - allowsMultiple: whether several files can be picked at once.
    ///
    /// While a panel is open a second call does nothing. The panel opens over
    /// the sketch's window on the Mac; on a phone or a tablet, and in an
    /// export, there is no panel and the call does nothing.
    func chooseFiles(withExtensions extensions: [String] = [], allowsMultiple: Bool = false) {
        host?.sketchWantsFiles(self, extensions: extensions, allowsMultiple: allowsMultiple)
    }
}

extension Sketch {
    /// Files picked through the open panel, from the runner: the paths join the
    /// inbox and the hook fires. Like a drop, a pick is live input outside a
    /// take, neither recorded nor replayed.
    func handleChosenFiles(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        chosenFileInbox.append(contentsOf: paths)
        filesChosen()
    }
}
