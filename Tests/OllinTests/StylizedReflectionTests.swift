@testable import Ollin
import CoreGraphics
import Foundation
import simd
import Testing

/// Behavioral probes for a stylized finish seen in a ray-traced reflection.
///
/// A reflection shades the surface it finds, and that shade is the physically-based one,
/// so a surface whose look comes from a stylized shading model or from a
/// light-independent layer needs its finish carried to the hit. Without it a cel-shaded
/// sphere reflects with no bands, a Gooch one with no warm-cool ramp, a velvet one with
/// no rim, a waxy one with no glow.
///
/// Each probe is a counterfactual pair against *the same material minus its stylized
/// part*, since that is the only reading that separates "the finish reached the trace"
/// from "this material is simply darker". A plain standard control is not enough: every
/// non-physically-based batch bakes a roughness of its own, which moves the mirrored
/// image on its own account, and a matched control holds that still.
///
/// The measured band lies below the horizon, where the floor holds the sphere's
/// mirrored image, and it has to clear the sphere's own raster pixels *entirely* or a
/// reading picks up how the finish shades head on instead. A difference map against the
/// control is what finds where the body ends. RT-gated: without ray tracing there is no
/// traced reflection to read.
@Suite
@MainActor
struct StylizedReflectionTests {

    /// What the mirrored image of the sphere reads as, over the band of floor that
    /// holds it: mean luminance, mean red-minus-blue and green-minus-red for the tone
    /// probes, and how many neighboring pixels along a scan line step by 6 or more,
    /// which is what cel banding puts there and a smooth ramp does not.
    private struct Reading {
        var luminance = 0.0, redMinusBlue = 0.0, greenMinusRed = 0.0
        var steps = 0
    }

    private func mirrored(_ finish: StylizedReflectionProbe.Finish) throws -> Reading {
        let scene = StylizedReflectionProbe.make(finish)
        let image = try #require(OllinApp.image(of: scene, frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var r = Reading()
        var count = 0.0
        for y in (h * 60 / 100)..<(h * 88 / 100) {
            var previous = -1
            for x in (w * 40 / 100)..<(w * 56 / 100) {
                let i = (y * w + x) * 4
                let red = Int(data[i]), green = Int(data[i + 1]), blue = Int(data[i + 2])
                let l = (red * 30 + green * 59 + blue * 11) / 100
                r.luminance += Double(l)
                r.redMinusBlue += Double(red - blue)
                r.greenMinusRed += Double(green - red)
                count += 1
                if previous >= 0, abs(l - previous) >= 6 { r.steps += 1 }
                previous = l
            }
        }
        r.luminance /= count
        r.redMinusBlue /= count
        r.greenMinusRed /= count
        return r
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func theMirrorHoldsTheSphereAtAll() throws {
        // The control that gives every test below its teeth: the band must read the
        // sphere's mirrored body, and taking the sphere away must clear it.
        let there = try mirrored(.standard)
        let gone = try mirrored(.nothing)
        #expect(gone.luminance - there.luminance > 20,
                """
                expected the mirrored sphere to darken its band of floor: \
                with \(there.luminance), without \(gone.luminance)
                """)
        #expect(gone.steps < 5,
                "expected an empty mirror to hold no banding: it stepped \(gone.steps) times")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aToonSurfaceKeepsItsBandsInAMirror() throws {
        // Cel shading is a staircase, so its mirrored image steps where the standard
        // finish's ramps. Counting the steps reads the banding itself rather than the
        // brightness it happens to land on.
        let toon = try mirrored(.toon)
        let control = try mirrored(.toonControl)
        #expect(toon.steps > control.steps * 2,
                """
                expected cel bands in the mirrored image: toon stepped \(toon.steps) times, \
                the same body shaded as standard \(control.steps)
                """)
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aGoochSurfaceKeepsItsToneRampInAMirror() throws {
        // The Gooch ramp replaces the diffuse *and* the ambient, so its mirrored image
        // turns warm where the standard one stays near neutral under this environment.
        let gooch = try mirrored(.gooch)
        let control = try mirrored(.goochControl)
        #expect(gooch.redMinusBlue - control.redMinusBlue > 8,
                """
                expected the warm-cool ramp in the mirrored image: Gooch read \
                \(gooch.redMinusBlue) red over blue, the same body shaded as standard \
                \(control.redMinusBlue)
                """)
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aRimGlowReachesTheMirror() throws {
        // The rim is a Fresnel layer over any model, and a reflection has its own view
        // direction, so the green rim has to show up in the mirrored silhouette.
        let rim = try mirrored(.rim)
        let control = try mirrored(.rimControl)
        #expect(rim.greenMinusRed - control.greenMinusRed > 10,
                """
                expected the green rim in the mirrored image: rimmed read \
                \(rim.greenMinusRed) green over red, the same body without it \
                \(control.greenMinusRed)
                """)
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aSubsurfaceBleedReachesTheMirror() throws {
        // The wrap term needs a light traveling the way the reflected ray does, so this
        // pair carries its own second light and the control wears the same lights with
        // no subsurface at all.
        let glow = try mirrored(.glow)
        let control = try mirrored(.glowControl)
        #expect(control.redMinusBlue - glow.redMinusBlue > 15,
                """
                expected the blue bleed in the mirrored image: glowing read \
                \(glow.redMinusBlue) red over blue, the same body without it \(control.redMinusBlue)
                """)
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aClearCoatReachesTheMirror() throws {
        // The coat is a polished film over the body, so what it adds to a black lacquer
        // is a reflection of the room. Its pair stands over a dark body, where a coat
        // reads, and the control is the same dielectric with no film on it.
        let coated = try mirrored(.coat)
        let control = try mirrored(.coatControl)
        #expect(coated.luminance - control.luminance > 2.5,
                """
                expected the coat's own reflection in the mirrored image: coated read \
                \(coated.luminance), the same body bare \(control.luminance)
                """)
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aSheenLobeReachesTheMirror() throws {
        // Sheen is fabric fuzz catching the room at the silhouette. A green tint over a
        // dark body makes it a channel reading rather than a brightness one.
        let sheened = try mirrored(.sheen)
        let control = try mirrored(.sheenControl)
        #expect(sheened.greenMinusRed - control.greenMinusRed > 4,
                """
                expected the green sheen in the mirrored image: sheened read \
                \(sheened.greenMinusRed) green over red, the same body bare \
                \(control.greenMinusRed)
                """)
    }
}

/// A sphere over a near-mirror floor, wearing one finish at a time. The camera looks
/// down far enough that the floor holds the whole mirrored body below the horizon,
/// where no pixel of the sphere's own raster image can reach.
private final class StylizedReflectionProbe: Sketch {
    /// Each stylized case is paired with the same material minus the stylized part, so
    /// a reading attributes to the finish rather than to the roughness a batch bakes
    /// from its specularSharpness, which every non-physically-based material also carries.
    enum Finish {
        case standard, nothing
        case toon, toonControl
        case gooch, goochControl
        case rim, rimControl
        case glow, glowControl
        case coat, coatControl
        case sheen, sheenControl
    }
    var finish: Finish = .standard

    static func make(_ finish: Finish) -> StylizedReflectionProbe {
        let probe = StylizedReflectionProbe()
        probe.finish = finish
        return probe
    }

    override var canvasSize: CanvasSize { .square(320) }

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 0.9, 0), radius: 8, azimuth: 0.0, elevation: 0.34))
        environment(.night)
        directionalLight(.white, direction: Vector3(-0.7, -0.5, -0.45), intensity: 1.2)
        // The subsurface pair needs a light that travels the way the reflected ray does,
        // since the wrap term is what a body passes through from behind.
        if finish == .glow || finish == .glowControl {
            directionalLight(.white, direction: Vector3(0.05, -1, 0.05), intensity: 1.4)
        }
        rayTracedReflections()
        withState {
            fill(Color(white: 0.9))
            material(.metal(roughness: 0.03))
            drawPlane(width: 18, depth: 14)
        }
        guard finish != .nothing else { return }
        withState {
            translate(0, 1.6, 0)
            // The layered lobes read against a *dark* body, the way a lacquered or a
            // felted surface does in life: the coat's polished film and the sheen's fuzz
            // are what a black base shows, where a pale one hides both under its own
            // diffuse. Every other case keeps the pale body its own probe wants.
            switch finish {
            case .coat, .coatControl, .sheen, .sheenControl: fill(Color(white: 0.05))
            default: fill(Color(white: 0.85))
            }
            switch finish {
            case .standard: material(.matte)
            case .toon: material(.toon)
            case .toonControl: material(Material(specular: 0.4, specularSharpness: 64))
            case .gooch: material(.gooch)
            case .goochControl: material(Material(specular: 0.25, specularSharpness: 48))
            case .rim: material(Material(specular: 0.08, specularSharpness: 20, rim: 1.0,
                                         rimSharpness: 2.2,
                                         rimColor: Color(red: 0.1, green: 1.0, blue: 0.1)))
            case .rimControl: material(Material(specular: 0.08, specularSharpness: 20))
            case .glow: material(Material(specular: 0.2, specularSharpness: 24, subsurface: 1.0,
                                          subsurfaceColor: Color(red: 0.1, green: 0.3, blue: 1.0)))
            case .glowControl: material(Material(specular: 0.2, specularSharpness: 24))
            case .coat: material(Material(shading: .physicallyBased, metallic: 0,
                                          roughness: 0.55, clearcoat: 1,
                                          clearcoatRoughness: 0.03))
            case .coatControl: material(Material(shading: .physicallyBased, metallic: 0,
                                                 roughness: 0.55))
            case .sheen: material(Material(shading: .physicallyBased, metallic: 0,
                                           roughness: 0.8, sheen: 1,
                                           sheenColor: Color(red: 0.1, green: 1.0, blue: 0.1),
                                           sheenRoughness: 0.25))
            case .sheenControl: material(Material(shading: .physicallyBased, metallic: 0,
                                                  roughness: 0.8))
            case .nothing: break
            }
            drawSphere(radius: 1.4)
        }
    }
}
