// figure: frame=0
//
// Guide figure (Chapter 22): detail maps. Two spheres wear the same base
// texture and base normal map, a photograph of a dry-stone wall cut down to
// the resolution a map covering a whole boulder would really have, seen close
// enough that it has run out of texels; the right one also carries a fine
// detail pair (color + normal) tiled across the base, so it keeps grain where
// the left dissolves soft.
import Ollin
import OllinSamplePhotos

final class SurfaceGrain: Sketch {

    override var canvasSize: CanvasSize { .size(880, 380) }

    var base = Image(width: 1, height: 1, color: .white)
    var baseBumps = Image(width: 1, height: 1, color: .white)
    var grain = Image(width: 1, height: 1, color: .white)
    var grainBumps = Image(width: 1, height: 1, color: .white)

    /// A picture and the normal map its own light and shade imply: the slope
    /// of its brightness at each texel, green-up. The reads wrap, so a map cut
    /// from a picture that tiles keeps tiling.
    func maps(_ picture: Image, size: Int, relief: Double) -> (Image, Image) {
        let small = picture.resized(width: size, height: size)
        var field = [Double](repeating: 0, count: size * size)
        for y in 0 ..< size {
            for x in 0 ..< size { field[y * size + x] = small[x, y].luminance }
        }
        func height(_ x: Int, _ y: Int) -> Double {
            field[(((y % size) + size) % size) * size + (((x % size) + size) % size)]
        }
        var normal = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0 ..< size {
            for x in 0 ..< size {
                let dx = (height(x + 1, y) - height(x - 1, y)) * relief
                let dy = (height(x, y + 1) - height(x, y - 1)) * relief
                let len = (dx * dx + dy * dy + 1).squareRoot()
                let i = (y * size + x) * 4
                normal[i]     = UInt8((-dx / len * 0.5 + 0.5) * 255)
                normal[i + 1] = UInt8((dy / len * 0.5 + 0.5) * 255)
                normal[i + 2] = UInt8((1 / len * 0.5 + 0.5) * 255)
            }
        }
        return (small, Image(width: size, height: size, premultipliedRGBA: normal)!)
    }

    override func setup() {
        // The base is deliberately small: this is the budget a single map
        // covering a whole form actually has, and it is what runs out.
        (base, baseBumps) = maps(SamplePhoto.stone.load(), size: 96, relief: 3)
        // The detail pair comes off the same photograph, close in: a patch of
        // its rough face, mirrored into a tile so it repeats without a grid.
        // Its color map is taken to gray and pulled in toward the middle,
        // because a detail color map multiplies the base and 128 is its
        // neutral, so a tinted one would paint the surface over instead of
        // adding a finer scale to it.
        let patch = SurfaceGrain.mirroredTile(
            SamplePhoto.stone.load().cropped(x: 310, y: 520, width: 200, height: 200))
        let (fine, fineBumps) = maps(patch, size: 200, relief: 3.5)
        grain = SurfaceGrain.towardGray(fine, swing: 1.1)
        grainBumps = fineBumps
    }

    /// A patch mirrored into a tile that repeats seamlessly: every edge meets
    /// its own reflection, so no join can disagree with itself.
    static func mirroredTile(_ patch: Image) -> Image {
        let n = patch.width * 2
        var bytes = [UInt8](repeating: 255, count: n * n * 4)
        for y in 0 ..< n {
            for x in 0 ..< n {
                let color = patch[min(x, n - 1 - x), min(y, n - 1 - y)]
                let i = (y * n + x) * 4
                bytes[i] = UInt8(min(max(color.red, 0), 1) * 255)
                bytes[i + 1] = UInt8(min(max(color.green, 0), 1) * 255)
                bytes[i + 2] = UInt8(min(max(color.blue, 0), 1) * 255)
            }
        }
        return Image(width: n, height: n, premultipliedRGBA: bytes)!
    }

    /// A color map taken to gray and pulled toward the middle, the form a
    /// detail map wants: it darkens and lightens the base without tinting it.
    static func towardGray(_ picture: Image, swing: Double) -> Image {
        let n = picture.width
        var luminance = [Double](repeating: 0, count: n * n)
        for y in 0 ..< n {
            for x in 0 ..< n { luminance[y * n + x] = picture[x, y].luminance }
        }
        // Centered on the patch's own average, not on the middle of the range,
        // so the map darkens and lightens the base in equal measure and the
        // surface keeps the tone the base gave it.
        let average = luminance.reduce(0, +) / Double(n * n)
        var bytes = [UInt8](repeating: 255, count: n * n * 4)
        for y in 0 ..< n {
            for x in 0 ..< n {
                let value = 0.5 + (luminance[y * n + x] - average) * swing
                let v = UInt8(min(max(value, 0), 1) * 255)
                let i = (y * n + x) * 4
                bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v
            }
        }
        return Image(width: n, height: n, premultipliedRGBA: bytes)!
    }

    override func draw() {
        background(Color(hex: 0x0B0D12))
        camera(.perspective(eye: Vector3(0, 0.25, 4.2), target: .zero,
                            fieldOfView: .pi / 4.6))
        environment(.studio.intensified(to: 0.8).lightingOnly())
        directionalLight(Color(kelvin: 5400), direction: Vector3(-0.6, -0.5, -0.6))
        ambientLight(Color(white: 0.06))
        fill(.white)
        material(.dielectric(roughness: 0.7))
        let dressed = Mesh.sphere(radius: 1.0, segments: 64, rings: 32)
            .textured(base).normalMapped(baseBumps, scale: 0.8)
        withState {
            translate(-1.15, 0, 0)
            drawMesh(dressed)
        }
        withState {
            translate(1.15, 0, 0)
            drawMesh(dressed.detailMapped(grain, normal: grainBumps,
                                          scale: 7, strength: 0.9))
        }
    }
}
