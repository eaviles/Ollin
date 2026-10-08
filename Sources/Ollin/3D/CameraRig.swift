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
/// `reset` returns to the sketch's framing (the center, distance, and angle its
/// camera call passes); the six axis views look straight down each axis (each flattens the
/// scene to two axes); and `isometric` is the three-quarter view that shows all
/// three axes at once (the angle where they foreshorten equally). The axis and
/// isometric views keep the current center and distance and only swing the orbit
/// angle.
public enum CameraView: String, Sendable, CaseIterable {
    case reset
    case front, back, left, right, top, bottom
    case isometric
}

/// The framing a camera call passes: where the camera looks, from how far, from
/// what angle, and through what lens. The rig keeps the last one it was handed as
/// its home, the view `resetCamera()` and an idle return go back to.
struct CameraFraming: Equatable {
    var target: Vector3
    var radius: Double
    var azimuth: Double
    var elevation: Double
    var fieldOfView: Double
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

    /// Whether `makeCamera` flattens with an orthographic projection instead of
    /// perspective, driven by the axis widget's Ortho|Perspective toggle. The
    /// orthographic framing matches the perspective view at the target distance, so
    /// flipping it leaves the scale put.
    var isOrthographic = false

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
    private let velSmoothingTau = 0.04          // release-velocity EMA time constant (s)
    private let maxSpin = 6.0                   // cap on carried velocity (rad/s)

    // MARK: Cinematic-move state

    private var activeMove: CameraMove?
    /// The move's own clock, which reads the time of the frame being posed: a
    /// move poses from it first and advances it after, the order `time` keeps,
    /// so frame N of an export shows the move at N/fps at any frame rate.
    private var moveClock: Double = 0
    private var baseAzimuth = 0.0
    private var baseElevation = 0.0
    private var baseRadius = 0.0
    private var baseTarget = Vector3.zero
    /// Set when a snap lands after a finite move (or an orbit's rise) has played
    /// out: the snapped pose is the move's resting state from then on, so its
    /// eased part no longer applies and a later snap does not replay it.
    private var easedPartHeld = false

    // MARK: Following a changed framing

    /// Where each part of a running move's base is gliding after the framing
    /// changed, `nil` for a part that has arrived or never moved. Only the parts
    /// whose argument changed glide, so a move that departed from a hand-framed
    /// pose keeps the angle the hands left when only the distance is retuned.
    private var baseGoalTarget: Vector3?
    private var baseGoalRadius: Double?
    private var baseGoalAzimuth: Double?
    private var baseGoalElevation: Double?
    /// The lens a changed `fieldOfView` glides to. The viewer never changes the
    /// lens, so it follows the framing under every driver.
    private var goalFieldOfView: Double?

    /// Whether the controller's pose is still the home it was framed at: true
    /// from the first call and after a reset, false once the viewer moves the
    /// camera or snaps it to another view. While it holds, a changed framing
    /// moves the camera; after that it moves only the home.
    private var restsAtHome = true

    /// How fast a part of the pose follows a changed framing (1/s), under a
    /// percent off in about 0.6 s, the length of a `cameraView` glide. It is an
    /// exponential approach rather than an eased glide because a parameter
    /// dragged in the inspector changes the framing every frame, and an eased
    /// glide that restarts every frame never leaves its flat start.
    private let homeGlideRate = 8.0

    /// A private smooth field for the handheld drift, seeded independently of the
    /// sketch's `noise()` so a handheld move neither reads nor disturbs it.
    private let breath = PerlinNoise(seed: 0x0A11_0CA3_CA3E_0B07)

    // MARK: Interactive-move state

    /// `updateInteractiveMove` is a small state machine over the two halves above:
    /// the move plays (`driving`) until the viewer touches the camera (`manual`),
    /// and after an idle stretch it eases back to the home framing (`returning`).
    private enum InteractivePhase { case driving, manual, returning }
    private var interactivePhase: InteractivePhase = .driving
    private var idleClock = 0.0
    private var returnClock = 0.0
    private var returnFromAzimuth = 0.0
    private var returnFromElevation = 0.0
    private var returnFromRadius = 0.0
    private var returnFromTarget = Vector3.zero
    /// The blend's continuously unwrapped azimuth destination. The move keeps
    /// orbiting underneath the return, so the destination must be tracked by its
    /// per-frame increments: re-wrapping the shortest arc each frame against the
    /// moving azimuth flips sign when it crosses the antipode mid-blend (a
    /// half-turn pop). `nil` until the first return frame establishes it.
    private var returnToAzimuth: Double?
    private var returnMoveAzimuth = 0.0

    /// The framing the sketch's last camera call passed: where a reset and the
    /// idle return go back to, rather than wherever the viewer left the camera.
    private(set) var home = CameraFraming(target: .zero, radius: 10, azimuth: 0,
                                          elevation: 0.3, fieldOfView: .pi / 3)

    /// Take this frame's framing from the camera call. The first call opens the
    /// shot on it. After that it is the rig's home, and an argument that changed
    /// moves the home there: a running move's base glides after it, a controller
    /// the viewer has not moved glides after it, and a controller the viewer has
    /// moved stays where the viewer left it (the next reset goes to the new
    /// home). Arguments that stay the same change nothing, so a sketch passing
    /// constants every frame sees no difference. `orthographic` sets the
    /// projection's starting state (an authored ortho camera opens flat); the
    /// axis widget's toggle owns it from then on.
    func frame(_ framing: CameraFraming, orthographic: Bool = false) {
        guard seeded else {
            seeded = true
            target = framing.target
            radius = framing.radius
            azimuth = framing.azimuth
            elevation = framing.elevation
            fieldOfView = framing.fieldOfView
            isOrthographic = orthographic
            home = framing
            return
        }
        guard framing != home else { return }
        let old = home
        home = framing
        if framing.fieldOfView != old.fieldOfView { goalFieldOfView = framing.fieldOfView }
        if framing.target != old.target {
            baseGoalTarget = framing.target
            if restsAtHome { goalTarget = framing.target }
        }
        if framing.radius != old.radius {
            baseGoalRadius = framing.radius
            if restsAtHome { goalRadius = framing.radius }
        }
        if framing.azimuth != old.azimuth {
            baseGoalAzimuth = framing.azimuth
            if restsAtHome { goalAzimuth = framing.azimuth }
        }
        if framing.elevation != old.elevation {
            baseGoalElevation = framing.elevation
            if restsAtHome { goalElevation = clampedElevation(framing.elevation) }
        }
    }

    /// The labeled form of `frame(_:orthographic:)`, the shape the camera calls
    /// pass their arguments in.
    func frame(target: Vector3, radius: Double, azimuth: Double = 0,
               elevation: Double, fieldOfView: Double, orthographic: Bool = false) {
        frame(CameraFraming(target: target, radius: radius, azimuth: azimuth,
                            elevation: elevation, fieldOfView: fieldOfView),
              orthographic: orthographic)
    }

    /// Move one part of the pose toward the goal a changed framing set, landing
    /// exactly and clearing the goal once it is within a hair, so a settled
    /// glide leaves the very value an export framed with.
    private func follow(_ value: inout Double, _ goal: inout Double?, _ f: Double) {
        guard let g = goal else { return }
        value += (g - value) * f
        if abs(g - value) <= 1e-9 * Swift.max(1, abs(g)) { value = g; goal = nil }
    }

    private func follow(_ value: inout Vector3, _ goal: inout Vector3?, _ f: Double) {
        guard let g = goal else { return }
        value = value.lerp(to: g, f)
        if (g - value).length <= 1e-9 * Swift.max(1, g.length) { value = g; goal = nil }
    }

    /// The share of the way to a changed framing one frame of `dt` covers.
    private func followShare(_ dt: Double) -> Double { 1 - exp(-homeGlideRate * dt) }

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
        if interacting || input.scrollDeltaY != 0 { restsAtHome = false }
        follow(&fieldOfView, &goalFieldOfView, followShare(dt))

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
            // Track a smoothed, capped velocity for the release flick. The EMA blend
            // derives from a time constant so the same physical flick carries the same
            // momentum at any frame rate (a fixed per-frame factor lags more at 30fps
            // than at 120fps).
            let instAz = (-dx * rot) / Swift.max(dt, 1e-4)
            let instEl = (dy * rot) / Swift.max(dt, 1e-4)
            let blend = 1 - exp(-dt / velSmoothingTau)
            velAzimuth = clampSpin(velAzimuth + (instAz - velAzimuth) * blend)
            velElevation = clampSpin(velElevation + (instEl - velElevation) * blend)
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

    /// Pose the active cinematic `move` at its clock, then advance the clock by
    /// `dt` seconds. A move handed in fresh starts its clock at zero, so its first
    /// frame shows it at its start; a different move, or any move taking over from
    /// the controller, departs from the current pose (so moves chain smoothly, and
    /// framing by hand between two runs of the same move is kept).
    func updateMove(_ move: CameraMove, dt: Double) {
        let takesOverFromTheHands = lastMode == .control
        lastMode = .move
        if move != activeMove || takesOverFromTheHands { startMove(move) }
        let f = followShare(dt)
        follow(&baseTarget, &baseGoalTarget, f)
        follow(&baseRadius, &baseGoalRadius, f)
        follow(&baseAzimuth, &baseGoalAzimuth, f)
        follow(&baseElevation, &baseGoalElevation, f)
        follow(&fieldOfView, &goalFieldOfView, f)
        apply(move, clock: moveClock)
        moveClock += dt
    }

    private func startMove(_ move: CameraMove) {
        activeMove = move
        moveClock = 0
        baseAzimuth = azimuth
        baseElevation = elevation
        baseRadius = radius
        baseTarget = target
        easedPartHeld = false
        // The move departs from the pose as it stands, which already answers any
        // framing change still on its way.
        baseGoalTarget = nil
        baseGoalRadius = nil
        baseGoalAzimuth = nil
        baseGoalElevation = nil
    }

    /// A finite move's eased value at `clock`: `from` until it starts, `to` once
    /// its `duration` has run.
    private func eased(_ from: Double, _ to: Double, _ duration: Double,
                       _ curve: Easing, _ clock: Double) -> Double {
        guard duration > 0 else { return to }
        if clock <= 0 { return from }
        if clock >= duration { return to }
        return Double.lerp(from, to, curve(clock / duration))
    }

    private func apply(_ move: CameraMove, clock: Double) {
        // Start from the base pose; a finite eased part overrides it by the clock,
        // and so does any cyclic part below. Read from the base every frame, so a
        // base that glides after a changed framing carries the whole move with it.
        azimuth = baseAzimuth
        elevation = baseElevation
        radius = baseRadius
        target = baseTarget

        if !easedPartHeld {
            switch move.kind {
            case let .pushIn(factor, duration, curve), let .pullOut(factor, duration, curve):
                radius = eased(baseRadius, baseRadius * factor, duration, curve, clock)
            case let .tilt(to, duration, curve):
                elevation = eased(baseElevation, to, duration, curve, clock)
            case let .orbitAndRise(_, rise, duration):
                elevation = eased(baseElevation, baseElevation + rise, duration, .easeInOut, clock)
            case let .reveal(duration, curve):
                radius = eased(baseRadius * 0.45, baseRadius, duration, curve, clock)
                let low = Swift.max(0.05, baseElevation * 0.35)
                elevation = eased(low, baseElevation, duration, curve, clock)
            case .turntable, .sway, .handheld:
                break
            }
        }

        switch move.kind {
        case let .turntable(period):
            azimuth = baseAzimuth + clock * angularSpeed(period)
        case let .sway(amplitude, period):
            azimuth = baseAzimuth + amplitude * sin(clock * angularSpeed(period))
        case let .orbitAndRise(period, _, _):
            azimuth = baseAzimuth + clock * angularSpeed(period)
        case let .handheld(amount, speed):
            let t = clock * speed
            // Three stretches of the one line, far enough apart never to meet
            // within the field's period of 256.
            azimuth = baseAzimuth + breath.signedValue(t) * amount
            elevation = baseElevation + breath.signedValue(t + 64) * amount
            radius = baseRadius * (1 + breath.signedValue(t + 128) * amount)
        case .pushIn, .pullOut, .tilt, .reveal:
            break   // radius / elevation already taken from the eased part
        }
    }

    private func angularSpeed(_ period: Double) -> Double {
        period != 0 ? Double.tau / period : 0
    }

    // MARK: Interactive move (auto-orbit the viewer can take over)

    /// Play `move` as an auto-orbit the viewer can grab. A drag / dolly / pan hands
    /// off to the interactive controller; after `idleTimeout` seconds of no input the
    /// pose eases back over `returnDuration` seconds to the home framing and the
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

    /// Snapshot the viewer's pose, restart the move from the *home* framing (so the
    /// blend's destination is the sketch's own shot, still orbiting), then hold the
    /// displayed pose at the viewer's pose; the return blends in from there.
    private func beginReturn(to move: CameraMove) {
        returnFromAzimuth = azimuth
        returnFromElevation = elevation
        returnFromRadius = radius
        returnFromTarget = target

        target = home.target
        radius = home.radius
        elevation = home.elevation
        azimuth = home.azimuth
        startMove(move)                  // base = the home framing, clock 0
        lastMode = .move                 // so the return's moves keep that base

        azimuth = returnFromAzimuth       // restore the displayed pose to the viewer's
        elevation = returnFromElevation
        radius = returnFromRadius
        target = returnFromTarget

        returnClock = 0
        returnToAzimuth = nil
        interactivePhase = .returning
    }

    /// Ease from the viewer's pose toward the home framing's orbit; when the blend
    /// completes the move owns the pose again. The move keeps advancing underneath,
    /// so the destination is a live orbit, not a frozen frame.
    private func advanceReturn(_ move: CameraMove, dt: Double, returnDuration: Double) {
        returnClock += dt
        let t = returnDuration > 0 ? Swift.min(returnClock / returnDuration, 1) : 1
        let e = easeInOut(t)

        updateMove(move, dt: dt)          // the home framing's pose, still orbiting
        let moveAzimuth = azimuth, moveElevation = elevation
        let moveRadius = radius, moveTarget = target

        // Wrap the destination onto the viewer's winding once, then follow the
        // move's own increments (small per frame, so they never wrap); see
        // `returnToAzimuth`. At the end the blend lands on the move's azimuth
        // modulo a full turn, which is the same pose.
        if let unwrapped = returnToAzimuth {
            returnToAzimuth = unwrapped + shortestArc(moveAzimuth - returnMoveAzimuth)
        } else {
            returnToAzimuth = returnFromAzimuth + shortestArc(moveAzimuth - returnFromAzimuth)
        }
        returnMoveAzimuth = moveAzimuth

        azimuth = returnFromAzimuth + (returnToAzimuth! - returnFromAzimuth) * e
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
        a + shortestArc(b - a) * t
    }

    /// The signed angular difference wrapped to (-π, π], the shortest way around.
    private func shortestArc(_ angle: Double) -> Double {
        var diff = angle.truncatingRemainder(dividingBy: .tau)
        if diff > .pi { diff -= .tau }
        if diff < -.pi { diff += .tau }
        return diff
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

    /// Begin a snap to a canonical inspection angle. `reset` restores the home
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
            toTarget = home.target
            toRadius = home.radius
            toAzimuth = home.azimuth
            toElevation = home.elevation
        case .front:  toAzimuth = 0;          toElevation = 0
        case .back:   toAzimuth = .pi;        toElevation = 0
        case .right:  toAzimuth = .pi / 2;    toElevation = 0
        case .left:   toAzimuth = -.pi / 2;   toElevation = 0
        case .top:    toAzimuth = 0;          toElevation = maxElevation
        case .bottom: toAzimuth = 0;          toElevation = -maxElevation
        case .isometric: toAzimuth = .pi / 4; toElevation = CameraRig.isoElevation
        }
        toElevation = clampedElevation(toElevation)
        restsAtHome = view == .reset

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
            if let move = activeMove, let duration = move.finiteDuration, moveClock >= duration {
                // The finite move already played out; a restart would replay it from
                // the snapped pose and compound a relative move (each snap pushing a
                // `pushIn` further in). Hold the snapped pose as its resting state.
                baseAzimuth = azimuth
                baseElevation = elevation
                baseRadius = radius
                baseTarget = target
                easedPartHeld = true
            } else if let move = activeMove,
                      case let .orbitAndRise(period, _, duration) = move.kind,
                      moveClock >= duration {
                // The rise (the move's finite intro) already played; re-base only the
                // endless orbit so each snap doesn't stack another rise onto the
                // elevation. Back-dating the base azimuth keeps the continuing spin
                // passing through the snapped pose with no jump.
                baseAzimuth = azimuth - moveClock * angularSpeed(period)
                baseElevation = elevation
                baseRadius = radius
                baseTarget = target
                easedPartHeld = true
            } else {
                activeMove = nil          // updateMove re-bases from the snapped pose
            }
        case .showcase:
            interactivePhase = .manual    // hold the snapped view, then idle-return to the home framing
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

    /// The current pose as a `Camera3D` orbiting the target, perspective by
    /// default, orthographic when `isOrthographic` is set. The orthographic framing
    /// is the perspective view's height at the target distance, so flipping
    /// projection doesn't jump the scale.
    func makeCamera(near: Double, far: Double) -> Camera3D {
        let e = clampedElevation(elevation)
        guard isOrthographic else {
            return .orbiting(target: target, radius: radius, azimuth: azimuth,
                             elevation: e, fieldOfView: fieldOfView,
                             near: near, far: far)
        }
        let ce = cos(e)
        let eye = target + Vector3(radius * ce * sin(azimuth),
                                   radius * sin(e),
                                   radius * ce * cos(azimuth))
        let height = 2 * radius * tan(fieldOfView / 2)
        return .orthographic(eye: eye, target: target, height: height, near: near, far: far)
    }
}
