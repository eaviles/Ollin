@testable import Ollin
import CoreGraphics
import Foundation
import Testing

/// A surface's maps, seen in a ray-traced mirror.
///
/// A reflected hit reads every map the surface binds, at the level its ray's
/// footprint asks for: the picture, a normal map's relief, a metallic-roughness map,
/// an occlusion map, and a glow. Read at full size with the other maps left out, a
/// relief and a glow show on the surface and not in a mirror facing it, and a fine
/// picture seen small in the mirror is grain. The stage is a floor in front of a
/// mirror wall: each statement reads the floor head on and its image in the mirror,
/// and the two have to agree. RT-gated: without ray tracing there is no traced
/// reflection.
@Suite(.serialized)
@MainActor
struct TracedHitMapTests {

    /// A floor in front of a mirror wall, with the trace on.
    final class Stage: Sketch {
        enum Floor: Sendable {
            /// A normal map whose two halves lean opposite ways along the floor's width.
            case tilted
            /// A metallic-roughness map: a rough dielectric half and a smooth metal half.
            case finished
            /// The same two finishes as two plain meshes, their factors in the material.
            case finishedByFactor
            /// An occlusion map, black over one half and white over the other.
            case occluded
            /// An emissive map, white over one half and black over the other.
            case glowMapped
            /// A constant emissive color over the whole floor.
            case glowFactor
            /// The floor glowing in its own color.
            case glowOwn
            /// A black floor with no glow at all.
            case dark
            /// A picture of one-texel black and white checks.
            case fine
        }
        var floor = Floor.tilted
        var nudge = 0.0

        override var canvasSize: CanvasSize { .square(256) }
        override func setup() { noLoop() }

        static func make(_ floor: Floor, nudge: Double = 0) -> Stage {
            let s = Stage()
            s.floor = floor
            s.nudge = nudge
            return s
        }

        /// A picture whose left and right halves hold two colors.
        static func halves(_ left: (UInt8, UInt8, UInt8), _ right: (UInt8, UInt8, UInt8),
                           size: Int = 64) -> Image {
            var bytes = [UInt8]()
            bytes.reserveCapacity(size * size * 4)
            for _ in 0..<size {
                for x in 0..<size {
                    let c = x < size / 2 ? left : right
                    bytes.append(contentsOf: [c.0, c.1, c.2, 255])
                }
            }
            return Image(width: size, height: size, premultipliedRGBA: bytes)!
        }

        /// One-texel checks: the finest picture a texture holds, and the mid gray of
        /// its two tones at every coarser level. Made the way a loaded picture is,
        /// from a decoded image, since that is the kind of picture that carries its
        /// smaller levels (one authored pixel by pixel is uploaded at full size alone).
        static let checks: Image = {
            let size = 512
            var bytes = [UInt8]()
            bytes.reserveCapacity(size * size * 4)
            for y in 0..<size {
                for x in 0..<size {
                    let v: UInt8 = (x + y) % 2 == 0 ? 255 : 0
                    bytes.append(contentsOf: [v, v, v, 255])
                }
            }
            let decoded = bytes.withUnsafeMutableBytes { raw -> CGImage in
                CGContext(data: raw.baseAddress, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
            }
            return Image(cgImage: decoded)
        }()

        override func draw() {
            background(Color(white: 0.5))
            camera(.perspective(eye: Vector3(nudge, 2.2, 3.2), target: Vector3(nudge, 0.4, -0.4),
                                fieldOfView: 1.0))
            environment(Environment.studio.lightingOnly())
            // The occlusion map dims the ambient alone, so its stage has no direct light.
            if floor != .occluded {
                directionalLight(.white, direction: Vector3(-0.6, -1, -0.3), intensity: 0.5)
            }
            rayTracedReflections(true)
            withState {
                material(.metal(roughness: 0.02))
                fill(.white)
                translate(0, 1, -1)
                rotateX(Double.pi / 2)
                drawPlane(width: 3, depth: 2)
            }
            let plane = Mesh.plane(width: 3, depth: 2)
            withState {
                switch floor {
                case .tilted:
                    // Leaning 45 degrees toward the floor's left and toward its right.
                    material(.matte)
                    fill(.white)
                    drawMesh(plane.normalMapped(Stage.halves((37, 128, 218), (218, 128, 218))))
                case .finished:
                    // Roughness in green, metalness in blue: rough and bare on the
                    // left, smooth and metal on the right.
                    material(.physicallyBased(metallic: 1, roughness: 1))
                    fill(.white)
                    drawMesh(plane.surfaceMapped(metallicRoughness: Stage.halves((0, 255, 0), (0, 51, 255))))
                case .finishedByFactor:
                    fill(.white)
                    material(.physicallyBased(metallic: 0, roughness: 1))
                    translate(-0.75, 0, 0)
                    drawPlane(width: 1.5, depth: 2)
                    material(.physicallyBased(metallic: 1, roughness: 0.2))
                    translate(1.5, 0, 0)
                    drawPlane(width: 1.5, depth: 2)
                case .occluded:
                    material(.physicallyBased(metallic: 0, roughness: 1))
                    fill(.white)
                    drawMesh(plane.surfaceMapped(occlusion: Stage.halves((0, 0, 0), (255, 255, 255))))
                case .glowMapped:
                    material(.matte)
                    fill(.black)
                    drawMesh(plane.surfaceMapped(emissive: Stage.halves((255, 255, 255), (0, 0, 0))))
                case .glowFactor:
                    material(.matte)
                    fill(.black)
                    drawMesh(plane.surfaceMapped(emissiveColor: Color(white: 0.7)))
                case .glowOwn:
                    material(.matte)
                    fill(Color(red: 0.9, green: 0.2, blue: 0.1))
                    drawMesh(plane.glowing(1))
                case .dark:
                    material(.matte)
                    fill(.black)
                    drawMesh(plane)
                case .fine:
                    material(.matte)
                    fill(.white)
                    drawMesh(plane.textured(Stage.checks))
                }
            }
        }
    }

    /// The floor head on and its image in the mirror wall, each over its left half and
    /// its right half, clear of the seam and the edges.
    private enum Box {
        static let floorLeft = (0.22...0.42, 0.60...0.75)
        static let floorRight = (0.58...0.78, 0.60...0.75)
        static let mirrorLeft = (0.33...0.45, 0.41...0.49)
        static let mirrorRight = (0.55...0.67, 0.41...0.49)
    }

    /// The green channel's mean and spread over a box of the frame, in 8-bit levels.
    private func read(_ image: CGImage, _ box: (ClosedRange<Double>, ClosedRange<Double>))
        -> (mean: Double, spread: Double) {
        let p = pixels(of: image)
        let w = image.width, h = image.height
        var sum = 0.0, squares = 0.0, count = 0.0
        for py in Int(box.1.lowerBound * Double(h))..<Int(box.1.upperBound * Double(h)) {
            for px in Int(box.0.lowerBound * Double(w))..<Int(box.0.upperBound * Double(w)) {
                let v = Double(p[(py * w + px) * 4 + 1])
                sum += v
                squares += v * v
                count += 1
            }
        }
        let mean = sum / count
        return (mean, max(squares / count - mean * mean, 0).squareRoot())
    }

    private func frame(_ floor: Stage.Floor, nudge: Double = 0) throws -> CGImage {
        try OllinApp.image(of: Stage.make(floor, nudge: nudge), frame: 0)
    }

    /// A normal map's relief shows in a mirror. The two halves of the floor lean
    /// opposite ways under a light from the side, so they shade apart, and the mirror
    /// holds the same two tones. Read flat, with the map left out of the hit, the
    /// mirror shows one tone across both.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aNormalMapsReliefShowsInAMirror() throws {
        let image = try frame(.tilted)
        let onFloor = read(image, Box.floorLeft).mean - read(image, Box.floorRight).mean
        let inMirror = read(image, Box.mirrorLeft).mean - read(image, Box.mirrorRight).mean
        #expect(abs(onFloor) > 30, "the two halves shade \(onFloor) levels apart on the floor")
        #expect(inMirror * onFloor > 0 && abs(inMirror) > 0.6 * abs(onFloor),
                "the mirror shows \(inMirror) levels between the halves, the floor \(onFloor)")
    }

    /// A metallic-roughness map sets the finish a mirror sees. The oracle is the same
    /// floor as two plain meshes with the map's two finishes as factors: the mirror
    /// holds the same image of both, and the two halves read apart in it.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aMetallicRoughnessMapSetsTheFinishInAMirror() throws {
        let mapped = try frame(.finished)
        let byFactor = try frame(.finishedByFactor)
        for (name, box) in [("left", Box.mirrorLeft), ("right", Box.mirrorRight)] {
            let a = read(mapped, box).mean, b = read(byFactor, box).mean
            #expect(abs(a - b) < 4, "the mirror's \(name) half reads \(a) by the map and \(b) by the factors")
        }
        let apart = read(mapped, Box.mirrorLeft).mean - read(mapped, Box.mirrorRight).mean
        #expect(abs(apart) > 15, "the two finishes read \(apart) levels apart in the mirror")
    }

    /// An occlusion map dims the ambient a mirror sees, as it dims it on the surface.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func anOcclusionMapDimsTheAmbientInAMirror() throws {
        let image = try frame(.occluded)
        let onFloor = read(image, Box.floorRight).mean - read(image, Box.floorLeft).mean
        let inMirror = read(image, Box.mirrorRight).mean - read(image, Box.mirrorLeft).mean
        #expect(onFloor > 30, "the open half reads \(onFloor) levels over the occluded half on the floor")
        #expect(inMirror > 0.6 * onFloor,
                "the mirror shows \(inMirror) levels between the halves, the floor \(onFloor)")
    }

    /// A glowing surface glows in a mirror: by its emissive map, by a constant
    /// emissive color, and in its own color. A hit that carries none of the three
    /// shows a neon sign's reflection as its unlit body.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aGlowShowsInAMirror() throws {
        let dark = try frame(.dark)
        let unlit = read(dark, Box.mirrorLeft).mean
        let mapped = try frame(.glowMapped)
        let lit = read(mapped, Box.mirrorLeft).mean, off = read(mapped, Box.mirrorRight).mean
        #expect(lit > unlit + 80, "the glowing half reads \(lit) in the mirror, a dark floor \(unlit)")
        #expect(off < unlit + 12, "the half the map leaves dark reads \(off) in the mirror, a dark floor \(unlit)")
        let onFloor = read(mapped, Box.floorLeft).mean
        #expect(lit > 0.7 * onFloor, "the glow reads \(lit) in the mirror and \(onFloor) on the floor")
        let factor = read(try frame(.glowFactor), Box.mirrorRight).mean
        #expect(factor > unlit + 60, "a constant glow reads \(factor) in the mirror, a dark floor \(unlit)")
        let own = try frame(.glowOwn)
        let p = pixels(of: own)
        let at = (Int(0.45 * 256) * 256 + Int(0.6 * 256)) * 4
        #expect(Int(p[at]) > Int(p[at + 2]) + 60,
                "a floor glowing in its own red reads \(p[at]), \(p[at + 1]), \(p[at + 2]) in the mirror")
    }

    /// A fine picture seen small in a mirror is read at its footprint. One-texel
    /// checks average to their mid gray once a pixel's footprint at the hit covers
    /// several texels, which is what the floor shows head on; read at full size, each
    /// ray lands on a black or a white texel, the mirror's image of the floor is
    /// grain, and the grain moves when the camera does. Measured 2026-11-11 on this
    /// stage: read at full size the mirror's image spread 3.25 levels and changed
    /// 4.34 levels a pixel for the hair of camera below; read at its footprint it
    /// spreads 0.51, the display dither's own floor, and does not change at all.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aFinePictureInAMirrorIsReadAtItsFootprint() throws {
        let image = try frame(.fine)
        let onFloor = read(image, Box.floorLeft)
        let inMirror = read(image, Box.mirrorLeft)
        #expect(inMirror.spread < 1.5, "the mirror's image of the checks spreads \(inMirror.spread) levels")
        #expect(abs(inMirror.mean - onFloor.mean) < 12,
                "the checks read \(inMirror.mean) in the mirror and \(onFloor.mean) on the floor")
        // The shimmer: the same view with the camera a hair to one side.
        let moved = try frame(.fine, nudge: 0.004)
        let a = pixels(of: image), b = pixels(of: moved)
        var change = 0.0, count = 0.0
        for py in Int(0.41 * 256)..<Int(0.49 * 256) {
            for px in Int(0.33 * 256)..<Int(0.67 * 256) {
                change += abs(Double(a[(py * 256 + px) * 4 + 1]) - Double(b[(py * 256 + px) * 4 + 1]))
                count += 1
            }
        }
        #expect(change / count < 1.5, "the mirror's image changes \(change / count) levels a pixel for a hair of camera")
    }

    /// The same frame twice is the same bytes with every map at a hit.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func theMappedHitsAreDeterministic() throws {
        for floor in [Stage.Floor.tilted, .finished, .glowMapped, .fine] {
            #expect(pixels(of: try frame(floor)) == pixels(of: try frame(floor)))
        }
    }
}
