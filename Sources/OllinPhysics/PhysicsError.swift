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

    public var description: String {
        switch self {
        case .unbuildable(let what): return what
        }
    }
}
