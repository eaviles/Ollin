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
}
