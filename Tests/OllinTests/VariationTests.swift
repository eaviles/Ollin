import Metal
import Testing
@testable import Ollin

/// The variation-seed surface: every sketch is born on a seed it can name, that
/// seed drives both generators, and re-seeding reproduces a run exactly. The
/// contact-sheet test needs a GPU, so it's Metal-gated like the snapshot suite;
/// the rest is CPU-only and runs in CI.
@Suite
@MainActor
struct VariationTests {

    /// A sketch that draws its randomness into a value we can compare.
    final class Rolls: Sketch {
        override var canvasSize: CanvasSize { .square(64) }
        var samples: [Double] = []
        override func setup() {
            samples = (0..<4).map { _ in random() } + [noise(0.3, 0.7)]
        }
        override func draw() { background(.white) }
    }

    @Test func aFreshSketchIsBornOnAReadableSeed() {
        let sketch = Rolls()
        #expect((1...99_999).contains(sketch.variation))
        // Both generators start from it, so the recipe's single `seed` is honest.
        #expect(sketch.recordedRandomSeed == sketch.variation)
        #expect(sketch.recordedNoiseSeed == sketch.variation)
    }

    @Test func unseededSketchesVaryRunToRun() {
        // Ten fresh instances landing on one seed is a ~1-in-10^36 accident, so
        // a repeat here means the roll isn't rolling.
        let seeds = Set((0..<10).map { _ in Rolls().variation })
        #expect(seeds.count > 1)
    }

    @Test func seedSetsTheVariationAndReproducesTheRun() {
        let a = Rolls(), b = Rolls()
        a.seed(4242)
        b.seed(4242)
        #expect(a.variation == 4242)
        #expect(b.variation == 4242)
        a.setup()
        b.setup()
        #expect(a.samples == b.samples)          // same seed, same piece
        #expect(!a.samples.isEmpty)
    }

    @Test func adjacentSeedsGiveDifferentRuns() {
        let a = Rolls(), b = Rolls()
        a.seed(100)
        b.seed(101)
        a.setup()
        b.setup()
        #expect(a.samples != b.samples)
    }

    /// `randomSeed`/`noiseSeed` reseed one generator without claiming the whole
    /// run: the sketch's `variation` stays what it was, so the recipe still
    /// splits them into `randomSeed`/`noiseSeed` rather than a single `seed`.
    @Test func partialReseedLeavesTheVariationAlone() {
        let sketch = Rolls()
        let born = sketch.variation
        sketch.randomSeed(3)
        #expect(sketch.variation == born)
        #expect(sketch.recordedRandomSeed == 3)
        #expect(sketch.recordedNoiseSeed == born)
    }

    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
    func contactSheetTilesEverySeed() throws {
        let tile = 100
        let sheet = try #require(OllinApp.contactSheet(of: { Rolls() }, seeds: [1, 2, 3, 4],
                                                       columns: 2, tileWidth: tile))
        // The sheet is sized from the grid, not the canvas: a 2×2 of square
        // tiles (the sketch's canvas is square), each under a label strip,
        // plus the outer margin and one gutter each way.
        let margin = max(10, tile / 20), gutter = margin
        let label = max(20, Int(Double(tile) * 0.085))
        #expect(sheet.width == margin * 2 + 2 * tile + gutter)
        #expect(sheet.height == margin * 2 + 2 * (tile + label) + gutter)
    }

    /// A tile below the minimum width clamps up rather than rendering a stamp
    /// too small to judge.
    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
    func tinyTilesClampToAReadableSize() throws {
        let sheet = try #require(OllinApp.contactSheet(of: { Rolls() }, seeds: [1],
                                                       columns: 1, tileWidth: 8))
        #expect(sheet.width == 10 * 2 + 64)   // clamped to the 64px floor
    }

    /// A tile is a fresh instance per seed, so a stateful sketch can't leak its
    /// accumulation into the next tile (the reused renderer is reset per tile).
    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
    func contactSheetBuildsOneSketchPerSeed() {
        var built = 0
        _ = OllinApp.contactSheet(of: { built += 1; return Rolls() }, seeds: [7, 8, 9],
                                  columns: 3, tileWidth: 40)
        #expect(built == 3)
    }

    @Test func anEmptySeedListMakesNoSheet() {
        #expect(OllinApp.contactSheet(of: { Rolls() }, seeds: []) == nil)
    }

    // MARK: - Parameter sweeps

    /// A sketch that records what its knob and seed were at draw time, so a
    /// sweep's tiles can testify to what actually reached them.
    final class Knobbed: Sketch {
        override var canvasSize: CanvasSize { .square(64) }
        @Param(0...500) var radius = 100.0
        nonisolated(unsafe) static var seen: [(radius: Double, variation: Int)] = []
        override func draw() {
            background(.white)
            Knobbed.seen.append((radius, variation))
        }
    }

    /// The sweep applies each value through the same restore path the live
    /// hosts use, and pins every tile to one seed, so the knob is the only
    /// thing changing across the sheet.
    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
    func sweepAppliesEachValueAtOnePinnedSeed() throws {
        Knobbed.seen = []
        let sheet = OllinApp.contactSheet(of: { Knobbed() },
                                          sweeping: "radius", values: [40, 120, 360],
                                          seed: 55, tileWidth: 64)
        #expect(sheet != nil)
        #expect(Knobbed.seen.map(\.radius) == [40, 120, 360])
        #expect(Knobbed.seen.map(\.variation) == [55, 55, 55])
    }

    /// An unknown parameter name returns nil rather than rendering a sheet of
    /// defaults that silently ignores the ask.
    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
    func sweepingAnUnknownParameterMakesNoSheet() {
        #expect(OllinApp.contactSheet(of: { Knobbed() },
                                      sweeping: "nosuch", values: [1, 2]) == nil)
    }

    /// A sweep with no seed given rolls one and pins every tile to it, so an
    /// unseeded sweep still isolates the parameter.
    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
    func unseededSweepStillPinsOneSeed() {
        Knobbed.seen = []
        _ = OllinApp.contactSheet(of: { Knobbed() },
                                  sweeping: "radius", values: [10, 20, 30],
                                  tileWidth: 64)
        #expect(Set(Knobbed.seen.map(\.variation)).count == 1)
    }

    /// The sweep recipe names the knob, its values, and the pinned seed.
    @Test func sweepRecipeCarriesKnobValuesAndSeed() {
        let recipe = ExportMetadata.sheetRecipe(sweep: "radius", values: [0.5, 2],
                                                seed: 77, frame: 3, fps: 30)
        #expect(recipe.contains("\"sweep\":\"radius\""))
        #expect(recipe.contains("\"values\":[0.5,2]"))
        #expect(recipe.contains("\"seed\":77"))
        #expect(recipe.contains("\"frame\":3"))
    }
}
