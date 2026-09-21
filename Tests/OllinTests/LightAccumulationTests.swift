import CoreGraphics
import Foundation
import Testing
import simd
import COllinShaders
@testable import Ollin

/// Light accumulation: the radiometric particle style, the running mean an
/// `Accumulator` keeps, the single-precision layers, the print filter, the camera a
/// kernel projects through, and the ball scatter. The CPU checks run everywhere;
/// the renders are Metal-gated and soft-skip without a GPU.
@Suite
@MainActor
struct LightAccumulationTests {

    // MARK: CPU

    /// `append(camera:aspect:)` writes the view then the projection, 128 bytes, as
    /// the shared `OllinCameraMatrices` a kernel reads.
    @Test func cameraParamsPackTheMatrices() {
        let camera = Camera3D.perspective(eye: Vector3(3, 4, 12), target: Vector3(0, 1, 0))
        var params = ComputeParams()
        params.append(camera: camera, aspect: 1.5)
        #expect(params.bytes.count == 128)
        let packed = params.bytes.withUnsafeBytes { $0.load(as: OllinCameraMatrices.self) }
        #expect(packed.view == camera.viewMatrix)
        #expect(packed.projection == camera.projectionMatrix(aspect: 1.5))
        #expect(camera.matrices(aspect: 1.5).view == camera.viewMatrix)
        // Anything appended after it lands past the matrices, so a kernel's struct
        // can begin with the camera and carry its own fields after.
        params.append(SIMD4<Float>(1, 2, 3, 4))
        #expect(params.bytes.count == 144)
    }

    /// Length sampling shares a pass's points by length times weight, at least
    /// one per line; per-line sampling gives every line the same count.
    @Test func lineSprayPointCounts() {
        let lines = [
            SprayLine(from: .zero, to: Vector3(1, 0, 0)),
            SprayLine(from: .zero, to: Vector3(0, 3, 0)),
            SprayLine(from: .zero, to: Vector3(0, 0, 1), weight: 2),
            SprayLine(from: Vector3(1, 1, 1), to: Vector3(1, 1, 1)),    // zero length
        ]
        #expect(LineSpray.pointCounts(for: lines, sampling: .perLine(25)) == [25, 25, 25, 25])
        // Weighted lengths 1, 3, 2, 0 over a hundred points: 16, 50, 33, and one.
        #expect(LineSpray.pointCounts(for: lines, sampling: .byLength(pointsPerPass: 100)) == [16, 50, 33, 1])
    }

    /// A spray line's optional end values default to the start's, and the tone
    /// form converts on the way in: the light is the color's linear RGB times
    /// the intensity.
    @Test func sprayLineDefaults() {
        let line = SprayLine(from: .zero, to: Vector3(1, 0, 0), color: .orange, intensity: 3)
        #expect(line.light == Color.orange.linearRGB * 3)
        #expect(line.endLight == line.light)
        #expect(line.weight == 1)
        #expect(line.length == 1)
        let lit = SprayLine(from: .zero, to: Vector3(1, 0, 0), light: SIMD3(0.2, 0.1, 0.05))
        #expect(lit.endLight == lit.light)
    }

    /// The two ways of naming a line's light meet exactly: a white line at
    /// intensity 0.4 is the line whose light is 0.4 in every channel, and a
    /// line given its light reads back as the tone that light encodes.
    @Test func sprayLineLightAndToneAreOneNumber() {
        let byTone = SprayLine(from: .zero, to: Vector3(1, 0, 0), color: .white, intensity: 0.4)
        let byLight = SprayLine(from: .zero, to: Vector3(1, 0, 0), light: SIMD3(repeating: 0.4))
        #expect(byTone == byLight)
        let radiance = Color.coral.linearRGB * 2.5
        let line = SprayLine(from: .zero, to: Vector3(0, 1, 0), light: radiance, endLight: radiance * 0.5)
        let tone = Color(linear: line.light / 2.5)
        #expect(abs(tone.red - Color.coral.red) < 1e-12 && abs(tone.green - Color.coral.green) < 1e-12
                && abs(tone.blue - Color.coral.blue) < 1e-12)
        #expect(line.endLight == radiance * 0.5)
    }

    /// The develop filter is one fragment pass carrying the exposure and the
    /// ground as display components.
    @Test func developIsOnePass() {
        let pass = Filter.develop(exposure: 2, ground: Color(red: 0.1, green: 0.2, blue: 0.3))
            .singlePass(width: 8, height: 8, resolve: { $0 })
        #expect(pass?.fragment == "ollin_fx_develop")
        #expect(pass?.params.first == SIMD4<Float>(2, 0, 0, 0))
        #expect(pass?.params.last == SIMD4<Float>(0.1, 0.2, 0.3, 1))
    }

    // MARK: Metal-gated

    /// The `.light` style deposits each particle's area, wherever it lands: five
    /// thousand one-pixel discs at random positions sum to their area times
    /// their alpha, half-pixel discs to a quarter of that, and the default `.marks`
    /// style (perceptual coverage, for ink) lands well above the light sum.
    @Test(.enabled(if: Snapshot.hasMetal))
    func lightParticlesDepositTheirArea() throws {
        let count = 5000
        let alpha: Float = 0.25
        func total(size: Float, style: ParticleStyle) throws -> Double {
            let sketch = ParticleDepositSketch(count: count, size: size, alpha: alpha, style: style)
            let image = try #require(OllinApp.image(of: sketch, frame: 0))
            return linearSum(of: image)
        }
        let expected = Double(count) * Double.pi / 4 * Double(alpha)
        let onePixel = try total(size: 1, style: .light)
        let halfPixel = try total(size: 0.5, style: .light)
        let twoPixel = try total(size: 2, style: .light)
        let marks = try total(size: 1, style: .marks)
        #expect(abs(onePixel - expected) / expected < 0.08, "one-pixel light: \(onePixel) vs \(expected)")
        #expect(abs(halfPixel / onePixel - 0.25) < 0.05, "half-pixel light: \(halfPixel / onePixel)")
        #expect(abs(twoPixel / onePixel - 4) < 0.4, "two-pixel light: \(twoPixel / onePixel)")
        #expect(marks > onePixel * 1.3, "marks \(marks) should read brighter than light \(onePixel)")
    }

    /// A one-pixel light particle lands in the texel that holds it (a neighbor or
    /// three may share it under multisampling) and deposits its whole area.
    @Test(.enabled(if: Snapshot.hasMetal))
    func oneLightPixelLightsOnePixel() throws {
        let sketch = ParticleDepositSketch(count: 1, size: 1, alpha: 1, style: .light,
                                           fixed: SIMD2<Float>(100.3, 200.7))
        let image = try #require(OllinApp.image(of: sketch, frame: 0))
        let lit = litPixels(of: image)
        #expect(lit.count >= 1 && lit.count <= 4, "lit texels: \(lit.count)")
        #expect(lit.allSatisfy { abs($0.x - 100) <= 1 && abs($0.y - 200) <= 1 })
        let sum = lit.reduce(0.0) { $0 + $1.value }
        #expect(abs(sum - Double.pi / 4) < 0.08, "deposit \(sum)")
    }

    /// An accumulator hands back the mean: six passes of the same faint square read
    /// the same as one, the count matches, `passes:` divides, and a reset restarts.
    @Test(.enabled(if: Snapshot.hasMetal))
    func accumulatorHoldsTheMean() throws {
        let one = AccumulatorSketch()
        let first = try #require(OllinApp.image(of: one, frame: 0))
        #expect(abs(centerLinear(of: first) - 0.2) < 0.02)
        #expect(one.light.passes == 1)

        let six = AccumulatorSketch()
        let sixth = try #require(OllinApp.image(of: six, frame: 5))
        #expect(abs(centerLinear(of: sixth) - 0.2) < 0.02, "six passes should still read 0.2, not their sum")
        #expect(six.light.passes == 6)

        let doubled = AccumulatorSketch()
        doubled.passesPerBlock = 2
        let half = try #require(OllinApp.image(of: doubled, frame: 2))
        #expect(abs(centerLinear(of: half) - 0.1) < 0.02, "two passes per block halve the mean")

        // `frameCount` is 1 on the first draw, so frame 5 is the sixth draw and a
        // reset at the start of the third leaves the third through sixth: four.
        let restarted = AccumulatorSketch()
        restarted.resetAtFrame = 3
        _ = OllinApp.image(of: restarted, frame: 5)
        #expect(restarted.light.passes == 4)
    }

    /// A feedback layer summing a step under half float's spacing stalls at
    /// `.float16` and keeps climbing at `.float32`.
    @Test(.enabled(if: Snapshot.hasMetal))
    func singlePrecisionFeedbackKeepsAdding() throws {
        let half = FeedbackSumSketch(precision: .float16)
        let halfImage = try #require(OllinApp.image(of: half, frame: 199))
        let single = FeedbackSumSketch(precision: .float32)
        let singleImage = try #require(OllinApp.image(of: single, frame: 199))
        let stalled = centerLinear(of: halfImage)
        let climbed = centerLinear(of: singleImage)
        #expect(abs(stalled - 0.5) < 0.01, "half float should hold 0.5, read \(stalled)")
        #expect(abs(climbed - 0.54) < 0.01, "single float should reach 0.54, read \(climbed)")
    }

    /// The develop filter prints the reference recipe: exposure, Reinhard, then the
    /// ground added as a display value.
    @Test(.enabled(if: Snapshot.hasMetal))
    func developPrintsTheRecipe() throws {
        let sketch = DevelopSketch()
        let image = try #require(OllinApp.image(of: sketch, frame: 0))
        // Linear 0.5 × exposure 2 = 1 → 1 / (1 + 1) = 0.5, plus a 0.1 ground → 0.6 display.
        let byte = centerByte(of: image)
        #expect(abs(Double(byte) - 0.6 * 255) <= 2, "printed \(byte)")
    }

    /// A kernel projecting through the packed camera lands where the sketch's own
    /// `project(_:)` puts the point, through the multi-buffer dispatch.
    @Test(.enabled(if: Snapshot.hasMetal))
    func kernelProjectsLikeTheSketch() throws {
        let sketch = ProjectionSketch()
        _ = OllinApp.image(of: sketch, frame: 0)
        let particles = try #require(sketch.out.snapshot())
        for (i, world) in sketch.points.enumerated() {
            let expected = try #require(sketch.expected[i])
            let got = particles[i].position
            #expect(abs(Double(got.x) - expected.x) < 0.05 && abs(Double(got.y) - expected.y) < 0.05,
                    "point \(i): kernel \(got) vs sketch \(expected)")
        }
        // A point behind the camera is marked dead (size 0), not drawn somewhere.
        #expect(particles[sketch.points.count].size == 0)
    }

    /// `ballSample` is uniform over the ball: every draw inside it, a mean radius of
    /// three quarters, an eighth of the draws inside the half-radius ball, and no
    /// bias in any axis.
    @Test(.enabled(if: Snapshot.hasMetal))
    func ballSampleIsUniform() throws {
        let sketch = BallSampleSketch()
        _ = OllinApp.image(of: sketch, frame: 0)
        let samples = try #require(sketch.out.snapshot())
        let radii = samples.map { Double(simd_length(SIMD3($0.x, $0.y, $0.z))) }
        #expect(radii.allSatisfy { $0 <= 1.0001 })
        let meanRadius = radii.reduce(0, +) / Double(radii.count)
        #expect(abs(meanRadius - 0.75) < 0.02, "mean radius \(meanRadius)")
        let inner = Double(radii.filter { $0 < 0.5 }.count) / Double(radii.count)
        #expect(abs(inner - 0.125) < 0.02, "inside the half ball \(inner)")
        let mean = samples.reduce(SIMD3<Double>.zero) { $0 + SIMD3(Double($1.x), Double($1.y), Double($1.z)) }
            / Double(samples.count)
        #expect(abs(mean.x) < 0.03 && abs(mean.y) < 0.03 && abs(mean.z) < 0.03, "centroid \(mean)")
    }

    /// A line spray converges: a still scene through a still camera reads the same
    /// after twelve frames as after two, the pass count climbs, and moving the lens
    /// restarts it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func lineSprayConvergesAndResets() throws {
        let sketch = SpraySketch()
        let early = try #require(OllinApp.image(of: sketch, frame: 1))
        #expect(sketch.spray.passes == 2 * sketch.spray.passesPerFrame)
        let earlyMean = meanLinear(of: early)
        #expect(earlyMean > 0.001, "the spray should have drawn something: \(earlyMean)")

        let late = SpraySketch()
        let lateImage = try #require(OllinApp.image(of: late, frame: 11))
        #expect(late.spray.passes == 12 * late.spray.passesPerFrame)
        let lateMean = meanLinear(of: lateImage)
        #expect(abs(lateMean - earlyMean) / earlyMean < 0.1, "mean drifted: \(earlyMean) → \(lateMean)")

        // Six draws, the lens moved from the fourth on: the fourth, fifth, and
        // sixth are all the average holds.
        let moved = SpraySketch()
        moved.refocusAtFrame = 4
        _ = OllinApp.image(of: moved, frame: 5)
        #expect(moved.spray.passes == 3 * moved.spray.passesPerFrame, "a lens change restarts the average")
    }

    @Test func sprayQuadPointCounts() {
        let quads = [
            SprayQuad(corner: .zero, edge1: Vector3(1, 0, 0), edge2: Vector3(0, 1, 0)),      // area 1
            SprayQuad(corner: .zero, edge1: Vector3(2, 0, 0), edge2: Vector3(0, 2, 0)),      // area 4
            SprayQuad(corner: .zero, edge1: Vector3(1, 0, 0), edge2: Vector3(0, 1, 0), weight: 3),
            SprayQuad(corner: .zero, edge1: Vector3(1, 0, 0), edge2: Vector3(2, 0, 0)),      // parallel: no area
        ]
        #expect(quads.map(\.area) == [1, 4, 1, 0])
        #expect(LineSpray.quadPointCounts(for: quads, sampling: .perLine(25)) == [25, 25, 25, 25])
        // Weighted areas 1, 4, 3, 0 over a hundred points: 12, 50, 37, and one.
        #expect(LineSpray.quadPointCounts(for: quads, sampling: .byLength(pointsPerPass: 100)) == [12, 50, 37, 1])
    }

    @Test func sprayQuadLightAndToneAreOneNumber() {
        let corner = Vector3(0, 0, 0), e1 = Vector3(1, 0, 0), e2 = Vector3(0, 1, 0)
        let named = SprayQuad(corner: corner, edge1: e1, edge2: e2, color: .white, intensity: 0.4)
        let given = SprayQuad(corner: corner, edge1: e1, edge2: e2, light: SIMD3(repeating: 0.4))
        #expect(named == given, "a tone times a brightness is the light it stands for")
        #expect(SprayQuad(corner: corner, edge1: e1, edge2: e2).light == SIMD3(repeating: 1))
        #expect(SprayQuad(corner: corner, edge1: e1, edge2: e2).pictureBounds == nil)
    }

    /// A quad's light is the whole quad's, however many points draw it and
    /// whatever its area, which is the line's law one dimension up.
    @Test func aQuadsLightIsSpreadOverItsOwnPoints() {
        let small = SprayQuad(corner: .zero, edge1: Vector3(1, 0, 0), edge2: Vector3(0, 1, 0),
                              light: SIMD3(repeating: 2))
        let large = SprayQuad(corner: .zero, edge1: Vector3(10, 0, 0), edge2: Vector3(0, 10, 0),
                              light: SIMD3(repeating: 2))
        let counts = LineSpray.quadPointCounts(for: [small, large], sampling: .byLength(pointsPerPass: 1010))
        let records = LineSpray.quadRecords(for: [small, large], counts: counts)
        for (record, count) in zip(records, counts) {
            #expect(abs(Double(record.corner.w) - 1 / Double(count)) < 1e-6,
                    "each point carries one \(count)th of its quad's light")
            // What a pass deposits is the share times the count: the light itself,
            // the same for a quad of one square unit and one of a hundred.
            #expect(abs(Double(record.light.x) * Double(record.corner.w) * Double(count) - 2) < 1e-5)
        }
    }

    @Test func aQuadCarriesThePatchOfThePictureItReads() {
        let plain = SprayQuad(corner: .zero, edge1: Vector3(1, 0, 0), edge2: Vector3(0, 1, 0))
        let read = SprayQuad(corner: .zero, edge1: Vector3(1, 0, 0), edge2: Vector3(0, 1, 0),
                             pictureBounds: Rectangle(x: 0.25, y: 0.5, width: 0.25, height: 0.5))
        let records = LineSpray.quadRecords(for: [plain, read], counts: [1, 1])
        #expect(records[0].texture.z == 0 && records[0].texture.w == 0,
                "a patch of no size is what tells the kernel to read no picture")
        #expect(records[1].texture == SIMD4<Float>(0.25, 0.5, 0.25, 0.5))
    }

    /// The surfaces reach the GPU through their own kernel and land in the same
    /// picture as the lines: a scene of quads alone draws light, and the two
    /// together draw more of it than either does by itself.
    @Test(.enabled(if: Snapshot.hasMetal))
    func quadsAndLinesScatterIntoOnePicture() throws {
        func ink(lines: Bool, quads: Bool) throws -> Double {
            let sketch = QuadSpraySketch()
            sketch.wantsLines = lines
            sketch.wantsQuads = quads
            let image = try #require(OllinApp.image(of: sketch, frame: 3))
            return linearSum(of: image)
        }
        let linesOnly = try ink(lines: true, quads: false)
        let quadsOnly = try ink(lines: false, quads: true)
        let both = try ink(lines: true, quads: true)

        #expect(quadsOnly > 0, "a scene of surfaces alone draws light")
        #expect(linesOnly > 0)
        #expect(both > linesOnly, "the surfaces add to the wires rather than replacing them")
        // One accumulator, one pass count, one picture: what the two draw
        // together is what they draw apart, added. The slack is the print's,
        // since the sum is read after the curve rather than before it.
        #expect(abs(both - (linesOnly + quadsOnly)) < (linesOnly + quadsOnly) * 0.1,
                "lines \(linesOnly) and quads \(quadsOnly) should add to about \(both)")
    }

    @Test func apertureReadsAsItsShape() {
        #expect(Aperture.round.bladeCount == 0)
        #expect(Aperture.blades(6).bladeCount == 6)
        #expect(Aperture.blades(6).rotation == 0)
        #expect(Aperture.blades(count: 5, rotation: 0.3).rotation == 0.3)
        // Under three there is no shape to scatter in, so it reads round.
        #expect(Aperture.blades(2).bladeCount == 0)
        #expect(Aperture.blades(0).bladeCount == 0)
        #expect(Aperture.round.picture == nil && Aperture.blades(6).picture == nil)
        #expect(Bokeh(focalDistance: 8).aperture == .round, "a lens is round unless told otherwise")
        #expect(Aperture.blades(6) == Aperture.blades(count: 6, rotation: 0))
        #expect(Aperture.blades(6) != Aperture.blades(7))
        #expect(Aperture.blades(6) != .round)
    }

    /// A drawn or loaded aperture is the same aperture only while it is the
    /// same picture, which is what a lens compares to know it changed.
    @Test func anApertureIsThePictureItWasGiven() throws {
        let one = try #require(Image(width: 4, height: 4, premultipliedRGBA: [UInt8](repeating: 255, count: 64)))
        let two = try #require(Image(width: 4, height: 4, premultipliedRGBA: [UInt8](repeating: 255, count: 64)))
        #expect(Aperture.picture(one) == Aperture.picture(one))
        #expect(Aperture.picture(one) != Aperture.picture(two), "same pixels, different picture")
        #expect(Aperture.picture(one) != .round)
        #expect(Aperture.picture(one).bladeCount == 0, "a mask is not described by a blade count")
        #expect(Aperture.picture(one).picture === one)
    }

    /// The round aperture is the scatter every picture was made with before
    /// there was a choice, so a lens that does not ask for a shape has to draw
    /// exactly what it drew before. This is the law that lets the aperture ship
    /// without moving a single committed image.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theRoundApertureDrawsWhatItAlwaysDrew() throws {
        let plain = try #require(OllinApp.image(of: MovingSpraySketch(), frame: 3))
        let asked = MovingSpraySketch()
        asked.aperture = .round
        let same = try #require(OllinApp.image(of: asked, frame: 3))
        #expect(pixelsEqual(plain, same), "asking for round must draw what asking for nothing draws")
    }

    /// An aperture moves where a sample lands, never how much light it
    /// carries: every sample deposits its line's share whatever hole it went
    /// through, so a hexagon, a triangle and the round ball print the same
    /// total light. Read below the print's ceiling, or a shape that crowds its
    /// middle clips and reads short of one that does not.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theApertureShapesTheLightWithoutChangingIt() throws {
        func ink(_ aperture: Aperture) throws -> Double {
            let sketch = AperturePointSketch()
            sketch.aperture = aperture
            sketch.printExposure = 1.2
            return linearSum(of: try #require(OllinApp.image(of: sketch, frame: 6)))
        }
        let round = try ink(.round)
        let six = try ink(.blades(6))
        let three = try ink(.blades(3))
        #expect(abs(six - round) < round * 0.03, "round \(round), six blades \(six)")
        #expect(abs(three - round) < round * 0.03, "round \(round), three blades \(three)")
    }

    /// The blades draw their own shape, and turning them turns it. A triangle
    /// is lopsided left to right; half a turn of its step mirrors it, and a
    /// whole step is the same iris again. The round ball leans neither way.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theBladesDrawTheirShapeAndTurnWithIt() throws {
        func lean(_ aperture: Aperture) throws -> Double {
            let sketch = AperturePointSketch()
            sketch.aperture = aperture
            return horizontalLean(of: try #require(OllinApp.image(of: sketch, frame: 6)))
        }
        let round = try lean(.round)
        let straight = try lean(.blades(3))
        let mirrored = try lean(.blades(count: 3, rotation: .pi / 3))
        let wholeStep = try lean(.blades(count: 3, rotation: 2 * .pi / 3))

        #expect(abs(round) < 0.15, "a ball is symmetric either way: \(round)")
        #expect(abs(straight) > 0.3, "a triangle leans: \(straight)")
        #expect(straight * mirrored < 0, "half a step mirrors it: \(straight) against \(mirrored)")
        #expect(abs(wholeStep - straight) < abs(straight) * 0.35,
                "a whole step is the same iris: \(wholeStep) against \(straight)")
    }

    /// An aperture drawn or loaded is a mask the lens reads across its hole:
    /// where the picture is dark, no light passes. This is the tier that
    /// covers an iris a sketch drew into a render target and a photographed
    /// one alike, since both arrive as an `Image`.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aDrawnApertureLetsLightThroughWhereItIsOpen() throws {
        let side = 32
        /// A mask filled on one side, dark on the other, or filled throughout.
        func mask(open: (Int) -> Bool) throws -> Image {
            var bytes = [UInt8](repeating: 0, count: side * side * 4)
            for y in 0 ..< side {
                for x in 0 ..< side where open(x) {
                    let i = (y * side + x) * 4
                    bytes[i] = 255; bytes[i + 1] = 255; bytes[i + 2] = 255; bytes[i + 3] = 255
                }
            }
            return try #require(Image(width: side, height: side, premultipliedRGBA: bytes))
        }
        func ink(_ aperture: Aperture) throws -> Double {
            let sketch = AperturePointSketch()
            sketch.aperture = aperture
            sketch.printExposure = 1.2
            return linearSum(of: try #require(OllinApp.image(of: sketch, frame: 6)))
        }
        func lean(_ aperture: Aperture) throws -> Double {
            let sketch = AperturePointSketch()
            sketch.aperture = aperture
            return horizontalLean(of: try #require(OllinApp.image(of: sketch, frame: 6)))
        }

        // A hole stopped all the way down passes nothing, which is also what
        // the canvas reads with no light on it at all: the print's own floor.
        let shut = try ink(.picture(try mask { _ in false }))
        let wideOpen = try ink(.picture(try mask { _ in true }))
        let half = try ink(.picture(try mask { $0 >= side / 2 }))
        #expect(wideOpen > shut, "an open hole passes light and a shut one does not")

        // Measured above that floor, a hole open on half its width passes half
        // the light, which is the mask being read per sample rather than once.
        let openLight = wideOpen - shut, halfLight = half - shut
        #expect(abs(halfLight / openLight - 0.5) < 0.08,
                "half a hole passes \(halfLight / openLight) of what the whole one does")

        // And it throws that light to the side it is open on: the mark's own
        // center moves that way, which is what says the picture is read at the
        // spot the sample took rather than merely thinning it everywhere.
        func center(_ aperture: Aperture) throws -> Double {
            let sketch = AperturePointSketch()
            sketch.aperture = aperture
            return centroidX(of: try #require(OllinApp.image(of: sketch, frame: 6)))
        }
        let openRight = try center(.picture(try mask { $0 >= side / 2 }))
        let openLeft = try center(.picture(try mask { $0 < side / 2 }))
        let openWide = try center(.picture(try mask { _ in true }))
        #expect(openRight > openWide + 1, "open on the right: \(openRight) against \(openWide)")
        #expect(openLeft < openWide - 1, "open on the left: \(openLeft) against \(openWide)")
    }

    /// A moving scene: `setLines` every frame with the same lines leaves the
    /// average alone (a settled export converges), moved lines restart it and
    /// reach the GPU (the light's centroid follows them), and while the point
    /// counts hold the point table is kept and the records ride a ring of at
    /// most `maxFramesInFlight` buffers rather than a fresh one per frame.
    @Test(.enabled(if: Snapshot.hasMetal))
    func setLinesEveryFrameKeepsOrRestartsTheAverageAsTheLinesAsk() throws {
        let still = MovingSpraySketch()
        still.shift = { _ in 0 }
        _ = try #require(OllinApp.image(of: still, frame: 5))
        #expect(still.spray.passes == 6 * still.spray.passesPerFrame, "the same lines again keep the average")
        #expect(still.spray.ringDepth == 1, "nothing was rewritten")

        let moving = MovingSpraySketch()
        moving.shift = { frame in Double(frame) * 0.2 }
        let image = try #require(OllinApp.image(of: moving, frame: 5))
        #expect(moving.spray.passes == moving.spray.passesPerFrame, "moved lines restart the average")
        #expect(moving.spray.ringDepth <= MetalRenderer.maxFramesInFlight && moving.spray.ringDepth >= 2,
                "the records ride a ring: \(moving.spray.ringDepth) buffers")
        #expect(moving.spray.pointTable === moving.tableAtFirstDraw, "the point table is kept while the counts hold")
        // The sixth frame's lines sit 1.0 unit to the right of the still scene's,
        // about 14 px through this camera and still on the canvas, so the light's
        // centroid has moved that far: the rewrite reached the GPU. A slot the
        // write never reached would still hold a frame from three draws back, at
        // most 0.4 units (6 px), which is why the bar sits at 10 and not merely
        // above zero.
        let stillImage = try #require(OllinApp.image(of: MovingSpraySketch(), frame: 5))
        let movedX = centroidX(of: image), stillX = centroidX(of: stillImage)
        #expect(movedX > stillX + 10, "centroid moved from \(stillX) to \(movedX)")

        // Under length sampling, lines that change their shares rebuild the table.
        let stretching = MovingSpraySketch()
        stretching.sampling = .byLength(pointsPerPass: 2000)
        stretching.stretch = { frame in 1 + Double(frame) * 0.5 }
        _ = try #require(OllinApp.image(of: stretching, frame: 2))
        #expect(stretching.spray.pointTable !== stretching.tableAtFirstDraw, "changed shares rebuild the point table")
        // The particles are another matter. Shares that move change the total by
        // a point or two every frame, and the buffer all of them land in is kept
        // through that: made again for each new total, a few million points are
        // hundreds of megabytes a frame.
        #expect(stretching.totalsSeen.count > 1, "the total moved: \(stretching.totalsSeen.sorted())")
        #expect(stretching.spray.particleStore === stretching.storeAtFirstDraw,
                "the particles are kept while the total drifts")
    }

    /// Room for the particles is a little more than was asked for, in whole
    /// blocks, so a total that drifts stays inside it, and it is handed back only
    /// when a scene has shrunk to under a quarter of it.
    @Test func sprayParticlesAreGivenRoomToDrift() {
        for count in [1, 2400, 4096, 65_537, 6_000_000] {
            let room = LineSpray.particleCapacity(for: count)
            #expect(room >= count + count / 16, "\(count) points get \(room)")
            #expect(room % 4096 == 0)
            #expect(room <= count + count / 16 + 4096, "and no more than a block over: \(room)")
            // What the same scene asks for a frame later, a little more or less,
            // fits in what it already has.
            #expect(LineSpray.particleCapacity(for: count - count / 64) * 4 > room)
            #expect(count + count / 64 <= room)
        }
    }

    /// `exportSettle` draws a written frame several times with the clock held: a
    /// still counts N passes for its frame (and one for each run-up frame), the
    /// mean stays the mean, and a sequence settles every written frame.
    @Test(.enabled(if: Snapshot.hasMetal))
    func settledExportsDrawEachWrittenFrameSeveralTimes() throws {
        OllinApp.exportSettle = 6
        defer { OllinApp.exportSettle = 1 }

        let still = AccumulatorSketch()
        let image = try #require(OllinApp.image(of: still, frame: 0))
        #expect(still.light.passes == 6, "one advance plus five held draws")
        #expect(abs(centerLinear(of: image) - 0.2) < 0.02, "the mean is still the mean")

        let later = AccumulatorSketch()
        _ = OllinApp.image(of: later, frame: 2)
        #expect(later.light.passes == 8, "two run-up frames drawn once, the captured one six times")
        #expect(later.frameCount == 8)
        #expect(abs(later.time - 2.0 / 60) < 1e-9, "the clock held at the captured frame")

        let sequence = AccumulatorSketch()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-settle-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: directory) }
        OllinApp.exportSequence(sequence, to: directory, frames: 2, fps: 60)
        #expect(sequence.light.passes == 12, "every written frame settles")
        let written = (try? FileManager.default.contentsOfDirectory(atPath: directory))?
            .filter { $0.hasSuffix(".png") }.count
        #expect(written == 2)
    }

    // MARK: Support

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return bytes }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return bytes
    }

    private func linear(_ byte: UInt8) -> Double {
        let c = Double(byte) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// The sum of linear luminance over every pixel (the light the frame holds).
    /// Whether two renders are the same picture, byte for byte.
    private func pixelsEqual(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height,
              let left = a.dataProvider?.data as Data?, let right = b.dataProvider?.data as Data?
        else { return false }
        return left == right
    }

    /// Which way the light leans: the ink-weighted skew in x about its own
    /// center, scaled by its own spread, so it says the shape's lopsidedness
    /// rather than its size or where it sits. A shape symmetric left to right
    /// reads about zero. Pixels under a tenth of the brightest are left out,
    /// since the print's dither floor covers the whole canvas and would
    /// otherwise outweigh the mark being read.
    private func horizontalLean(of image: CGImage, vertical: Bool = false) -> Double {
        guard let data = image.dataProvider?.data as Data? else { return 0 }
        let bytesPerRow = image.bytesPerRow, width = image.width, height = image.height
        var peak = 0.0
        data.withUnsafeBytes { raw in
            for y in 0 ..< height {
                for x in 0 ..< width { peak = max(peak, Double(raw[y * bytesPerRow + x * 4])) }
            }
        }
        guard peak > 0 else { return 0 }
        let floor = peak * 0.35
        var weight = 0.0, first = 0.0, second = 0.0, third = 0.0
        data.withUnsafeBytes { raw in
            for y in 0 ..< height {
                for x in 0 ..< width {
                    let value = Double(raw[y * bytesPerRow + x * 4])
                    guard value >= floor else { continue }
                    let position = vertical ? Double(y) : Double(x)
                    weight += value
                    first += value * position
                    second += value * position * position
                    third += value * position * position * position
                }
            }
        }
        guard weight > 0 else { return 0 }
        let mean = first / weight
        let variance = second / weight - mean * mean
        guard variance > 1e-9 else { return 0 }
        let cube = third / weight - 3 * mean * second / weight + 2 * mean * mean * mean
        return cube / (variance * variance.squareRoot())
    }

    /// How wide the light sits, in pixels: twice the intensity-weighted spread
    /// about its own center, which reads a shape's extent without a threshold
    /// to pick and without caring where on the canvas it landed.
    private func discWidth(of image: CGImage) -> Double {
        guard let data = image.dataProvider?.data as Data? else { return 0 }
        let bytesPerRow = image.bytesPerRow, width = image.width, height = image.height
        var weight = 0.0, meanX = 0.0, meanSquare = 0.0
        data.withUnsafeBytes { raw in
            for y in 0 ..< height {
                for x in 0 ..< width {
                    let value = Double(raw[y * bytesPerRow + x * 4]) / 255
                    guard value > 0 else { continue }
                    weight += value
                    meanX += value * Double(x)
                    meanSquare += value * Double(x) * Double(x)
                }
            }
        }
        guard weight > 0 else { return 0 }
        let center = meanX / weight
        return 2 * (meanSquare / weight - center * center).squareRoot()
    }

    private func linearSum(of image: CGImage) -> Double {
        let d = pixels(of: image)
        var sum = 0.0
        for i in stride(from: 0, to: d.count, by: 4) {
            sum += (linear(d[i]) + linear(d[i + 1]) + linear(d[i + 2])) / 3
        }
        return sum
    }

    private func meanLinear(of image: CGImage) -> Double {
        linearSum(of: image) / Double(image.width * image.height)
    }

    private func litPixels(of image: CGImage) -> [(x: Int, y: Int, value: Double)] {
        let d = pixels(of: image)
        var out: [(Int, Int, Double)] = []
        for y in 0 ..< image.height {
            for x in 0 ..< image.width {
                let i = (y * image.width + x) * 4
                if d[i] > 1 || d[i + 1] > 1 || d[i + 2] > 1 {
                    out.append((x, y, (linear(d[i]) + linear(d[i + 1]) + linear(d[i + 2])) / 3))
                }
            }
        }
        return out
    }

    /// The x of the light's centroid, in pixels: where the picture's brightness sits.
    private func centroidX(of image: CGImage) -> Double {
        let d = pixels(of: image)
        var sum = 0.0, weight = 0.0
        for y in 0 ..< image.height {
            for x in 0 ..< image.width {
                let i = (y * image.width + x) * 4
                let v = linear(d[i]) + linear(d[i + 1]) + linear(d[i + 2])
                sum += Double(x) * v
                weight += v
            }
        }
        return weight > 0 ? sum / weight : 0
    }

    private func centerByte(of image: CGImage) -> UInt8 {
        let d = pixels(of: image)
        let i = ((image.height / 2) * image.width + image.width / 2) * 4
        return d[i + 1]
    }

    private func centerLinear(of image: CGImage) -> Double { linear(centerByte(of: image)) }
}

// MARK: - Probe sketches

/// Draws `count` white particles at seeded random positions (or one at `fixed`)
/// in the given style, additively over black.
@MainActor
private final class ParticleDepositSketch: Sketch {
    var buffer: ComputeBuffer<OllinParticle>!
    var style: ParticleStyle = .marks
    override var canvasSize: CanvasSize { .square(512) }

    convenience init(count: Int, size: Float, alpha: Float, style: ParticleStyle, fixed: SIMD2<Float>? = nil) {
        self.init()
        var state: UInt32 = 12345
        func next() -> Float {
            state = state &* 1664525 &+ 1013904223
            return Float(state >> 8) / Float(1 << 24)
        }
        var particles: [OllinParticle] = []
        for _ in 0 ..< count {
            let position = fixed ?? SIMD2<Float>(16 + next() * 480, 16 + next() * 480)
            particles.append(OllinParticle(position: position, velocity: .zero,
                                           color: SIMD4(1, 1, 1, alpha), size: size,
                                           life: 1, seedA: 0, seedB: 0))
        }
        buffer = ComputeBuffer(particles)
        self.style = style
    }

    override func draw() {
        background(.black)
        blendMode(.add)
        drawParticles(buffer, style: style)
    }
}

/// Adds a 20% white square into an accumulator every frame and shows the mean.
@MainActor
private final class AccumulatorSketch: Sketch {
    var light: Accumulator!
    var passesPerBlock = 1
    var resetAtFrame: Int? = nil
    override var canvasSize: CanvasSize { .square(64) }

    override func setup() { light = makeAccumulator() }

    override func draw() {
        background(.black)
        if let resetAtFrame, frameCount == resetAtFrame { light.reset() }
        withAccumulator(light, passes: passesPerBlock) {
            blendMode(.add)
            noStroke()
            fill(Color(white: 1, alpha: 0.2))
            drawRect(0, 0, width, height)
        }
        drawImage(light.image, 0, 0)
    }
}

/// A feedback layer seeded at linear 0.5 that adds 0.0002 every frame.
@MainActor
private final class FeedbackSumSketch: Sketch {
    var precision: LayerPrecision = .float16
    var sum: Feedback!
    override var canvasSize: CanvasSize { .square(32) }

    convenience init(precision: LayerPrecision) {
        self.init()
        self.precision = precision
    }

    override func setup() { sum = makeFeedback(precision: precision) }

    override func draw() {
        background(.black)
        withFeedback(sum) { previous in
            if frameCount == 1 {
                background(Color(white: 0.7354))     // sRGB 0.7354 is linear 0.5
            } else {
                drawImage(previous, 0, 0)
            }
            blendMode(.add)
            noStroke()
            fill(Color(white: 1, alpha: 0.0002))
            drawRect(0, 0, width, height)
        }
        drawImage(sum.image, 0, 0)
    }
}

/// A layer at linear 0.5 printed at exposure 2 on a 0.1 ground.
@MainActor
private final class DevelopSketch: Sketch {
    override var canvasSize: CanvasSize { .square(32) }
    override func draw() {
        background(.black)
        let layer = makeRenderTarget()
        withTarget(layer) { background(Color(white: 0.7354)) }
        let printed = layer.filtered(.develop(exposure: 2, ground: Color(white: 0.1)))
        drawImage(printed.image, 0, 0)
    }
}

/// A kernel projecting five world points (and one behind the camera) through the
/// packed camera, over the multi-buffer dispatch: a `SIMD4<Float>` list in, an
/// `OllinParticle` list out.
@MainActor
private final class ProjectionSketch: Sketch {
    let points = [Vector3(0, 0, 0), Vector3(1, 0.5, -2), Vector3(-2, 1, 1),
                  Vector3(0.3, -1.2, 2), Vector3(2, 2, -3)]
    var expected: [Vector2?] = []
    var world: ComputeBuffer<SIMD4<Float>>!
    var out: ComputeBuffer<OllinParticle>!
    override var canvasSize: CanvasSize { .size(320, 200) }

    private let kernel = ComputeKernel(entry: "project_probe", """
        kernel void project_probe(device const float4 *world [[buffer(0)]],
                                  device OllinParticle *out [[buffer(1)]],
                                  constant OllinComputeUniforms &u [[buffer(10)]],
                                  constant OllinCameraMatrices &camera [[buffer(11)]],
                                  uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            float4 screen = ollin_project(camera, world[id].xyz, u.resolution);
            OllinParticle p;
            p.position = screen.xy;
            p.velocity = float2(screen.z, screen.w);
            p.color = float4(1.0);
            p.size = screen.w > 0.0 ? 1.0 : 0.0;
            p.life = 1.0; p.seedA = 0.0; p.seedB = 0.0;
            out[id] = p;
        }
    """)

    required init() {
        super.init()
        var list = points.map { SIMD4<Float>(Float($0.x), Float($0.y), Float($0.z), 1) }
        list.append(SIMD4<Float>(0, 0, 20, 1))   // behind a camera at z = 10 looking at the origin
        world = ComputeBuffer(list)
        out = ComputeBuffer(count: list.count)
    }

    override func draw() {
        background(.black)
        camera(.perspective(eye: Vector3(3, 2, 10), target: .zero, fieldOfView: .pi / 4))
        expected = points.map { project($0) }
        compute(kernel, buffers: [world, out], params: cameraParams())
    }
}

/// Fills a buffer with `ballSample` draws.
@MainActor
private final class BallSampleSketch: Sketch {
    let out = ComputeBuffer<SIMD4<Float>>(count: 16384)
    override var canvasSize: CanvasSize { .square(16) }
    private let kernel = ComputeKernel(entry: "ball_probe", """
        kernel void ball_probe(device float4 *out [[buffer(0)]],
                               constant OllinComputeUniforms &u [[buffer(10)]],
                               uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            out[id] = float4(ballSample(float3(float(id), 0.37, 1.9)), 0.0);
        }
    """)
    override func draw() {
        background(.black)
        compute(kernel, over: out)
    }
}

/// A small spray of a few bright lines through a still camera.
@MainActor
private final class SpraySketch: Sketch {
    var spray: LineSpray!
    var refocusAtFrame: Int? = nil
    override var canvasSize: CanvasSize { .square(96) }

    override func setup() {
        var lines: [SprayLine] = []
        for i in 0 ..< 12 {
            let a = Double(i) / 12 * .tau
            lines.append(SprayLine(from: Vector3(cos(a) * 2, sin(a) * 2, 0),
                                   to: Vector3(cos(a + 0.5) * 2, sin(a + 0.5) * 2, 0.5),
                                   intensity: 0.4))
        }
        spray = makeLineSpray(lines, sampling: .perLine(200), passesPerFrame: 3,
                              bokeh: Bokeh(focalDistance: 8, strength: 0.05, minSize: 0.02))
    }

    override func draw() {
        background(.black)
        camera(.perspective(eye: Vector3(0, 0, 8), target: .zero, fieldOfView: .pi / 4))
        if let refocusAtFrame, frameCount >= refocusAtFrame {
            spray.bokeh = Bokeh(focalDistance: 6, strength: 0.05, minSize: 0.02)
        }
        drawLineSpray(spray)
        drawImage(spray.developed(exposure: 40).image, 0, 0)
    }
}

/// The ring of twelve lines, rebuilt every draw: shifted along x by `shift(frame)`,
/// the even ones stretched by `stretch(frame)` (only some, so the shares under
/// length sampling move), then handed to `setLines`. With both at their rest
/// values the lines are the same every frame.
@MainActor
private final class MovingSpraySketch: Sketch {
    var spray: LineSpray!
    var sampling: LineSpray.Sampling = .perLine(200)
    var aperture: Aperture = .round
    var shift: (Int) -> Double = { _ in 0 }
    var stretch: (Int) -> Double = { _ in 1 }
    /// The point table as built in `setup()`, read on the first draw.
    var tableAtFirstDraw: AnyObject?
    /// The particles as the first draw made them, and every total a draw asked for.
    var storeAtFirstDraw: AnyObject?
    var totalsSeen: Set<Int> = []
    override var canvasSize: CanvasSize { .square(96) }

    private func lines(frame: Int) -> [SprayLine] {
        let dx = shift(frame)
        return (0 ..< 12).map { i in
            let a = Double(i) / 12 * .tau
            let s = i % 2 == 0 ? stretch(frame) : 1
            return SprayLine(from: Vector3(cos(a) * 2 + dx, sin(a) * 2, 0),
                             to: Vector3(cos(a + 0.5) * 2 * s + dx, sin(a + 0.5) * 2 * s, 0.5),
                             light: SIMD3(repeating: 0.4))
        }
    }

    override func setup() {
        // The spray takes its per-frame seed from the sketch's own generator,
        // so two renders repeat each other only if that does.
        randomSeed(7)
        spray = makeLineSpray(lines(frame: 0), sampling: sampling, passesPerFrame: 3,
                              bokeh: Bokeh(focalDistance: 8, strength: 0.02, minSize: 0.02,
                                           aperture: aperture))
    }

    override func draw() {
        background(.black)
        camera(.perspective(eye: Vector3(0, 0, 8), target: .zero, fieldOfView: .pi / 4))
        if frameCount == 1 { tableAtFirstDraw = spray.pointTable }
        let now = lines(frame: frameCount - 1)
        spray.setLines(now)
        drawLineSpray(spray)
        if frameCount == 1 { storeAtFirstDraw = spray.particleStore }
        totalsSeen.insert(LineSpray.pointCounts(for: now, sampling: sampling).reduce(0, +))
        drawImage(spray.developed(exposure: 40).image, 0, 0)
    }
}

/// A spray of a ring of lines, a pair of quads, or both, for reading what each
/// contributes to one picture.
private final class QuadSpraySketch: Sketch {
    var spray: LineSpray!
    var wantsLines = true, wantsQuads = true
    override var canvasSize: CanvasSize { .square(96) }

    override func setup() {
        let lines = wantsLines ? (0 ..< 12).map { i -> SprayLine in
            let a = Double(i) / 12 * .tau
            return SprayLine(from: Vector3(cos(a) * 2, sin(a) * 2, 0),
                             to: Vector3(cos(a + 0.5) * 2, sin(a + 0.5) * 2, 0.5),
                             light: SIMD3(repeating: 0.4))
        } : []
        spray = makeLineSpray(lines, sampling: .perLine(200), passesPerFrame: 3,
                              bokeh: Bokeh(focalDistance: 8, strength: 0.02, minSize: 0.02))
        if wantsQuads {
            spray.setQuads([
                SprayQuad(corner: Vector3(-1.5, -1.5, 0), edge1: Vector3(3, 0, 0),
                          edge2: Vector3(0, 3, 0), light: SIMD3(repeating: 0.4)),
                SprayQuad(corner: Vector3(-0.5, -0.5, 0.5), edge1: Vector3(1, 0, 0),
                          edge2: Vector3(0, 1, 0), light: SIMD3(repeating: 0.4)),
            ])
        }
    }

    override func draw() {
        background(.black)
        camera(.perspective(eye: Vector3(0, 0, 8), target: .zero, fieldOfView: .pi / 4))
        drawLineSpray(spray)
        drawImage(spray.developed(exposure: 40).image, 0, 0)
    }
}

/// A single point of light well off the plane of focus, so what lands on the
/// canvas is the shape of the hole it was scattered through. The point is a
/// line whose ends are the same place, which is how a dot is drawn.
private final class AperturePointSketch: Sketch {
    var spray: LineSpray!
    var aperture: Aperture = .round
    var printExposure = 6.0
    override var canvasSize: CanvasSize { .square(96) }

    override func setup() {
        randomSeed(7)
        let dot = Vector3(0, 0, 0)
        spray = makeLineSpray([SprayLine(from: dot, to: dot, light: SIMD3(repeating: 3))],
                              sampling: .perLine(4000), passesPerFrame: 4,
                              bokeh: Bokeh(focalDistance: 2, strength: 0.09, minSize: 0.01,
                                           aperture: aperture))
    }

    override func draw() {
        background(.black)
        camera(.perspective(eye: Vector3(0, 0, 8), target: .zero, fieldOfView: .pi / 4))
        drawLineSpray(spray)
        drawImage(spray.developed(exposure: printExposure).image, 0, 0)
    }
}
