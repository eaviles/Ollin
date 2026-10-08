@testable import Ollin
import Testing
import CoreGraphics

/// A traced shadow under an export's temporal anti-aliasing. The export draws
/// the scene once per jitter offset (sixteen passes at the `.detail` tier it
/// lands on) and averages them, so each pass traces its share of one set of
/// points on the light instead of the whole set again: the passes together
/// trace every point once, and a frame costs the set rather than the set times
/// the passes.
///
/// Nothing here diffs a committed image. Each probe compares two renders of
/// the same scene, so it reads the same on any GPU that traces.
@Suite(.serialized)
@MainActor
struct TracedShadowPassTests {

    enum Lamp: Hashable { case point, rectangle, disk }

    struct Setting: Hashable {
        var lamp: Lamp
        var temporal: Bool
        var rays: Int?
        var shadows = true
    }

    private static var renders: [Setting: [UInt8]] = [:]

    private func render(_ setting: Setting) throws -> [UInt8] {
        if let known = Self.renders[setting] { return known }
        let sketch = PenumbraSet()
        sketch.setting = setting
        let bytes = pixels(of: try OllinApp.image(of: sketch, frame: 0))
        Self.renders[setting] = bytes
        return bytes
    }

    private func luminance(_ d: [UInt8], _ i: Int) -> Double {
        0.2126 * Double(d[i * 4]) + 0.7152 * Double(d[i * 4 + 1]) + 0.0722 * Double(d[i * 4 + 2])
    }

    /// The penumbra: floor the lamp lights that a render of the whole set darkens
    /// part of the way, neither lit nor fully in shadow.
    private func penumbra(of shadowed: [UInt8], lit: [UInt8]) -> [Int] {
        (0..<(lit.count / 4)).filter { i in
            let a = luminance(lit, i), s = luminance(shadowed, i)
            return a > 40 && s < 0.92 * a && s > 0.15 * a + 8
        }
    }

    /// The passes share one set and trace all of it: under temporal AA the
    /// penumbra reads what the same set traced whole in one pass reads, within
    /// the sub-pixel jitter's own change. Measured on an M2: 1.2 to 2.2 levels
    /// shared, 0.9 to 1.6 with every pass tracing the whole set, and 41 to 88
    /// with every pass tracing the same share, where the set collapses to a few
    /// points on the light and the soft edge goes hard.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing),
          arguments: [Lamp.point, .rectangle, .disk])
    func theSharedPassesTraceTheWholeSet(lamp: Lamp) throws {
        let lit = try render(Setting(lamp: lamp, temporal: false, rays: 16, shadows: false))
        let whole = try render(Setting(lamp: lamp, temporal: false, rays: 16))
        let shared = try render(Setting(lamp: lamp, temporal: true, rays: 16))
        let band = penumbra(of: whole, lit: lit)
        #expect(band.count > 2000, "\(band.count) penumbra pixels")
        let gap = band.map { abs(luminance(shared, $0) - luminance(whole, $0)) }.reduce(0, +)
            / Double(max(1, band.count))
        #expect(gap < 4, "the shared passes' penumbra is \(gap) levels off the whole set's")
        let sharedBand = penumbra(of: shared, lit: lit)
        #expect(abs(Double(sharedBand.count) / Double(band.count) - 1) < 0.1,
                "\(sharedBand.count) penumbra pixels shared against \(band.count) whole")
    }

    /// A pass never traces fewer than one ray, and the set is the budget shared
    /// out: under the sixteen passes, a budget of one ray and a budget of
    /// sixteen trace the same sixteen points, one a pass, and draw the same frame.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func eachPassTracesItsShareOfTheBudget() throws {
        let one = try render(Setting(lamp: .point, temporal: true, rays: 1))
        let sixteen = try render(Setting(lamp: .point, temporal: true, rays: 16))
        #expect(one == sixteen)
        let thirtyTwo = try render(Setting(lamp: .point, temporal: true, rays: 32))
        #expect(thirtyTwo != sixteen)
    }
}

/// A floor under a hovering slab and a ball, lit by one lamp wide enough to
/// throw a broad penumbra, seen from above.
private final class PenumbraSet: Sketch {
    var setting = TracedShadowPassTests.Setting(lamp: .point, temporal: false, rays: nil)
    override var canvasSize: CanvasSize { .size(320, 240) }

    override func draw() {
        background(.black)
        ambientLight(Color(white: 0.05))
        let at = Vector3(0.4, 4.2, 0.3)
        switch setting.lamp {
        case .point:
            // Low over the pieces, so its traced radius throws a penumbra many
            // pixels wide.
            pointLight(.white, at: Vector3(0.2, 2.6, 0.3), intensity: 0.5)
        case .rectangle:
            rectangleLight(.white, at: at, direction: Vector3(0, -1, 0), width: 1.6, height: 1.0,
                           up: .unitZ, intensity: 40)
        case .disk:
            diskLight(.white, at: at, direction: Vector3(0, -1, 0), radius: 0.8, intensity: 40)
        }
        if setting.shadows {
            castShadows()
            shadowSoftness(1)
            if let rays = setting.rays { shadowSamples(rays) }
        }
        if setting.temporal { temporalAntialiasing() }
        camera(Camera3D(eye: Vector3(0, 5.5, 3.5), target: Vector3(0, 0, 0.2),
                        projection: .perspective(fieldOfView: .pi / 4)))
        withState { fill(Color(white: 0.8)); drawPlane(width: 14, depth: 14) }
        withState { translate(-0.6, 1.3, 0); fill(Color(white: 0.6)); drawBox(width: 1.4, height: 0.2, depth: 0.9) }
        withState { translate(1.0, 0.9, 0.5); fill(Color(white: 0.6)); drawSphere(radius: 0.45) }
    }
}
