import CoreGraphics
import Testing
@testable import Ollin

/// Newton's basins, checked against the laws the method promises rather than
/// against a picture: a root sits inside its own basin, the three basins of the
/// cube roots of one turn into each other by a third of a turn, wherever two
/// basins meet the third is within reach (the boundary is a Wada set), a cycle
/// that catches the method leaves trapped pools, the shading darkens with the
/// step count, the palette turns with `phase`, and eight roots each keep a
/// basin. Every probe renders, so the whole suite wants Metal.
@MainActor
@Suite
struct NewtonBasinsTests {

    /// Pure red, green, blue, and five more, so a pixel names its basin by the
    /// nearest stop.
    static let stops: [Color] = [
        Color(red: 1, green: 0, blue: 0), Color(red: 0, green: 1, blue: 0),
        Color(red: 0, green: 0, blue: 1), Color(red: 1, green: 1, blue: 0),
        Color(red: 0, green: 1, blue: 1), Color(red: 1, green: 0, blue: 1),
        Color(red: 1, green: 1, blue: 1), Color(red: 0.5, green: 0.5, blue: 0.5),
    ]

    /// The three cube roots of one, counter-clockwise from the real axis.
    static let cubeRoots = [Vector2(1, 0), Vector2(-0.5, 0.8660254), Vector2(-0.5, -0.8660254)]

    /// The generator's pixels as sRGB bytes, row-major from the top.
    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return data
    }

    /// Which stop (or -1 for the trapped black) each pixel is nearest.
    private func basins(_ probe: NewtonProbe) throws -> (map: [Int], n: Int, rgb: [UInt8]) {
        let image = try #require(OllinApp.image(of: probe, frame: 1))
        let bytes = pixels(of: image)
        let n = image.width
        let stops = Self.stops.prefix(max(probe.roots.count, 1)).map { c -> SIMD3<Double> in
            SIMD3(c.red, c.green, c.blue)
        }
        var map = [Int](repeating: -1, count: n * n)
        for i in 0 ..< n * n {
            let c = SIMD3(Double(bytes[i * 4]), Double(bytes[i * 4 + 1]), Double(bytes[i * 4 + 2])) / 255
            var best = -1, bestDistance = 0.35   // farther than that from every stop is trapped
            for (k, s) in stops.enumerated() {
                let d = ((c - s) * (c - s)).sum().squareRoot()
                if d < bestDistance { bestDistance = d; best = k }
            }
            map[i] = best
        }
        return (map, n, bytes)
    }

    /// The pixel under a point of the plane (zoom 1 spans 3 units, y up).
    private func pixel(_ p: Vector2, n: Int, center: Vector2 = .zero, zoom: Double = 1) -> (Int, Int) {
        let span = 3.0 / zoom
        let x = Int(((p.x - center.x) / span + 0.5) * Double(n))
        let y = Int(((center.y - p.y) / span + 0.5) * Double(n))
        return (min(max(x, 0), n - 1), min(max(y, 0), n - 1))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aRootSitsInsideItsOwnBasin() throws {
        let probe = NewtonProbe(roots: Self.cubeRoots)
        let (map, n, _) = try basins(probe)
        for (k, root) in Self.cubeRoots.enumerated() {
            let (x, y) = pixel(root, n: n)
            #expect(map[y * n + x] == k, "root \(k) at pixel (\(x), \(y)) reads basin \(map[y * n + x])")
            // And the whole neighborhood with it: the immediate basin is a disk.
            for dy in -6 ... 6 {
                for dx in -6 ... 6 {
                    #expect(map[(y + dy) * n + x + dx] == k)
                }
            }
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theThreeBasinsTurnIntoEachOtherByAThirdOfATurn() throws {
        let probe = NewtonProbe(roots: Self.cubeRoots)
        let (map, n, _) = try basins(probe)
        let span = 3.0
        var agree = 0, total = 0
        for y in stride(from: 8, to: n - 8, by: 3) {
            for x in stride(from: 8, to: n - 8, by: 3) {
                let p = Vector2((Double(x) + 0.5) / Double(n) - 0.5, 0.5 - (Double(y) + 0.5) / Double(n)) * span
                guard p.length < 1.3 else { continue }   // keep the turned point in frame
                let a = 2 * Double.pi / 3
                let turned = Vector2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a))
                let (tx, ty) = pixel(turned, n: n)
                let here = map[y * n + x], there = map[ty * n + tx]
                guard here >= 0, there >= 0 else { continue }
                total += 1
                if there == (here + 1) % 3 { agree += 1 }
            }
        }
        #expect(total > 4000)
        // The boundary is dust, so a sample straddling it can land on any
        // basin after the turn's rounding; everything else agrees.
        #expect(Double(agree) / Double(total) > 0.97,
                "\(agree) of \(total) samples turn into the next basin")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func whereverTwoBasinsMeetTheThirdIsWithinReach() throws {
        let probe = NewtonProbe(roots: Self.cubeRoots, size: 512)
        let (map, n, _) = try basins(probe)
        let reach = 12
        var boundary = 0, wada = 0
        for y in stride(from: reach, to: n - reach, by: 2) {
            for x in stride(from: reach, to: n - reach, by: 2) {
                let here = map[y * n + x]
                guard here >= 0 else { continue }
                let right = map[y * n + x + 1], below = map[(y + 1) * n + x]
                guard (right >= 0 && right != here) || (below >= 0 && below != here) else { continue }
                boundary += 1
                var seen = Set<Int>()
                for dy in -reach ... reach {
                    for dx in -reach ... reach {
                        let b = map[(y + dy) * n + x + dx]
                        if b >= 0 { seen.insert(b) }
                    }
                }
                if seen.count == 3 { wada += 1 }
            }
        }
        #expect(boundary > 500)
        #expect(Double(wada) / Double(boundary) > 0.95,
                "\(wada) of \(boundary) boundary pixels see all three basins within \(reach) px")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aCycleThatCatchesTheMethodLeavesTrappedPools() throws {
        // z^3 - 2z + 2: Newton's step sends 0 to 1 and 1 back to 0, and the
        // cycle is superattracting, so the plane around both is never brought
        // to a root.
        let roots = [Vector2(-1.7693, 0), Vector2(0.88465, 0.58974), Vector2(0.88465, -0.58974)]
        let probe = NewtonProbe(roots: roots)
        let (map, n, _) = try basins(probe)
        // The pool is wide around 0, where one step lands within a hair of 1
        // (the step there squares the distance), and thin around 1, where the
        // step stretches distances sixfold on the way back.
        for p in [Vector2.zero, Vector2(1, 0), Vector2(0.05, 0.05), Vector2(0.02, -0.03)] {
            let (x, y) = pixel(p, n: n)
            #expect(map[y * n + x] == -1, "\(p) should be trapped, reads basin \(map[y * n + x])")
        }
        for (k, root) in roots.enumerated() {
            let (x, y) = pixel(root, n: n)
            #expect(map[y * n + x] == k)
        }
        // And a plain cubic has no pools: nothing in the cube-roots frame is trapped.
        let plain = try basins(NewtonProbe(roots: Self.cubeRoots))
        let trapped = plain.map.filter { $0 < 0 }.count
        #expect(trapped < 4, "\(trapped) pixels of the cube roots never landed")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theShadingDarkensWithTheStepCount() throws {
        // The root lands at step zero. A point out along the same ray needs a
        // few steps, and one just past the critical point at zero is flung far
        // out and walks back for fifteen or so, so with shading on both read
        // darker, the second much more; with shading off the root and the
        // outward point match. (The contour per step keeps the shade from
        // being monotonic pointwise, so the law compares far apart.)
        func brightness(_ shading: Double, at p: Vector2) throws -> Double {
            let probe = NewtonProbe(roots: Self.cubeRoots, shading: shading)
            let (_, n, rgb) = try basins(probe)
            let (x, y) = pixel(p, n: n)
            let i = (y * n + x) * 4
            return Double(Int(rgb[i]) + Int(rgb[i + 1]) + Int(rgb[i + 2])) / (3 * 255)
        }
        let atRoot = try brightness(1, at: Vector2(1, 0))
        let outward = try brightness(1, at: Vector2(1.45, 0))
        let flung = try brightness(1, at: Vector2(0.05, 0))
        #expect(atRoot > outward + 0.05, "root \(atRoot) against outward \(outward)")
        #expect(atRoot > flung + 0.15, "root \(atRoot) against the flung point \(flung)")
        #expect(abs(try brightness(0, at: Vector2(1, 0)) - (try brightness(0, at: Vector2(1.45, 0)))) < 0.02)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func phaseTurnsThePaletteAroundTheWheel() throws {
        let probe = NewtonProbe(roots: Self.cubeRoots, phase: 1.0 / 3)
        let (map, n, _) = try basins(probe)
        for (k, root) in Self.cubeRoots.enumerated() {
            let (x, y) = pixel(root, n: n)
            #expect(map[y * n + x] == (k + 1) % 3)
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func eightRootsEachKeepABasin() throws {
        let roots = (0 ..< 8).map { i -> Vector2 in
            let a = Double(i) / 8 * .tau
            return Vector2(cos(a), sin(a))
        }
        let probe = NewtonProbe(roots: roots)
        let (map, n, _) = try basins(probe)
        for (k, root) in roots.enumerated() {
            let (x, y) = pixel(root, n: n)
            #expect(map[y * n + x] == k, "root \(k) reads basin \(map[y * n + x])")
        }
        // A ninth root is dropped, not wrapped: the factory keeps eight.
        let nine = Generator.newton(roots: roots + [Vector2(0, 0)])
        if case let .newton(_, _, kept, _, _, _, _, _, _) = nine.kind {
            #expect(kept.count == 8)
        } else {
            Issue.record("the newton factory built another kind")
        }
    }
}

/// A square canvas filled by the generator at 1:1 with a one-stop-per-root
/// palette and no shading unless asked, so a pixel's color names its basin.
private final class NewtonProbe: Sketch {
    let roots: [Vector2]
    let size: Int
    let shading: Double
    let phase: Double

    init(roots: [Vector2], size: Int = 256, shading: Double = 0, phase: Double = 0) {
        self.roots = roots
        self.size = size
        self.shading = shading
        self.phase = phase
        super.init()
    }

    required init() {
        self.roots = NewtonBasinsTests.cubeRoots
        self.size = 256
        self.shading = 0
        self.phase = 0
        super.init()
    }

    override var canvasSize: CanvasSize { .square(size) }

    override func draw() {
        let layer = generate(.newton(roots: roots,
                                     colors: Array(NewtonBasinsTests.stops.prefix(roots.count)),
                                     shading: shading, phase: phase),
                             width: size, height: size)
        drawImage(layer.image, 0, 0)
    }
}
