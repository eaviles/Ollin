import Foundation
import Ollin
import Testing
import simd

/// Pure CPU checks on `Rotation3D`, the turn a body faces by: it reads back as
/// the angle and axis it was built from, composes in the stated order, undoes
/// itself, points one direction at another, and turns a vector the way the
/// drawing stack does. No Metal, so these run everywhere including CI.
@Suite
struct Rotation3DTests {

    private func close(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool {
        abs(a - b) <= eps
    }

    private func close(_ a: Vector3, _ b: Vector3, _ eps: Double = 1e-9) -> Bool {
        (a - b).length <= eps
    }

    @Test func anAngleAboutAnAxisReadsBack() {
        let turn = Rotation3D(angle: 0.7, axis: Vector3(0, 0, 3))
        #expect(close(turn.angle, 0.7))
        #expect(close(turn.axis, .unitZ))
        #expect(close(Rotation3D.aboutY(1.2).angle, 1.2))
        #expect(close(Rotation3D.aboutY(1.2).axis, .unitY))
    }

    @Test func noTurnHasNoAngleAndAnAxisToLeanOn() {
        #expect(close(Rotation3D.identity.angle, 0))
        #expect(Rotation3D.identity.axis == .unitY)
        #expect(Rotation3D(angle: 1, axis: .zero) == .identity)
        #expect(Rotation3D(x: 0, y: 0, z: 0, w: 0) == .identity)
    }

    @Test func aTurnAndItsNegatedQuaternionAreOneValue() {
        // The same turn written both ways compares equal, so a body's pose read
        // back from a solver matches the value that set it.
        let a = Rotation3D(x: 0, y: 0.6, z: 0, w: 0.8)
        let b = Rotation3D(x: 0, y: -0.6, z: 0, w: -0.8)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(a.w >= 0)
    }

    @Test func aQuarterTurnAboutYTakesXToMinusZ() {
        // Right-handed: looking down from +y, +x swings toward -z.
        let quarter = Rotation3D.aboutY(.pi / 2)
        #expect(close(Vector3.unitX.rotated(by: quarter), Vector3(0, 0, -1)))
        #expect(close(Vector3.unitY.rotated(by: quarter), .unitY))
    }

    @Test func composingTurnsByTheSecondFirst() {
        let a = Rotation3D.aboutX(.pi / 2)
        let b = Rotation3D.aboutY(.pi / 2)
        let v = Vector3.unitX
        // `a * b` is b then a, so it matches turning by b and then by a.
        let stepwise = v.rotated(by: b).rotated(by: a)
        #expect(close(v.rotated(by: a * b), stepwise))
        #expect(!close(v.rotated(by: b * a), stepwise), "the order has to matter here")
    }

    @Test func aTurnUndoneIsNoTurn() {
        let turn = Rotation3D(angle: 2.1, axis: Vector3(1, 2, 3))
        let back = turn * turn.inverse
        #expect(close(back.angle, 0, 1e-9))
        let v = Vector3(3, -1, 2)
        #expect(close(v.rotated(by: turn).rotated(by: turn.inverse), v))
    }

    @Test func theTurnBetweenTwoDirections() {
        let turn = Rotation3D(from: .unitX, to: Vector3(0, 5, 0))
        #expect(close(Vector3.unitX.rotated(by: turn), .unitY))
        #expect(close(turn.angle, .pi / 2))
        // Already aligned: nothing to do.
        #expect(Rotation3D(from: .unitZ, to: Vector3(0, 0, 4)) == .identity)
        // Opposed: a half turn that still lands where asked.
        let flip = Rotation3D(from: .unitX, to: -.unitX)
        #expect(close(flip.angle, .pi))
        #expect(close(Vector3.unitX.rotated(by: flip), -.unitX, 1e-9))
    }

    @Test func halfwayBetweenTwoTurnsIsHalfTheAngle() {
        let a = Rotation3D.identity
        let b = Rotation3D.aboutZ(1.0)
        let mid = a.interpolated(to: b, 0.5)
        #expect(close(mid.angle, 0.5))
        #expect(close(mid.axis, .unitZ))
        #expect(a.interpolated(to: b, 0) == a)
        #expect(close(a.interpolated(to: b, 1).angle, 1.0))
        // The short way round: from nothing to almost a full turn is a small
        // turn the other way, not a long swing.
        let nearlyRound = Rotation3D.aboutZ(2 * .pi - 0.2)
        let step = a.interpolated(to: nearlyRound, 0.5)
        #expect(close(step.angle, 0.1, 1e-9))
    }

    @Test func theMatrixAgreesWithTheVector() {
        let turn = Rotation3D(angle: 0.9, axis: Vector3(1, 1, 0))
        let m = turn.matrix
        let v = Vector3(1, 2, 3)
        let byMatrix = m * SIMD4<Float>(1, 2, 3, 1)
        let byValue = v.rotated(by: turn)
        #expect(close(Vector3(Double(byMatrix.x), Double(byMatrix.y), Double(byMatrix.z)),
                      byValue, 1e-5))
    }

    @Test func survivesARoundTripThroughCodable() throws {
        let turn = Rotation3D(angle: 1.3, axis: Vector3(0.2, -1, 0.5))
        let data = try JSONEncoder().encode(turn)
        let back = try JSONDecoder().decode(Rotation3D.self, from: data)
        #expect(back == turn)
    }
}
