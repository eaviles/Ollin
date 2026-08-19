import Foundation

/// The settings of a Gray-Scott reaction-diffusion system: two chemicals spread
/// across a surface at different rates and react where they meet, and the
/// balance between how fast the first is fed in and how fast the second is
/// removed decides whether the result settles into spots, stripes, a maze, or a
/// slowly dividing coral.
///
/// `feed` and `kill` are the same two numbers the texture-space simulation
/// takes, so a pairing that gives a look there gives the same look here. The
/// presets are the well-traveled corners of that parameter space.
public struct SurfaceChemistry: Sendable, Equatable {

    /// How fast the first chemical is replenished. Higher values fill the
    /// surface in; lower values starve it.
    public var feed: Double
    /// How fast the second chemical is removed. Raising it past `feed` lets the
    /// pattern die back; lowering it lets the second chemical take over.
    public var kill: Double
    /// How fast the first chemical spreads, per step.
    public var spread: Double
    /// How fast the second chemical spreads. Keeping it well under `spread` is
    /// what makes a pattern form at all: the pattern's scale comes from the gap
    /// between the two rates.
    public var secondSpread: Double

    /// A system built from its four rates. The defaults are the coral regime,
    /// with the two spread rates at the values the reaction is classically
    /// written with. They carry over exactly, because the surface operator is
    /// scaled to the same magnitude a square grid's five-point stencil has.
    public init(feed: Double = 0.055,
                kill: Double = 0.062,
                spread: Double = 0.16,
                secondSpread: Double = 0.08) {
        self.feed = Swift.max(0, feed)
        self.kill = Swift.max(0, kill)
        self.spread = Swift.max(0, spread)
        self.secondSpread = Swift.max(0, secondSpread)
    }

    /// Branching, endlessly dividing fronts. The default, and the one that reads
    /// most like something living when it drives growth.
    public static let coral = SurfaceChemistry(feed: 0.055, kill: 0.062)
    /// Isolated dots that hold their spacing, the leopard end of the range.
    public static let spots = SurfaceChemistry(feed: 0.035, kill: 0.065)
    /// Winding corridors of even width.
    public static let maze = SurfaceChemistry(feed: 0.029, kill: 0.057)
    /// Blobs that stretch and pinch in two, over and over.
    public static let mitosis = SurfaceChemistry(feed: 0.0367, kill: 0.0649)
    /// Long drifting worms that keep rearranging.
    public static let worms = SurfaceChemistry(feed: 0.078, kill: 0.061)
}

/// Reaction-diffusion run directly on a mesh surface: the pattern grows in the
/// surface itself rather than in a texture that has to be wrapped onto it, so
/// there is no seam, no stretching, and no need for texture coordinates.
///
/// The concentrations live one per vertex and spread through the mesh's own
/// edges, weighted by the shape of the triangles around them. That weighting is
/// the whole trick: neighbors on a triangle mesh sit at unequal distances, so
/// treating them equally (the way a pixel grid can) would shear the pattern
/// wherever the triangles are stretched.
///
/// Hold one across frames and step it, the way you would a growth or a physics
/// world. `values` is the second chemical's concentration at each vertex, 0 to
/// 1, matching `mesh.positions` by index; `displaced(by:)` is the quick way to
/// see it, pushing each vertex along its normal by its concentration.
///
/// ```swift
/// // Held, seeded once:
/// let pattern = MeshReactionDiffusion(mesh: Mesh.icosphere(subdivisions: 5),
///                                     chemistry: .coral, seed: 7)
///
/// // In draw():
/// pattern.step(12)
/// drawMesh(pattern.displaced(by: 0.06))
/// ```
///
/// Cost is one pass over the vertices per step, so a few thousand vertices
/// stepped a dozen times a frame stays interactive. The mesh's topology is
/// fixed: to grow the surface as the pattern develops, use `MeshGrowth` with the
/// `.chemical` driver instead.
public final class MeshReactionDiffusion {

    /// The surface the pattern lives on. Its topology never changes.
    public let mesh: Mesh
    /// The settings driving the reaction. Changing them mid-run is fine, and is
    /// the usual way to steer a pattern from one regime into another.
    public var chemistry: SurfaceChemistry

    /// The first chemical's concentration at each vertex, 0 to 1.
    public private(set) var substrate: [Double]
    /// The second chemical's concentration at each vertex, 0 to 1. This is the
    /// one that carries the visible pattern.
    public private(set) var values: [Double]

    private let operators: MeshOperators
    private let normals: [Vector3]
    /// The simulation runs on the welded surface; `remap` sends each of the
    /// caller's vertices to the shared one it merged into.
    private let welded: WeldedMesh
    private var weldedSubstrate: [Double]
    private var weldedValues: [Double]
    private var rng: SplitMix64

    /// A pattern seeded on `mesh`. The surface starts full of the first chemical
    /// with a few random patches of the second, which is what the pattern grows
    /// out from; `patches` sets how many, and the same seed always places them
    /// the same way.
    ///
    /// - Parameters:
    ///   - mesh: The surface to run on. Its coincident vertices are welded
    ///     first, so the flat-shaded meshes the generators produce spread as one
    ///     surface rather than as loose triangles.
    ///   - chemistry: The reaction settings.
    ///   - patches: How many patches of the second chemical to start from.
    ///   - patchRadius: Each patch's radius, as a fraction of the mesh's size.
    ///   - seed: The random seed placing the patches.
    public init(mesh: Mesh,
                chemistry: SurfaceChemistry = .coral,
                patches: Int = 12,
                patchRadius: Double = 0.06,
                seed: UInt64 = 0) {
        self.mesh = mesh
        self.chemistry = chemistry
        self.rng = SplitMix64(seed: seed)

        let welded = WeldedMesh(mesh)
        self.welded = welded
        self.operators = MeshOperators(positions: welded.positions, triangles: welded.triangles)
        self.normals = mesh.normals.count == mesh.positions.count
            ? mesh.normals
            : mesh.withSmoothNormals().normals

        self.weldedSubstrate = [Double](repeating: 1, count: welded.positions.count)
        self.weldedValues = [Double](repeating: 0, count: welded.positions.count)
        self.substrate = [Double](repeating: 1, count: mesh.positions.count)
        self.values = [Double](repeating: 0, count: mesh.positions.count)
        seedPatches(count: patches, radius: patchRadius)
    }

    /// Copy the welded concentrations back onto the caller's vertex numbering,
    /// so `values` and `substrate` always line up with `mesh.positions`.
    private func publish() {
        for v in welded.remap.indices where v < substrate.count {
            let source = welded.remap[v]
            guard source < weldedSubstrate.count else { continue }
            substrate[v] = weldedSubstrate[source]
            values[v] = weldedValues[source]
        }
    }

    /// Drop `count` round patches of the second chemical at random vertices,
    /// each reaching `radius` (a fraction of the mesh's longest side) around it.
    /// Called once at init; call it again to re-seed a settled pattern.
    ///
    /// A patch is half substrate and a quarter reagent rather than pure reagent.
    /// That is the standard seed, and it matters: with no substrate left in the
    /// patch there is nothing for the reagent to react with, so it decays before
    /// enough substrate can diffuse in and the pattern dies instead of igniting.
    public func seedPatches(count: Int, radius: Double = 0.06) {
        let positions = welded.positions
        guard !positions.isEmpty else { return }
        let extent = Swift.max(mesh.size.x, Swift.max(mesh.size.y, mesh.size.z))
        // Floored at a few edge lengths across. A patch only a vertex or two
        // wide diffuses away faster than the reaction can take hold, so on a
        // fine mesh a radius given as a fraction of the whole form would seed
        // patterns that never ignite.
        let reach = Swift.max(extent * radius, operators.meanEdgeLength * 3)
        for _ in 0 ..< Swift.max(count, 0) {
            let center = positions[Int.random(in: 0 ..< positions.count, using: &rng)]
            for v in positions.indices where positions[v].distance(to: center) < reach {
                weldedSubstrate[v] = 0.5
                weldedValues[v] = 0.25
            }
        }
        publish()
    }

    /// Set both concentrations at one vertex, the manual way to paint a seed.
    public func seed(at vertex: Int, value: Double) {
        guard vertex >= 0, vertex < welded.remap.count else { return }
        let target = welded.remap[vertex]
        guard target < weldedValues.count else { return }
        weldedValues[target] = Swift.min(Swift.max(value, 0), 1)
        weldedSubstrate[target] = 1 - weldedValues[target]
        publish()
    }

    /// Advance the reaction by `steps` steps.
    public func step(_ steps: Int = 1) {
        for _ in 0 ..< Swift.max(steps, 0) {
            (weldedSubstrate, weldedValues) = grayScottStep(operators: operators,
                                                           substrate: weldedSubstrate,
                                                           values: weldedValues,
                                                           chemistry: chemistry)
        }
        publish()
    }

    /// The concentration at a vertex, 0 to 1.
    public func value(at vertex: Int) -> Double {
        vertex >= 0 && vertex < values.count ? values[vertex] : 0
    }

    /// A copy of the mesh with every vertex pushed along its normal in
    /// proportion to the pattern there, which is the quickest way to see the
    /// result as relief. A negative `amount` carves the pattern in instead.
    public func displaced(by amount: Double) -> Mesh {
        var out = mesh
        for v in out.positions.indices where v < values.count {
            out.positions[v] = out.positions[v] + normals[v] * (values[v] * amount)
        }
        return out.withSmoothNormals()
    }
}

/// One explicit Gray-Scott step over a surface, shared by the standalone
/// pattern and the growth driver.
///
/// The reaction is the textbook one. What surface geometry changes is the
/// diffusion term, which runs through the mesh's cotangent Laplacian rather than
/// a stencil. That operator is scaled to be dimensionless, and on an evenly
/// triangulated surface it works out to the same magnitude a square grid's
/// five-point stencil has, so the feed and kill numbers behave the way they do
/// in texture space.
///
/// Sub-steps are derived rather than fixed: a badly shaped triangle raises the
/// operator's bound and an explicit step would blow up, so the step is split
/// into as many smaller ones as the worst vertex needs. On a well-shaped mesh
/// that is always one.
func grayScottStep(operators: MeshOperators,
                   substrate: [Double],
                   values: [Double],
                   chemistry: SurfaceChemistry) -> (substrate: [Double], values: [Double]) {
    let bound = operators.spectralBound
    let fastest = Swift.max(chemistry.spread, chemistry.secondSpread)
    let substeps = bound > 0 ? Swift.max(1, Int((fastest * bound).rounded(.up))) : 1
    let dt = 1.0 / Double(substeps)

    var u = substrate
    var v = values
    for _ in 0 ..< substeps {
        let lapU = operators.laplacian(of: u)
        let lapV = operators.laplacian(of: v)
        for i in u.indices where i < v.count {
            let a = u[i], b = v[i]
            let reaction = a * b * b
            let da = chemistry.spread * lapU[i] - reaction + chemistry.feed * (1 - a)
            let db = chemistry.secondSpread * lapV[i] + reaction - (chemistry.kill + chemistry.feed) * b
            u[i] = Swift.min(Swift.max(a + da * dt, 0), 1)
            v[i] = Swift.min(Swift.max(b + db * dt, 0), 1)
        }
    }
    return (u, v)
}
