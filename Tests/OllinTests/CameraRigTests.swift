@testable import Ollin
import Testing

/// Pure CPU checks on `CameraRig`: the interactive controller's orbit / dolly /
/// pan responses and damping, and the cinematic-move pose, driven by synthetic
/// `CameraInput` rather than real events. No Metal, so these run everywhere.
@Suite
struct CameraRigTests {

    private let dt = 1.0 / 60
    private let height = 1000.0

    private func input(x: Double = 500, y: Double = 500, left: Bool = false, right: Bool = false,
                       mods: ModifierKeys = [], scroll: Double = 0) -> CameraInput {
        CameraInput(mouseX: x, mouseY: y, leftPressed: left, rightPressed: right,
                    modifiers: mods, scrollDeltaY: scroll)
    }

    private func fresh(radius: Double = 10, elevation: Double = 0.3) -> CameraRig {
        let rig = CameraRig()
        rig.seed(target: .zero, radius: radius, elevation: elevation, fieldOfView: .pi / 3)
        return rig
    }

    /// The first seed wins; a later one is ignored, so passing framing every frame
    /// does not snap the pose.
    @Test func seedOnce() {
        let rig = CameraRig()
        rig.seed(target: Vector3(1, 2, 3), radius: 8, azimuth: 0.5, elevation: 0.4, fieldOfView: .pi / 3)
        #expect(rig.radius == 8)
        #expect(rig.azimuth == 0.5)
        rig.seed(target: .zero, radius: 99, elevation: 0, fieldOfView: .pi / 4)
        #expect(rig.radius == 8)
    }

    /// A turntable move advances the azimuth a full turn over its period.
    @Test func turntableSpins() {
        let rig = fresh(radius: 6)
        let start = rig.azimuth
        for _ in 0..<60 { rig.updateMove(.turntable(period: 4), dt: dt) }   // 1s of a 4s turn
        #expect(abs((rig.azimuth - start) - Double.tau * 0.25) < 0.05)
    }

    /// A rightward left-drag turns the azimuth and then settles to rest.
    @Test func orbitDragTurnsAndSettles() {
        let rig = fresh()
        rig.updateControl(input: input(left: true), dt: dt, viewportHeight: height)
        var x = 500.0
        for _ in 0..<40 { x += 5; rig.updateControl(input: input(x: x, left: true), dt: dt, viewportHeight: height) }
        for _ in 0..<400 { rig.updateControl(input: input(x: x), dt: dt, viewportHeight: height) }
        #expect(rig.azimuth < -1.0)                       // dragged right -> azimuth decreased

        let before = rig.azimuth                          // and it has settled
        rig.updateControl(input: input(x: x), dt: dt, viewportHeight: height)
        #expect(abs(rig.azimuth - before) < 1e-4)
    }

    /// A vertical drag changes the elevation.
    @Test func dragChangesElevation() {
        let rig = fresh()
        rig.updateControl(input: input(left: true), dt: dt, viewportHeight: height)
        var y = 500.0
        for _ in 0..<40 { y += 5; rig.updateControl(input: input(y: y, left: true), dt: dt, viewportHeight: height) }
        for _ in 0..<200 { rig.updateControl(input: input(y: y), dt: dt, viewportHeight: height) }
        #expect(abs(rig.elevation - 0.3) > 0.2)
    }

    /// Scrolling up dollies in (radius shrinks) and settles.
    @Test func scrollDolliesIn() {
        let rig = fresh(radius: 10)
        for _ in 0..<10 { rig.updateControl(input: input(scroll: 3), dt: dt, viewportHeight: height) }
        for _ in 0..<200 { rig.updateControl(input: input(), dt: dt, viewportHeight: height) }
        #expect(rig.radius < 9)
        #expect(rig.radius > 0)
    }

    /// A right-drag pans the target off the origin without orbiting.
    @Test func rightDragPans() {
        let rig = fresh()
        rig.updateControl(input: input(right: true), dt: dt, viewportHeight: height)
        var x = 500.0
        for _ in 0..<30 { x += 6; rig.updateControl(input: input(x: x, right: true), dt: dt, viewportHeight: height) }
        for _ in 0..<200 { rig.updateControl(input: input(x: x), dt: dt, viewportHeight: height) }
        #expect(rig.target.distance(to: .zero) > 0.1)
        #expect(abs(rig.azimuth) < 0.05)
    }

    /// A shift+left-drag pans too (the modifier route), not orbits.
    @Test func modifierDragPans() {
        let rig = fresh()
        rig.updateControl(input: input(left: true, mods: [.shift]), dt: dt, viewportHeight: height)
        var x = 500.0
        for _ in 0..<30 { x += 6; rig.updateControl(input: input(x: x, left: true, mods: [.shift]), dt: dt, viewportHeight: height) }
        for _ in 0..<200 { rig.updateControl(input: input(x: x), dt: dt, viewportHeight: height) }
        #expect(rig.target.distance(to: .zero) > 0.1)
        #expect(abs(rig.azimuth) < 0.05)
    }

    /// Even a hard vertical drag never tips the elevation past the pole.
    @Test func elevationStaysOffPole() {
        let rig = fresh()
        rig.updateControl(input: input(left: true), dt: dt, viewportHeight: height)
        var y = 500.0
        for _ in 0..<400 { y -= 20; rig.updateControl(input: input(y: y, left: true), dt: dt, viewportHeight: height) }
        for _ in 0..<100 { rig.updateControl(input: input(y: y), dt: dt, viewportHeight: height) }
        #expect(abs(rig.elevation) < Double.pi / 2)
        #expect(rig.makeCamera(near: 0.1, far: 100).eye.length.isFinite)
    }

    /// Frame a shot by hand, then a cinematic move departs from that pose.
    @Test func moveContinuesFromFramedPose() {
        let rig = fresh()
        rig.updateControl(input: input(left: true), dt: dt, viewportHeight: height)
        var x = 500.0
        for _ in 0..<30 { x += 5; rig.updateControl(input: input(x: x, left: true), dt: dt, viewportHeight: height) }
        for _ in 0..<120 { rig.updateControl(input: input(x: x), dt: dt, viewportHeight: height) }
        let framed = rig.azimuth
        rig.updateMove(.turntable(period: 100), dt: dt)   // slow, so frame 1 barely moves
        #expect(abs(rig.azimuth - framed) < 0.05)
    }
}
