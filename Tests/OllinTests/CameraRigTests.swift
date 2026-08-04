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

    // MARK: Interactive move (auto-orbit the viewer can take over)

    private let move = CameraMove.turntable(period: 8)

    private func interactive(_ rig: CameraRig, _ inp: CameraInput,
                             idleTimeout: Double = 10, returnDuration: Double = 4) {
        rig.updateInteractiveMove(move, input: inp, dt: dt, viewportHeight: height,
                                  idleTimeout: idleTimeout, returnDuration: returnDuration)
    }

    /// While no one touches it, the auto-orbit just spins (the move drives).
    @Test func interactiveMoveSpinsWhenIdle() {
        let rig = fresh(radius: 6)
        let start = rig.azimuth
        for _ in 0..<60 { interactive(rig, input()) }     // 1s of a period-8 turn
        #expect(abs((rig.azimuth - start) - Double.tau / 8) < 0.05)
    }

    /// A drag hands off to the controller: the turntable stops advancing, and once
    /// released (still well within the idle window) the pose settles to rest rather
    /// than spinning on at the move's rate.
    @Test func dragInterruptsTheAutoOrbit() {
        let rig = fresh(radius: 6)
        for _ in 0..<30 { interactive(rig, input()) }     // let it spin a bit
        interactive(rig, input(left: true))
        var x = 500.0
        for _ in 0..<30 { x -= 6; interactive(rig, input(x: x, left: true)) }
        for _ in 0..<120 { interactive(rig, input(x: x)) }   // 2s idle (< 10), settles
        let a1 = rig.azimuth
        interactive(rig, input(x: x))
        // If the turntable were still active it would advance ~tau/8/60 ≈ 0.013 rad.
        #expect(abs(rig.azimuth - a1) < 1e-3)
    }

    /// After the idle timeout the camera glides back to the *opening* framing: a
    /// viewer who dollied in and tilted away ends up at the seeded radius/elevation.
    @Test func idleReturnsToOpeningFraming() {
        let rig = fresh(radius: 6, elevation: 0.3)
        func step(_ inp: CameraInput) { interactive(rig, inp, idleTimeout: 1, returnDuration: 1) }
        for _ in 0..<10 { step(input(scroll: 3)) }        // dolly in, away from radius 6
        step(input(left: true)); var y = 500.0
        for _ in 0..<30 { y += 6; step(input(y: y, left: true)) }   // tilt away from 0.3
        for _ in 0..<30 { step(input(y: y)) }             // 0.5s settle (< idle 1)
        #expect(rig.radius < 5.5)
        #expect(abs(rig.elevation - 0.3) > 0.1)
        for _ in 0..<300 { step(input()) }                // idle past timeout + full return
        #expect(abs(rig.radius - 6) < 0.05)
        #expect(abs(rig.elevation - 0.3) < 0.05)
    }

    /// No discontinuity at the manual→returning seam: the pose is held at the
    /// viewer's pose when the return begins and blends in from there.
    @Test func returnStartsWithoutAJump() {
        let rig = fresh(radius: 6)
        func step(_ inp: CameraInput) { interactive(rig, inp, idleTimeout: 1, returnDuration: 4) }
        step(input(left: true)); var x = 500.0
        for _ in 0..<20 { x += 4; step(input(x: x, left: true)) }
        var prev = rig.azimuth
        var maxJump = 0.0
        for _ in 0..<120 {                                // 2s, crosses the 1s seam at 60
            step(input(x: x))
            maxJump = Swift.max(maxJump, abs(rig.azimuth - prev))
            prev = rig.azimuth
        }
        #expect(maxJump < 0.1)                            // a seam jump would be far larger
    }

    /// Grabbing the camera again mid-return cancels it: the new input drives the
    /// pose instead of snapping back to the opening shot.
    @Test func interactionCancelsReturn() {
        let rig = fresh(radius: 6)
        func step(_ inp: CameraInput) { interactive(rig, inp, idleTimeout: 1, returnDuration: 4) }
        for _ in 0..<10 { step(input(scroll: 3)) }        // dolly in
        for _ in 0..<90 { step(input()) }                 // 1.5s: into the (4s) return
        let midReturn = rig.radius
        #expect(midReturn < 5.9)                          // not yet back at 6
        for _ in 0..<10 { step(input(scroll: 3)) }        // grab again, dolly further
        for _ in 0..<30 { step(input()) }                 // 0.5s settle (< idle 1)
        #expect(rig.radius < midReturn)                   // followed the new dolly, not the return
    }

    // MARK: Scene inspection views

    /// The true isometric elevation, `asin(1/√3)` — what `.corner` snaps to.
    private let isoElevation = 0.6154797086703873

    /// A cut (animated: false) snaps the orbit angle to the canonical view at once,
    /// keeping the current center and distance.
    @Test func viewCutsToAxisAngle() {
        let rig = fresh(radius: 7)
        rig.requestView(.front, animated: false, duration: 0)
        #expect(abs(rig.azimuth) < 1e-9)
        #expect(abs(rig.elevation) < 1e-9)
        #expect(rig.radius == 7)                          // distance unchanged

        rig.requestView(.right, animated: false, duration: 0)
        #expect(abs(rig.azimuth - .pi / 2) < 1e-9)

        rig.requestView(.top, animated: false, duration: 0)
        #expect(rig.elevation > 1.5 && rig.elevation < .pi / 2)   // near the pole, never on it
    }

    /// `.corner` is the isometric three-quarter angle (45° around, `asin(1/√3)` up).
    @Test func cornerViewIsIsometric() {
        let rig = fresh()
        rig.requestView(.corner, animated: false, duration: 0)
        #expect(abs(rig.azimuth - .pi / 4) < 1e-9)
        #expect(abs(rig.elevation - isoElevation) < 1e-9)
    }

    /// An animated snap glides to the target angle over its duration: partway it is
    /// between the start and the destination, and by the end it has arrived.
    @Test func viewGlidesToAngle() {
        let rig = fresh()
        rig.requestView(.right, animated: true, duration: 0.5)
        for _ in 0..<15 { rig.applyViewSnap(dt: dt) }     // 0.25s of 0.5
        #expect(rig.azimuth > 0.1 && rig.azimuth < .pi / 2 - 0.1)
        for _ in 0..<30 { rig.applyViewSnap(dt: dt) }     // finish
        #expect(abs(rig.azimuth - .pi / 2) < 1e-6)
    }

    /// `.reset` restores the full opening framing (target, radius, and angle), even
    /// after the viewer has dollied and panned away.
    @Test func resetRestoresOpeningFraming() {
        let rig = fresh(radius: 6, elevation: 0.3)
        for _ in 0..<10 { rig.updateControl(input: input(scroll: 3), dt: dt, viewportHeight: height) }
        rig.updateControl(input: input(right: true), dt: dt, viewportHeight: height)
        var x = 500.0
        for _ in 0..<30 { x += 6; rig.updateControl(input: input(x: x, right: true), dt: dt, viewportHeight: height) }
        for _ in 0..<60 { rig.updateControl(input: input(x: x), dt: dt, viewportHeight: height) }
        #expect(rig.radius < 5.5 || rig.target.distance(to: .zero) > 0.1)   // drifted away

        rig.requestView(.reset, animated: false, duration: 0)
        #expect(abs(rig.radius - 6) < 1e-9)
        #expect(abs(rig.elevation - 0.3) < 1e-9)
        #expect(abs(rig.azimuth) < 1e-9)
        #expect(rig.target.distance(to: .zero) < 1e-9)
    }

    /// Once an `orbitAndRise` has finished its rise, a view snap hands the pose back
    /// to the continuing orbit without replaying the rise: the elevation holds at the
    /// snapped angle (instead of climbing by another rise after every snap) while the
    /// azimuth keeps turning through the snapped pose.
    @Test func orbitAndRiseHoldsElevationAfterSnap() {
        let rig = fresh(elevation: 0.3)
        rig.driver = .move
        let move = CameraMove.orbitAndRise(period: 8, rise: 0.4, in: 1)
        for _ in 0..<120 { rig.updateMove(move, dt: dt) }        // 2s: the 1s rise has played
        #expect(abs(rig.elevation - 0.7) < 1e-6)

        rig.requestView(.front, animated: false, duration: 0)    // snaps elevation to 0
        let snapped = rig.azimuth
        for _ in 0..<60 { rig.updateMove(move, dt: dt) }         // 1s more of the orbit
        #expect(abs(rig.elevation) < 1e-6)                       // held, not risen again
        #expect(abs((rig.azimuth - snapped) - Double.tau / 8) < 0.05)   // still turning, no jump
    }

    /// After a snap, interactive control resumes from the snapped pose with no jump
    /// (the hand-back resyncs the controller's goal to it).
    @Test func controlResumesFromSnappedPose() {
        let rig = fresh(radius: 6)
        rig.requestView(.right, animated: false, duration: 0)   // driver defaults to .control
        let snapped = rig.azimuth
        for _ in 0..<60 { rig.updateControl(input: input(), dt: dt, viewportHeight: height) }
        #expect(abs(rig.azimuth - snapped) < 1e-3)              // held, not drifted
    }

    /// The axis widget's Ortho|Perspective toggle drives `isOrthographic`: the rig
    /// builds a perspective camera by default and an orthographic one when set, with
    /// the orthographic height matching the perspective frustum at the target
    /// distance (2·radius·tan(fov/2)) so flipping projection leaves the scale put.
    @Test func orthographicToggleMatchesFramedScale() {
        let rig = fresh(radius: 10)
        guard case .perspective = rig.makeCamera(near: 0.1, far: 100).projection else {
            Issue.record("default projection should be perspective"); return
        }
        rig.isOrthographic = true
        guard case .orthographic(let h) = rig.makeCamera(near: 0.1, far: 100).projection else {
            Issue.record("isOrthographic should produce an orthographic projection"); return
        }
        #expect(abs(h - 2 * 10 * tan((.pi / 3) / 2)) < 1e-9)
    }

    // MARK: Seeding from an authored camera

    /// The orbit decomposition inverts `Camera3D.orbiting` exactly: an orbit
    /// camera comes back as the parameters that built it.
    @Test func orbitPoseRoundTripsAnOrbitingCamera() {
        let cam = Camera3D.orbiting(target: Vector3(1, 2, 3), radius: 8,
                                    azimuth: 0.7, elevation: 0.4,
                                    fieldOfView: 1.1)
        let pose = cam.orbitPose
        #expect((pose.target - Vector3(1, 2, 3)).length < 1e-9)
        #expect(abs(pose.radius - 8) < 1e-9)
        #expect(abs(pose.azimuth - 0.7) < 1e-9)
        #expect(abs(pose.elevation - 0.4) < 1e-9)
        #expect(abs(pose.fieldOfView - 1.1) < 1e-12)
        #expect(!pose.orthographic)
    }

    /// Seeding the rig from an arbitrary authored camera reproduces its shot:
    /// `makeCamera` lands on the same eye and view axis (up snaps to y-up, the
    /// rig's one convention).
    @Test func seededRigReproducesAnAuthoredCamera() {
        let cam = Camera3D.perspective(eye: Vector3(4, 3, -2), target: Vector3(0.5, 1, 0),
                                       fieldOfView: 0.9, near: 0.25, far: 60)
        let pose = cam.orbitPose
        let rig = CameraRig()
        rig.seed(target: pose.target, radius: pose.radius, azimuth: pose.azimuth,
                 elevation: pose.elevation, fieldOfView: pose.fieldOfView,
                 orthographic: pose.orthographic)
        let made = rig.makeCamera(near: cam.near, far: cam.far)
        #expect((made.eye - cam.eye).length < 1e-9)
        #expect((made.target - cam.target).length < 1e-9)
        #expect(made.near == cam.near)
        #expect(made.far == cam.far)
        guard case .perspective(let fov) = made.projection else {
            Issue.record("expected a perspective projection"); return
        }
        #expect(abs(fov - 0.9) < 1e-12)
    }

    /// An authored orthographic camera opens the rig flat, its frame height
    /// mapped to the field of view at the target distance so the seeded shot
    /// shows the authored extent, and toggling projections holds the scale.
    @Test func orthographicCameraSeedsAnOrthographicRig() {
        let cam = Camera3D.orthographic(eye: Vector3(0, 0, 10), target: .zero, height: 5)
        let pose = cam.orbitPose
        #expect(pose.orthographic)
        let rig = CameraRig()
        rig.seed(target: pose.target, radius: pose.radius, azimuth: pose.azimuth,
                 elevation: pose.elevation, fieldOfView: pose.fieldOfView,
                 orthographic: pose.orthographic)
        guard case .orthographic(let h) = rig.makeCamera(near: 0.1, far: 100).projection else {
            Issue.record("expected an orthographic projection"); return
        }
        #expect(abs(h - 5) < 1e-9)

        // The seed's flag lands once: a later seed can't flip it back.
        rig.seed(target: .zero, radius: 3, elevation: 0, fieldOfView: .pi / 3)
        #expect(rig.isOrthographic)
    }
}
