@testable import Ollin
import Testing
import CoreGraphics

/// The camera as a surface: a feed's frame is an `Image`, so a mesh wears it through
/// `textured(_:)` with no API of its own. What that path has to get right is that
/// each frame's *fresh* image reaches the surface: a camera hands back a new `Image`
/// per capture, and the material is set again every draw, so a feed that changes
/// between two draws must show the new picture and never a stale texture.
@Suite
@MainActor
struct LiveSurfaceTests {

    /// A feed the way a camera behaves: a fresh `Image` every read, of whatever
    /// color the "room" is right now.
    final class SwatchFeed: VideoFeed {
        var color: Color = .red
        var frame: Image? { Image(width: 8, height: 8, color: color) }
        var frameSize: Vector2? { Vector2(8, 8) }
    }

    /// A globe wearing the feed, flat-lit so the texture reads as itself. The room
    /// turns from red to blue after the first draw.
    final class Probe: Sketch {
        let feed = SwatchFeed()
        let globe = Mesh.sphere(radius: 1.3, segments: 24, rings: 12)
        var draws = 0
        override var canvasSize: CanvasSize { .square(96) }

        override func draw() {
            background(.black)
            camera(Camera3D(eye: Vector3(0, 0, 4), target: .zero))
            ambientLight(.white)
            draws += 1
            feed.color = draws <= 1 ? .red : .blue
            fill(.white)
            material(Material())
            if let frame = feed.frame { drawMesh(globe.textured(frame)) }
        }
    }

    private func center(_ image: CGImage) -> (r: Int, b: Int) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let i = ((h / 2) * w + w / 2) * 4
        return (Int(data[i]), Int(data[i + 2]))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aFeedFrameOnAMeshFollowsTheFeed() throws {
        // The same sketch rendered twice: the first frame wears the red room and
        // uploads it; by the second the room is blue and the globe has to be too.
        // A texture held against the mesh or the material from the first draw
        // would keep it red.
        let probe = Probe()
        let first = try #require(OllinApp.image(of: probe, frame: 0))
        let later = try #require(OllinApp.image(of: probe, frame: 0))
        let a = center(first), b = center(later)
        #expect(a.r > 150 && a.b < 60, "the first frame should wear the red room: \(a)")
        #expect(b.b > 150 && b.r < 60, "a later frame should wear the blue room, not a stale texture: \(b)")
    }
}
