import Foundation

/// Which eye of a stereo pair a camera is standing in for.
public enum StereoEye: String, CaseIterable, Sendable {
    case left
    case right

    /// Which way this eye steps off the centre line: left is negative along the
    /// camera's own right axis.
    var sign: Double { self == .left ? -1 : 1 }
}

/// How far apart the two eyes stand, and how far away they agree.
///
/// These are the only two numbers a stereo pair needs, and both are artwork
/// parameters rather than quality settings: they decide how deep the piece
/// reads, the way a focal length decides how a shot is framed. Leave either one
/// out and it is worked out from the camera, which usually says enough.
///
/// - `convergence` is the distance at which the two eyes see the same thing.
///   Whatever sits there lands on the screen; nearer things come out of it,
///   farther things sit behind it. Unset, it is the camera's own target: you are
///   already looking at the thing the piece is about.
/// - `interocular` is the distance between the eyes, in world units. Unset, the
///   eyes sit **1% of the frame width apart**, measured at the convergence
///   plane. For a perspective camera that one sentence is also the classic
///   comfort rule, because 1% of the frame width apart at the convergence plane
///   is exactly 1% of the frame width apart at infinity: the far background
///   separates by less than a viewer's own eyes do, so nothing ever asks them to
///   diverge.
///
/// A world unit is whatever the sketch draws in, so the derived figure follows
/// the scene rather than assuming meters. Setting `interocular` by hand is how
/// you push the depth: half the derived figure reads flatter and safer, twice it
/// reads deeper and starts to strain.
public struct StereoGeometry: Equatable, Sendable {

    /// Distance between the eyes in world units; `nil` derives it (see above).
    public var interocular: Double?
    /// The distance at which the eyes agree; `nil` uses the camera's target.
    public var convergence: Double?

    public init(interocular: Double? = nil, convergence: Double? = nil) {
        self.interocular = interocular
        self.convergence = convergence
    }

    /// Both numbers taken from the camera.
    public static let automatic = StereoGeometry()

    /// The two numbers this comes to for `camera` at a viewport `aspect`, with
    /// anything left out worked out from the camera.
    ///
    /// Worth having in hand: it is how a sketch can show the spacing it is
    /// about to export with, or take the derived figure as the thing to scale
    /// rather than replacing it with a number out of nowhere.
    ///
    /// The frame width is read off the camera's own projection rather than its
    /// field of view, so a lens described by intrinsics and one described by an
    /// angle are measured the same way, and the letterboxing an intrinsic camera
    /// applies is already in the number.
    public func resolved(for camera: Camera3D, aspect: Double = 1) -> (interocular: Double, convergence: Double) {
        let distance = (camera.eye - camera.target).length
        let convergence = max(self.convergence ?? distance, 1e-6)
        if let interocular { return (interocular, convergence) }

        let p00 = Double(camera.projectionMatrix(aspect: aspect).columns.0.x)
        guard p00 > 0 else { return (convergence / 100, convergence) }
        // Half the frame width at the convergence plane is `convergence / p00` for a
        // camera with a vanishing point, and `1 / p00` for one without: an
        // orthographic frame is the same width wherever you measure it.
        let orthographic = if case .orthographic = camera.projection { true } else { false }
        let halfWidth = (orthographic ? 1 : convergence) / p00
        return (halfWidth / 50, convergence)
    }
}

public extension Camera3D {

    /// This camera as one eye of a stereo pair.
    ///
    /// The eye and its target both step sideways along the camera's own right
    /// axis, so the two eyes look **parallel** rather than crossing at a point,
    /// and the projection leans back in so they agree exactly at `convergence`.
    /// That is the rig a stereo film is shot on, and the reason for it is that
    /// toeing two cameras in at a subject tilts their frames against each other,
    /// which reads as a vertical misalignment at the corners that no viewer can
    /// fuse away.
    ///
    /// Everything else about the camera is untouched, so a pair renders through
    /// the ordinary path: same near and far, same lens, same everything a single
    /// frame would have used.
    func stereoEye(_ eye: StereoEye, interocular: Double, convergence: Double) -> Camera3D {
        let lateral = eye.sign * interocular / 2
        guard lateral != 0, convergence > 0 else { return self }
        // The right axis exactly as `lookAt` builds it, so the step is along the
        // frame's own horizontal rather than an approximation of it.
        let back = (self.eye - target).normalized
        let axis = up.cross(back)
        guard axis.length > 1e-9 else { return self }   // up parallel to the view: no horizon to step along
        let right = axis.normalized

        var camera = self
        camera.eye = self.eye + right * lateral
        camera.target = target + right * lateral
        camera.stereoLateral = lateral
        camera.stereoConvergence = convergence
        return camera
    }

    /// The horizontal angle this camera frames, in radians, measured at
    /// `convergence`. For a camera with a vanishing point that is just its lens
    /// angle across the frame, the same at any distance. An orthographic camera
    /// has no lens angle at all, so what comes back is the angle its frame would
    /// subtend from `convergence` away, which is the honest reading of the
    /// question a player asks when it wants to know how wide the shot is.
    func horizontalFieldOfView(aspect: Double, convergence: Double) -> Double {
        let p00 = Double(projectionMatrix(aspect: aspect).columns.0.x)
        guard p00 > 0, convergence > 0 else { return .pi / 3 }
        let orthographic = if case .orthographic = projection { true } else { false }
        let halfWidth = (orthographic ? 1 : convergence) / p00
        return 2 * atan(halfWidth / convergence)
    }

    /// The pair `geometry` comes to for this camera at a viewport `aspect`.
    func stereoPair(_ geometry: StereoGeometry = .automatic,
                    aspect: Double) -> (left: Camera3D, right: Camera3D) {
        let (interocular, convergence) = geometry.resolved(for: self, aspect: aspect)
        return (stereoEye(.left, interocular: interocular, convergence: convergence),
                stereoEye(.right, interocular: interocular, convergence: convergence))
    }
}
