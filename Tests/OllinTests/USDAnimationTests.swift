import CoreGraphics
import Foundation
import simd
@testable import Ollin
import Testing

/// USD transform animation (stage 3 of the USD-native arc): xformOp
/// timeSamples baked into `SceneAnimation` tracks. Pins the timebase
/// (timeCodesPerSecond, its framesPerSecond fallback, the startTimeCode
/// offset), the per-attribute sampling rules (linear componentwise,
/// quaternion slerp, non-lerpable holds), the union-of-times bake across a
/// prim's ops (the pivot idiom included), name-bound track application, the
/// crate container agreeing with text through the system usdcat writer, and
/// the whole path from `Scene(contentsOf:)` through `apply(_:at:)`.
@Suite
@MainActor
struct USDAnimationTests {

    private func stage(_ usda: String) throws -> USDStage {
        try USDStage.load(data: Data(usda.utf8))
    }

    /// Write a usda string to a temp file and load it as a `Scene` (the
    /// platform-importer walk plus the raw-tree lights/animation read).
    private func loadUSDScene(_ usda: String) throws -> Ollin.Scene? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-\(ProcessInfo.processInfo.globallyUniqueString).usda")
        try usda.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return Scene(contentsOf: url)
    }

    // MARK: The timebase

    @Test func timeCodesPerSecondScalesTimeCodesToSeconds() throws {
        let s = try stage("""
        #usda 1.0
        (
            timeCodesPerSecond = 48
        )

        def Xform "mover"
        {
            double3 xformOp:translate.timeSamples = {
                0: (0, 0, 0),
                24: (1, 0, 0),
                48: (4, 0, 0),
            }
            uniform token[] xformOpOrder = ["xformOp:translate"]
        }
        """)
        let (animation, rests) = try #require(Scene.resolveUSDAnimation(s))
        #expect(animation.tracks.count == 1)
        #expect(rests.count == 1 && rests[0].name == "mover")
        let track = animation.tracks[0]
        #expect(track.nodeName == "mover")
        let sampler = try #require(track.translation)
        #expect(sampler.times == [0, 0.5, 1])
        #expect(sampler.values.map(\.x) == [0, 1, 4])
        #expect(animation.duration == 1)
    }

    @Test func startTimeCodeShiftsTheTimelineToZero() throws {
        // The frame-101 opening convention: the animation still starts at 0 s.
        let s = try stage("""
        #usda 1.0
        (
            startTimeCode = 101
            timeCodesPerSecond = 24
        )

        def Xform "mover"
        {
            double3 xformOp:translate.timeSamples = {
                101: (0, 0, 0),
                149: (2, 0, 0),
            }
            uniform token[] xformOpOrder = ["xformOp:translate"]
        }
        """)
        let (animation, _) = try #require(Scene.resolveUSDAnimation(s))
        let sampler = try #require(animation.tracks[0].translation)
        #expect(sampler.times == [0, 2])
        #expect(animation.duration == 2)
    }

    @Test func framesPerSecondIsTheFallbackTimebase() throws {
        let s = try stage("""
        #usda 1.0
        (
            framesPerSecond = 12
        )

        def Xform "mover"
        {
            double3 xformOp:translate.timeSamples = {
                0: (0, 0, 0),
                12: (1, 0, 0),
            }
            uniform token[] xformOpOrder = ["xformOp:translate"]
        }
        """)
        let (animation, _) = try #require(Scene.resolveUSDAnimation(s))
        #expect(animation.tracks[0].translation?.times == [0, 1])
    }

    // MARK: Attribute sampling

    @Test func sampledLerpsTuplesAndClampsOutsideTheRange() throws {
        let s = try stage("""
        #usda 1.0

        def Xform "a"
        {
            double3 xformOp:translate.timeSamples = {
                10: (0, 0, 0),
                20: (4, 8, 0),
            }
            uniform token[] xformOpOrder = ["xformOp:translate"]
        }
        """)
        let attr = try #require(s.prims[0].attribute("xformOp:translate"))
        #expect(attr.sampled(at: 15) == .tuple([2, 4, 0]))
        #expect(attr.sampled(at: 0) == .tuple([0, 0, 0]))
        #expect(attr.sampled(at: 99) == .tuple([4, 8, 0]))
    }

    @Test func quaternionSamplesInterpolateAlongTheArc() throws {
        // 0 deg to 90 deg about y, authored real-first; halfway must be the
        // 45 deg rotation (componentwise lerp would land off the unit arc).
        let s = try stage("""
        #usda 1.0

        def Xform "a"
        {
            quatf xformOp:orient.timeSamples = {
                0: (1, 0, 0, 0),
                10: (0.7071067811865476, 0, 0.7071067811865476, 0),
            }
            uniform token[] xformOpOrder = ["xformOp:orient"]
        }
        """)
        let attr = try #require(s.prims[0].attribute("xformOp:orient"))
        guard case .tuple(let q)? = attr.sampled(at: 5) else {
            Issue.record("expected a quaternion tuple")
            return
        }
        let half = 22.5 * Double.pi / 180
        #expect(abs(q[0] - cos(half)) < 1e-9)
        #expect(abs(q[2] - sin(half)) < 1e-9)
        #expect(abs(q[1]) < 1e-12 && abs(q[3]) < 1e-12)
    }

    @Test func nonLerpableValuesHoldTheEarlierSample() throws {
        let s = try stage("""
        #usda 1.0

        def Xform "a"
        {
            token visibility.timeSamples = {
                0: "inherited",
                10: "invisible",
            }
        }
        """)
        let attr = try #require(s.prims[0].attribute("visibility"))
        #expect(attr.sampled(at: 5) == .token("inherited"))
        #expect(attr.sampled(at: 10) == .token("invisible"))
    }

    // MARK: The bake

    @Test func unionTimesSampleEveryOpAtEveryKey() throws {
        // Translate keyed at 0/48, rotation keyed at 24: the track carries all
        // three times, the translation midpoint interpolated.
        let s = try stage("""
        #usda 1.0

        def Xform "mover"
        {
            double3 xformOp:translate.timeSamples = {
                0: (0, 0, 0),
                48: (4, 0, 0),
            }
            float xformOp:rotateY.timeSamples = {
                24: 90,
            }
            uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:rotateY"]
        }
        """)
        let (animation, _) = try #require(Scene.resolveUSDAnimation(s))
        let track = animation.tracks[0]
        #expect(track.translation?.times == [0, 1, 2])
        #expect(track.translation?.values.map(\.x) == [0, 2, 4])
    }

    @Test func pivotStacksBakeIntoOrbitingTranslationKeys() throws {
        // The pivot idiom: a rotation between a translate:pivot pair orbits
        // the prim about the pivot, so the baked *translation* moves.
        let s = try stage("""
        #usda 1.0

        def Xform "swing"
        {
            double3 xformOp:translate:pivot = (1, 0, 0)
            float xformOp:rotateY.timeSamples = {
                0: 0,
                24: 180,
            }
            uniform token[] xformOpOrder = ["xformOp:translate:pivot", "xformOp:rotateY", "!invert!xformOp:translate:pivot"]
        }
        """)
        let (animation, rests) = try #require(Scene.resolveUSDAnimation(s))
        let track = animation.tracks[0]
        let t = try #require(track.translation)
        #expect(simd_length(t.values[0] - SIMD4<Float>(0, 0, 0, 0)) < 1e-6)
        #expect(simd_length(t.values[1] - SIMD4<Float>(2, 0, 0, 0)) < 1e-5)
        let r = try #require(track.rotation)
        #expect(abs(r.values[1].y) > 0.9999)   // the half-turn about y
        // The rest pose is the stack at rest: the identity here.
        #expect(simd_length(rests[0].pose.t) < 1e-6)
    }

    @Test func consecutiveQuaternionKeysStayOnOneHemisphere() throws {
        // A full turn in 90 deg steps crosses the double cover; baked
        // neighbors must never sit antipodal or the slerp would backtrack.
        let s = try stage("""
        #usda 1.0

        def Xform "spinner"
        {
            float xformOp:rotateY.timeSamples = {
                0: 0,
                6: 90,
                12: 180,
                18: 270,
                24: 360,
            }
            uniform token[] xformOpOrder = ["xformOp:rotateY"]
        }
        """)
        let (animation, _) = try #require(Scene.resolveUSDAnimation(s))
        let r = try #require(animation.tracks[0].rotation)
        for k in 1..<r.values.count {
            #expect(simd_dot(r.values[k - 1], r.values[k]) > -1e-6)
        }
    }

    @Test func aStageWithoutSamplesCarriesNoAnimation() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // OllinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Examples/3D/Geometry/USDScene/stage.usda")
        let s = try USDStage.load(contentsOf: url)
        #expect(Scene.resolveUSDAnimation(s) == nil)
    }

    // MARK: Application

    @Test func usdSceneAnimatesThroughApply() throws {
        // The whole path: Scene(contentsOf:) picks up the animation, apply
        // poses the named node on the sketch clock. 0..180 deg about y over
        // 2 s; at 0.5 s the sampler slerps a quarter of the arc, 45 deg.
        let scene = try #require(try loadUSDScene("""
        #usda 1.0
        (
            defaultPrim = "Root"
            timeCodesPerSecond = 24
        )

        def Xform "Root"
        {
            def Xform "spinner"
            {
                double3 xformOp:translate = (0, 2, 0)
                float3 xformOp:rotateXYZ.timeSamples = {
                    0: (0, 0, 0),
                    48: (0, 180, 0),
                }
                uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:rotateXYZ"]
            }
        }
        """))
        var posed = scene
        let animation = try #require(scene.animations.first)
        #expect(animation.duration == 2)

        posed.apply(animation, at: 0.5)
        let node = try #require(posed.node("spinner"))
        let m = node.localTransform
        let x = SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z)
        let expected = SIMD3<Float>(cos(.pi / 4), 0, -sin(.pi / 4))
        #expect(simd_length(x - expected) < 1e-4)
        // The un-animated translate op still holds through the baked base.
        #expect(abs(m.columns.3.y - 2) < 1e-5)

        // Absolute, not additive: the same time twice is the same pose.
        posed.apply(animation, at: 0.5)
        #expect(posed.node("spinner")?.localTransform == m)
    }

    @Test func tracksBindTheFirstNodeOfTheirNameDepthFirst() throws {
        // Two prims named "arm" in different branches: the track (and its
        // rest pose) lands on the first match, the subscript's rule.
        let scene = try #require(try loadUSDScene("""
        #usda 1.0
        (
            defaultPrim = "Root"
        )

        def Xform "Root"
        {
            def Xform "left"
            {
                def Xform "arm"
                {
                    double3 xformOp:translate.timeSamples = {
                        0: (0, 0, 0),
                        24: (0, 3, 0),
                    }
                    uniform token[] xformOpOrder = ["xformOp:translate"]
                }
            }

            def Xform "right"
            {
                def Xform "arm"
                {
                }
            }
        }
        """))
        var posed = scene
        let animation = try #require(scene.animations.first)
        posed.apply(animation, at: animation.duration)
        let left = posed.node("left")?.children.first
        let right = posed.node("right")?.children.first
        #expect(abs((left?.localTransform.columns.3.y ?? 0) - 3) < 1e-5)
        #expect(abs(right?.localTransform.columns.3.y ?? 0) < 1e-6)
    }

    // MARK: The loop wrap

    /// The committed mobile asset wraps seamlessly: frames one authored lap
    /// apart sample the same animation time and must render byte-identically
    /// (apply is absolute, and nothing else in the probe reads the clock).
    @Test(.enabled(if: Snapshot.hasMetal))
    func exampleAssetWrapsByteIdentically() throws {
        let before = try #require(OllinApp.image(of: USDMobileWrapProbe(), frame: 5))
        let after = try #require(OllinApp.image(of: USDMobileWrapProbe(), frame: 21))
        #expect(rgba(before) == rgba(after))
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: space, bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return data
    }

    // MARK: The crate container

    /// The same animation authored as text and converted to crate by the
    /// system usdcat must bake to identical tracks, which exercises the crate
    /// TimeSamples decode (the doubly-indirected layout) against a reference
    /// writer's real output.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/usdcat")))
    func crateAgreesWithTextOnAnimation() throws {
        let usda = """
        #usda 1.0
        (
            defaultPrim = "Root"
            startTimeCode = 0
            endTimeCode = 48
            timeCodesPerSecond = 24
        )

        def Xform "Root"
        {
            def Xform "swing"
            {
                double3 xformOp:translate:pivot = (1.5, 0, 0)
                float3 xformOp:rotateXYZ.timeSamples = {
                    0: (0, 0, 0),
                    24: (0, 120, 0),
                    48: (0, 240, 15),
                }
                uniform token[] xformOpOrder = ["xformOp:translate:pivot", "xformOp:rotateXYZ", "!invert!xformOp:translate:pivot"]
            }

            def Xform "bob"
            {
                double3 xformOp:translate.timeSamples = {
                    0: (0, 0.5, 0),
                    12: (0, 1.25, 0),
                    48: (0, 0.5, 0),
                }
                float xformOp:scaleX = 2
                uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:scaleX"]
            }
        }
        """
        let dir = FileManager.default.temporaryDirectory
        let stem = "ollin-\(ProcessInfo.processInfo.globallyUniqueString)"
        let textURL = dir.appendingPathComponent(stem + ".usda")
        let crateURL = dir.appendingPathComponent(stem + ".usdc")
        try usda.write(to: textURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: textURL)
            try? FileManager.default.removeItem(at: crateURL)
        }
        let convert = Process()
        convert.executableURL = URL(fileURLWithPath: "/usr/bin/usdcat")
        convert.arguments = [textURL.path, "-o", crateURL.path]
        try convert.run()
        convert.waitUntilExit()
        try #require(convert.terminationStatus == 0)

        let textStage = try USDStage.load(contentsOf: textURL)
        let crateStage = try USDStage.load(contentsOf: crateURL)
        let fromText = try #require(Scene.resolveUSDAnimation(textStage))
        let fromCrate = try #require(Scene.resolveUSDAnimation(crateStage))

        #expect(fromText.animation.duration == fromCrate.animation.duration)
        #expect(fromText.animation.tracks.count == fromCrate.animation.tracks.count)
        for (a, b) in zip(fromText.animation.tracks, fromCrate.animation.tracks) {
            #expect(a.nodeName == b.nodeName)
            #expect(a.translation?.times == b.translation?.times)
            #expect(a.translation?.values == b.translation?.values)
            #expect(a.rotation?.values == b.rotation?.values)
            #expect(a.scale?.values == b.scale?.values)
        }
    }
}

/// The wrap probe: the committed mobile asset applied at half-second steps
/// wrapped over its 8-second lap, so frame 5 (2.0 s) and frame 21 (10.0 s,
/// wrapped to 2.0 s) must pose, and render, identically. Frame-count-driven so
/// the sample times are exact.
private final class USDMobileWrapProbe: Sketch {
    override var canvasSize: CanvasSize { .square(192) }
    private var mobile: Ollin.Scene!

    override func setup() {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // OllinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Examples/3D/Geometry/USDAnimatedScene/stage.usda")
        mobile = Ollin.Scene(contentsOf: url)
    }

    override func draw() {
        background(Color(white: 0.05))
        camera(mobile.camera ?? .orbiting(target: Vector3(0, 1.6, 0), radius: 7))
        ambientLight(Color(white: 0.2))
        for l in mobile.lights { light(l) }
        if let lap = mobile.animations.first {
            let t = Double(frameCount - 1) * 0.5
            mobile.apply(lap, at: t.truncatingRemainder(dividingBy: lap.duration))
        }
        fill(.white)
        drawScene(mobile)
    }
}
