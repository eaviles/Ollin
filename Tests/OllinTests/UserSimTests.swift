import CoreGraphics
import Ollin
import Testing

/// A simulation of the sketch's own (`Sim.shader`) and what comes with it: the
/// field's edge rule, its precision, its extra inputs, its inject kernel, and the
/// readback. Everything runs headless on a 48-cell field and is compared **cell for
/// cell**, against the built-in rule, against a plain CPU reference, or against the
/// numbers the kernel was told to write.
@Suite
@MainActor
struct UserSimTests {

    // MARK: The kernel against the built-in rule

    @Test(.enabled(if: Snapshot.hasMetal))
    func aKernelOfOnesOwnMatchesTheBuiltInLifeCellForCell() throws {
        let soup = randomCells(count: 700, seed: 5)
        let builtIn = try grid(probe(.gameOfLife(), stamps: soup), generations: 12)
        let own = try grid(probe(.shader(UserSimTests.lifeKernel), stamps: soup), generations: 12)
        #expect(own == builtIn)
        #expect(own != stamped(soup))   // the run advanced
        #expect(own.joined().contains(1))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theKernelWrapsLikeTheBuiltInRule() throws {
        // A blinker across the right edge: alive at x = 47, 0, 1 on one row. On a
        // torus it is the period-two oscillator it always was; the built-in rule
        // wraps, so the kernel under the default edge must agree after an odd count.
        let blinker = [(x: 47, y: 20, white: 1.0), (x: 0, y: 20, white: 1.0), (x: 1, y: 20, white: 1.0)]
        let builtIn = try grid(probe(.gameOfLife(), stamps: blinker), generations: 3)
        let own = try grid(probe(.shader(UserSimTests.lifeKernel), stamps: blinker), generations: 3)
        #expect(own == builtIn)
        // Vertical now, straddling the seam: alive at (0, 19), (0, 20), (0, 21).
        #expect(own[19][0] == 1 && own[20][0] == 1 && own[21][0] == 1)
        #expect(own[20][47] == 0 && own[20][1] == 0)
    }

    // MARK: The edge rule

    @Test(.enabled(if: Snapshot.hasMetal))
    func clampedAndWrappingEdgesDifferExactlyAtTheBorder() throws {
        // One step of a kernel that writes each cell's live-neighbor count, from a
        // soup that reaches every edge, read back as numbers. Both edges must match
        // their own CPU reference exactly, and the two may differ only on the border.
        let soup = randomCells(count: 900, seed: 9)
        let wrapped = try counts(edge: .wrapping, stamps: soup)
        let clamped = try counts(edge: .clamped, stamps: soup)
        let start = stamped(soup)
        #expect(wrapped == neighborCounts(start, wrapsX: true, wrapsY: true))
        #expect(clamped == neighborCounts(start, wrapsX: false, wrapsY: false))
        var differing = 0, interiorDiffering = 0
        for y in 0 ..< 48 {
            for x in 0 ..< 48 where wrapped[y][x] != clamped[y][x] {
                differing += 1
                if x > 0 && y > 0 && x < 47 && y < 47 { interiorDiffering += 1 }
            }
        }
        #expect(differing > 0)
        #expect(interiorDiffering == 0)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theTwoAxesWrapApart() throws {
        let soup = randomCells(count: 900, seed: 11)
        let start = stamped(soup)
        let scroll = try counts(edge: FieldEdge(wrapsX: true, wrapsY: false), stamps: soup)
        #expect(scroll == neighborCounts(start, wrapsX: true, wrapsY: false))
        let tube = try counts(edge: FieldEdge(wrapsX: false, wrapsY: true), stamps: soup)
        #expect(tube == neighborCounts(start, wrapsX: false, wrapsY: true))
        #expect(scroll != tube)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theBuiltInRulesHonorTheEdgeToo() throws {
        // The built-in Life under a clamped edge, from a soup that reaches every side,
        // against a CPU Life whose reads past the border return the border cell (a
        // border cell then counts itself as its own off-edge neighbor, which is what
        // clamping means). Cell for cell over five generations, and not the torus.
        let soup = randomCells(count: 700, seed: 31)
        let walled = try grid(probe(.gameOfLife(), stamps: soup, edge: .clamped), generations: 5)
        var reference = stamped(soup)
        for _ in 0 ..< 5 { reference = lifeStep(reference, wrapsX: false, wrapsY: false) }
        #expect(walled == reference)
        let torus = try grid(probe(.gameOfLife(), stamps: soup), generations: 5)
        #expect(torus != walled)
        var wrappedReference = stamped(soup)
        for _ in 0 ..< 5 { wrappedReference = lifeStep(wrappedReference, wrapsX: true, wrapsY: true) }
        #expect(torus == wrappedReference)
    }

    // MARK: Readback, inputs, inject, precision, and the info the kernel sees

    @Test(.enabled(if: Snapshot.hasMetal))
    func theReadbackIsTheImage() throws {
        // The same deterministic run twice: one instance's picture at frame g - 1
        // (g generations) against another's `snapshot()` taken during frame g, which
        // reads the state that frame g - 1 left, so the same g generations.
        let soup = randomCells(count: 700, seed: 21)
        let pictured = try grid(probe(.shader(UserSimTests.lifeKernel), stamps: soup), generations: 8)
        let reader = probe(.shader(UserSimTests.lifeKernel), stamps: soup)
        reader.snapshotAtFrameCount = 9
        _ = try #require(OllinApp.image(of: reader, frame: 8))
        let snap = try #require(reader.captured)
        #expect(snap.width == 48 && snap.height == 48)
        let read = (0 ..< 48).map { y in (0 ..< 48).map { x in snap[x, y].x > 0.5 ? 1 : 0 } }
        #expect(read == pictured)
        #expect(read.joined().contains(1))
        // Before the field has run there is nothing to read.
        #expect(probe(.shader(UserSimTests.lifeKernel), stamps: []).field == nil)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anExtraLayerReachesTheKernel() throws {
        // A kernel that copies its first input: the field becomes the layer drawn into
        // it, here white on the left half, and reads zero where the layer is clear.
        let copy = Shader("""
        float4 shade(float2 uv, ShaderInfo info) { return input(info, 0); }
        """)
        let sketch = InputProbe()
        sketch.probeSim = .shader(copy)
        sketch.snapshotAtFrameCount = 3
        _ = try #require(OllinApp.image(of: sketch, frame: 2))
        let snap = try #require(sketch.captured)
        #expect(snap[5, 24].x == 1 && snap[5, 24].w == 1)
        #expect(snap[40, 24].x == 0 && snap[40, 24].w == 0)
        #expect(snap[23, 10].x == 1 && snap[24, 10].x == 0)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theInjectKernelAddsWhereTheMarkLandedAndThePrecisionKeepsIt() throws {
        // An identity step under an inject that adds 4097 per full mark. Two marked
        // frames sum to 8194, which a 32-bit float holds and a half float cannot
        // (its spacing is 4 past 4096 and 8 past 8192).
        let identity = Shader("float4 shade(float2 uv, ShaderInfo info) { return cell(info); }")
        let adder = Shader("""
        float4 shade(float2 uv, ShaderInfo info) {
            float4 s = cell(info);
            float4 m = mark(info);
            return float4(s.r + m.a * 4097.0, s.g, s.b, s.a);
        }
        """)
        let wide = probe(.shader(identity, inject: adder), stamps: [(x: 5, y: 5, white: 1.0)],
                         precision: .float32, stampEveryFrame: true)
        wide.snapshotAtFrameCount = 3
        _ = try #require(OllinApp.image(of: wide, frame: 2))
        let exact = try #require(wide.captured)
        #expect(exact[5, 5].x == 8194)
        #expect(exact[6, 5].x == 0)          // the mark covered its own cell only
        let half = probe(.shader(identity, inject: adder), stamps: [(x: 5, y: 5, white: 1.0)],
                         stampEveryFrame: true)
        half.snapshotAtFrameCount = 3
        _ = try #require(OllinApp.image(of: half, frame: 2))
        let rounded = try #require(half.captured)
        #expect(rounded[5, 5].x != 8194)
        #expect(abs(rounded[5, 5].x - 8194) <= 8)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theKernelSeesItsSubstepsRestAndInputCount() throws {
        // Each substep adds one to red and records the pass index and the substep
        // count; the rest state is what an untouched channel starts at.
        let counting = Shader("""
        float4 shade(float2 uv, ShaderInfo info) {
            float4 s = cell(info);
            return float4(s.r + 1.0, float(info.pass), float(info.substeps), s.a);
        }
        """)
        let sketch = probe(.shader(counting, substeps: 3, rest: SIMD4(0, 0, 0, 0.25)), stamps: [])
        sketch.snapshotAtFrameCount = 3
        _ = try #require(OllinApp.image(of: sketch, frame: 2))
        let snap = try #require(sketch.captured)
        #expect(snap[10, 10].x == 6)      // two frames of three substeps
        #expect(snap[10, 10].y == 2)      // the last pass of each frame
        #expect(snap[10, 10].z == 3)
        #expect(snap[10, 10].w == 0.25)   // the rest state's alpha, kept by the data inject
    }

    // MARK: Probes and readback

    /// The Game of Life as a kernel of one's own, the rule the built-in runs.
    static let lifeKernel = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        float n = 0.0;
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                if (dx != 0 || dy != 0) { n += step(0.5, cell(info, dx, dy).r); }
            }
        }
        float me = step(0.5, cell(info).r);
        float alive = (n == 3.0 || (me > 0.5 && n == 2.0)) ? 1.0 : 0.0;
        return float4(alive, alive, alive, 1.0);
    }
    """)

    /// One step that writes each cell's count of live neighbors into red.
    static let countKernel = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        float n = 0.0;
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                if (dx != 0 || dy != 0) { n += step(0.5, cell(info, dx, dy).r); }
            }
        }
        return float4(n, 0.0, 0.0, 1.0);
    }
    """)

    private func probe(_ sim: Sim, stamps: [(x: Int, y: Int, white: Double)],
                       edge: FieldEdge = .wrapping, precision: LayerPrecision = .float16,
                       stampEveryFrame: Bool = false) -> UserSimProbeSketch {
        let sketch = UserSimProbeSketch()
        sketch.probeSim = sim
        sketch.stamps = stamps
        sketch.edge = edge
        sketch.precision = precision
        sketch.stampEveryFrame = stampEveryFrame
        return sketch
    }

    /// The neighbor counts one step after the stamp, read back as numbers under `edge`.
    private func counts(edge: FieldEdge, stamps: [(x: Int, y: Int, white: Double)]) throws -> [[Int]] {
        let sketch = probe(.shader(UserSimTests.countKernel), stamps: stamps, edge: edge)
        sketch.snapshotAtFrameCount = 2
        _ = try #require(OllinApp.image(of: sketch, frame: 1))
        let snap = try #require(sketch.captured)
        return (0 ..< 48).map { y in (0 ..< 48).map { x in Int(snap[x, y].x.rounded()) } }
    }

    /// The rendered field decoded to 0/1 by its red byte. The headless drive draws
    /// frames 0...frame and the sim steps once per draw, so a read at `frame: g - 1`
    /// holds `g` generations past the frame-1 stamp.
    private func grid(_ sketch: Sketch, generations: Int) throws -> [[Int]] {
        let image = try #require(OllinApp.image(of: sketch, frame: generations - 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (0 ..< h).map { y in (0 ..< w).map { x in data[(y * w + x) * 4] > 127 ? 1 : 0 } }
    }

    private func randomCells(count: Int, seed: UInt64) -> [(x: Int, y: Int, white: Double)] {
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        var cells: Set<Int> = []
        while cells.count < count {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            cells.insert(Int((state >> 33) % 2304))
        }
        return cells.sorted().map { (x: $0 % 48, y: $0 / 48, white: 1.0) }
    }

    private func stamped(_ stamps: [(x: Int, y: Int, white: Double)]) -> [[Int]] {
        var g = [[Int]](repeating: [Int](repeating: 0, count: 48), count: 48)
        for s in stamps { g[s.y][s.x] = 1 }
        return g
    }

    /// One generation of Life (B3/S23) over `neighborCounts` under the same edge.
    private func lifeStep(_ g: [[Int]], wrapsX: Bool, wrapsY: Bool) -> [[Int]] {
        let n = neighborCounts(g, wrapsX: wrapsX, wrapsY: wrapsY)
        return (0 ..< 48).map { y in
            (0 ..< 48).map { x in
                n[y][x] == 3 || (g[y][x] == 1 && n[y][x] == 2) ? 1 : 0
            }
        }
    }

    /// Each cell's live neighbors, with a read past an edge wrapping or clamped to
    /// the border cell per axis, which is what the sampler does.
    private func neighborCounts(_ g: [[Int]], wrapsX: Bool, wrapsY: Bool) -> [[Int]] {
        func at(_ x: Int, _ y: Int) -> Int {
            let cx = wrapsX ? (x + 48) % 48 : min(max(0, x), 47)
            let cy = wrapsY ? (y + 48) % 48 : min(max(0, y), 47)
            return g[cy][cx]
        }
        return (0 ..< 48).map { y in
            (0 ..< 48).map { x in
                var n = 0
                for dy in -1 ... 1 { for dx in -1 ... 1 where dx != 0 || dy != 0 { n += at(x + dx, y + dy) } }
                return n
            }
        }
    }
}

/// A 48-cell field stamped with full-texel unit polygons on frame 1 (or every frame),
/// drawn 1:1, with a `snapshot()` taken during the frame the test names.
@MainActor
private final class UserSimProbeSketch: Sketch {
    override var canvasSize: CanvasSize { .square(48) }
    var probeSim: Sim = .gameOfLife()
    var stamps: [(x: Int, y: Int, white: Double)] = []
    var edge: FieldEdge = .wrapping
    var precision: LayerPrecision = .float16
    var stampEveryFrame = false
    var snapshotAtFrameCount = 0
    var captured: FieldSnapshot?
    private(set) var field: SimField?

    override func setup() {
        field = makeSimField(probeSim, scale: 1, edge: edge, precision: precision)
    }

    override func draw() {
        background(.black)
        guard let field else { return }
        if frameCount == snapshotAtFrameCount { captured = field.snapshot() }
        withField(field) {
            if frameCount == 1 || stampEveryFrame {
                noStroke()
                for s in stamps {
                    fill(Color(white: s.white))
                    let x = Double(s.x), y = Double(s.y)
                    drawPolygon([Vector2(x, y), Vector2(x + 1, y),
                                 Vector2(x + 1, y + 1), Vector2(x, y + 1)])
                }
            }
        }
        drawImage(field.image, 0, 0)
    }
}

/// A field whose kernel reads an extra layer: white over the left half each frame.
@MainActor
private final class InputProbe: Sketch {
    override var canvasSize: CanvasSize { .square(48) }
    var probeSim: Sim = .gameOfLife()
    var snapshotAtFrameCount = 0
    var captured: FieldSnapshot?
    private var field: SimField!

    override func setup() { field = makeSimField(probeSim, scale: 1) }

    override func draw() {
        background(.black)
        if frameCount == snapshotAtFrameCount { captured = field.snapshot() }
        let half = makeRenderTarget()
        withTarget(half) {
            noStroke(); fill(.white)
            drawPolygon([Vector2(0, 0), Vector2(24, 0), Vector2(24, 48), Vector2(0, 48)])
        }
        field.inputs = [half]
        withField(field) {}
        drawImage(field.image, 0, 0)
    }
}
