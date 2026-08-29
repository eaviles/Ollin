#if !os(macOS)

import Foundation
import UIKit
import MetalKit
import simd

/// An `MTKView` that reports a touch to its `Sketch` as `mouseX`/`mouseY`, in
/// sketch coordinates (points, top-left origin). A UIKit view is measured from
/// its top-left corner already, so nothing is flipped here.
///
/// One finger drives the pointer, which is what lets a sketch written for a
/// mouse run on glass with no change: `mouseX`/`mouseY` follow the finger, and
/// `mousePressed` is true while it is down. A stylus or a screen that measures
/// force feeds `pressure` as well.
final class OllinMTKView: MTKView {
    weak var sketch: Sketch?

    /// How this run is fitted to what it is thrown onto, when it is. The
    /// pointer goes back through it, so a piece being calibrated still reads
    /// `mouseX` in its own canvas rather than in screen corners.
    var projection: ProjectionPlacement?

    /// Whether this canvas stays out of the touch path entirely, so every touch
    /// goes to whatever is behind it.
    var ignoresInput = false

    /// Match the display the canvas landed on. The rate is asked for here
    /// rather than at build time, because a view has no screen until it joins a
    /// window, and a phone that can draw at 120 would otherwise stay at 60.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let screen = window?.windowScene?.screen else { return }
        preferredFramesPerSecond = screen.maximumFramesPerSecond
    }

    // MARK: - The finger as a pointer

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !ignoresInput, let touch = touches.first else { return }
        report(touch)
        reportForce(touch)
        sketch?.handleMouseButton(pressed: true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !ignoresInput, let touch = touches.first else { return }
        report(touch)
        reportForce(touch)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !ignoresInput, let touch = touches.first else { return }
        endTouch(touch)
    }

    /// A touch the system took away (a call arrived, a system gesture won) must
    /// end the press too. Without this the sketch keeps a finger down that is
    /// no longer on the glass.
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !ignoresInput, let touch = touches.first else { return }
        endTouch(touch)
    }

    private func endTouch(_ touch: UITouch) {
        report(touch)
        sketch?.setPressure(0, canVary: false)
        sketch?.handleMouseButton(pressed: false)
    }

    /// Hand the sketch the touch position in its own coordinates (see
    /// `canvasPoint(_:)` for the conversion).
    private func report(_ touch: UITouch) {
        guard let sketch, let point = canvasPoint(touch.location(in: self)) else { return }
        sketch.setMouse(x: point.x, y: point.y)
    }

    /// Hand the sketch the press force, and whether this device can vary it at
    /// all. A screen that cannot measure force reports a maximum of zero, and
    /// then a touch is a plain full press, which is what a mouse click reports.
    private func reportForce(_ touch: UITouch) {
        let maximum = Double(touch.maximumPossibleForce)
        guard maximum > 0 else {
            sketch?.setPressure(1, canVary: false)
            return
        }
        sketch?.setPressure(min(Double(touch.force) / maximum, 1), canVary: true)
    }

    /// A point in the view, in sketch space. The view's bounds are in points,
    /// but the logical canvas (`sketch.width`/`height`) may be larger (a 1080
    /// canvas shown on a 393-pt screen), so normalize by the bounds and rescale
    /// into canvas space.
    func canvasPoint(_ viewPoint: CGPoint) -> Vector2? {
        guard let sketch else { return nil }
        let bw = Double(bounds.width), bh = Double(bounds.height)
        // A fitted piece fills the display and puts its picture inside that
        // through a warp, so the pointer takes the same warp backwards.
        if let projection, bw > 0, bh > 0 {
            let onCanvas = projection.canvasPoint(
                fromOutput: Vector2(Double(viewPoint.x) / bw, Double(viewPoint.y) / bh))
            return Vector2(onCanvas.x * sketch.width, onCanvas.y * sketch.height)
        }
        let x = bw > 0 ? Double(viewPoint.x) / bw * sketch.width : Double(viewPoint.x)
        let y = bh > 0 ? Double(viewPoint.y) / bh * sketch.height : Double(viewPoint.y)
        return Vector2(x, y)
    }

    /// What the canvas says about itself, for a reader that cannot see it. The
    /// runner calls this once a frame on either platform. The touch side has no
    /// described parts yet, so this costs one call and does nothing.
    func refreshDescription() {}
}

@MainActor
func makeOllinMTKView(device: MTLDevice, size: CGSize, sketch: Sketch) -> OllinMTKView {
    let view = OllinMTKView(frame: CGRect(origin: .zero, size: size), device: device)
    view.sketch = sketch
    // One finger is the pointer, so the second one must not move it.
    view.isMultipleTouchEnabled = false
    configureOllinCanvas(view, sketch: sketch)
    return view
}

#endif
