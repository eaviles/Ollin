import CoreGraphics
import Ollin
import Testing

/// Behavioral probes for the `.multiScaleTuring` sim, run headless on a small field
/// and read back. Three of these pin bugs that a whole-frame snapshot diff cannot
/// catch, because each one moves texture everywhere rather than shifting a silhouette,
/// and a mean difference averages that away:
///
///   - the field must **self-organize from noise** (a uniform start is a fixed point of
///     the rule, so a constant rest state leaves it black forever);
///   - the pattern must be **isotropic** (reading the pyramid rung whose texel is the
///     blur width gives one sample per feature and locks the pattern to the lattice, so
///     it comes out as right angles);
///   - the **variation radius** must average a scale's disagreement (read at a single
///     point, the finest scale wins nearly everywhere and buries the coarse ones).
///
/// Metal-gated. Like the artificial-life sims, there is no exactness claim across GPUs
/// here beyond determinism on one machine, so these are behavioral rather than pixel
/// comparisons, and the shipped snapshot covers the composed look.
@Suite
@MainActor
struct MultiScaleTuringTests {

    @Test(.enabled(if: Snapshot.hasMetal))
    func fieldOrganizesFromNoiseRatherThanStayingFlat() throws {
        // Frame 1 is the seeded noise: full range, no structure. By frame 120 the rule
        // has built structure, and the field still spans its range (normalization).
        let early = try grid(probe(), frame: 1)
        let later = try grid(probe(), frame: 120)
        #expect(spread(early) > 0.25)      // the noise seed actually filled the field
        #expect(spread(later) > 0.5)       // and every step renormalizes to the range
        // Structure means neighbours agree far more than random noise does.
        #expect(neighbourCorrelation(early) < 0.35)
        #expect(neighbourCorrelation(later) > 0.8)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func patternIsIsotropicRatherThanLockedToTheLattice() throws {
        // A box-kernel pyramid read at the blur's own rung makes a rectilinear pattern:
        // strokes run along the axes, so axis-aligned gradient energy far exceeds
        // diagonal. A Gaussian pyramid gathered as a disc keeps the two comparable.
        // Measured on this probe: reading a single tap at the matching rung scores 0.63,
        // the shipped disc gather two rungs finer scores 0.11. The threshold sits between
        // them with room on both sides, and the counterfactual was run to confirm this
        // test actually fails on the defect rather than merely passing on the fix.
        #expect(axisPreference(try grid(probe(), frame: 200)) < 0.3)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func averagingVariationLetsTheCoarseScalesHoldGround() throws {
        // With the variation read at a single point the finest scale claims a dense web
        // of pixels (its disagreement crosses zero along every contour of its own
        // structure, and least disagreement wins), so the picture is all fine grain.
        // Averaging it over each scale's own neighbourhood is what lets coarse regions
        // form, which shows up as markedly less high-frequency energy.
        let averaged = highFrequencyEnergy(try grid(probe(), frame: 200))
        let pointwise = highFrequencyEnergy(try grid(probe(variationRadius: 0), frame: 200))
        #expect(pointwise > averaged * 1.5)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func rosetteFoldsTheFieldIntoRotationalSymmetry() throws {
        // A 4-fold rosette must be (near) invariant under a quarter turn. Compared
        // against the same field's own quarter-turn, and against an unfolded field as
        // the control, so the test measures the fold rather than the sim's smoothness.
        let folded = try grid(probe(scales: .rosette(4)), frame: 200)
        let free = try grid(probe(), frame: 200)
        #expect(quarterTurnError(folded) < quarterTurnError(free) * 0.5)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func seedPicksThePatternAndReplaysIt() throws {
        let a = try grid(probe(seed: 3), frame: 60)
        let b = try grid(probe(seed: 3), frame: 60)
        let c = try grid(probe(seed: 9), frame: 60)
        #expect(meanDifference(a, b) < 0.005)    // same seed replays
        #expect(meanDifference(a, c) > 0.05)     // a different seed is a different field
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aFieldOnlyReadFromStillSteps() throws {
        // A Turing field needs no seeding, so a sketch that never opens a withField
        // block is the natural way to write one. Reading it has to keep it running, or
        // it sits at its noise seed and the sketch shows a black square with no hint why.
        let read = try grid(ReadOnlyTuringSketch(), frame: 120)
        #expect(neighbourCorrelation(read) > 0.8)
    }

    // MARK: Readback helpers

    /// A configured probe. `Sketch`'s init is `required`, so settings ride stored
    /// properties rather than an initializer.
    private func probe(scales: [TuringScale] = TuringScale.ladder, seed: Double = 7,
                       variationRadius: Double? = nil) -> TuringProbeSketch {
        let sketch = TuringProbeSketch()
        sketch.turingSeed = seed
        sketch.scales = variationRadius.map { r in
            scales.map {
                TuringScale(activatorRadius: $0.activatorRadius, inhibitorRadius: $0.inhibitorRadius,
                            amount: $0.amount, weight: $0.weight, symmetry: $0.symmetry,
                            variationRadius: r)
            }
        } ?? scales
        return sketch
    }

    /// The rendered field as a 0…1 luminance grid.
    private func grid(_ sketch: Sketch, frame: Int) throws -> [[Double]] {
        let image = try #require(OllinApp.image(of: sketch, frame: frame))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (0 ..< h).map { y in (0 ..< w).map { x in Double(data[(y * w + x) * 4]) / 255 } }
    }

    private func spread(_ g: [[Double]]) -> Double {
        let flat = g.flatMap { $0 }
        return (flat.max() ?? 0) - (flat.min() ?? 0)
    }

    /// Correlation between each texel and its right-hand neighbour: near 0 for noise,
    /// near 1 once the field has organized into smooth structure.
    private func neighbourCorrelation(_ g: [[Double]]) -> Double {
        var a: [Double] = [], b: [Double] = []
        for row in g {
            for x in 0 ..< row.count - 1 { a.append(row[x]); b.append(row[x + 1]) }
        }
        let ma = a.reduce(0, +) / Double(a.count), mb = b.reduce(0, +) / Double(b.count)
        var cov = 0.0, va = 0.0, vb = 0.0
        for i in 0 ..< a.count {
            let da = a[i] - ma, db = b[i] - mb
            cov += da * db; va += da * da; vb += db * db
        }
        return (va > 0 && vb > 0) ? cov / (va * vb).squareRoot() : 0
    }

    /// How strongly the field's edges prefer the axes, from the distribution of gradient
    /// directions: the gradient-energy-weighted mean of cos(4θ). An edge running along an
    /// axis scores +1, one running at 45° scores −1, and a field with no directional
    /// preference averages to 0. The fourth harmonic is the right one because rectilinear
    /// structure is 90°-periodic, and comparing gradient *magnitudes* along the axes
    /// against the diagonals does not separate the two cases (a diagonal step across a
    /// vertical edge crosses it about as steeply as a horizontal one does).
    ///
    /// Sobel rather than central differences, since Sobel's diagonal neighbours keep the
    /// operator itself from favouring the axes it is being used to measure.
    private func axisPreference(_ g: [[Double]]) -> Double {
        var weighted = 0.0, total = 0.0
        for y in 1 ..< g.count - 1 {
            for x in 1 ..< g[y].count - 1 {
                let gx = (g[y - 1][x + 1] + 2 * g[y][x + 1] + g[y + 1][x + 1])
                       - (g[y - 1][x - 1] + 2 * g[y][x - 1] + g[y + 1][x - 1])
                let gy = (g[y + 1][x - 1] + 2 * g[y + 1][x] + g[y + 1][x + 1])
                       - (g[y - 1][x - 1] + 2 * g[y - 1][x] + g[y - 1][x + 1])
                let energy = gx * gx + gy * gy
                guard energy > 1e-9 else { continue }
                // cos(4θ) = ((gx² − gy²)² − 4gx²gy²) / (gx² + gy²)²
                let cos4 = ((gx * gx - gy * gy) * (gx * gx - gy * gy) - 4 * gx * gx * gy * gy)
                         / (energy * energy)
                weighted += energy * cos4
                total += energy
            }
        }
        return total > 0 ? weighted / total : 0
    }

    /// How much of the field sits at the finest wavelength: the mean difference between
    /// a texel and the average of its four neighbours (a discrete Laplacian magnitude).
    private func highFrequencyEnergy(_ g: [[Double]]) -> Double {
        var total = 0.0, n = 0.0
        for y in 1 ..< g.count - 1 {
            for x in 1 ..< g[y].count - 1 {
                let mean = (g[y][x - 1] + g[y][x + 1] + g[y - 1][x] + g[y + 1][x]) / 4
                total += abs(g[y][x] - mean); n += 1
            }
        }
        return total / n
    }

    /// Mean absolute difference between the field and itself turned a quarter turn about
    /// the center: small when the field carries 4-fold symmetry.
    private func quarterTurnError(_ g: [[Double]]) -> Double {
        let n = g.count
        var total = 0.0, count = 0.0
        for y in 0 ..< n {
            for x in 0 ..< g[y].count {
                total += abs(g[y][x] - g[x][n - 1 - y]); count += 1
            }
        }
        return total / count
    }

    private func meanDifference(_ a: [[Double]], _ b: [[Double]]) -> Double {
        var total = 0.0, n = 0.0
        for y in 0 ..< min(a.count, b.count) {
            for x in 0 ..< min(a[y].count, b[y].count) {
                total += abs(a[y][x] - b[y][x]); n += 1
            }
        }
        return total / n
    }
}

/// A small square Turing field drawn raw, full-canvas, for readback. Square so the
/// symmetry probe can turn it a quarter turn without resampling. Configured through
/// stored properties set right after construction (`Sketch`'s init is `required`, so a
/// probe takes its settings the way `RipplesProbeSketch` does rather than through one).
@MainActor
private final class TuringProbeSketch: Sketch {
    override var canvasSize: CanvasSize { .square(128) }
    var scales: [TuringScale] = TuringScale.ladder
    var turingSeed: Double = 7

    private var field: SimField!

    override func setup() {
        field = simField(.multiScaleTuring(scales: scales, seed: turingSeed), scale: 1)
    }

    override func draw() {
        background(.black)
        withField(field) {}
        drawImage(field.image, 0, 0)
    }
}

/// The same field with no `withField` block at all, the shape a self-organizing sim
/// invites: reading it is the only thing keeping it stepping.
@MainActor
private final class ReadOnlyTuringSketch: Sketch {
    override var canvasSize: CanvasSize { .square(128) }
    private var field: SimField!

    override func setup() { field = simField(.multiScaleTuring(seed: 7), scale: 1) }

    override func draw() {
        background(.black)
        drawImage(field.image, 0, 0)
    }
}
