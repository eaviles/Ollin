import Testing
import CoreGraphics
@testable import Ollin

/// Every bare camera call on a sketch sets the camera its typed twin sets, and
/// so draws the same picture, pixel for pixel: `perspective(eye:...)` and
/// `camera(.perspective(eye:...))` are two spellings of one view, and the rig
/// calls (`cameraControl`, `cameraMove`, `cameraShowcase`, `cameraView`,
/// `resetCamera`) hand the sketch's framing, clock, and input to a `CameraRig`
/// and set the `Camera3D` it makes.
///
/// A rig call's twin is either the `Camera3D` value the rig makes of that
/// framing, written out, or a second rig the test drives by hand with the same
/// framing and the same input and then passes to `camera(_:)`. The numbers are
/// uneven on purpose (a target off the origin, a radius unlike the default, an
/// azimuth unlike the elevation, a near and far unlike the defaults), and the
/// canvas is wider than it is tall, so a call that handed two of them over in
/// the wrong order, or the width where the height belongs, would set another
/// camera.
///
/// Each pair is read two ways. The cameras are compared as values, which is
/// what catches a near or far plane that no pixel of this scene shows, and the
/// frames are compared as pixels. A third render through a camera the pair
/// must not be (a dropped argument, a hand that never moved, a move that never
/// ran) has to differ, so a pair that set no camera worth the name fails.
@Suite
@MainActor
struct CameraRigFormsTests {

    /// One camera's two spellings, and a camera it must not be.
    struct Pair: Sendable, CustomTestStringConvertible {
        let name: String
        /// The frame the picture is taken at. The calls run on every frame up
        /// to it, at 60 frames a second, as an export runs them.
        let frame: Int
        let bare: @MainActor @Sendable (Sketch, CameraRig) -> Void
        let twin: @MainActor @Sendable (Sketch, CameraRig) -> Void
        let other: @MainActor @Sendable (Sketch, CameraRig) -> Void
        var testDescription: String { name }
    }

    nonisolated static let aim = Vector3(0.1, 0.05, -0.08)
    nonisolated static let eye = Vector3(1.6, 1.3, 2.4)
    nonisolated static let tipped = Vector3(0.15, 1, 0)

    /// A camera somebody authored, in perspective, for the `from:` forms.
    nonisolated static let authored = Camera3D.orbiting(
        target: aim, radius: 3.1, azimuth: 0.7, elevation: 0.45, fieldOfView: 0.9, near: 0.3, far: 40)
    /// And one authored flat, which has to open the rig orthographic.
    nonisolated static let authoredFlat = Camera3D.orthographic(
        eye: eye, target: aim, height: 2.2, near: 0.3, far: 40)

    /// The input of a frame in which nobody touches anything.
    static var rest: CameraInput {
        CameraInput(mouseX: 0, mouseY: 0, leftPressed: false, rightPressed: false,
                    modifiers: [], scrollDeltaY: 0, pinchScale: 1)
    }

    /// What a viewer's hand does over the first frames, written into the
    /// sketch's own input fields the way a window writes them, and returned as
    /// the value a rig reads: a drag that orbits (frames 2 to 4, with a scroll
    /// on 3 and a pinch on 4), a shift-drag that pans (5 and 6), a right-drag
    /// that pans (7), and then nothing. Every field takes a value of its own,
    /// so a call that read one field for another would move the camera
    /// somewhere else.
    @discardableResult
    static func hand(_ s: Sketch) -> CameraInput {
        let k = s.frameCount
        let input = CameraInput(mouseX: 20 + 3 * Double(k), mouseY: 30 + 2 * Double(k),
                                leftPressed: (2...6).contains(k), rightPressed: k == 7,
                                modifiers: (5...6).contains(k) ? [.shift] : [],
                                scrollDeltaY: k == 3 ? 4 : 0, pinchScale: k == 4 ? 1.2 : 1)
        s.mouseX = input.mouseX
        s.mouseY = input.mouseY
        s.mouseIsPressed = input.leftPressed
        s.rightMouseIsPressed = input.rightPressed
        s.modifiers = input.modifiers
        s.scrollDeltaY = input.scrollDeltaY
        s.pinchScale = input.pinchScale
        return input
    }

    /// The hand-held rig held at its home framing: what the view pairs snap
    /// away from and reset to.
    static func holdHome(_ s: Sketch) {
        s.cameraControl(target: aim, radius: 3.1, azimuth: 0.7, elevation: 0.45,
                        fieldOfView: 0.9, near: 0.2, far: 60)
    }

    nonisolated static let pairs: [Pair] = [
        Pair(name: "perspective", frame: 0,
             bare: { s, _ in s.perspective(eye: eye, target: aim, up: tipped, fieldOfView: 0.8, near: 0.2, far: 60) },
             twin: { s, _ in
                 s.camera(Camera3D.perspective(eye: eye, target: aim, up: tipped, fieldOfView: 0.8, near: 0.2, far: 60))
             },
             other: { s, _ in s.camera(Camera3D.perspective(eye: eye, target: aim)) }),

        Pair(name: "ortho", frame: 0,
             bare: { s, _ in s.ortho(eye: eye, target: aim, up: tipped, height: 2.2, near: 0.2, far: 60) },
             twin: { s, _ in
                 s.camera(Camera3D.orthographic(eye: eye, target: aim, up: tipped, height: 2.2, near: 0.2, far: 60))
             },
             other: { s, _ in s.camera(Camera3D.perspective(eye: eye, target: aim, up: tipped)) }),

        // Nobody touches it, so the hand-held rig stays on its framing: the
        // orbiting camera of the same numbers. The other camera is the one a
        // call that swapped the two angles would set.
        Pair(name: "control at rest", frame: 2,
             bare: { s, _ in
                 s.cameraControl(target: aim, radius: 3.1, azimuth: 0.7, elevation: 0.45,
                                 fieldOfView: 0.9, near: 0.2, far: 60)
             },
             twin: { s, _ in
                 s.camera(Camera3D.orbiting(target: aim, radius: 3.1, azimuth: 0.7, elevation: 0.45,
                                            fieldOfView: 0.9, near: 0.2, far: 60))
             },
             other: { s, _ in
                 s.camera(Camera3D.orbiting(target: aim, radius: 3.1, azimuth: 0.45, elevation: 0.7,
                                            fieldOfView: 0.9, near: 0.2, far: 60))
             }),

        // The sketch's input fields reach the rig each in its own place, with
        // the frame's own step and the canvas's height.
        Pair(name: "control under the hand", frame: 8,
             bare: { s, _ in
                 hand(s)
                 s.cameraControl(target: aim, radius: 3.1, azimuth: 0.7, elevation: 0.45,
                                 fieldOfView: 0.9, near: 0.2, far: 60)
             },
             twin: { s, rig in
                 let input = hand(s)
                 rig.frame(target: aim, radius: 3.1, azimuth: 0.7, elevation: 0.45, fieldOfView: 0.9)
                 rig.updateControl(input: input, dt: s.deltaTime, viewportHeight: s.height)
                 s.camera(rig.makeCamera(near: 0.2, far: 60))
             },
             other: { s, _ in holdHome(s) }),

        // A fifth of a second into a turntable. The other camera is the
        // framing held still, so the move has to have run.
        Pair(name: "move", frame: 12,
             bare: { s, _ in
                 s.cameraMove(.turntable(period: 7), target: aim, radius: 3.1, elevation: 0.45,
                              fieldOfView: 0.9, near: 0.2, far: 60)
             },
             twin: { s, rig in
                 rig.frame(target: aim, radius: 3.1, elevation: 0.45, fieldOfView: 0.9)
                 rig.updateMove(.turntable(period: 7), dt: s.deltaTime)
                 s.camera(rig.makeCamera(near: 0.2, far: 60))
             },
             other: { s, _ in
                 s.camera(Camera3D.orbiting(target: aim, radius: 3.1, azimuth: 0, elevation: 0.45,
                                            fieldOfView: 0.9, near: 0.2, far: 60))
             }),

        // The viewer takes the orbit, lets go, and the picture is taken partway
        // through the glide home: a call that swapped the idle wait and the
        // glide's length would still be waiting. The other camera is the orbit
        // nobody touched.
        Pair(name: "showcase taken and let go", frame: 20,
             bare: { s, _ in
                 hand(s)
                 s.cameraShowcase(.turntable(period: 7), target: aim, radius: 3.1, elevation: 0.45,
                                  fieldOfView: 0.9, near: 0.2, far: 60, idleReturn: 0.05, returnDuration: 0.5)
             },
             twin: { s, rig in
                 let input = hand(s)
                 rig.frame(target: aim, radius: 3.1, elevation: 0.45, fieldOfView: 0.9)
                 rig.updateInteractiveMove(.turntable(period: 7), input: input, dt: s.deltaTime,
                                           viewportHeight: s.height, idleTimeout: 0.05, returnDuration: 0.5)
                 s.camera(rig.makeCamera(near: 0.2, far: 60))
             },
             other: { s, _ in
                 s.cameraShowcase(.turntable(period: 7), target: aim, radius: 3.1, elevation: 0.45,
                                  fieldOfView: 0.9, near: 0.2, far: 60, idleReturn: 0.05, returnDuration: 0.5)
             }),

        // An authored flat camera opens the rig on its own pose, orthographic,
        // inside its own clip range. The other camera is the authored shot
        // held still.
        Pair(name: "move from an authored camera", frame: 12,
             bare: { s, _ in s.cameraMove(.turntable(period: 7), from: authoredFlat) },
             twin: { s, rig in
                 let pose = authoredFlat.orbitPose
                 rig.frame(target: pose.target, radius: pose.radius, azimuth: pose.azimuth,
                           elevation: pose.elevation, fieldOfView: pose.fieldOfView,
                           orthographic: pose.orthographic)
                 rig.updateMove(.turntable(period: 7), dt: s.deltaTime)
                 s.camera(rig.makeCamera(near: authoredFlat.near, far: authoredFlat.far))
             },
             other: { s, _ in s.camera(authoredFlat) }),

        // The authored pose is the home, and a clip range named in the call
        // wins over the camera's own. The other camera is the one a call that
        // dropped the authored azimuth would set.
        Pair(name: "control from an authored camera", frame: 2,
             bare: { s, _ in s.cameraControl(from: authored, near: 0.2, far: 60) },
             twin: { s, _ in
                 let pose = authored.orbitPose
                 s.camera(Camera3D.orbiting(target: pose.target, radius: pose.radius, azimuth: pose.azimuth,
                                            elevation: pose.elevation, fieldOfView: pose.fieldOfView,
                                            near: 0.2, far: 60))
             },
             other: { s, _ in
                 s.camera(Camera3D.orbiting(target: aim, radius: 3.1, azimuth: 0, elevation: 0.45,
                                            fieldOfView: 0.9, near: 0.2, far: 60))
             }),

        Pair(name: "showcase from an authored camera", frame: 20,
             bare: { s, _ in
                 hand(s)
                 s.cameraShowcase(.turntable(period: 7), from: authored, idleReturn: 0.05, returnDuration: 0.5)
             },
             twin: { s, rig in
                 let input = hand(s)
                 let pose = authored.orbitPose
                 rig.frame(target: pose.target, radius: pose.radius, azimuth: pose.azimuth,
                           elevation: pose.elevation, fieldOfView: pose.fieldOfView,
                           orthographic: pose.orthographic)
                 rig.updateInteractiveMove(.turntable(period: 7), input: input, dt: s.deltaTime,
                                           viewportHeight: s.height, idleTimeout: 0.05, returnDuration: 0.5)
                 s.camera(rig.makeCamera(near: authored.near, far: authored.far))
             },
             other: { s, _ in s.camera(authored) }),

        // A cut to the view from the right keeps the center and the distance
        // and swings the angle: the orbiting camera a quarter turn around, level.
        Pair(name: "view, cut", frame: 2,
             bare: { s, _ in
                 if s.frameCount == 2 { s.cameraView(.right, animated: false) }
                 holdHome(s)
             },
             twin: { s, _ in
                 s.camera(Camera3D.orbiting(target: aim, radius: 3.1, azimuth: .pi / 2, elevation: 0,
                                            fieldOfView: 0.9, near: 0.2, far: 60))
             },
             other: { s, _ in holdHome(s) }),

        // A glide to the view from above, caught partway. The other camera is
        // the cut, which is already there.
        Pair(name: "view, glide", frame: 9,
             bare: { s, _ in
                 if s.frameCount == 2 { s.cameraView(.top, animated: true, duration: 0.4) }
                 holdHome(s)
             },
             twin: { s, rig in
                 if s.frameCount == 2 { rig.requestView(.top, animated: true, duration: 0.4) }
                 rig.frame(target: aim, radius: 3.1, azimuth: 0.7, elevation: 0.45, fieldOfView: 0.9)
                 rig.updateControl(input: rest, dt: s.deltaTime, viewportHeight: s.height)
                 rig.applyViewSnap(dt: s.deltaTime)
                 s.camera(rig.makeCamera(near: 0.2, far: 60))
             },
             other: { s, _ in
                 if s.frameCount == 2 { s.cameraView(.top, animated: false) }
                 holdHome(s)
             }),

        // A reset is the view named `.reset`, with the same glide. The other
        // camera never reset and still looks from the right.
        Pair(name: "reset, glide", frame: 9,
             bare: { s, _ in
                 if s.frameCount == 2 { s.cameraView(.right, animated: false) }
                 if s.frameCount == 3 { s.resetCamera(animated: true, duration: 0.5) }
                 holdHome(s)
             },
             twin: { s, _ in
                 if s.frameCount == 2 { s.cameraView(.right, animated: false) }
                 if s.frameCount == 3 { s.cameraView(.reset, animated: true, duration: 0.5) }
                 holdHome(s)
             },
             other: { s, _ in
                 if s.frameCount == 2 { s.cameraView(.right, animated: false) }
                 holdHome(s)
             }),
    ]

    @Test(arguments: pairs)
    func theBareCallSetsItsCamera(_ pair: Pair) throws {
        let bare = OneView(pair.bare), twin = OneView(pair.twin), other = OneView(pair.other)
        let bareFrame = pixels(of: try OllinApp.image(of: bare, frame: pair.frame))
        let twinFrame = pixels(of: try OllinApp.image(of: twin, frame: pair.frame))
        let otherFrame = pixels(of: try OllinApp.image(of: other, frame: pair.frame))
        let blank = pixels(of: try OllinApp.image(of: OneView { _, _ in }, frame: 0))
        #expect(bare.seen != nil, "the bare call set no camera")
        #expect(bare.seen == twin.seen)
        #expect(bareFrame != blank, "the bare call's camera sees nothing")
        #expect(bareFrame == twinFrame)
        #expect(bareFrame != otherFrame, "a camera the pair must not be drew the same picture")
    }

    // MARK: Calls that answer with a value

    nonisolated static let shot = Camera3D.perspective(eye: eye, target: aim, fieldOfView: 0.8, near: 0.2, far: 60)
    nonisolated static let point = Vector3(0.3, 0.2, -0.1)

    /// `project(_:)` is the drawer's projection at the canvas's own size, the
    /// width first: on a canvas wider than tall, the two sizes the other way
    /// around put the point somewhere else.
    @Test func projectAnswersAtTheCanvasSize() {
        let sketch = Sketch()
        sketch.setCanvasSize(width: 96, height: 72)
        #expect(sketch.project(Self.point) == nil, "a point was projected with no camera set")
        sketch.camera(Self.shot)
        let bare: Vector2? = sketch.project(Self.point)
        let core: Vector2? = sketch.drawer.project(Self.point, viewport: SIMD2<Float>(96, 72))
        let turned: Vector2? = sketch.drawer.project(Self.point, viewport: SIMD2<Float>(72, 96))
        #expect(bare != nil, "a point in front of the camera did not project")
        #expect(bare == core)
        #expect(bare != turned)
    }

    /// `cameraParams()` is the active camera packed at the canvas's aspect,
    /// width over height, and nothing at all while no camera is set.
    @Test func cameraParamsPackTheActiveCameraAtTheCanvasAspect() {
        let sketch = Sketch()
        sketch.setCanvasSize(width: 96, height: 72)
        #expect(sketch.cameraParams().isEmpty, "matrices were packed with no camera set")
        sketch.camera(Self.shot)
        var core = ComputeParams()
        core.append(camera: Self.shot, aspect: 96.0 / 72.0)
        var turned = ComputeParams()
        turned.append(camera: Self.shot, aspect: 72.0 / 96.0)
        let bare = sketch.cameraParams()
        #expect(!bare.isEmpty)
        #expect(bare.bytes == core.bytes)
        #expect(bare.bytes != turned.bytes)
    }

    /// `cameraAxis(_:)` sets the flag the host reads each frame, on by default
    /// and off when asked.
    @Test func cameraAxisSetsTheFlagTheHostReads() {
        let sketch = Sketch()
        #expect(!sketch.showsCameraAxis)
        sketch.cameraAxis()
        #expect(sketch.showsCameraAxis)
        sketch.cameraAxis(false)
        #expect(!sketch.showsCameraAxis)
    }
}

/// A 96 by 72 point canvas with one lit box on it, seen through whatever camera
/// the closure sets. The box's three sides differ and the light comes from off
/// every axis, so a camera that moved, turned, or changed its lens shows. The
/// sketch keeps a spare rig for a twin to drive by hand, and remembers the
/// camera the last frame was drawn through. With no camera set it draws
/// nothing, which is the blank frame.
@MainActor
private final class OneView: Sketch {
    var look: (Sketch, CameraRig) -> Void = { _, _ in }
    let spare = CameraRig()
    private(set) var seen: Camera3D?

    convenience init(_ look: @escaping (Sketch, CameraRig) -> Void) {
        self.init()
        self.look = look
    }

    override var canvasSize: CanvasSize { .size(96, 72) }

    override func draw() {
        background(.black)
        look(self, spare)
        seen = activeCamera
        guard seen != nil else { return }
        directionalLight(.white, direction: Vector3(-0.4, -0.8, -0.5))
        fill(Color(red: 0.9, green: 0.7, blue: 0.3))
        drawBox(width: 0.9, height: 0.5, depth: 0.7)
    }
}
