import Foundation
import simd
import COllinShaders

/// One line of light for a `LineSpray`: a segment in world space with light at
/// each end and a weight. A pass scatters points along it, each point carrying
/// the line's share of light, so over many passes the line adds up to exactly
/// its `light` however many points draw it.
///
/// The light is linear RGB radiance, the numbers a lighting calculation ends
/// with, so a sketch that works in light hands it over as it is. A line named
/// as a tone and a brightness converts on the way in: `color: .orange,
/// intensity: 2` is the line whose light is `Color.orange.linearRGB * 2`.
public struct SprayLine: Sendable, Equatable {
    /// The segment's ends, world space.
    public var start: Vector3
    public var end: Vector3
    /// The light at `start`: linear RGB radiance emitted per pass, with no
    /// ceiling, so a line can shine well past white. `endLight` is the light at
    /// `end`, and the points between carry the blend.
    public var light: SIMD3<Double>
    public var endLight: SIMD3<Double>
    /// Under length sampling, this line's share of the pass's points relative to
    /// its length (2 draws twice the points, at half the light each). Ignored by
    /// per-line sampling.
    public var weight: Double

    /// A line carrying `light` (linear RGB radiance per pass) at its start and
    /// `endLight` at its end; `endLight` defaults to `light`.
    public init(from start: Vector3, to end: Vector3,
                light: SIMD3<Double>, endLight: SIMD3<Double>? = nil,
                weight: Double = 1) {
        self.start = start
        self.end = end
        self.light = light
        self.endLight = endLight ?? light
        self.weight = max(0, weight)
    }

    /// A line named as a tone and a brightness: `color` (an sRGB `Color`) times
    /// `intensity` (a linear multiplier) becomes the light at the start, and
    /// `endColor` times `endIntensity` the light at the end, each defaulting to
    /// the start's. `SprayLine(from: a, to: b)` is a white line at intensity 1.
    public init(from start: Vector3, to end: Vector3,
                color: Color = .white, endColor: Color? = nil,
                intensity: Double = 1, endIntensity: Double? = nil,
                weight: Double = 1) {
        self.init(from: start, to: end,
                  light: color.linearRGB * intensity,
                  endLight: (endColor ?? color).linearRGB * (endIntensity ?? intensity),
                  weight: weight)
    }

    /// The segment's length in world units.
    public var length: Double { start.distance(to: end) }
}

/// A flat surface in the spray, sampled over its area.
///
/// Where a ``SprayLine`` is a wire, a quad is a face: the parallelogram spanned
/// by two edges from one corner. Its points land anywhere on it, so a scene
/// made of quads is a scene of surfaces rather than a wireframe of one.
///
/// ```swift
/// SprayQuad(corner: Vector3(-1, 0, -1),
///           edge1: Vector3(2, 0, 0), edge2: Vector3(0, 0, 2),
///           color: .white, intensity: 0.6)   // a lit floor, two units square
/// ```
///
/// The light follows the same law a line's does: `light` is the **whole quad's**
/// radiance per pass, not a brightness per unit of area. Scaling a quad spreads
/// the same light over more surface rather than making it brighter, so a scene
/// that works in light per unit area multiplies by its own extent on the way in.
public struct SprayQuad: Sendable, Equatable {
    /// The corner the two edges run from, world space.
    public var corner: Vector3
    /// One edge from `corner`. With `edge2` it spans the surface.
    public var edge1: Vector3
    /// The other edge from `corner`.
    public var edge2: Vector3
    /// Linear RGB radiance emitted per pass over the whole quad, with no
    /// ceiling, so a quad can shine well past white.
    public var light: SIMD3<Double>
    /// The patch of the spray's ``LineSpray/picture`` this quad reads, in
    /// `0...1` across it, or nil to read none and stand on its `light` alone.
    public var pictureBounds: Rectangle?
    /// Under length sampling, this quad's share of the pass's points relative
    /// to its area. Ignored by per-line sampling.
    public var weight: Double

    /// A quad carrying `light` (linear RGB radiance per pass) over its surface.
    public init(corner: Vector3, edge1: Vector3, edge2: Vector3,
                light: SIMD3<Double>, pictureBounds: Rectangle? = nil, weight: Double = 1) {
        self.corner = corner
        self.edge1 = edge1
        self.edge2 = edge2
        self.light = light
        self.pictureBounds = pictureBounds
        self.weight = max(0, weight)
    }

    /// A quad named as a tone and a brightness: `color` (an sRGB `Color`) times
    /// `intensity` (a linear multiplier) becomes its light.
    public init(corner: Vector3, edge1: Vector3, edge2: Vector3,
                color: Color = .white, intensity: Double = 1,
                pictureBounds: Rectangle? = nil, weight: Double = 1) {
        self.init(corner: corner, edge1: edge1, edge2: edge2,
                  light: color.linearRGB * intensity, pictureBounds: pictureBounds, weight: weight)
    }

    /// The surface's area in world units, the length of the cross product of
    /// its two edges. A quad whose edges are parallel has none.
    public var area: Double { edge1.cross(edge2).length }
}

/// The lens a `LineSpray` scatters through: how far the plane of focus sits, how
/// fast the blur grows away from it, and how the light fades with distance.
///
/// Every sample is pushed to a random spot inside a ball whose radius is
/// `strength × defocus^power`, never smaller than `minSize`, where `defocus` is
/// the sample's distance from the focal plane along the camera's axis. Summing
/// millions of those samples *is* the blur: a line on the focal plane stays
/// crisp, one far from it dissolves, and nothing is filtered afterward.
/// The shape a lens scatters light through: the hole an out-of-focus highlight
/// takes the form of.
///
/// A sample is pushed to a random spot inside the aperture, so the aperture is
/// what a point of light too far from focus turns into. The default is round,
/// which is the ball every lens here scattered in before there was a choice.
/// An iris of straight blades gives the polygonal highlight a real camera does:
/// six blades for the hexagonal sparkle, five for the pentagon, three for a
/// triangle, and enough of them to be round again.
///
/// ```swift
/// spray.bokeh.aperture = .blades(6)                    // hexagonal sparkles
/// spray.bokeh.aperture = .blades(count: 5, rotation: .pi / 10)
/// ```
///
/// A shape no number of straight blades describes is drawn or loaded instead:
/// ``picture(_:)`` takes any `Image`, which is as readily a small render target
/// a sketch drew its own iris into as a file it loaded. Nothing is bundled.
///
/// ```swift
/// let iris = makeRenderTarget(width: 128, height: 128)
/// withTarget(iris) {
///     background(.black)
///     fill(.white)
///     drawPolygon((0 ..< 6).map { ... })
/// }
/// spray.bokeh.aperture = .picture(iris.image)
/// ```
///
/// Unchecked rather than checked `Sendable` because a drawn or loaded aperture
/// is an `Image`, which is a reference the main actor owns. The lens travels
/// with the spray, and a `LineSpray` is main-actor bound, so the reference
/// never crosses to another thread; equality is that same identity, since two
/// pictures are the same aperture when they are the same picture.
public enum Aperture: @unchecked Sendable, Equatable {
    /// The round default: a uniform spot in a ball, the scatter every picture
    /// made before there was a choice.
    case round
    /// An iris of `count` straight blades, turned by `rotation` radians. Three
    /// or more; below that there is no shape to scatter in and it reads round.
    case blades(count: Int, rotation: Double)
    /// A shape drawn or loaded: the image is read across the aperture, and a
    /// sample's light is multiplied by what it finds, so white passes and black
    /// stops. Only the red channel is read, since a mask has one number.
    case picture(Image)

    /// An iris of `count` straight blades, unturned: `.blades(6)` is the
    /// hexagonal highlight.
    public static func blades(_ count: Int) -> Aperture { .blades(count: count, rotation: 0) }

    /// How the kernel reads it: the blade count, or zero for round and for a
    /// picture, which the kernel tells apart by whether one is bound.
    var bladeCount: Int {
        guard case .blades(let count, _) = self else { return 0 }
        return count >= 3 ? count : 0
    }

    /// The turn on the blades, radians.
    var rotation: Double {
        guard case .blades(_, let rotation) = self else { return 0 }
        return rotation
    }

    /// The mask this aperture reads, if it is one.
    var picture: Image? {
        guard case .picture(let image) = self else { return nil }
        return image
    }

    public static func == (a: Aperture, b: Aperture) -> Bool {
        switch (a, b) {
        case (.round, .round):
            return true
        case (.blades(let aCount, let aTurn), .blades(let bCount, let bTurn)):
            return aCount == bCount && aTurn == bTurn
        case (.picture(let aImage), .picture(let bImage)):
            return aImage === bImage
        default:
            return false
        }
    }
}

public struct Bokeh: Sendable, Equatable {
    /// Distance from the camera to the plane of focus, along the view axis, in
    /// world units.
    public var focalDistance: Double
    /// The ball's radius per unit of defocus (world units per world unit): the
    /// aperture, in effect. 0 turns the lens into a pinhole.
    public var strength: Double
    /// The smallest ball a sample scatters in, world units, so a line exactly in
    /// focus still has a body rather than a hairline.
    public var minSize: Double
    /// The exponent the defocus distance takes before `strength` scales it. 1
    /// grows the blur in proportion to distance; 1.5 keeps the region near focus
    /// crisper and lets far things dissolve faster.
    public var power: Double
    /// How fast light fades away from the focal plane: each sample's light is
    /// multiplied by `exp(-attenuation × defocus)`. 0 keeps every sample at full
    /// light.
    public var attenuation: Double
    /// The shape light scatters through, round unless told otherwise. See
    /// ``Aperture``.
    public var aperture: Aperture = .round

    public init(focalDistance: Double, strength: Double = 0.05, minSize: Double = 0.015,
                power: Double = 1, attenuation: Double = 0, aperture: Aperture = .round) {
        self.aperture = aperture
        self.focalDistance = max(0, focalDistance)
        self.strength = max(0, strength)
        self.minSize = max(0, minSize)
        self.power = max(0, power)
        self.attenuation = max(0, attenuation)
    }
}

/// Lines of light rendered as depth of field: the sandpainting lens.
///
/// Give it an array of `SprayLine`s once. Each frame, `drawLineSpray` scatters a
/// pass of points along them on the GPU (a fresh spot on each line, then a fresh
/// spot in the bokeh ball around it, projected through the sketch's camera), adds
/// them as light into an `Accumulator`, and the running mean converges into a
/// photograph with a real lens: lines on the focal plane sharp, the rest
/// dissolved into bokeh, no blur filter anywhere. Print it with `developed`.
///
/// ```swift
/// var spray: LineSpray!
/// override func setup() {
///     spray = makeLineSpray(lines, sampling: .byLength(pointsPerPass: 50_000), passesPerFrame: 5)
///     spray.bokeh = Bokeh(focalDistance: 49, strength: 0.095)
/// }
/// override func draw() {
///     camera(.orbiting(radius: 49, azimuth: -0.46, elevation: -0.42, fieldOfView: 20 * .pi / 180))
///     drawLineSpray(spray)                                   // one frame of passes
///     drawImage(spray.developed(exposure: 500, ground: Color(hex: 0x151010)).image, 0, 0)
/// }
/// ```
///
/// Moving the camera or turning the lens restarts the average on its own: the
/// samples drawn before no longer describe the picture. `passes` says how far
/// the picture has converged. A scene that moves hands its new lines to
/// `setLines(_:)` each frame; that restarts the average too, and it is built to
/// be called every frame (nothing is allocated while the lines keep their point
/// counts, and the same lines again cost nothing at all).
///
/// Persistent, like the `Accumulator` it owns: create it once in `setup()` and
/// hold it.
@MainActor
public final class LineSpray {

    /// How a pass distributes its points over the lines.
    public enum Sampling: Sendable, Equatable {
        /// Every line gets the same number of points per pass, whatever its length.
        case perLine(Int)
        /// A pass's `pointsPerPass` points are shared out by length (times each
        /// line's `weight`), at least one per line, so a long line is drawn as
        /// densely as a short one.
        case byLength(pointsPerPass: Int)
    }

    /// The lens. Changing it restarts the average.
    public var bokeh: Bokeh

    /// A picture the quads read, or nil. Each ``SprayQuad`` names the patch of
    /// it that belongs to the quad through `pictureBounds`, and its light is
    /// multiplied by what it finds there, so a photograph or a sheet of glyphs
    /// becomes an object made of light for the lens to throw out of focus.
    ///
    /// The texels are read as **linear** light, the same units a quad's own
    /// `light` is in. Changing the picture restarts the average.
    public var picture: Image? {
        didSet {
            guard picture !== oldValue else { return }
            pictureSource = picture.map(ImageComputeTexture.init)
            reset()
        }
    }

    /// The picture as the dispatch binds it, built once when it is set rather
    /// than wrapped again every frame.
    private var pictureSource: ImageComputeTexture?

    /// The aperture's mask, bound the same way. Rebuilt when the lens changes
    /// to an aperture drawn or loaded rather than described by a blade count.
    private var apertureSource: ImageComputeTexture?
    /// The aperture the mask was built for, so it is wrapped again only when
    /// the lens actually changed shape.
    private var apertureShape: Aperture = .round

    /// The diameter, in canvas points, each sample's light spreads over. The total
    /// light is the same at any size (a wider point is dimmer), so this softens
    /// the grain without changing the exposure. 1 is the reference's one-pixel
    /// point and the cheapest to draw.
    public var pointSize: Double = 1

    /// Passes drawn per frame: more converge faster and cost proportionally.
    public var passesPerFrame: Int

    /// The lines, as given.
    public private(set) var lines: [SprayLine]

    /// The quads, as given. Empty unless a scene has surfaces in it.
    public private(set) var quads: [SprayQuad] = []

    /// How the points are shared out.
    public let sampling: Sampling

    /// The running mean the passes converge into.
    public let accumulator: Accumulator

    /// Passes accumulated so far (`accumulator.passes`).
    public var passes: Int { accumulator.passes }

    /// The running mean as an `Image`, linear light: the picture before printing.
    public var image: Image { accumulator.image }

    /// The mean printed: scaled by `exposure`, rolled off through the Reinhard
    /// curve, and laid on `ground` (see `Filter.develop(exposure:ground:)`).
    public func developed(exposure: Double, ground: Color = .black) -> RenderTarget {
        accumulator.developed(exposure: exposure, ground: ground)
    }

    /// Start the average over. Called for you when the camera, the lens, the
    /// lines, or the point size change.
    public func reset() { accumulator.reset() }

    /// Replace the lines (a scene that moves between frames). Restarts the
    /// average when the lines changed; the same lines again leave it alone, so
    /// a sketch that rebuilds its scene every draw still converges under a
    /// settled export. Cheap to call every frame: while every line keeps its
    /// point count (always under `.perLine`, and under `.byLength` while the
    /// lengths round to the same shares) the point table is kept and the line
    /// records are rewritten into a ring of buffers rather than allocated.
    public func setLines(_ lines: [SprayLine]) {
        guard lines != self.lines else { return }
        self.lines = lines
        linesChanged = true
        reset()
    }

    /// Replace the quads, the surfaces beside the lines. Restarts the average
    /// when they changed; the same quads again leave it alone, exactly as
    /// ``setLines(_:)`` does, and for the same reason.
    ///
    /// Lines and quads are one picture: both scatter into the same accumulator
    /// in the same pass, so a scene mixes wires and surfaces and prints once.
    public func setQuads(_ quads: [SprayQuad]) {
        guard quads != self.quads else { return }
        self.quads = quads
        quadsChanged = true
        reset()
    }

    // The GPU side: the line records, one line index per point, and the points.
    //
    // The records live in a ring of `MetalRenderer.maxFramesInFlight` buffers,
    // one slot written per frame at most, so a slot is only ever rewritten after
    // every frame that read it has completed; the live path's ring of vertex
    // buffers rests on the same count. A scene that changes its point counts
    // (a new line count, or `.byLength` shares that moved) rebuilds everything.
    private var lineBuffers: [ComputeBuffer<OllinSprayLine>] = []
    private var lineSlot = 0
    private var lineBuffer: ComputeBuffer<OllinSprayLine>? { lineBuffers.isEmpty ? nil : lineBuffers[lineSlot] }
    private var pointLines: ComputeBuffer<UInt32>?
    private var counts: [Int] = []
    private var pointsPerPass = 0
    // The same three for the quads, kept apart because a surface's share is its
    // area and a line's is its length, which are not the same units.
    private var quadBuffers: [ComputeBuffer<OllinSprayQuad>] = []
    private var quadSlot = 0
    private var quadBuffer: ComputeBuffer<OllinSprayQuad>? { quadBuffers.isEmpty ? nil : quadBuffers[quadSlot] }
    private var pointQuads: ComputeBuffer<UInt32>?
    private var quadCounts: [Int] = []
    private var quadPointsPerPass = 0
    private var quadsChanged = false
    /// The quads' own mark, kept apart from the lines' so one refresh cannot
    /// consume the frame the other is testing against.
    private var lastQuadWriteFrame = -1
    private var points: PingPong<OllinParticle>?
    private var pointsAllocated = 0
    private var lastSignature: Signature?
    /// Set by `setLines`, consumed by the next `record`, which is what bounds the
    /// writes to one per frame however many times the lines are set between draws.
    private var linesChanged = false
    /// The frame the ring last advanced in, so a second draw of the same frame
    /// rewrites the same slot rather than one a frame in flight may be reading.
    private var lastWriteFrame = -1

    /// What a pass depends on; a change to any of it restarts the average.
    private struct Signature: Equatable {
        var camera: Camera3D
        var bokeh: Bokeh
        var pointSize: Double
        var width: Int, height: Int
        var lines: Int
        var quads: Int
    }

    init(lines: [SprayLine], sampling: Sampling, passesPerFrame: Int, bokeh: Bokeh,
         accumulator: Accumulator) {
        self.lines = lines
        self.sampling = sampling
        self.passesPerFrame = max(1, passesPerFrame)
        self.bokeh = bokeh
        self.accumulator = accumulator
        rebuild()
        rebuildQuads()
    }

    /// Lay the lines out for the GPU from scratch: each line's record with its
    /// share, and the point-to-line table a thread reads to find its line.
    private func rebuild() {
        guard !lines.isEmpty else {
            lineBuffers = []; lineSlot = 0; counts = []; pointLines = nil; pointsPerPass = 0
            return
        }
        counts = LineSpray.pointCounts(for: lines, sampling: sampling)
        var table: [UInt32] = []
        table.reserveCapacity(counts.reduce(0, +))
        for (i, n) in counts.enumerated() {
            table.append(contentsOf: repeatElement(UInt32(i), count: n))
        }
        lineBuffers = [ComputeBuffer(LineSpray.records(for: lines, counts: counts))]
        lineSlot = 0
        pointLines = ComputeBuffer(table)
        pointsPerPass = table.count
    }

    /// The same, for the surfaces: each quad's record with its share, and the
    /// point-to-quad table a thread reads to find the quad it belongs to.
    private func rebuildQuads() {
        guard !quads.isEmpty else {
            quadBuffers = []; quadSlot = 0; quadCounts = []; pointQuads = nil; quadPointsPerPass = 0
            return
        }
        quadCounts = LineSpray.quadPointCounts(for: quads, sampling: sampling)
        var table: [UInt32] = []
        table.reserveCapacity(quadCounts.reduce(0, +))
        for (i, n) in quadCounts.enumerated() {
            table.append(contentsOf: repeatElement(UInt32(i), count: n))
        }
        quadBuffers = [ComputeBuffer(LineSpray.quadRecords(for: quads, counts: quadCounts))]
        quadSlot = 0
        pointQuads = ComputeBuffer(table)
        quadPointsPerPass = table.count
    }

    /// The quad twin of `refresh`, on the same once-a-frame rule and the same
    /// ring, so a scene whose surfaces move every frame costs no allocation
    /// while their point counts hold.
    private func refreshQuads(frame: Int) {
        guard quadsChanged else { return }
        quadsChanged = false
        let newCounts = quads.isEmpty ? [] : LineSpray.quadPointCounts(for: quads, sampling: sampling)
        guard newCounts == quadCounts, !quadBuffers.isEmpty else {
            rebuildQuads()
            lastQuadWriteFrame = frame
            return
        }
        let records = LineSpray.quadRecords(for: quads, counts: quadCounts)
        if frame != lastQuadWriteFrame {
            quadSlot = (quadSlot + 1) % MetalRenderer.maxFramesInFlight
            lastQuadWriteFrame = frame
        }
        if quadSlot < quadBuffers.count {
            quadBuffers[quadSlot].replaceContents(records)
        } else {
            quadBuffers.append(ComputeBuffer(records))
        }
    }

    /// Bring the GPU side up to date with lines set since the last pass, at
    /// most once per frame: the records are rewritten into the ring's next slot
    /// while the layout holds, and everything is rebuilt when it does not.
    private func refresh(frame: Int) {
        guard linesChanged else { return }
        linesChanged = false
        let newCounts = lines.isEmpty ? [] : LineSpray.pointCounts(for: lines, sampling: sampling)
        guard newCounts == counts, !lineBuffers.isEmpty else {
            rebuild()
            lastWriteFrame = frame
            return
        }
        let records = LineSpray.records(for: lines, counts: counts)
        if frame != lastWriteFrame {
            lineSlot = (lineSlot + 1) % MetalRenderer.maxFramesInFlight
            lastWriteFrame = frame
        }
        if lineSlot < lineBuffers.count {
            lineBuffers[lineSlot].replaceContents(records)
        } else {
            lineBuffers.append(ComputeBuffer(records))
        }
    }

    /// The GPU records: each line's ends, its light at each, and its share of a
    /// pass (`start.w`, one over its point count).
    static func records(for lines: [SprayLine], counts: [Int]) -> [OllinSprayLine] {
        var records: [OllinSprayLine] = []
        records.reserveCapacity(lines.count)
        for (i, line) in lines.enumerated() {
            let a = line.light, b = line.endLight
            records.append(OllinSprayLine(
                start: SIMD4<Float>(Float(line.start.x), Float(line.start.y), Float(line.start.z),
                                    1 / Float(counts[i])),
                end: SIMD4<Float>(Float(line.end.x), Float(line.end.y), Float(line.end.z), 0),
                startColor: SIMD4<Float>(Float(a.x), Float(a.y), Float(a.z), 0),
                endColor: SIMD4<Float>(Float(b.x), Float(b.y), Float(b.z), 0)))
        }
        return records
    }

    /// What the tests read: how many record buffers the ring holds, and the
    /// point table's identity, so a rewrite in place can be told from a rebuild.
    var ringDepth: Int { lineBuffers.count }
    var pointTable: AnyObject? { pointLines }

    /// Points per line for one pass: the same for every line, or shared by length.
    static func pointCounts(for lines: [SprayLine], sampling: Sampling) -> [Int] {
        switch sampling {
        case .perLine(let n):
            return Array(repeating: max(1, n), count: lines.count)
        case .byLength(let total):
            let weighted = lines.map { $0.length * $0.weight }
            let sum = weighted.reduce(0, +)
            guard sum > 0 else { return Array(repeating: 1, count: lines.count) }
            let perUnit = Double(max(1, total)) / sum
            return weighted.map { max(1, Int((perUnit * $0).rounded(.down))) }
        }
    }

    /// Points per quad for one pass: the same for every quad, or shared by area.
    ///
    /// Under length sampling the quads draw from a pool of their own rather
    /// than from the lines', because a length and an area are not the same
    /// units and a budget shared between them would mean nothing. The number
    /// is the same one, spent twice.
    static func quadPointCounts(for quads: [SprayQuad], sampling: Sampling) -> [Int] {
        switch sampling {
        case .perLine(let n):
            return Array(repeating: max(1, n), count: quads.count)
        case .byLength(let total):
            let weighted = quads.map { $0.area * $0.weight }
            let sum = weighted.reduce(0, +)
            guard sum > 0 else { return Array(repeating: 1, count: quads.count) }
            let perUnit = Double(max(1, total)) / sum
            return weighted.map { max(1, Int((perUnit * $0).rounded(.down))) }
        }
    }

    /// The GPU records: each quad's corner and edges, its light, the patch of
    /// the picture it reads, and its share of a pass (`corner.w`, one over its
    /// point count), which is what keeps the light the whole quad's.
    static func quadRecords(for quads: [SprayQuad], counts: [Int]) -> [OllinSprayQuad] {
        var records: [OllinSprayQuad] = []
        records.reserveCapacity(quads.count)
        for (i, quad) in quads.enumerated() {
            let bounds = quad.pictureBounds
            records.append(OllinSprayQuad(
                corner: SIMD4<Float>(Float(quad.corner.x), Float(quad.corner.y), Float(quad.corner.z),
                                     1 / Float(counts[i])),
                edge1: SIMD4<Float>(Float(quad.edge1.x), Float(quad.edge1.y), Float(quad.edge1.z), 0),
                edge2: SIMD4<Float>(Float(quad.edge2.x), Float(quad.edge2.y), Float(quad.edge2.z), 0),
                light: SIMD4<Float>(Float(quad.light.x), Float(quad.light.y), Float(quad.light.z), 0),
                texture: SIMD4<Float>(Float(bounds?.x ?? 0), Float(bounds?.y ?? 0),
                                      Float(bounds?.width ?? 0), Float(bounds?.height ?? 0))))
        }
        return records
    }

    /// The scatter kernel: one thread per point per pass. Reads its line, picks a
    /// spot along it and a spot in the bokeh ball around that spot in camera
    /// space, fades by attenuation, projects through the camera, and writes the
    /// particle the light path draws.
    static let kernel = ComputeKernel(entry: "ollin_line_spray", """
        struct OllinSprayParams {
            OllinCameraMatrices camera;
            float4 lens;   // x focal distance, y strength, z minimum size, w power
            float4 misc;   // x attenuation, y point size, z points per pass, w seed
            float4 hole;   // x blades (0 none), y rotation, z 1 when a mask is bound
        };

        kernel void ollin_line_spray(device const OllinSprayLine *lines [[buffer(0)]],
                                     device const uint *lineOf [[buffer(1)]],
                                     device OllinParticle *out [[buffer(2)]],
                                     texture2d<float> mask [[texture(0)]],
                                     constant OllinComputeUniforms &u [[buffer(10)]],
                                     constant OllinSprayParams &p [[buffer(11)]],
                                     uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            uint perPass = max(uint(p.misc.z), 1u);
            OllinSprayLine line = lines[lineOf[id % perPass]];

            // Fresh randomness per point per frame, from small seed parts.
            float3 seed = float3(float(id & 4095u), float(id >> 12u), p.misc.w);
            float t = hash13(seed);
            float3 world = mix(line.start.xyz, line.end.xyz, t);
            float3 light = mix(line.startColor.xyz, line.endColor.xyz, t) * line.start.w;

            // Into camera space; the defocus is measured along the view axis.
            float3 eye = (p.camera.view * float4(world, 1.0)).xyz;
            float defocus = abs(-eye.z - p.lens.x);
            float radius = max(pow(defocus, p.lens.w) * p.lens.y, p.lens.z);
            // The aperture: the shape the sample is scattered through, which is
            // what a point too far from focus turns into. Round is the ball,
            // untouched; blades place the sample in the polygon exactly; a
            // mask takes the square and lets the picture say what passes.
            float3 spot = seed + float3(7.3, 1.9, 4.1);
            uint blades = uint(p.hole.x);
            if (blades >= 3u) {
                eye += bladeSample(spot, blades, p.hole.y) * radius;
            } else if (p.hole.z > 0.5) {
                float2 uv;
                float3 offset = maskSample(spot, uv);
                constexpr sampler maskSampler(filter::linear, address::clamp_to_edge);
                eye += offset * radius;
                light *= mask.sample(maskSampler, uv, level(0)).r;
            } else {
                eye += ballSample(spot) * radius;
            }
            light *= exp(-defocus * p.misc.x);

            float4 screen = ollin_project_eye(p.camera, eye, u.resolution);
            OllinParticle o;
            o.velocity = float2(0.0);
            o.life = 1.0;
            o.seedA = 0.0;
            o.seedB = 0.0;
            if (screen.w <= 0.0) {          // behind the camera: draw nothing
                o.position = float2(-16.0);
                o.size = 0.0;
                o.color = float4(0.0);
                out[id] = o;
                return;
            }
            // A point's whole light lands in its disc: alpha spreads it over the
            // disc's area in canvas points, so the exposure is the same at any size.
            float size = max(p.misc.y, 1e-3);
            o.position = screen.xy;
            o.size = size;
            o.color = float4(light, 1.27323954474 / (size * size));
            out[id] = o;
        }
        """)

    /// The quad scatter kernel: one thread per point per pass over the surfaces.
    ///
    /// The same lens and the same deposit as the lines'. What differs is the
    /// sample: two numbers place it anywhere on the parallelogram, and the same
    /// two read the picture at the matching spot, so a texel travels with the
    /// place it belongs to rather than with the thread.
    static let quadKernel = ComputeKernel(entry: "ollin_quad_spray", """
        struct OllinQuadSprayParams {
            OllinCameraMatrices camera;
            float4 lens;   // x focal distance, y strength, z minimum size, w power
            float4 misc;   // x attenuation, y point size, z points per pass, w seed
            float4 where;  // x first particle this dispatch writes, yzw unused
            float4 hole;   // x blades (0 none), y rotation, z 1 when a mask is bound
        };

        kernel void ollin_quad_spray(device const OllinSprayQuad *quads [[buffer(0)]],
                                     device const uint *quadOf [[buffer(1)]],
                                     device OllinParticle *out [[buffer(2)]],
                                     texture2d<float> picture [[texture(0)]],
                                     texture2d<float> mask [[texture(1)]],
                                     constant OllinComputeUniforms &u [[buffer(10)]],
                                     constant OllinQuadSprayParams &p [[buffer(11)]],
                                     uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            uint perPass = max(uint(p.misc.z), 1u);
            OllinSprayQuad quad = quads[quadOf[id % perPass]];

            // Fresh randomness per point per frame, from small seed parts.
            float3 seed = float3(float(id & 4095u), float(id >> 12u), p.misc.w);
            float su = hash13(seed);
            float sv = hash13(seed + float3(3.7, 8.1, 2.3));
            float3 world = quad.corner.xyz + su * quad.edge1.xyz + sv * quad.edge2.xyz;
            float3 light = quad.light.xyz * quad.corner.w;

            // The picture, read where the sample landed. A patch of no size
            // means the quad carries no picture and its light stands alone.
            if (quad.texture.z > 0.0 && quad.texture.w > 0.0) {
                constexpr sampler pictureSampler(filter::linear, address::clamp_to_edge);
                float2 uv = quad.texture.xy + float2(su, sv) * quad.texture.zw;
                light *= picture.sample(pictureSampler, uv, level(0)).rgb;
            }

            // Into camera space; the defocus is measured along the view axis.
            float3 eye = (p.camera.view * float4(world, 1.0)).xyz;
            float defocus = abs(-eye.z - p.lens.x);
            float radius = max(pow(defocus, p.lens.w) * p.lens.y, p.lens.z);
            // The aperture: the shape the sample is scattered through, which is
            // what a point too far from focus turns into. Round is the ball,
            // untouched; blades place the sample in the polygon exactly; a
            // mask takes the square and lets the picture say what passes.
            float3 spot = seed + float3(7.3, 1.9, 4.1);
            uint blades = uint(p.hole.x);
            if (blades >= 3u) {
                eye += bladeSample(spot, blades, p.hole.y) * radius;
            } else if (p.hole.z > 0.5) {
                float2 uv;
                float3 offset = maskSample(spot, uv);
                constexpr sampler maskSampler(filter::linear, address::clamp_to_edge);
                eye += offset * radius;
                light *= mask.sample(maskSampler, uv, level(0)).r;
            } else {
                eye += ballSample(spot) * radius;
            }
            light *= exp(-defocus * p.misc.x);

            float4 screen = ollin_project_eye(p.camera, eye, u.resolution);
            OllinParticle o;
            o.velocity = float2(0.0);
            o.life = 1.0;
            o.seedA = 0.0;
            o.seedB = 0.0;
            uint slot = uint(p.where.x) + id;
            if (screen.w <= 0.0) {          // behind the camera: draw nothing
                o.position = float2(-16.0);
                o.size = 0.0;
                o.color = float4(0.0);
                out[slot] = o;
                return;
            }
            float size = max(p.misc.y, 1e-3);
            o.position = screen.xy;
            o.size = size;
            o.color = float4(light, 1.27323954474 / (size * size));
            out[slot] = o;
        }
        """)

    /// One frame: reset if anything the picture depends on changed, scatter
    /// `passesPerFrame` passes of points, and add them into the accumulator.
    func record(into drawer: Drawer, camera: Camera3D, width: Double, height: Double,
                seed: Float, frame: Int) {
        refresh(frame: frame)
        refreshQuads(frame: frame)
        if bokeh.aperture != apertureShape {
            apertureShape = bokeh.aperture
            apertureSource = bokeh.aperture.picture.map(ImageComputeTexture.init)
        }
        let lineCount = pointsPerPass * passesPerFrame
        let quadCount = quadPointsPerPass * passesPerFrame
        let count = lineCount + quadCount
        guard count > 0 else { return }

        let signature = Signature(camera: camera, bokeh: bokeh, pointSize: pointSize,
                                  width: Int(width), height: Int(height),
                                  lines: lines.count, quads: quads.count)
        if signature != lastSignature {
            lastSignature = signature
            accumulator.reset()
        }
        if points == nil || pointsAllocated != count {
            points = PingPong(count: count)
            pointsAllocated = count
        }
        guard let points else { return }

        // The lens and the print are the same for both, so the two dispatches
        // differ only in where they start writing and how many points a pass
        // spreads over their own primitive.
        func lensParams(perPass: Int, at offset: Int) -> ComputeParams {
            var params = ComputeParams()
            params.append(camera: camera, aspect: height > 0 ? width / height : 1)
            params.append(SIMD4<Float>(Float(bokeh.focalDistance), Float(bokeh.strength),
                                       Float(bokeh.minSize), Float(bokeh.power)))
            params.append(SIMD4<Float>(Float(bokeh.attenuation), Float(pointSize),
                                       Float(perPass), seed))
            if offset >= 0 { params.append(SIMD4<Float>(Float(offset), 0, 0, 0)) }
            params.append(SIMD4<Float>(Float(bokeh.aperture.bladeCount), Float(bokeh.aperture.rotation),
                                       apertureSource == nil ? 0 : 1, 0))
            return params
        }

        let write = points.write
        if let lineBuffer, let pointLines, lineCount > 0 {
            // A 1-D dispatch that may bind an aperture mask, so it takes the
            // 2-D form with a height of one, as every textured kernel here does.
            drawer.recordDispatch(RecordedDispatch(
                kernel: LineSpray.kernel, gridWidth: lineCount, gridHeight: 1,
                textures: [apertureSource],
                buffers: [lineBuffer, pointLines, write],
                params: lensParams(perPass: pointsPerPass, at: -1).bytes))
        }
        if let quadBuffer, let pointQuads, quadCount > 0 {
            // A 1-D dispatch that also binds a picture, so it takes the 2-D
            // form with a height of one, the way every textured kernel here does.
            drawer.recordDispatch(RecordedDispatch(
                kernel: LineSpray.quadKernel, gridWidth: quadCount, gridHeight: 1,
                textures: [pictureSource, apertureSource],
                buffers: [quadBuffer, pointQuads, write],
                params: lensParams(perPass: quadPointsPerPass, at: lineCount).bytes))
        }
        points.swap()

        // One accumulator, one pass count, one picture: the wires and the
        // surfaces are the same image and print together.
        drawer.withAccumulator(accumulator, passes: passesPerFrame) {
            drawer.blendMode(.add)
            drawer.recordParticles(write, count: count, style: .light)
        }
    }
}
