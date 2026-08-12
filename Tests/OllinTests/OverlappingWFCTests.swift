@testable import Ollin
import Testing

/// Pure-CPU checks on Wave Function Collapse's overlapping model: what a sample
/// teaches, and what the solver is then allowed to build out of it.
///
/// The defining property is *local indistinguishability*: every patch of the
/// output has to be a patch the sample actually contained. Nearly every way of
/// getting the algorithm wrong (a bad overlap test, a propagator that forgets a
/// direction, an off-by-one in the read-out) breaks it, so it does most of the
/// work here and each of the narrower tests pins one piece against a
/// counterfactual.
@Suite
struct OverlappingWFCTests {

    // MARK: - Samples

    /// Build a sample from rows of characters, one color per distinct character.
    /// Keeps the fixtures readable as pictures.
    private func sample(_ rows: [String]) -> Image {
        let height = rows.count
        let width = rows[0].count
        let image = Image(width: width, height: height)
        let inks: [Character: Color] = [
            ".": Color(hex: 0x101820), "#": Color(hex: 0xF0F0F0),
            "o": Color(hex: 0xE4572E), "+": Color(hex: 0x3FA7D6),
        ]
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                image[x, y] = inks[ch] ?? .white
            }
        }
        return image
    }

    /// A 2-color checkerboard: only two 3x3 patches exist (the two phases), and
    /// they can only ever follow each other, so any correct solve is a perfect
    /// checkerboard.
    private var checkerboard: Image {
        sample((0 ..< 8).map { y in
            String((0 ..< 8).map { x in (x + y) % 2 == 0 ? "#" : "." })
        })
    }

    /// Vertical stripes, two on two off. Directional: it teaches that color runs
    /// down the image forever but never sideways for more than two pixels.
    private var stripes: Image {
        sample((0 ..< 8).map { _ in
            String((0 ..< 8).map { x in x % 4 < 2 ? "#" : "." })
        })
    }

    // MARK: - Helpers

    /// Every distinct NxN patch of `image`, read as a flat list of pixel words,
    /// with the image treated as wrapping if asked.
    private func patches(of image: Image, size n: Int, wrapping: Bool) -> Set<[UInt32]> {
        var out = Set<[UInt32]>()
        let lastX = wrapping ? image.width - 1 : image.width - n
        let lastY = wrapping ? image.height - 1 : image.height - n
        guard lastX >= 0, lastY >= 0 else { return out }
        for py in 0 ... lastY {
            for px in 0 ... lastX {
                var patch: [UInt32] = []
                for y in 0 ..< n {
                    for x in 0 ..< n {
                        let c = image[(px + x) % image.width, (py + y) % image.height]
                        patch.append(word(c))
                    }
                }
                out.insert(patch)
            }
        }
        return out
    }

    /// A color as one comparable word, quantized to the 8-bit values an image
    /// actually stores.
    private func word(_ c: Color) -> UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return byte(c.red) << 24 | byte(c.green) << 16 | byte(c.blue) << 8 | byte(c.alpha)
    }

    /// The patches a model actually learned, read back through `pattern(_:)`.
    /// With symmetry on, this is a superset of the sample's own patches (it
    /// holds the turned and mirrored copies too), so it, not the raw sample, is
    /// what an output has to be built out of.
    private func learnedPatches(_ model: OverlappingWFC) -> Set<[UInt32]> {
        var out = Set<[UInt32]>()
        for i in 0 ..< model.patternCount {
            out.insert(patches(of: model.pattern(i), size: model.patternSize, wrapping: false).first ?? [])
        }
        return out
    }

    // MARK: - The defining property

    /// Every 3x3 patch of a synthesized texture is a patch the sample contained.
    /// Learned without symmetry, so the vocabulary is exactly the sample's own
    /// patches and the claim is the literal one: nothing in the output was
    /// invented. This is the test that fails if the overlap rule, the
    /// propagator, or the read-out is wrong.
    @Test func everyPatchOfTheOutputCameFromTheSample() {
        let source = stripes
        var rng = SplitMix64(seed: 7)
        let model = OverlappingWFC(learningFrom: source, patternSize: 3, symmetry: .none)
        #expect(model != nil)
        let output = model?.solve(width: 24, height: 24, using: &rng)
        #expect(output != nil)
        guard let output else { return }

        let allowed = patches(of: source, size: 3, wrapping: true)
        let produced = patches(of: output, size: 3, wrapping: false)
        #expect(!produced.isEmpty)
        #expect(produced.isSubset(of: allowed))
    }

    /// With symmetry on, the vocabulary is the sample's patches *and* their
    /// turned and mirrored copies, and the output must be built out of exactly
    /// that set: no more (nothing invented) and, on a sample with real freedom,
    /// no fewer than a couple of them (the solve isn't just repeating one patch).
    @Test func everyPatchOfTheOutputIsOneTheModelLearned() {
        let source = stripes
        var rng = SplitMix64(seed: 7)
        let model = OverlappingWFC(learningFrom: source, patternSize: 3, symmetry: .all)
        #expect(model != nil)
        guard let model, let output = model.solve(width: 24, height: 24, using: &rng) else {
            Issue.record("the model did not solve")
            return
        }

        let produced = patches(of: output, size: 3, wrapping: false)
        #expect(produced.count > 1)
        #expect(produced.isSubset(of: learnedPatches(model)))
    }

    /// The same property with the output solved as a torus: now the patches that
    /// straddle the seam have to be legal too, which is what makes the texture
    /// tile.
    @Test func aTileableOutputIsLegalAcrossItsSeam() {
        let source = stripes
        var rng = SplitMix64(seed: 11)
        let model = OverlappingWFC(learningFrom: source, patternSize: 3, symmetry: .none)
        #expect(model != nil)
        guard let model, let output = model.solve(width: 16, height: 16, tileable: true, using: &rng) else {
            Issue.record("the model did not solve")
            return
        }

        let allowed = patches(of: source, size: 3, wrapping: true)
        // Reading the output as wrapping includes every patch across the seam.
        let produced = patches(of: output, size: 3, wrapping: true)
        #expect(produced.isSubset(of: allowed))
    }

    /// A checkerboard admits exactly one answer up to its two phases, so the
    /// solver has to reproduce it exactly rather than merely legally.
    @Test func aCheckerboardResolvesToACheckerboard() {
        var rng = SplitMix64(seed: 3)
        let model = OverlappingWFC(learningFrom: checkerboard, patternSize: 3)
        let output = model?.solve(width: 12, height: 12, using: &rng)
        #expect(output != nil)
        guard let output else { return }

        let corner = word(output[0, 0])
        let other = word(output[1, 0])
        #expect(corner != other)
        for y in 0 ..< output.height {
            for x in 0 ..< output.width {
                let expected = (x + y) % 2 == 0 ? corner : other
                #expect(word(output[x, y]) == expected)
            }
        }
    }

    // MARK: - What the sample teaches

    /// A checkerboard holds exactly two distinct 3x3 patches, whichever way it is
    /// turned or mirrored, so symmetry can't invent any.
    @Test func aCheckerboardTeachesTwoPatterns() {
        let model = OverlappingWFC(learningFrom: checkerboard, patternSize: 3)
        #expect(model?.patternCount == 2)
        let plain = OverlappingWFC(learningFrom: checkerboard, patternSize: 3, symmetry: .none)
        #expect(plain?.patternCount == 2)
    }

    /// Vertical stripes are not symmetric: turning them makes horizontal stripes,
    /// which are patches the sample never held. So `.rotations` learns strictly
    /// more than `.none`, and `.all` at least as much again. This is the
    /// counterfactual that a symmetry setting does anything at all.
    @Test func symmetryTeachesTurnedCopiesOfTheSample() {
        let plain = OverlappingWFC(learningFrom: stripes, patternSize: 3, symmetry: .none)
        let turned = OverlappingWFC(learningFrom: stripes, patternSize: 3, symmetry: .rotations)
        let every = OverlappingWFC(learningFrom: stripes, patternSize: 3, symmetry: .all)
        #expect(plain != nil && turned != nil && every != nil)
        guard let plain, let turned, let every else { return }
        #expect(turned.patternCount > plain.patternCount)
        #expect(every.patternCount >= turned.patternCount)
    }

    /// What `wrapsSample` changes, on a sample small enough to count by hand: an
    /// 8x8 field with a single lit pixel in the top-left corner.
    ///
    /// Read as bounded, a 3x3 patch may only be cut from the 36 positions where
    /// it fits whole, and just one of those covers the lit pixel, so the sample
    /// teaches 2 patterns (lit-in-the-corner, and all-dark). Read as wrapping,
    /// all 64 positions are legal corners and 9 of them see the lit pixel (the
    /// three columns 6, 7, 0 by the three rows 6, 7, 0), each at a different
    /// place inside the patch: 9 patterns, plus all-dark, is 10.
    @Test func wrappingTheSampleCutsPatchesFromEveryPosition() {
        var source = Image(width: 8, height: 8, color: Color(hex: 0x101820))
        source[0, 0] = Color(hex: 0xF0F0F0)

        let bounded = OverlappingWFC(learningFrom: source, patternSize: 3, symmetry: .none,
                                     wrapsSample: false)
        let wrapped = OverlappingWFC(learningFrom: source, patternSize: 3, symmetry: .none,
                                     wrapsSample: true)
        #expect(bounded?.patternCount == 2)
        #expect(wrapped?.patternCount == 10)
    }

    /// `.rotations` means the four quarter turns and nothing else.
    ///
    /// Pinned exactly: the set it learns is the rotation-closure of the set
    /// learned with no symmetry at all. The sample is chiral (an L, which no
    /// turn can carry onto its mirror), so a set that quietly included mirrors
    /// would be strictly larger and this would fail.
    @Test func rotationsMeansTheFourTurnsAndNoMirrors() {
        let source = sample([
            "........",
            "..o.....",
            "..o.....",
            "..ooo...",
            "........",
            ".....o..",
            ".....oo.",
            "........",
        ])
        let plain = OverlappingWFC(learningFrom: source, patternSize: 3, symmetry: .none)
        let turned = OverlappingWFC(learningFrom: source, patternSize: 3, symmetry: .rotations)
        let every = OverlappingWFC(learningFrom: source, patternSize: 3, symmetry: .all)
        #expect(plain != nil && turned != nil && every != nil)
        guard let plain, let turned, let every else { return }

        var closure = Set<[UInt32]>()
        for patch in learnedPatches(plain) {
            var turn = patch
            for _ in 0 ..< 4 {
                closure.insert(turn)
                turn = rotate(turn, size: 3)
            }
        }
        #expect(learnedPatches(turned) == closure)
        // And the mirrors really are extra: a chiral sample learns more with them.
        #expect(every.patternCount > turned.patternCount)
    }

    /// A patch turned a quarter turn, for checking the closure above.
    private func rotate(_ p: [UInt32], size n: Int) -> [UInt32] {
        var out = p
        for y in 0 ..< n {
            for x in 0 ..< n {
                out[y * n + x] = p[x * n + (n - 1 - y)]
            }
        }
        return out
    }

    /// A sample read as bounded can teach patches that nothing may follow: the
    /// ones along its edges. Those have to be ruled out before the solve starts,
    /// because a pattern with no legal neighbor is never eliminated by
    /// propagation (nothing ever withdraws support from it) and would otherwise
    /// survive to be chosen, making the output quietly illegal rather than
    /// failing outright. So the output must still be built only from patches the
    /// sample held.
    /// The sample has a hard rule at top and bottom and a scatter of marks
    /// between. Read as bounded, no patch anywhere carries a rule through its
    /// middle row, so the patches that hold one along an edge have nothing that
    /// can sit above or below them: they are the stranded case. The scattered
    /// marks compose freely, so once the stranded patches are ruled out the
    /// solve still has plenty to work with, and what it builds must all have
    /// come from the sample.
    @Test func aBoundedSampleStillYieldsALegalOutput() {
        let source = sample([
            "########",
            "........",
            "..o.....",
            "........",
            ".....o..",
            "........",
            "..o.....",
            "########",
        ])
        var rng = SplitMix64(seed: 4)
        let model = OverlappingWFC(learningFrom: source, patternSize: 3, symmetry: .none,
                                   wrapsSample: false)
        #expect(model != nil)
        guard let model, let output = model.solve(width: 20, height: 20, using: &rng) else {
            Issue.record("the model did not solve")
            return
        }
        let produced = patches(of: output, size: 3, wrapping: false)
        #expect(produced.count > 1)
        #expect(produced.isSubset(of: patches(of: source, size: 3, wrapping: false)))
    }

    /// Weights are occurrence counts, so they sum to the number of patches cut:
    /// one per position per learned variant.
    @Test func weightsCountEveryPatchCut() {
        let source = checkerboard
        let model = OverlappingWFC(learningFrom: source, patternSize: 3, symmetry: .none)
        #expect(model != nil)
        guard let model else { return }
        let total = (0 ..< model.patternCount).reduce(0.0) { $0 + model.weight($1) }
        #expect(total == Double(source.width * source.height))
    }

    /// A learned pattern reads back as the little picture it stands for.
    @Test func aPatternReadsBackAsItsOwnPatch() {
        let model = OverlappingWFC(learningFrom: checkerboard, patternSize: 3, symmetry: .none)
        #expect(model != nil)
        guard let model else { return }
        for i in 0 ..< model.patternCount {
            let patch = model.pattern(i)
            #expect(patch.width == 3 && patch.height == 3)
            // Each is one phase of the board: diagonal neighbors match, edge
            // neighbors don't.
            #expect(word(patch[0, 0]) == word(patch[1, 1]))
            #expect(word(patch[0, 0]) != word(patch[1, 0]))
        }
    }

    // MARK: - Reproducibility

    /// Same sample, same seed, same texture, byte for byte. The catalog-wide
    /// promise, and the reason every choice is drawn over a fixed order.
    @Test func aSeedRepeatsTheSameTexture() {
        let source = stripes
        let model = OverlappingWFC(learningFrom: source, patternSize: 3)
        #expect(model != nil)
        guard let model else { return }

        var first = SplitMix64(seed: 99)
        var second = SplitMix64(seed: 99)
        let a = model.solve(width: 16, height: 16, using: &first)
        let b = model.solve(width: 16, height: 16, using: &second)
        #expect(a != nil && b != nil)
        guard let a, let b else { return }
        #expect(a.premultipliedPixels() == b.premultipliedPixels())
    }

    /// A different seed is free to give a different texture; on a sample with
    /// real freedom in it, it does. (The counterfactual to the test above: if
    /// solving ignored the generator, both tests would still pass separately but
    /// not together.)
    @Test func adifferentSeedExploresADifferentTexture() {
        let source = sample([
            "..........",
            ".oo...oo..",
            ".oo...oo..",
            "..........",
            "....oo....",
            "....oo....",
            "..........",
            ".oo...oo..",
        ])
        let model = OverlappingWFC(learningFrom: source, patternSize: 3)
        #expect(model != nil)
        guard let model else { return }

        var first = SplitMix64(seed: 1)
        var second = SplitMix64(seed: 2)
        let a = model.solve(width: 20, height: 20, using: &first)
        let b = model.solve(width: 20, height: 20, using: &second)
        #expect(a != nil && b != nil)
        guard let a, let b else { return }
        #expect(a.premultipliedPixels() != b.premultipliedPixels())
    }

    // MARK: - Refusals

    /// A sample smaller than one patch has nothing to teach, and says so rather
    /// than half-learning.
    @Test func aSampleSmallerThanOnePatchIsRefused() {
        let tiny = Image(width: 2, height: 2, color: .white)
        #expect(OverlappingWFC(learningFrom: tiny, patternSize: 3, wrapsSample: false) == nil)
        // Read as wrapping, the same picture does teach: every position is a
        // legal corner once the patch may run off the edge and back on.
        #expect(OverlappingWFC(learningFrom: tiny, patternSize: 3, wrapsSample: true) != nil)
    }

    /// An output smaller than one patch is refused too.
    @Test func anOutputSmallerThanOnePatchIsRefused() {
        var rng = SplitMix64(seed: 5)
        let model = OverlappingWFC(learningFrom: checkerboard, patternSize: 3)
        #expect(model?.solve(width: 2, height: 2, using: &rng) == nil)
    }
}
