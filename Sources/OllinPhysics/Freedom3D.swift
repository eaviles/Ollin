import Foundation
import Ollin

/// Which ways a `Body3D` is allowed to move: the six degrees of freedom a
/// rigid body has, any of which the solver can take away. Everything is free
/// by default (`.all`); restricting a body is how a 3D world is made to behave
/// like a flat one, or how a crate is kept from ever tipping over.
///
/// ```swift
/// let coin = world.addBody(.cylinder(height: 0.1, radius: 0.4),
///                          at: Vector3(0, 4, 0), freedom: .plane())
/// ```
///
/// The axes are the world's, not the body's: a body that may only turn about
/// `turnY` keeps its feet on the ground however it is spun. Combine the six on
/// their own when none of the named sets fits:
///
/// ```swift
/// slider.freedom = [.moveX, .turnZ]     // runs along x, spinning as it goes
/// ```
public struct Freedom3D: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// Travel along the world's x axis.
    public static let moveX = Freedom3D(rawValue: 1 << 0)
    /// Travel along the world's y axis (up).
    public static let moveY = Freedom3D(rawValue: 1 << 1)
    /// Travel along the world's z axis.
    public static let moveZ = Freedom3D(rawValue: 1 << 2)
    /// Turn about the world's x axis.
    public static let turnX = Freedom3D(rawValue: 1 << 3)
    /// Turn about the world's y axis (up).
    public static let turnY = Freedom3D(rawValue: 1 << 4)
    /// Turn about the world's z axis.
    public static let turnZ = Freedom3D(rawValue: 1 << 5)

    /// Every direction: the default, a body the solver may move any way at all.
    public static let all: Freedom3D = [.moveX, .moveY, .moveZ,
                                        .turnX, .turnY, .turnZ]

    /// Travel any way, but never turn: a body that slides and is shoved around
    /// without ever spinning or rolling.
    public static let noTurning: Freedom3D = [.moveX, .moveY, .moveZ]

    /// Turn any way, but never travel: a body pinned where it is, free to spin.
    /// A turntable without a joint holding it.
    public static let noMoving: Freedom3D = [.turnX, .turnY, .turnZ]

    /// Travel any way and spin about the world's up axis, but never tip over:
    /// a fridge on a dolly, a chess piece that slides and turns but won't fall.
    public static let upright: Freedom3D = [.moveX, .moveY, .moveZ, .turnY]

    /// Flat motion: travel in the plane facing `normal` and turn only about
    /// `normal`, which is what makes a 3D world behave like a 2D one. The
    /// default plane faces the camera (`x` across, `y` up), so a sketch drawn
    /// side-on reads as flat however the bodies are hit.
    ///
    /// ```swift
    /// ball.freedom = .plane()                    // x and y, spinning about z
    /// puck.freedom = .plane(normal: .unitY)      // x and z, spinning about y
    /// ```
    ///
    /// The solver takes away whole world axes, so `normal` is rounded to the
    /// axis it points most nearly along; there is no tilted plane.
    public static func plane(normal: Vector3 = .unitZ) -> Freedom3D {
        let x = abs(normal.x), y = abs(normal.y), z = abs(normal.z)
        if x >= y && x >= z { return [.moveY, .moveZ, .turnX] }
        if y >= z { return [.moveX, .moveZ, .turnY] }
        return [.moveX, .moveY, .turnZ]
    }
}
