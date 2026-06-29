import Foundation

/// The input a `CameraRig` reads to drive the interactive controller, filled by
/// the `Sketch` from its own input fields so the rig stays free of any windowing
/// framework. Mouse coordinates are in canvas units (the same space `viewportHeight`
/// is measured in), so the rotation and pan scalings are unit-consistent.
struct CameraInput {
    var mouseX: Double
    var mouseY: Double
    var leftPressed: Bool
    var rightPressed: Bool
    var modifiers: ModifierKeys
    var scrollDeltaY: Double
}

/// A canonical camera angle for inspecting a 3D scene, the way a modeling tool's
/// numpad snaps the viewport to a known orientation.
///
/// `reset` returns to the sketch's opening framing (its center, distance, and
/// angle); the six axis views look straight down each axis (each flattens the
/// scene to two axes); and `corner` is the isometric three-quarter view that shows
/// all three axes at once. The axis and corner views keep the current center and
/// distance and only swing the orbit angle.
public enum CameraView: String, Sendable, CaseIterable {
    case reset
    case front, back, left, right, top, bottom
    case corner
}

/// Owns the canonical orbit pose (target, radius, azimuth, elevation, field of
/// view) that both the interactive controller and the cinematic moves drive, and
/// turns it into a `Camera3D` each frame.
///
/// Internal: the `Sketch` holds one and advances it explicitly from
/// `cameraControl()` / `cameraMove(_:)`, so it never relies on the per-frame
/// reflection pass that auto-advances `@Eased` and stored `Timeline`s. Because
/// both halves write the same pose, framing a shot by hand and then handing off
/// to a cinematic move continues from where the hands left it.
final class CameraRig {
    // The canonical pose `Camera3D.orbiting` consumes.
    var target: Vector3 = .zero
    var radius: Double = 10
    var azimuth: Double = 0
    var elevation: Double = 0.3
    var fieldOfView: Double = .pi / 3

    private var seeded = false

    /// Keep the elevation a hair off the poles so the look-at frame never degenerates
    /// (eye straight above the target leaves the up vector parallel to the view).
    private let maxElevation = Double.pi / 2 - 0.01

    /// Which half drove the pose last, so the controller re-syncs its goal to the
    /// current pose whenever it resumes after a cinematic move (or on the first
    /// frame), letting "frame by hand, run a move, grab it again" pick up smoothly.
    private enum Mode { case none, control, move }
    private var lastMode: Mode = .none

    /// Which public camera API is driving the rig this frame, set by the `Sketch`
    /// before its per-frame update so a finished view snap knows how to hand the
    /// pose back to the right motion with no jump.
    enum Driver { case control, move, showcase }
    var driver: Driver = .control

    // MARK: Interactive control state

    // The input-driven goal the smoothed pose eases toward (the damping target).
    private var goalAzimuth = 0.0
    private var goalElevation = 0.0
    private var goalRadius = 0.0
    private var goalTarget = Vector3.zero
    private var lastMouseX = 0.0
    private var lastMouseY = 0.0
    private var wasInteracting = false
    // Release momentum: a smoothed, capped angular velocity (rad/s) carried after an
    // orbit ends, so a flick keeps a little spin before settling.
    private var velAzimuth = 0.0
    private var velElevation = 0.0

    // Tunables (good defaults; reimplemented from the canonical orbit-control model).
    private let orbitSensitivity = 1.0          // a full canvas-height drag is one turn
    private let dollyBase = 0.97                 // radius multiply per scroll unit
    private let minRadius = 0.05
    private let maxRadius = 1e6
    private let smoothRate = 14.0                // pose-to-goal easing rate (1/s)
    private let momentumDecay = 5.0              // how fast a released spin dies (1/s)
    private let velSmoothing = 0.35             // EMA factor for the release velocity
    private let maxSpin = 6.0                   // cap on carried velocity (rad/s)

    // MARK: Cinematic-move state

    private var activeMove: CameraMove?
    private var moveClock: Double = 0
    private var baseAzimuth = 0.0
    private var baseElevation = 0.0
    private var baseRadius = 0.0
    private var baseTarget = Vector3.zero
    private var radiusTimeline: Timeline<Double>?
    private var elevationTimeline: Timeline<Double>?

    /// A private smooth field for the handheld drift, seeded independently of the
    /// sketch's `noise()` so a handheld move neither reads nor disturbs it.
    private let breath = PerlinNoise(seed: 0x0A11_0CA3_CA3E_0B07)

    // MARK: Interactive-move state

    /// `updateInteractiveMove` is a small state machine over the two halves above:
    /// the move plays (`driving`) until the viewer touches the camera (`manual`),
    /// and after an idle stretch it eases back to the opening shot (`returning`).
    private enum InteractivePhase { case driving, manual, returning }
    private var interactivePhase: InteractivePhase = .driving
    private var idleClock = 0.0
    private var returnClock = 0.0
    private var returnFromAzimuth = 0.0
    private var returnFromElevation = 0.0
    private var returnFromRadius = 0.0
    private var returnFromTarget = Vector3.zero

    /// The opening framing captured at `seed()`, so the idle return glides back to
    /// the shot the sketch framed rather than wherever the viewer left the camera.
    private var anchorTarget = Vector3.zero
    private var anchorRadius = 10.0
    private var anchorAzimuth = 0.0
    private var anchorElevation = 0.3

    /// Seed the starting pose once. The first `cameraControl()` / `cameraMove()`
    /// call wins; later calls keep whatever the controller or move has reached, so
    /// passing framing arguments every frame does not snap the pose back.
    func seed(target: Vector3, radius: Double, azimuth: Double = 0,
              elevation: Double, fieldOfView: Double) {
        guard !seeded else { return }
        seeded = true
        self.target = target
        self.radius = radius
        self.azimuth = azimuth
        self.elevation = elevation
        self.fieldOfView = fieldOfView
        anchorTarget = target
        anchorRadius = radius
        anchorAzimuth = azimuth
        anchorElevation = elevation
    }

    // MARK: Interactive control

    /// Drive the pose from this frame's `input` with damped orbit / dolly / pan.
    func updateControl(input: CameraInput, dt: Double, viewportHeight: Double) {
        // Resume cleanly after a move (or on the first control frame): the goal
        // starts at wherever the pose currently is, and a fresh drag won't jump.
        if lastMode != .control {
            syncControlGoal()
            lastMouseX = input.mouseX
            lastMouseY = input.mouseY
            wasInteracting = false
        }
        lastMode = .control

        let panModifier = input.modifiers.contains(.shift) || input.modifiers.contains(.option)
        let isOrbit = input.leftPressed && !panModifier
        let isPan = input.rightPressed || (input.leftPressed && panModifier)
        let interacting = isOrbit || isPan

        // Seed the reference point when a drag starts, so the first frame has no
        // delta (otherwise an earlier hover position would snap the camera), and a
        // fresh orbit starts from rest.
        if interacting && !wasInteracting {
            lastMouseX = input.mouseX
            lastMouseY = input.mouseY
            if isOrbit { velAzimuth = 0; velElevation = 0 }
        }
        let dx = input.mouseX - lastMouseX
        let dy = input.mouseY - lastMouseY
        lastMouseX = input.mouseX
        lastMouseY = input.mouseY
        wasInteracting = interacting

        let height = Swift.max(viewportHeight, 1)

        if isOrbit {
            let rot = Double.tau / height * orbitSensitivity
            goalAzimuth -= dx * rot
            goalElevation += dy * rot
            // Track a smoothed, capped velocity for the release flick.
            let instAz = (-dx * rot) / Swift.max(dt, 1e-4)
            let instEl = (dy * rot) / Swift.max(dt, 1e-4)
            velAzimuth = clampSpin(velAzimuth + (instAz - velAzimuth) * velSmoothing)
            velElevation = clampSpin(velElevation + (instEl - velElevation) * velSmoothing)
        } else if isPan {
            velAzimuth = 0   // a deliberate pan cancels any carried orbit spin
            velElevation = 0
        } else {
            // Idle: coast on the released orbit's momentum, decaying to rest.
            goalAzimuth += velAzimuth * dt
            goalElevation += velElevation * dt
            let decay = exp(-momentumDecay * dt)
            velAzimuth *= decay
            velElevation *= decay
        }

        if isPan {
            // Move the target across the focal plane so it tracks the cursor: world
            // units per canvas unit is 2 * radius * tan(fov/2) / height.
            let scale = 2 * goalRadius * tan(fieldOfView / 2) / height
            let basis = orbitBasis(azimuth: goalAzimuth, elevation: clampedElevation(goalElevation))
            goalTarget = goalTarget - basis.right * (dx * scale) + basis.up * (dy * scale)
        }

        if input.scrollDeltaY != 0 {
            goalRadius *= pow(dollyBase, input.scrollDeltaY)
            goalRadius = Swift.min(Swift.max(goalRadius, minRadius), maxRadius)
        }

        goalElevation = clampedElevation(goalElevation)

        // Ease the actual pose toward the goal, frame-rate-independently.
        let f = 1 - exp(-smoothRate * dt)
        azimuth += (goalAzimuth - azimuth) * f
        elevation += (goalElevation - elevation) * f
        radius += (goalRadius - radius) * f
        target = target.lerp(to: goalTarget, f)
    }

    private func syncControlGoal() {
        goalAzimuth = azimuth
        goalElevation = elevation
        goalRadius = radius
        goalTarget = target
        velAzimuth = 0
        velElevation = 0
    }

    private func clampSpin(_ v: Double) -> Double {
        Swift.min(Swift.max(v, -maxSpin), maxSpin)
    }

    // MARK: Cinematic moves

    /// Advance the active cinematic `move` by `dt` seconds, writing the pose. When a
    /// different move is handed in, its clock restarts and it departs from the
    /// current pose (so moves chain smoothly).
    func updateMove(_ move: CameraMove, dt: Double) {
        lastMode = .move
        if move != activeMove { startMove(move) }
        moveClock += dt
        radiusTimeline?.advance(by: dt)
        elevationTimeline?.advance(by: dt)
        apply(move, clock: moveClock)
    }

    private func startMove(_ move: CameraMove) {
        activeMove = move
        moveClock = 0
        baseAzimuth = azimuth
        baseElevation = elevation
        baseRadius = radius
        baseTarget = target
        radiusTimeline = nil
        elevationTimeline = nil

        switch move.kind {
        case let .pushIn(factor, duration, ease), let .pullOut(factor, duration, ease):
            radiusTimeline = Timeline(baseRadius).to(baseRadius * factor, in: duration, ease: ease)
        case let .tilt(to, duration, ease):
            elevationTimeline = Timeline(baseElevation).to(to, in: duration, ease: ease)
        case let .orbitAndRise(_, rise, duration):
            elevationTimeline = Timeline(baseElevation).to(baseElevation + rise, in: duration, ease: .easeInOut)
        case let .reveal(duration, ease):
            radiusTimeline = Timeline(baseRadius * 0.45).to(baseRadius, in: duration, ease: ease)
            let low = Swift.max(0.05, baseElevation * 0.35)
            elevationTimeline = Timeline(low).to(baseElevation, in: duration, ease: ease)
        case .turntable, .sway, .handheld:
            break
        }
    }

    private func apply(_ move: CameraMove, clock: Double) {
        // Start from the departure pose; any finite eased property overrides via its
        // timeline, any cyclic property via the clock below.
        azimuth = baseAzimuth
        elevation = elevationTimeline?.value ?? baseElevation
        radius = radiusTimeline?.value ?? baseRadius
        target = baseTarget

        switch move.kind {
        case let .turntable(period):
            azimuth = baseAzimuth + clock * angularSpeed(period)
        case let .sway(amplitude, period):
            azimuth = baseAzimuth + amplitude * sin(clock * angularSpeed(period))
        case let .orbitAndRise(period, _, _):
            azimuth = baseAzimuth + clock * angularSpeed(period)
        case let .handheld(amount, speed):
            let t = clock * speed
            azimuth = baseAzimuth + breath.signedValue(t, 0, 0) * amount
            elevation = baseElevation + breath.signedValue(t, 10, 0) * amount
            radius = baseRadius * (1 + breath.signedValue(t, 20, 0) * amount)
        case .pushIn, .pullOut, .tilt, .reveal:
            break   // radius / elevation already taken from the timelines
        }
    }

    private func angularSpeed(_ period: Double) -> Double {
        period != 0 ? Double.tau / period : 0
    }

    // MARK: Interactive move (auto-orbit the viewer can take over)

    /// Play `move` as an auto-orbit the viewer can grab. A drag / dolly / pan hands
    /// off to the interactive controller; after `idleTimeout` seconds of no input the
    /// pose eases back over `returnDuration` seconds to the opening framing and the
    /// move resumes. Reuses `updateMove` and `updateControl` for the two halves, so
    /// it adds only the phase bookkeeping and the return blend.
    func updateInteractiveMove(_ move: CameraMove, input: CameraInput, dt: Double,
                               viewportHeight: Double, idleTimeout: Double,
                               returnDuration: Double) {
        // Any fresh touch (in driving or returning) hands off to the controller this
        // very frame, so the input that started it (a scroll tick included) lands.
        let interacting = isInteracting(input)
        if interacting && interactivePhase != .manual {
            interactivePhase = .manual
            idleClock = 0
        }

        switch interactivePhase {
        case .driving:
            updateMove(move, dt: dt)

        case .manual:
            updateControl(input: input, dt: dt, viewportHeight: viewportHeight)
            if interacting {
                idleClock = 0
            } else {
                idleClock += dt
                if idleClock >= idleTimeout { beginReturn(to: move) }
            }

        case .returning:
            advanceReturn(move, dt: dt, returnDuration: returnDuration)
        }
    }

    /// Whether this frame's input is the viewer driving the camera: an orbit drag, a
    /// pan (right-drag or modifier-drag), or a scroll dolly.
    private func isInteracting(_ input: CameraInput) -> Bool {
        let panModifier = input.modifiers.contains(.shift) || input.modifiers.contains(.option)
        let isOrbit = input.leftPressed && !panModifier
        let isPan = input.rightPressed || (input.leftPressed && panModifier)
        return isOrbit || isPan || input.scrollDeltaY != 0
    }

    /// Snapshot the viewer's pose, restart the move from the *opening* framing (so the
    /// blend's destination is the original shot, still orbiting), then hold the
    /// displayed pose at the viewer's pose; the return blends in from there.
    private func beginReturn(to move: CameraMove) {
        returnFromAzimuth = azimuth
        returnFromElevation = elevation
        returnFromRadius = radius
        returnFromTarget = target

        target = anchorTarget
        radius = anchorRadius
        elevation = anchorElevation
        azimuth = anchorAzimuth
        startMove(move)                  // base = opening framing, clock 0

        azimuth = returnFromAzimuth       // restore the displayed pose to the viewer's
        elevation = returnFromElevation
        radius = returnFromRadius
        target = returnFromTarget

        returnClock = 0
        interactivePhase = .returning
    }

    /// Ease from the viewer's pose toward the opening-shot orbit; when the blend
    /// completes the move owns the pose again. The move keeps advancing underneath,
    /// so the destination is a live orbit, not a frozen frame.
    private func advanceReturn(_ move: CameraMove, dt: Double, returnDuration: Double) {
        returnClock += dt
        let t = returnDuration > 0 ? Swift.min(returnClock / returnDuration, 1) : 1
        let e = easeInOut(t)

        updateMove(move, dt: dt)          // the opening-framing pose, still orbiting
        let moveAzimuth = azimuth, moveElevation = elevation
        let moveRadius = radius, moveTarget = target

        azimuth = lerpAngle(returnFromAzimuth, moveAzimuth, e)
        elevation = returnFromElevation + (moveElevation - returnFromElevation) * e
        radius = returnFromRadius + (moveRadius - returnFromRadius) * e
        target = returnFromTarget.lerp(to: moveTarget, e)

        if returnClock >= returnDuration { interactivePhase = .driving }
    }

    /// Hermite smoothstep (flat slope at both ends), so the return ramps in and out
    /// smoothly (the orbit's angular velocity rises from rest to full).
    private func easeInOut(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    /// Interpolate an angle along the shortest arc, so a viewer who spun the camera
    /// far around returns the short way instead of unwinding every turn.
    private func lerpAngle(_ a: Double, _ b: Double, _ t: Double) -> Double {
        var diff = (b - a).truncatingRemainder(dividingBy: .tau)
        if diff > .pi { diff -= .tau }
        if diff < -.pi { diff += .tau }
        return a + diff * t
    }

    // MARK: View snap (the scene-inspection standard views)

    /// An in-progress snap toward a canonical angle, eased over `snapDuration`.
    /// While active it overrides whatever the per-frame motion produced, so the
    /// camera glides to the view regardless of which driver is running.
    private var snapActive = false
    private var snapClock = 0.0
    private var snapDuration = 0.0
    private var snapFromAzimuth = 0.0
    private var snapFromElevation = 0.0
    private var snapFromRadius = 0.0
    private var snapFromTarget = Vector3.zero
    private var snapToAzimuth = 0.0
    private var snapToElevation = 0.0
    private var snapToRadius = 0.0
    private var snapToTarget = Vector3.zero

    /// The isometric three-quarter elevation: tilted so the three axes foreshorten
    /// equally (45° around, `asin(1/√3)` up).
    private static let isoElevation = asin(1.0 / sqrt(3.0))

    /// Begin a snap to a canonical inspection angle. `reset` restores the opening
    /// framing (target, radius, and angle); the others keep the current target and
    /// radius and only swing the orbit angle. `animated: false` (or a non-positive
    /// `duration`) cuts instantly.
    func requestView(_ view: CameraView, animated: Bool, duration: Double) {
        var toTarget = target
        var toRadius = radius
        var toAzimuth = azimuth
        var toElevation = elevation

        switch view {
        case .reset:
            toTarget = anchorTarget
            toRadius = anchorRadius
            toAzimuth = anchorAzimuth
            toElevation = anchorElevation
        case .front:  toAzimuth = 0;          toElevation = 0
        case .back:   toAzimuth = .pi;        toElevation = 0
        case .right:  toAzimuth = .pi / 2;    toElevation = 0
        case .left:   toAzimuth = -.pi / 2;   toElevation = 0
        case .top:    toAzimuth = 0;          toElevation = maxElevation
        case .bottom: toAzimuth = 0;          toElevation = -maxElevation
        case .corner: toAzimuth = .pi / 4;    toElevation = CameraRig.isoElevation
        }
        toElevation = clampedElevation(toElevation)

        if !animated || duration <= 0 {
            target = toTarget; radius = toRadius
            azimuth = toAzimuth; elevation = toElevation
            snapActive = false
            handBackAfterSnap()
            return
        }

        snapFromAzimuth = azimuth
        snapFromElevation = elevation
        snapFromRadius = radius
        snapFromTarget = target
        snapToAzimuth = toAzimuth
        snapToElevation = toElevation
        snapToRadius = toRadius
        snapToTarget = toTarget
        snapClock = 0
        snapDuration = duration
        snapActive = true
    }

    /// While a snap is in progress, override this frame's pose with the eased blend
    /// toward the canonical angle. Called by the `Sketch` after its per-frame update
    /// and before `makeCamera`. Returns whether the snap owned the pose this frame.
    @discardableResult
    func applyViewSnap(dt: Double) -> Bool {
        guard snapActive else { return false }
        snapClock += dt
        let t = snapDuration > 0 ? Swift.min(snapClock / snapDuration, 1) : 1
        let e = easeInOut(t)
        azimuth = lerpAngle(snapFromAzimuth, snapToAzimuth, e)
        elevation = snapFromElevation + (snapToElevation - snapFromElevation) * e
        radius = snapFromRadius + (snapToRadius - snapFromRadius) * e
        target = snapFromTarget.lerp(to: snapToTarget, e)
        if t >= 1 {
            snapActive = false
            handBackAfterSnap()
        }
        return true
    }

    /// Hand the pose back to the active driver once a snap finishes, so the
    /// underlying motion resumes from the snapped pose rather than jumping to where
    /// it had drifted underneath.
    private func handBackAfterSnap() {
        switch driver {
        case .control:
            lastMode = .none              // updateControl resyncs its goal to the snapped pose
        case .move:
            activeMove = nil              // updateMove re-bases from the snapped pose
        case .showcase:
            interactivePhase = .manual    // hold the snapped view, then idle-return to the opening shot
            idleClock = 0
            lastMode = .none
        }
    }

    // MARK: Pose

    private func clampedElevation(_ e: Double) -> Double {
        Swift.min(Swift.max(e, -maxElevation), maxElevation)
    }

    /// The eye position for a pose, and the camera right / up basis at it, used to
    /// pan the target across the focal plane.
    private func orbitBasis(azimuth: Double, elevation: Double) -> (right: Vector3, up: Vector3) {
        let up = Vector3.unitY
        let ce = cos(elevation)
        let offset = Vector3(radius * ce * sin(azimuth),
                             radius * sin(elevation),
                             radius * ce * cos(azimuth))
        let forward = (-offset).normalized               // from eye toward target
        let right = forward.cross(up).normalized
        let camUp = right.cross(forward)
        return (right, camUp)
    }

    /// The current pose as a perspective `Camera3D` orbiting the target.
    func makeCamera(near: Double, far: Double) -> Camera3D {
        .orbiting(target: target, radius: radius, azimuth: azimuth,
                  elevation: clampedElevation(elevation), fieldOfView: fieldOfView,
                  near: near, far: far)
    }
}
