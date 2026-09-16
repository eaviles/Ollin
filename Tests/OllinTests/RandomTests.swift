import Testing
@testable import Ollin

/// The seeded choice helpers: reproducibility under a seed, weight semantics
/// (zero never picked, bias holds), and the shuffle being a true permutation.
@Suite
@MainActor
struct RandomTests {

    @Test func seededChoicesReproduce() {
        let a = Sketch(), b = Sketch()
        a.randomSeed(42)
        b.randomSeed(42)
        let items = ["ink", "coral", "gold", "teal"]
        for _ in 0..<50 {
            #expect(a.randomChoice(items) == b.randomChoice(items))
        }
        for _ in 0..<50 {
            #expect(a.randomChoice(items, weights: [6, 3, 1, 0.5])
                == b.randomChoice(items, weights: [6, 3, 1, 0.5]))
        }
        #expect(a.shuffled(items) == b.shuffled(items))
    }

    @Test func uniformChoiceReachesEveryElement() {
        let sketch = Sketch()
        sketch.randomSeed(7)
        let items = [0, 1, 2, 3]
        var seen = Set<Int>()
        for _ in 0..<200 {
            seen.insert(sketch.randomChoice(items))
        }
        #expect(seen == Set(items))
    }

    @Test func zeroWeightIsNeverPicked() {
        let sketch = Sketch()
        sketch.randomSeed(3)
        for _ in 0..<500 {
            #expect(sketch.randomChoice(["a", "b", "c"], weights: [0, 1, 0]) == "b")
        }
    }

    @Test func weightsBiasTheOdds() {
        let sketch = Sketch()
        sketch.randomSeed(11)
        var first = 0
        for _ in 0..<1000 where sketch.randomChoice([1, 2], weights: [9, 1]) == 1 {
            first += 1
        }
        #expect(first > 800 && first < 980)   // ~900 expected; deterministic under the seed
    }

    @Test func shuffledIsASeededPermutation() {
        let sketch = Sketch()
        let items = Array(1...20)
        sketch.randomSeed(5)
        let once = sketch.shuffled(items)
        sketch.randomSeed(5)
        let again = sketch.shuffled(items)
        #expect(once == again)
        #expect(once.sorted() == items)
        #expect(once != items)   // seed 5 happens not to be the identity permutation
    }

    @Test func zeroWidthRangeReturnsItsBoundWithoutConsumingARoll() {
        // Load-bearing for seeded sketches (documented in Docs/Generators/Random.md):
        // an empty range short-circuits, so parameter-scaled jitter should roll
        // random(-1, 1) * amount to keep the draw sequence stable at zero.
        let a = Sketch(), b = Sketch()
        a.randomSeed(9)
        b.randomSeed(9)
        #expect(a.random(5, 5) == 5)
        #expect(a.random() == b.random())   // the zero-width call drew nothing
    }

    // MARK: The generator itself

    @Test func randomnessCarriesTheSketchSeedIntoTheStandardLibrary() {
        let a = Sketch(), b = Sketch()
        a.randomSeed(11)
        b.randomSeed(11)
        let items = ["ink", "coral", "gold", "teal"]
        for _ in 0..<50 {
            #expect(items.randomElement(using: &a.randomness)
                == items.randomElement(using: &b.randomness))
            #expect(Int.random(in: 1 ... 6, using: &a.randomness)
                == Int.random(in: 1 ... 6, using: &b.randomness))
        }
        #expect(items.shuffled(using: &a.randomness) == items.shuffled(using: &b.randomness))
    }

    @Test func randomnessIsTheSameStreamTheSketchDrawsFrom() {
        // Not a second generator beside `random()`: one stream, so a draw
        // through either spelling advances the other.
        let a = Sketch(), b = Sketch()
        a.randomSeed(3)
        b.randomSeed(3)
        _ = Double.random(in: 0 ..< 1, using: &a.randomness)
        _ = b.random()
        #expect(a.random() == b.random())
    }

    @Test func randomnessDrivesTheSeedableGenerators() {
        // The point of exposing it: Ollin's own `using:` generators land on the
        // sketch's seed rather than on a separate one the sketch has to keep.
        let a = Sketch(), b = Sketch()
        a.seed(5)
        b.seed(5)
        let rule = LSystem(axiom: "F", choices: ["F": ["F+F", "F-F", "FF"]], angle: 25)
        #expect(rule.expanded(iterations: 5, using: &a.randomness)
            == rule.expanded(iterations: 5, using: &b.randomness))
        // And a different seed reaches it, so it is genuinely the sketch's.
        let c = Sketch()
        c.seed(6)
        #expect(rule.expanded(iterations: 5, using: &c.randomness)
            != rule.expanded(iterations: 5, using: &a.randomness))
    }

    @Test func aPaletteTakesTheSketchSeededGenerator() {
        // Here rather than in PaletteTests, which is deliberately off the main
        // actor: a hop into it costs the whole run more than the test is worth.
        let a = Sketch(), b = Sketch()
        a.randomSeed(4)
        b.randomSeed(4)
        let p = Palette(.red, .green, .blue, .white)
        for _ in 0..<40 {
            #expect(p.randomElement(using: &a.randomness)
                == p.randomElement(using: &b.randomness))
        }
        #expect(p.shuffled(using: &a.randomness) == p.shuffled(using: &b.randomness))
    }

    @Test func assigningAGeneratorReplacesTheStream() {
        let sketch = Sketch()
        sketch.randomSeed(1)
        let first = sketch.random()
        sketch.randomness = SplitMix64(seed: 1)
        #expect(sketch.random() == first)
    }
}
