@testable import Ollin
import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers
import Testing

/// What a texture does when it lands on fewer pixels than it has texels.
///
/// A picture read at one texel per pixel is only right while the two counts
/// match. Past that the sampler is picking one texel out of the many the pixel
/// covers, so the surface reads as noise, it changes completely when the camera
/// creeps forward, and its average tone is wrong. The answer is the mip chain:
/// each level is the one above it averaged down, and the sampler reads the level
/// that matches what the pixel covers.
///
/// The probes stage a checker, which is the unfair case: it has the highest
/// contrast a texture can have at the smallest size it can have it. The picture
/// arrives two ways, and the difference between them is the whole test. A
/// decoded picture carries the chain. A picture whose bytes the sketch wrote
/// takes the per-frame upload path, which stays at one level on purpose.
@Suite(.serialized)
@MainActor
struct TextureFilteringTests {

    // MARK: The same checker, arriving three ways

    static func checkerBytes(size: Int, cell: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let v: UInt8 = ((x / cell) + (y / cell)) % 2 == 0 ? 255 : 0
                let i = (y * size + x) * 4
                bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v; bytes[i + 3] = 255
            }
        }
        return bytes
    }

    static func cgChecker(size: Int, cell: Int) -> CGImage {
        var bytes = checkerBytes(size: size, cell: cell)
        let ctx = CGContext(data: &bytes, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    /// A decoded file: the path a mesh's maps and a sketch's `loadImage` take.
    static func loaded(size: Int = 64, cell: Int = 4) -> Image {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cgChecker(size: size, cell: cell), nil)
        CGImageDestinationFinalize(dest)
        return Image(data: data as Data)!
    }

    /// A picture drawn into a bitmap: the loader hands back a linear format for
    /// one of these, so it is rebuilt by hand, which is a second place the chain
    /// has to be filled.
    static func drawn(size: Int = 64, cell: Int = 4) -> Image {
        Image(cgImage: cgChecker(size: size, cell: cell))
    }

    /// Bytes the sketch owns: the per-frame upload, one level by design.
    static func authored(size: Int = 64, cell: Int = 4) -> Image {
        Image(width: size, height: size, premultipliedRGBA: checkerBytes(size: size, cell: cell))!
    }

    // MARK: Two scenes

    /// A floor running to the horizon: the stretched case, where one pixel covers
    /// many texels along the view and few across it.
    final class Floor: Sketch {
        var texture: Image = TextureFilteringTests.loaded()
        var drift = 0.0
        override var canvasSize: CanvasSize { .square(256) }
        override func draw() {
            background(.black)
            perspective(eye: Vector3(0, 1.2, 6 + Double(frameCount) * drift),
                        target: Vector3(0, 0.6, -40), fieldOfView: .pi / 3)
            ambientLight(.white)
            var floor = Mesh.plane(width: 80, depth: 400)
            floor.uvs = floor.uvs.map { Vector2($0.x * 40, $0.y * 200) }
            fill(.white)
            drawMesh(floor.textured(texture, wrap: .tile))
        }
    }

    /// The same picture tiled far past the pixels there are to hold it, looked at
    /// straight on: the even case, where a pixel covers many texels each way and
    /// the long-axis taps have nothing to give.
    final class Wall: Sketch {
        var texture: Image = TextureFilteringTests.loaded()
        var tiles = 40.0
        override var canvasSize: CanvasSize { .square(256) }
        override func draw() {
            background(.black)
            ortho(eye: Vector3(0, 100, 0), target: .zero, up: Vector3(0, 0, -1), height: 200)
            ambientLight(.white)
            var plane = Mesh.plane(width: 200, depth: 200)
            plane.uvs = plane.uvs.map { Vector2($0.x * tiles, $0.y * tiles) }
            fill(.white)
            drawMesh(plane.textured(texture, wrap: .tile))
        }
    }

    // MARK: Reading a frame

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// The mean and the spread of one channel over the middle of a frame. The
    /// spread is the reading that matters: a surface that is being sampled a
    /// texel at a time is black-and-white noise, so it comes back near 127.
    private func spread(_ image: CGImage, y0: Double = 0.2, y1: Double = 0.8) -> (mean: Double, sd: Double) {
        let d = pixels(of: image), w = image.width
        var sum = 0.0, sq = 0.0, n = 0.0
        for py in Int(Double(image.height) * y0)..<Int(Double(image.height) * y1) {
            for px in (w / 5)..<(w * 4 / 5) {
                let v = Double(d[(py * w + px) * 4 + 1])
                sum += v; sq += v * v; n += 1
            }
        }
        let mean = sum / n
        return (mean, (sq / n - mean * mean).squareRoot())
    }

    /// Read the corner texel of a texture's second level. The textures live in
    /// private storage, so the read goes through a blit into a shared copy.
    private func secondLevelTexel(of texture: MTLTexture, on device: MTLDevice) -> Int? {
        let w = max(texture.width / 2, 1), h = max(texture.height / 2, 1)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat,
                                                        width: w, height: h, mipmapped: false)
        d.storageMode = .shared
        guard texture.mipmapLevelCount > 1,
              let copy = device.makeTexture(descriptor: d),
              let queue = device.makeCommandQueue(),
              let buffer = queue.makeCommandBuffer(),
              let blit = buffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 1,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: w, height: h, depth: 1),
                  to: copy, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { raw in
            copy.getBytes(raw.baseAddress!, bytesPerRow: w * 4,
                          from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        return Int(bytes[0])
    }

    // MARK: The chain itself

    /// A decoded picture arrives with its smaller levels, however it was decoded.
    /// The bytes a sketch writes do not: that upload runs again every frame a
    /// pixel changes, and it costs about 0.7 ms at canvas size to average levels
    /// a full-size picture never reads.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aDecodedPictureCarriesSmallerLevels() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        #expect(try #require(Self.loaded().texture(for: device)).mipmapLevelCount == 7)
        #expect(try #require(Self.drawn().texture(for: device)).mipmapLevelCount == 7)
        #expect(try #require(Self.authored().texture(for: device)).mipmapLevelCount == 1)
    }

    /// Each level averages in linear light, which is the light the renderer
    /// blends in. Black beside white is the reading that separates the two
    /// answers: half of the light is 188 written down, while halfway between the
    /// two *numbers* is 128, and a chain built that way would darken every
    /// picture as it got smaller.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theSmallerLevelsAverageInLinearLight() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        for picture in [Self.loaded(cell: 1), Self.drawn(cell: 1)] {
            let texture = try #require(picture.texture(for: device))
            let level1 = try #require(secondLevelTexel(of: texture, on: device))
            #expect(abs(level1 - 188) <= 2, "half the light is 188, not \(level1)")
        }
    }

    /// A value map carries the chain too: without one a normal map keeps
    /// flickering at a distance the base color has stopped flickering at.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aValueMapCarriesTheChainAsWell() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        #expect(try #require(Self.loaded().linearTexture(for: device)).mipmapLevelCount == 7)
    }

    // MARK: What it does to a picture

    /// The even case, and the whole point: tiled forty times across 256 pixels,
    /// one level is black-and-white noise that averages to the wrong tone, and
    /// the chain reads as the flat grey the checker actually is.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aTiledPlaneStopsBoiling() throws {
        let smooth = spread(try #require(OllinApp.image(of: { let s = Wall(); s.texture = Self.loaded(); return s }(), frame: 1)))
        let noisy = spread(try #require(OllinApp.image(of: { let s = Wall(); s.texture = Self.authored(); return s }(), frame: 1)))
        #expect(smooth.sd < 2, "the filtered plane should be flat: \(smooth)")
        #expect(abs(smooth.mean - 188) < 3, "and hold the checker's own tone: \(smooth)")
        #expect(noisy.sd > 100, "one level is noise, or this probe proves nothing: \(noisy)")
    }

    /// Made *larger* nothing changes, byte for byte. There is no level above the
    /// first, so a texture drawn at its own size or bigger reads the pixels it
    /// always read, and the chain cannot soften a picture a sketch meant to show
    /// close up.
    @Test(.enabled(if: Snapshot.hasMetal))
    func whatIsNotShrunkIsUntouched() throws {
        func render(_ picture: Image) throws -> [UInt8] {
            let s = Wall(); s.texture = picture; s.tiles = 0.5   // one texel over eight pixels
            return pixels(of: try #require(OllinApp.image(of: s, frame: 1)))
        }
        #expect(try render(Self.loaded()) == render(Self.authored()))
    }

    /// The stretched case, measured over time rather than in one frame: creep the
    /// camera forward by a fraction of a texel and ask how much the far floor
    /// changed. That is the crawl, and the chain takes a third of it away. What is
    /// left over is a soft field still shifting rather than a hard one; the
    /// sharpness it gave up to get there is what the anisotropic probe below
    /// takes back.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aRecedingFloorCrawlsLess() throws {
        func crawl(_ picture: Image) throws -> Double {
            var frames: [[UInt8]] = []
            for f in 1...2 {
                let s = Floor(); s.texture = picture; s.drift = 0.03
                frames.append(pixels(of: try #require(OllinApp.image(of: s, frame: f))))
            }
            var sum = 0.0, n = 0.0
            for py in 128..<166 {
                for px in 51..<205 {
                    let i = (py * 256 + px) * 4 + 1
                    sum += abs(Double(frames[0][i]) - Double(frames[1][i])); n += 1
                }
            }
            return sum / n
        }
        let filtered = try crawl(Self.loaded()), raw = try crawl(Self.authored())
        #expect(filtered < raw * 0.8, "the far floor still crawls: \(filtered) against \(raw)")
    }

    /// The same frame twice, byte for byte, now that the floor is read with
    /// sixteen readings taken along the long axis of the footprint. This is the
    /// probe that caught what those readings cost when the *whole* renderer was
    /// asked for them: a plain lit box rendered differently on every run (about
    /// 450 bytes at up to 12 of 255), because a screen-space pass that returns
    /// early has no four neighbors left to work a footprint out from. Only a
    /// picture on a surface is read that way now.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFilteredFloorRendersTheSameTwice() throws {
        func render() throws -> [UInt8] {
            let s = Floor(); s.texture = Self.loaded()
            return pixels(of: try #require(OllinApp.image(of: s, frame: 1)))
        }
        #expect(try render() == render())
    }

    /// The long thin footprint, answered. A pixel on a receding floor covers many
    /// texels along the view and few across it, and one level has to be picked for
    /// the long side, so the picture goes soft in *both* directions and the far
    /// band flattens to the checker's own grey. Sixteen readings taken along that
    /// long axis average only what the pixel really covers, so the rows stay
    /// apart. The same band of the same frame reads a spread of 0.51 with one
    /// reading and 8.20 with sixteen, which is what makes a threshold between them
    /// mean something. The tone is the guard on the other side: contrast bought by
    /// reading a sharper level than the pixel covers would pull the mean off 188,
    /// and it holds at 187.3.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aRecedingFloorKeepsItsRowsApart() throws {
        let s = Floor(); s.texture = Self.loaded()
        let band = spread(try #require(OllinApp.image(of: s, frame: 1)), y0: 0.52, y1: 0.62)
        #expect(band.sd > 4, "the far floor has gone flat: \(band)")
        #expect(abs(band.mean - 188) < 3, "and it must still be the checker's tone: \(band)")
    }

    /// The traced export reads the same levels. It already worked out a mip level
    /// per hit from the ray's own spread; until there were levels to read, that
    /// arithmetic had nowhere to land.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theTracedExportReadsTheSameLevels() throws {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: 16, denoise: false)
        defer { OllinApp.pathTracedExport = nil }
        let smooth = spread(try #require(OllinApp.image(of: { let s = Wall(); s.texture = Self.loaded(); return s }(), frame: 1)))
        let noisy = spread(try #require(OllinApp.image(of: { let s = Wall(); s.texture = Self.authored(); return s }(), frame: 1)))
        #expect(smooth.sd < 2, "the traced plane should be flat: \(smooth)")
        #expect(noisy.sd > 10, "sixteen samples hide some of it, never all: \(noisy)")
    }
}
