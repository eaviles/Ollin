@testable import Ollin
import CoreGraphics
import Foundation
import Testing

/// A picture on a surface, seen in a ray-traced mirror.
///
/// A traced hit shades the surface it finds from the colors baked into its vertices
/// and its finish, so a mesh drawn with a picture (`Mesh.textured`) used to reach the
/// mirror as its plain fill, white over a whole red and blue floor. The oracle is a
/// counterfactual: the same floor drawn without a picture, its two halves filled with
/// the picture's two colors. Both have the same color at every point, so the mirror
/// must hold the same image of both, to a level or two. RT-gated: without ray tracing
/// there is no traced reflection to read.
@Suite
@MainActor
struct TexturedReflectionTests {

    /// Mean red, green, and blue over a box of the frame, in 8-bit sRGB.
    private func mean(_ image: CGImage, x: ClosedRange<Double>, y: ClosedRange<Double>) -> SIMD3<Double> {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = SIMD3<Double>(repeating: 0)
        var count = 0.0
        for py in Int(y.lowerBound * Double(h))..<Int(y.upperBound * Double(h)) {
            for px in Int(x.lowerBound * Double(w))..<Int(x.upperBound * Double(w)) {
                let i = (py * w + px) * 4
                sum += SIMD3(Double(data[i]), Double(data[i + 1]), Double(data[i + 2]))
                count += 1
            }
        }
        return sum / count
    }

    /// A layer's picture is drawn after the traced scene is built, so it reaches the
    /// trace by a second route from a loaded picture's: both are read here.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing),
          arguments: [PicturedFloorProbe.Floor.layer, .loaded])
    func aPictureOnAFloorShowsInATracedMirror(_ floor: PicturedFloorProbe.Floor) throws {
        let probe = PicturedFloorProbe()
        probe.floor = floor
        let pictured = try OllinApp.image(of: probe, frame: 0)
        let plain = PicturedFloorProbe()
        plain.floor = .filled
        let filled = try OllinApp.image(of: plain, frame: 0)
        // The floor head on, and its image in the mirror wall, each over the red half
        // and over the blue half, clear of the seam and the edges.
        let boxes: [(String, ClosedRange<Double>, ClosedRange<Double>)] = [
            ("floor, red half", 0.22...0.42, 0.60...0.75),
            ("floor, blue half", 0.58...0.78, 0.60...0.75),
            ("mirror, red half", 0.33...0.45, 0.41...0.49),
            ("mirror, blue half", 0.55...0.67, 0.41...0.49),
        ]
        for (name, x, y) in boxes {
            let a = mean(pictured, x: x, y: y), b = mean(filled, x: x, y: y)
            let gap = max(abs(a.x - b.x), abs(a.y - b.y), abs(a.z - b.z))
            #expect(gap <= 2, "\(name): pictured \(a), filled \(b)")
        }
        // The mirror holds the floor at all: its red half is red and its blue half blue.
        let red = mean(pictured, x: 0.33...0.45, y: 0.41...0.49)
        let blue = mean(pictured, x: 0.55...0.67, y: 0.41...0.49)
        #expect(red.x > red.z + 40 && blue.z > blue.x + 40, "mirror red \(red), blue \(blue)")
    }
}

/// A floor, red on its left half and blue on its right, in front of a mirror wall, with
/// the trace on: drawn as one plane with a picture on it (a layer, or a picture made
/// from pixels), and as two planes filled with the picture's two colors.
@MainActor
final class PicturedFloorProbe: Sketch {
    /// How the floor gets its two colors.
    enum Floor: Sendable { case layer, loaded, filled }

    override var canvasSize: CanvasSize { .square(256) }
    var floor = Floor.layer

    override func setup() { noLoop() }

    override func draw() {
        background(Color(white: 0.5))
        camera(.perspective(eye: Vector3(0, 2.2, 3.2), target: Vector3(0, 0.4, -0.4), fieldOfView: 1.0))
        environment(Environment.studio.lightingOnly())
        directionalLight(.white, direction: Vector3(-0.3, -1, -0.5), intensity: 2)
        rayTracedReflections(true)
        // The mirror first, so a picture-less surface leads the traced run the floor
        // would join if a picture did not start a geometry of its own.
        withState {
            material(.metal(roughness: 0.02))
            fill(.white)
            translate(0, 1, -1)
            rotateX(Double.pi / 2)
            drawPlane(width: 3, depth: 2)
        }
        withState {
            material(.matte)
            switch floor {
            case .layer:
                let picture = makeRenderTarget(width: 64, height: 64)
                withTarget(picture) {
                    background(.red)
                    noStroke()
                    fill(.blue)
                    drawRect(32, 0, 32, 64)
                }
                fill(.white)
                drawMesh(Mesh.plane(width: 3, depth: 2).textured(picture.image))
            case .loaded:
                let picture = Image(width: 64, height: 64, color: .red)
                for y in 0..<64 {
                    for x in 32..<64 { picture[x, y] = .blue }
                }
                fill(.white)
                drawMesh(Mesh.plane(width: 3, depth: 2).textured(picture))
            case .filled:
                fill(.red)
                translate(-0.75, 0, 0)
                drawPlane(width: 1.5, depth: 2)
                fill(.blue)
                translate(1.5, 0, 0)
                drawPlane(width: 1.5, depth: 2)
            }
        }
    }
}
