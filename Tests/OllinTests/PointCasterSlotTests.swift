@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// A point light casts from any caster slot, not only as the frame's primary caster.
///
/// The renderer reaches that two ways, and these probes run on both: a ray-tracing GPU
/// traces every point caster against the frame's one acceleration structure, and every
/// other GPU renders each one into its own cube of the cube-map array. Run the suite with
/// `OLLIN_NO_RAY_TRACING=1` to read the second path on a GPU that would otherwise trace.
///
/// Nothing here diffs a committed image. Each probe renders the same scene twice, once
/// with the caster and once without it, and reads the floor where that light's shadow
/// belongs: a light that throws nothing leaves the two renders equal, which is exactly
/// what the old behavior did with a point light in any slot but the first.
@Suite(.serialized)
@MainActor
struct PointCasterSlotTests {

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// Mean red over a fractional box of the frame (top-left origin).
    private func mean(_ image: CGImage, x: ClosedRange<Double>, y: ClosedRange<Double>) -> Double {
        let d = pixels(of: image)
        let w = image.width, h = image.height
        var sum = 0, count = 0
        for py in Int(Double(h) * y.lowerBound)..<Int(Double(h) * y.upperBound) {
            for px in Int(Double(w) * x.lowerBound)..<Int(Double(w) * x.upperBound) {
                sum += Int(d[(py * w + px) * 4]); count += 1
            }
        }
        return Double(sum) / Double(max(count, 1))
    }

    /// The right-hand band of floor, where the light standing to the left throws the box.
    private let right = (x: 0.60...0.68, y: 0.46...0.54)
    /// The lower band, where the light standing beyond the box throws it toward the camera.
    private let lower = (x: 0.46...0.54, y: 0.60...0.68)

    @Test(.enabled(if: Snapshot.hasMetal))
    func aPointLightBesideTheKeyThrowsItsShadow() throws {
        // A directional key straight down takes slot 0 (the caster priority puts it there),
        // which leaves the point light standing to the left in slot 1. Its shadow of the
        // box belongs on the right-hand band of floor. Before a point light could cast from
        // any slot, that light lit the scene and threw nothing, so the band read the same
        // with the box as without it.
        let withBox = try #require(OllinApp.image(of: PointSlotScene.make(.keyAndPoint, box: true), frame: 1))
        let without = try #require(OllinApp.image(of: PointSlotScene.make(.keyAndPoint, box: false), frame: 1))
        let shadowed = mean(withBox, x: right.x, y: right.y)
        let lit = mean(without, x: right.x, y: right.y)
        #expect(lit - shadowed > 25,
                "the point light beside the key throws nothing: the band reads \(shadowed) with the box, \(lit) without it")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func everyPointLightThrowsItsOwnShadow() throws {
        // Two point lights, one to the left and one beyond the box, so each throws the box
        // its own way: the first onto the right-hand band, the second onto the lower one.
        // On a ray-tracing GPU both trace; elsewhere they hold a cube of the array each.
        let withBox = try #require(OllinApp.image(of: PointSlotScene.make(.twoPoints, box: true), frame: 1))
        let without = try #require(OllinApp.image(of: PointSlotScene.make(.twoPoints, box: false), frame: 1))
        let firstShadow = mean(withBox, x: right.x, y: right.y)
        let firstLit = mean(without, x: right.x, y: right.y)
        let secondShadow = mean(withBox, x: lower.x, y: lower.y)
        let secondLit = mean(without, x: lower.x, y: lower.y)
        #expect(firstLit - firstShadow > 25,
                "the first point light throws nothing: \(firstShadow) with the box, \(firstLit) without it")
        #expect(secondLit - secondShadow > 25,
                "the second point light throws nothing: \(secondShadow) with the box, \(secondLit) without it")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theKeyKeepsItsOwnShadowBesideThem() throws {
        // The extra caster must not cost slot 0 its own map: the key comes in low from the
        // left instead, so it throws the box onto the right-hand band by itself.
        let withBox = try #require(OllinApp.image(of: PointSlotScene.make(.lowKeyAndPoint, box: true), frame: 1))
        let without = try #require(OllinApp.image(of: PointSlotScene.make(.lowKeyAndPoint, box: false), frame: 1))
        let shadowed = mean(withBox, x: right.x, y: right.y)
        let lit = mean(without, x: right.x, y: right.y)
        #expect(lit - shadowed > 25,
                "the key light lost its shadow beside the point caster: \(shadowed) with the box, \(lit) without it")
    }
}

/// The scenes the slot probes read: a floor seen from straight above with a box at the
/// middle, lit so each caster throws that box onto a band of floor of its own.
private final class PointSlotScene: Sketch {
    enum Kind { case keyAndPoint, twoPoints, lowKeyAndPoint }
    var kind: Kind = .keyAndPoint
    var hasBox = true

    static func make(_ kind: Kind, box: Bool) -> PointSlotScene {
        let scene = PointSlotScene()
        scene.kind = kind
        scene.hasBox = box
        return scene
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.02))
        ambientLight(Color(white: 0.04))
        castShadows()
        // Straight down, so the floor reads as a plan and a shadow's direction is the
        // light's own with no projection to undo. Screen right is +x, screen down is +z.
        camera(Camera3D(eye: Vector3(0, 9, 0.001), target: .zero,
                        projection: .perspective(fieldOfView: .pi / 3)))
        switch kind {
        case .keyAndPoint:
            // A key straight down throws the box onto its own footprint, which the box
            // hides from this camera, so the right-hand band belongs to the point light.
            directionalLight(.white, direction: Vector3(0, -1, 0), intensity: 0.5)
            pointLight(.white, at: Vector3(-3, 6, 0), intensity: 1.5)
        case .twoPoints:
            pointLight(.white, at: Vector3(-3, 6, 0), intensity: 1.0)
            pointLight(.white, at: Vector3(0, 6, -3), intensity: 1.0)
        case .lowKeyAndPoint:
            // The key comes in from the left and throws the box to the right; the point
            // light stands overhead, where its own shadow hides under the box.
            directionalLight(.white, direction: Vector3(1, -1.5, 0), intensity: 1.0)
            pointLight(.white, at: Vector3(0, 6, 0), intensity: 0.6)
        }
        withState { fill(Color(white: 0.85)); specular(0); drawPlane(width: 30, depth: 30) }
        if hasBox {
            withState {
                translate(0, 0.9, 0)
                fill(Color(white: 0.6)); specular(0)
                drawBox(width: 1.0, height: 1.8, depth: 1.0)
            }
        }
    }
}
