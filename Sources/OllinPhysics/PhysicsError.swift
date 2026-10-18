import Foundation

/// What a world throws when it is handed something it cannot build from.
///
/// A vehicle with no wheels, a figure from a scene with no skin, a cloth from
/// a mesh with no triangle, a rope through one point: each is a failure the
/// call can see for itself, so it throws rather than handing back `nil`
/// beside a printed line. The text says what was needed.
public enum PhysicsError: Error, CustomStringConvertible {
    /// The thing could not be built from what was handed in; the text names
    /// what it needed.
    case unbuildable(String)
    /// The 3D world already holds as many bodies as it was made for
    /// (`World3D(maxBodies:)`), so nothing more can be added until one is
    /// removed. Rigid bodies, soft bodies, ropes, a ragdoll's limbs, a
    /// vehicle's chassis, and a character's inner body all count.
    case full(maxBodies: Int)

    public var description: String {
        switch self {
        case .unbuildable(let what): return what
        case .full(let maxBodies):
            return "the world is full: it was made for \(maxBodies) bodies and holds that many. "
                + "Make it with a larger maxBodies, or remove a body first."
        }
    }
}
