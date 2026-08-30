@testable import Ollin
import CoreGraphics
import Foundation
import Testing

/// Behavioral probes for `glossyReflections()`, the traced reflection's lobe.
///
/// One traced ray describes a mirror exactly and describes nothing else. Left alone, a
/// rough surface is served by fading that one ray into the prefiltered environment, so a
/// satin floor standing in a red room shows a gray sky. With the lobe on, each ray leaves
/// along a microfacet drawn from the surface's own distribution and every pixel gathers
/// the rays its neighbors sent, so what the floor shows is the room, blurred by exactly as
/// much as the floor is rough.
///
/// Every reading is a counterfactual against the same scene with the lobe off, since that
/// is the only comparison that separates "the room reached the floor" from "this floor is
/// simply brighter". The band read is a strip of floor in front of the wall, which the
/// wall's own raster never touches. RT-gated: without ray tracing there is no traced
/// reflection to spread.
@Suite
@MainActor
struct GlossyReflectionTests {

    /// What the strip of floor reads as: its mean red-minus-blue (the red wall's color
    /// arriving, which the gray environment cannot supply), its mean luminance, and its
    /// grain, the mean distance from a 3x3 median. Grain is how speckle shows up in a
    /// number: a stray ray hundreds of times brighter than the one beside it moves no mean
    /// worth reading but stands far off its own neighborhood.
    private struct Reading {
        var redMinusBlue = 0.0, luminance = 0.0, grain = 0.0, sharpness = 0.0
    }

    private func floorStrip(gloss: Bool, roughness: Double) throws -> Reading {
        let scene = GlossyProbe.make(gloss: gloss, roughness: roughness)
        let image = try #require(OllinApp.image(of: scene, frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let luma = { (x: Int, y: Int) -> Double in
            let i = (y * w + x) * 4
            return (Double(data[i]) * 30 + Double(data[i + 1]) * 59 + Double(data[i + 2]) * 11) / 100
        }
        var r = Reading()
        var count = 0.0
        for y in (h * 62 / 100)..<(h * 92 / 100) {
            for x in (w * 8 / 100)..<(w * 92 / 100) {
                let i = (y * w + x) * 4
                r.redMinusBlue += Double(data[i]) - Double(data[i + 2])
                r.luminance += luma(x, y)
                // The 3x3 median this pixel is measured against, which every pixel in the
                // band has room for.
                var window = [Double]()
                for dy in -1...1 { for dx in -1...1 { window.append(luma(x + dx, y + dy)) } }
                window.sort()
                r.grain += abs(luma(x, y) - window[4])
                // How fast the strip changes down the screen. A lobe blurs what the floor
                // shows, so the same picture arrives with gentler slopes.
                r.sharpness += abs(luma(x, y + 1) - luma(x, y - 1))
                count += 1
            }
        }
        r.redMinusBlue /= count
        r.luminance /= count
        r.grain /= count
        r.sharpness /= count
        return r
    }

    /// The control that gives the rest their teeth: with the lobe on, the floor has to
    /// show the room. The red wall's color is the reading, because the environment around
    /// the scene is gray and cannot supply it: whatever red arrives on that floor came off
    /// the wall by way of a traced ray. The mirror path fades most of it away at this
    /// roughness, which is the shortcoming the lobe is here to fix. Verified red by giving
    /// the glossy composite the mirror path's own early fade back.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func theRoomReachesTheFloor() throws {
        let lobe = try floorStrip(gloss: true, roughness: 0.34)
        let mirrorRay = try floorStrip(gloss: false, roughness: 0.34)
        #expect(lobe.redMinusBlue > 6 && lobe.redMinusBlue > mirrorRay.redMinusBlue * 1.5,
                """
                expected the satin floor to take the red wall's color: with the lobe \
                \(lobe.redMinusBlue), without \(mirrorRay.redMinusBlue)
                """)
    }

    /// The lobe itself, separated from everything else the setting changes. A rough
    /// surface cannot hold a sharp image, so the same room has to arrive on it with
    /// gentler slopes: the strip's own rate of change down the screen drops by a third.
    /// Nothing but the spread can do that, since a single ray traced from the same point
    /// carries the same picture at full sharpness however it is later blended. Verified
    /// red by keeping the mirror direction in place of the drawn microfacet.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aRoughSurfaceBlursWhatItShows() throws {
        let lobe = try floorStrip(gloss: true, roughness: 0.34)
        let mirrorRay = try floorStrip(gloss: false, roughness: 0.34)
        #expect(lobe.sharpness < mirrorRay.sharpness * 0.8,
                """
                expected the satin floor's image to arrive blurred: with the lobe \
                \(lobe.sharpness), with one mirror ray \(mirrorRay.sharpness)
                """)
    }

    /// A mirror was never the problem. Its lobe is one direction wide, so the drawn
    /// microfacet is the surface normal and the traced ray is the same ray either way; the
    /// resolve then gives a neighbor's off-lobe ray a weight near zero and the pixel keeps
    /// its own. Nothing here is arranged to make that happen: it falls out of the weight.
    /// Verified red by spreading every surface as though it were rough.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aMirrorReadsTheSameEitherWay() throws {
        let lobe = try floorStrip(gloss: true, roughness: 0.03)
        let mirrorRay = try floorStrip(gloss: false, roughness: 0.03)
        #expect(abs(lobe.luminance - mirrorRay.luminance) < 2,
                """
                expected a near-mirror floor to read the same with the lobe as without: \
                \(lobe.luminance) against \(mirrorRay.luminance)
                """)
    }

    /// Past the ceiling the lobe is wide enough that the prefiltered environment is the
    /// honest answer, so Ollin hands back to it and the two paths meet again. Without that
    /// hand-back a very rough surface would step visibly at the ceiling. Two things keep
    /// the promise, so both have to go before this reads: the G-buffer stops marking a
    /// surface past the ceiling as worth a ray, and the composite fades to the environment
    /// as it approaches one. Verified red with both taken out together.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func pastTheCeilingTheEnvironmentTakesOver() throws {
        let lobe = try floorStrip(gloss: true, roughness: 0.92)
        let mirrorRay = try floorStrip(gloss: false, roughness: 0.92)
        #expect(abs(lobe.luminance - mirrorRay.luminance) < 2,
                """
                expected a floor rougher than the glossy ceiling to read the same either \
                way: \(lobe.luminance) against \(mirrorRay.luminance)
                """)
    }

    /// The speckle test, and the reason the trace widens every surface along the chain to
    /// the cone that reached it. The probe is the unkind case: a satin floor whose rays
    /// land on a near-mirror ball, whose own reflection is a pinpoint light. Without the
    /// rule one ray in a hundred comes back many times brighter than the ray beside it and
    /// the floor crawls with white dots; the grain over this strip runs about 1.5 without
    /// it and about 0.8 with it, against 0.4 for the mirror path on the same frame.
    /// Verified red by handing the trace a cone of no width, which is what the surfaces
    /// along the chain are widened to.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func theFloorsImageIsQuiet() throws {
        let lobe = try floorStrip(gloss: true, roughness: 0.34)
        // The floor must still be showing something, or an empty layer would pass this on
        // its own: nothing is the quietest picture there is.
        #expect(lobe.luminance > 40,
                "expected the strip to be lit floor at all, luminance \(lobe.luminance)")
        #expect(lobe.grain < 0.8,
                "expected the resolved floor to be free of speckle, grain \(lobe.grain)")
    }

    /// Off unless asked for, and persistent once asked (a quality setting, like the bounce
    /// count beside it, not per-frame state like the lights).
    @Test
    func theSettingIsOffUntilAskedFor() {
        let sketch = Sketch()
        #expect(sketch.drawer.glossyReflectionsEnabled == false)
        sketch.glossyReflections()
        #expect(sketch.drawer.glossyReflectionsEnabled)
        sketch.glossyReflections(false)
        #expect(sketch.drawer.glossyReflectionsEnabled == false)
    }
}

/// A satin floor between a red wall and a near-mirror ball, seen from low down so the
/// floor fills the lower half. The wall is matte, so it reflects nothing itself and is
/// only there to be seen; the ball is the speckle's source. Fixed camera, no time.
private final class GlossyProbe: Sketch {
    var gloss = false
    var roughness = 0.34

    static func make(gloss: Bool, roughness: Double) -> GlossyProbe {
        let probe = GlossyProbe()
        probe.gloss = gloss
        probe.roughness = roughness
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x0b0d11))
        camera(.orbiting(target: Vector3(0, 0.6, 0), radius: 7.2,
                         azimuth: 0.2, elevation: 0.22,
                         fieldOfView: .pi / 4, near: 1, far: 30))
        environment(.studio.intensified(to: 1.0))
        directionalLight(.white, direction: Vector3(-0.35, -1, -0.3), intensity: 0.8)
        rayTracedReflections()
        if gloss { glossyReflections() }

        withState {
            material(.metal(roughness: roughness))
            fill(Color(hex: 0x9298a2))
            translate(0, -0.4, 0)
            drawBox(width: 24, height: 0.8, depth: 24)
        }
        withState {
            material(.matte)
            fill(Color(red: 0.86, green: 0.24, blue: 0.14))
            translate(0, 2.0, -4.2)
            drawBox(width: 9, height: 4.0, depth: 0.4)
        }
        withState {
            material(.metal(roughness: 0.03))
            fill(Color(hex: 0xd6dae2))
            translate(0, 0.9, -1.0)
            drawSphere(radius: 0.9)
        }
    }
}
