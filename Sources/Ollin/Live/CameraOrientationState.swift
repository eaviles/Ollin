import Foundation
import Observation
import simd

/// The live camera state the axis widget reads, written by the drawing runner each
/// frame. It is split deliberately so the 2D path stays untaxed and the render
/// thread can't drive a re-entrant SwiftUI pass:
///
/// - `orientation` changes every frame and is observed; the runner publishes it off
///   the render call stack (on the main queue, never inline, since mutating an
///   observed value inside the render callback would drive a re-entrant layout
///   pass). Driving the widget from this data, rather than a `TimelineView(.animation)`,
///   is deliberate: SwiftUI pauses that free-running timeline when the window
///   isn't the active window, which would freeze the widget while the scene keeps
///   orbiting. A data update on the main queue is honored regardless of focus, so
///   the tripod tracks the orbit even when the window is in the background.
/// - `is3D` / `axisVisible` / `gridVisible` change rarely and *are* observed: they
///   gate whether the widget mounts at all. A 2D sketch leaves `is3D` false, so no
///   widget (and no timeline) is created. The runner publishes them off the render
///   call stack and only on a real change, the way the stats readout does.
@Observable
final class CameraOrientationState {
    /// The active camera's world to view rotation (its upper-left 3x3), so a world
    /// axis `a` projects onto the puck as `orientation * a` (x right, y up, z toward
    /// the viewer). Identity when no 3D camera is set this frame.
    var orientation = matrix_identity_float3x3
    /// Whether this frame has a 3D camera at all; the widget stays unmounted (and
    /// its timeline absent) otherwise, so a 2D sketch pays nothing.
    var is3D = false
    /// The sketch's own `cameraAxis(_:)` / `groundGrid(_:)` flags, mirrored so the
    /// widget shows when the sketch asks (the menu toggle is OR-ed on top in the host).
    var axisVisible = false
    var gridVisible = false
}
