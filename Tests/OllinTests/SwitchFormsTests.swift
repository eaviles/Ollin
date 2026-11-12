import Testing
import CoreGraphics
@testable import Ollin

/// Every `no…` switch on a sketch puts back exactly the state its feature
/// changed: a scene that turns the feature on and then calls the switch draws,
/// pixel for pixel, what the same scene draws when it never asked, and the
/// scene with the feature left on draws something else, so a switch over a
/// feature that showed nothing cannot pass. Three switches turn off something
/// that is on by default (`noFill`, `noStroke`, `noLights`); those are read
/// against the same state reached another way, and against the default they
/// must change.
///
/// The switches whose feature needs several frames, a ray-tracing GPU, or the
/// live window to show are read on the state they set instead, in the second
/// table: the feature raises a flag on the drawer and the switch lowers it.
/// The numbers are uneven on purpose, and each solid scene is lit and seen
/// from off every axis.
@Suite
@MainActor
struct SwitchFormsTests {

    typealias Step = @MainActor @Sendable (Sketch) -> Void

    /// One switch's three scenes: `bare` goes through the switch, `twin` is
    /// the scene it must match, and `other` is the scene it must not.
    struct Pair: Sendable, CustomTestStringConvertible {
        let name: String
        var side = 64
        let bare: Step
        let twin: Step
        let other: Step
        var testDescription: String { name }
    }

    /// The pair for a feature that is off until asked for. `bare` turns it on
    /// and switches it off again, `twin` never asks, and `other` leaves it on.
    /// `scene` runs before the switch (a camera, the lights) and `content`
    /// after it (what is drawn).
    nonisolated static func switching(_ name: String, side: Int = 64, scene: @escaping Step = { _ in },
                                      on: @escaping Step, off: @escaping Step,
                                      content: @escaping Step) -> Pair {
        Pair(name: name, side: side,
             bare: { scene($0); on($0); off($0); content($0) },
             twin: { scene($0); content($0) },
             other: { scene($0); on($0); content($0) })
    }

    // MARK: The flat scenes

    nonisolated static let blue = Color(red: 0.2, green: 0.6, blue: 1)
    nonisolated static let warm = Color(red: 0.9, green: 0.7, blue: 0.3)

    /// A fill, a stroke, and a weight, so a scene that dropped one would show.
    nonisolated static let ink: Step = { s in
        s.fill(Color(red: 0.95, green: 0.8, blue: 0.3))
        s.stroke(blue)
        s.strokeWeight(2)
    }

    nonisolated static let mark: Step = { $0.drawRect(8, 10, 40, 30, cornerRadius: 4) }

    nonisolated static let zigzag = [Vector2(6, 50), Vector2(22, 12), Vector2(40, 48), Vector2(58, 18)]

    /// A wide open path with two corners, which every stroke setting changes.
    nonisolated static let stroked: Step = { s in
        s.strokeWeight(7)
        s.drawPolyline(zigzag)
    }

    /// A paragraph that wraps to several lines in its box.
    nonisolated static let paragraph: Step = { s in
        s.fill(.white)
        s.noStroke()
        s.textSize(9)
        s.drawText("one two three four five six seven eight", in: Rectangle(x: 4, y: 6, width: 56, height: 54))
    }

    /// Ten characters, a full stop, then five more, in a box ten ems wide: the
    /// stop is the one character that will not fit on the first line.
    nonisolated static let passage: Step = { s in
        s.fill(.white)
        s.noStroke()
        s.textSize(6)
        s.drawText("あいうえおかきくけこ。さしすせそ", in: Rectangle(x: 2, y: 6, width: 60, height: 40))
    }

    // MARK: The solid scenes

    /// A camera off every axis and one lamp that throws its shadows to the
    /// side the camera sees.
    nonisolated static let view: Step = { s in
        s.camera(Camera3D(eye: Vector3(1.6, 1.3, 2.4), target: .zero))
        s.directionalLight(.white, direction: Vector3(0.6, -0.7, -0.3))
    }

    nonisolated static let solid: Step = { s in
        s.fill(warm)
        s.drawBox(width: 0.9, height: 0.5, depth: 0.7)
    }

    nonisolated static let ball: Step = { s in
        s.fill(warm)
        s.drawSphere(radius: 0.6, segments: 20, rings: 9)
    }

    /// The box resting flush on a floor, for the settings a shadow shows.
    nonisolated static let grounded: Step = { s in
        s.fill(Color(white: 0.85))
        s.withState {
            s.translate(0, -0.25, 0)
            s.drawPlane(width: 6, depth: 6)
        }
        solid(s)
    }

    /// The table is kept in two halves so neither literal is long enough to
    /// slow the type checker.
    nonisolated static let pairs: [Pair] = flatPairs + solidPairs

    nonisolated static let flatPairs: [Pair] = [
        // On by default, so the switch is read against the drawer's own call
        // and against the default it must change.
        Pair(name: "fill", bare: { ink($0); $0.noFill(); mark($0) },
             twin: { ink($0); $0.drawer.noFill(); mark($0) },
             other: { ink($0); mark($0) }),
        Pair(name: "stroke", bare: { ink($0); $0.noStroke(); mark($0) },
             twin: { ink($0); $0.drawer.noStroke(); mark($0) },
             other: { ink($0); mark($0) }),

        // Drawing state on a flat canvas.
        switching("fill medium", scene: ink, on: { $0.fillMedium(.impasto) }, off: { $0.noFillMedium() },
                  content: { $0.drawRect(8, 10, 44, 38) }),
        switching("stroke profile", scene: ink, on: { $0.strokeProfile(.taper()) }, off: { $0.noStrokeProfile() },
                  content: stroked),
        switching("stroke brush", scene: ink, on: { $0.strokeBrush(Brush(.circle, spacing: 1.5)) },
                  off: { $0.noStrokeBrush() }, content: stroked),
        switching("stroke medium", scene: ink, on: { $0.strokeMedium(.oil) }, off: { $0.noStrokeMedium() },
                  content: stroked),
        switching("stroke dash", scene: ink, on: { $0.strokeDash([7, 5], phase: 2) }, off: { $0.noStrokeDash() },
                  content: stroked),
        // The folds turn about the origin standing when they are asked for, so
        // the scene moves it to the middle first.
        switching("symmetry", scene: { ink($0); $0.translate(32, 30) },
                  on: { $0.symmetry(5, mirrored: true) }, off: { $0.noSymmetry() },
                  content: { $0.drawCircle(15, 6, 7) }),
        switching("tint", on: { $0.tint(Color(red: 1, green: 0.3, blue: 0.2)) }, off: { $0.noTint() },
                  content: { s in
                      let picture = Image(width: 4, height: 4, color: .white)
                      picture[1, 2] = blue
                      s.drawImage(picture, 10, 12, 40, 36)
                  }),
        switching("text justify", on: { $0.textJustify() }, off: { $0.noTextJustify() }, content: paragraph),
        switching("text hanging punctuation", on: { $0.textHangingPunctuation() },
                  off: { $0.noTextHangingPunctuation() }, content: passage),
    ]

    /// The 3D scene's settings, each on a 96-point canvas.
    nonisolated static let solidPairs: [Pair] = [
        // On by default too. Its twin is the scoped form, which goes flat for
        // one body and gives the lamps back.
        Pair(name: "lights", side: 96, bare: { view($0); $0.noLights(); solid($0) },
             twin: { s in view(s); s.withoutLights { solid(s) } },
             other: { view($0); solid($0) }),
        switching("shadows", side: 96, scene: view, on: { $0.castShadows() }, off: { $0.noShadows() },
                  content: grounded),
        // The march refines the caster's shadow, so the caster is on in all three.
        switching("contact shadows", side: 96,
                  scene: { view($0); $0.castShadows(); $0.shadowSoftness(0.8) },
                  on: { $0.contactShadows(length: 0.5) }, off: { $0.noContactShadows() }, content: grounded),
        // A disc placed behind the box is hidden where the box stands, and
        // drawn over it once the depth is let go.
        switching("depth", side: 96, scene: { view($0); solid($0) },
                  on: { $0.depth(at: Vector3(0, 0, -3)) }, off: { $0.noDepth() },
                  content: { s in
                      s.fill(.white)
                      s.noStroke()
                      s.drawCircle(48, 48, 22)
                  }),
        // The lens is open and focused well in front of the box, so the blur
        // has something to do.
        switching("depth of field", side: 96,
                  scene: { s in
                      var lens = Camera3D(eye: Vector3(1.6, 1.3, 2.4), target: .zero)
                      lens.aperture = 0.15
                      lens.focusDistance = 1.2
                      s.camera(lens)
                      s.directionalLight(.white, direction: Vector3(0.6, -0.7, -0.3))
                  },
                  on: { $0.depthOfField(focusRange: 0.1, maxBlur: 21) }, off: { $0.noDepthOfField() },
                  content: solid),
        switching("environment", side: 96, scene: view, on: { $0.environment(.studio) }, off: { $0.noEnvironment() },
                  content: { s in
                      s.material(.metal(roughness: 0.3))
                      ball(s)
                  }),
        switching("feature edges", side: 96, scene: view,
                  on: { $0.featureEdges(creaseAngle: 0.5) }, off: { $0.noFeatureEdges() },
                  content: { s in
                      s.stroke(blue)
                      s.strokeWeight(2)
                      solid(s)
                  }),
        switching("fog", side: 96, scene: view,
                  on: { $0.fog(Color(red: 0.6, green: 0.7, blue: 0.9), density: 0.5, heightFalloff: 0.2) },
                  off: { $0.noFog() }, content: solid),
        switching("matcap", side: 96, scene: view, on: { $0.matcap(Matcap.chrome) }, off: { $0.noMatcap() },
                  content: solid),
        switching("outline", side: 96, scene: view,
                  on: { $0.outline(width: 3, color: blue) }, off: { $0.noOutline() }, content: ball),
        // A red wall behind a glass ball, out of the environment's picture:
        // the ball shows the wall only while the scene is read through it.
        switching("scene through glass", side: 96,
                  scene: { s in
                      s.camera(.orbiting(target: .zero, radius: 5, azimuth: 0, elevation: 0,
                                         fieldOfView: .pi / 4, near: 1, far: 20))
                      s.environment(.studio)
                  },
                  on: { $0.sceneThroughGlass() }, off: { $0.noSceneThroughGlass() },
                  content: { s in
                      s.withState {
                          s.fill(Color(hex: 0xd94430))
                          s.material(.dielectric(roughness: 0.8))
                          s.translate(0, 0, -2.5)
                          s.drawBox(width: 8, height: 8, depth: 0.4)
                      }
                      s.fill(.white)
                      s.material(.glass())
                      s.drawSphere(radius: 1.2)
                  }),
        // A polished ball under one lamp: the highlight is a speck the filter widens.
        switching("specular antialiasing", side: 96, scene: view,
                  on: { $0.specularAntialiasing(strength: 3) }, off: { $0.noSpecularAntialiasing() },
                  content: { s in
                      s.material(.metal(roughness: 0.12))
                      ball(s)
                  }),
        // A spot from above, so there is a cone in the air to light.
        switching("volumetric light", side: 96,
                  scene: { s in
                      view(s)
                      s.spotLight(.white, at: Vector3(0.3, 2.4, 0.4), direction: Vector3(-0.1, -1, -0.1).normalized,
                                  coneAngle: .pi / 6, penumbra: 0.2, intensity: 3)
                  },
                  on: { $0.volumetricLight(1.5, anisotropy: 0.3) }, off: { $0.noVolumetricLight() },
                  content: grounded),
    ]

    @Test(arguments: pairs)
    func theSwitchPutsTheDefaultBack(_ pair: Pair) throws {
        let bare = pixels(of: try OllinApp.image(of: Stage(pair.side, pair.bare), frame: 1))
        let twin = pixels(of: try OllinApp.image(of: Stage(pair.side, pair.twin), frame: 1))
        let other = pixels(of: try OllinApp.image(of: Stage(pair.side, pair.other), frame: 1))
        #expect(bare != other, "the switch changed nothing, so matching its twin proves nothing")
        #expect(bare == twin)
    }

    // MARK: The switches read on their state

    /// One switch whose feature a single headless frame cannot show: `on`
    /// asks for the feature, `off` is the switch, and `isSet` reads what the
    /// drawer (or the sketch) holds for it.
    struct Flag: Sendable, CustomTestStringConvertible {
        let name: String
        let on: Step
        let off: Step
        let isSet: @MainActor @Sendable (Sketch) -> Bool
        var testDescription: String { name }
    }

    nonisolated static let flags: [Flag] = [
        // These three show only on a GPU that traces rays, or over several frames.
        Flag(name: "caustics", on: { $0.caustics(intensity: 1.3, dispersion: 0.4) }, off: { $0.noCaustics() },
             isSet: { $0.drawer.causticsEnabled }),
        Flag(name: "global illumination", on: { $0.globalIllumination(intensity: 1.7) },
             off: { $0.noGlobalIllumination() }, isSet: { $0.drawer.globalIlluminationEnabled }),
        Flag(name: "motion blur", on: { $0.motionBlur(shutter: 0.3) }, off: { $0.noMotionBlur() },
             isSet: { $0.drawer.motionBlurEnabled }),
        // These two act in the live window alone: an export draws every frame at full size.
        Flag(name: "temporal upscaling", on: { $0.temporalUpscaling(.detail) }, off: { $0.noTemporalUpscaling() },
             isSet: { $0.drawer.temporalUpscalingEnabled }),
        Flag(name: "frame interpolation", on: { $0.frameInterpolation() }, off: { $0.noFrameInterpolation() },
             isSet: { $0.drawer.frameInterpolationEnabled }),
        // These three have their rendered pair in their own suites.
        Flag(name: "temporal antialiasing", on: { $0.temporalAntialiasing() }, off: { $0.noTemporalAntialiasing() },
             isSet: { $0.drawer.temporalAAEnabled }),
        Flag(name: "aerial perspective", on: { $0.aerialPerspective(density: 0.3, haziness: 0.6) },
             off: { $0.noAerialPerspective() }, isSet: { $0.drawer.aerialActive }),
        Flag(name: "lens flare", on: { $0.lensFlare(amount: 1.4) }, off: { $0.noLensFlare() },
             isSet: { $0.drawer.lensFlareSetting != nil }),
        // Not a drawing state at all: what the sketch says of itself to a screen reader.
        Flag(name: "description", on: { $0.describe("A box on a floor.") }, off: { $0.noDescription() },
             isSet: { !$0.accessibleDescription.isEmpty }),
    ]

    @Test(arguments: flags)
    func theSwitchLowersWhatItsFeatureRaised(_ flag: Flag) {
        let sketch = Sketch()
        #expect(!flag.isSet(sketch), "the feature is on before anything asked for it")
        flag.on(sketch)
        #expect(flag.isSet(sketch), "the feature raised nothing, so the switch proved nothing")
        flag.off(sketch)
        #expect(!flag.isSet(sketch))
    }

    /// `noLoop()` stops the loop and tells the host once, and `loop()` starts
    /// it again: the host is what stops asking for frames.
    @Test func noLoopStopsTheLoopAndTellsTheHost() {
        let sketch = Sketch()
        var heard: [Bool] = []
        sketch.loopStateDidChange = { heard.append($0) }
        #expect(sketch.isLooping)

        sketch.noLoop()
        #expect(!sketch.isLooping)
        sketch.noLoop()                 // already stopped: nothing more to say
        #expect(heard == [false])

        sketch.loop()
        #expect(sketch.isLooping)
        #expect(heard == [false, true])
    }

    /// `noClear(precision:)` keeps the canvas between frames at the precision
    /// asked for, and `clearEachFrame()` is the way back.
    @Test func noClearKeepsTheCanvasAtThePrecisionAsked() {
        let sketch = Sketch()
        #expect(!sketch.drawer.accumulates)

        sketch.noClear(precision: .float32)
        #expect(sketch.drawer.accumulates)
        #expect(sketch.drawer.accumulationPrecision == .float32)

        sketch.clearEachFrame()
        #expect(!sketch.drawer.accumulates)

        sketch.noClear()
        #expect(sketch.drawer.accumulates)
        #expect(sketch.drawer.accumulationPrecision == .float16)
    }
}

/// A square canvas cleared to black, with whatever the pair paints on it.
@MainActor
private final class Stage: Sketch {
    var side = 64
    var paint: (Sketch) -> Void = { _ in }

    convenience init(_ side: Int, _ paint: @escaping (Sketch) -> Void) {
        self.init()
        self.side = side
        self.paint = paint
    }

    override var canvasSize: CanvasSize { .square(side) }

    override func draw() {
        background(.black)
        paint(self)
    }
}
