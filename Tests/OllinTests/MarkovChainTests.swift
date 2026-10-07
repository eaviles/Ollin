import Testing
import Ollin

/// The chain is a pure value, so it is checked by what it produces: walks a
/// source forces, twins that differ in one setting, and a declared table
/// against the sequence it was counted from.
@Suite struct MarkovChainTests {

    /// The walk a seed gives is pinned, so a change to the generator or to the
    /// way a successor is chosen cannot quietly move a chain someone tuned.
    @Test func aSeededWalkIsPinned() {
        let source = [0, 1, 0, 2, 0, 3, 1, 2, 3, 0, 2, 1, 1, 0, 3, 3, 2]
        var chain = MarkovChain(learning: source, order: 2, seed: 11, loops: true)
        chain.start(with: [0, 1])
        #expect(chain.next(40) == [0, 3, 1, 2, 3, 0, 2, 0, 1, 0, 3, 3, 2, 0, 1, 0, 2, 1, 1, 0,
                                   3, 1, 2, 3, 0, 2, 0, 3, 1, 2, 3, 0, 2, 0, 3, 3, 2, 0, 1, 0])
    }

    @Test func aChainWithOneWayThroughRepeatsItExactly() {
        var chain = MarkovChain(learning: [0, 1, 2], seed: 1, loops: true)
        chain.start(at: 0)
        #expect(chain.next(9) == [1, 2, 0, 1, 2, 0, 1, 2, 0])
    }

    /// Looking back further is the whole reason `order` exists. This sequence
    /// is ambiguous at order 1 and completely determined at order 2, so the two
    /// chains are a counterfactual pair over identical training data.
    @Test func alongerMemoryResolvesWhatAShortOneCannot() {
        let source = ["a", "b", "a", "c"]

        var deep = MarkovChain(learning: source, order: 2, seed: 3, loops: true)
        deep.start(with: ["c", "a"])
        #expect(deep.next(8) == ["b", "a", "c", "a", "b", "a", "c", "a"])

        // At order 1, "a" is followed by "b" half the time and "c" the other
        // half, so the same walk cannot come out fixed.
        var shallow = MarkovChain(learning: source, order: 1, seed: 3, loops: true)
        shallow.start(at: "a")
        let afterA = shallow.next(200).enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
        #expect(Set(afterA) == ["b", "c"])
    }

    @Test func theSameSeedWalksTheSameWayAndAnotherDoesNot() {
        let source = [0, 1, 0, 2, 0, 3, 1, 2, 3, 0, 2, 1]
        var one = MarkovChain(learning: source, seed: 11)
        var same = MarkovChain(learning: source, seed: 11)
        var other = MarkovChain(learning: source, seed: 12)
        one.start(at: 0); same.start(at: 0); other.start(at: 0)

        let walk = one.next(300)
        #expect(walk == same.next(300))
        #expect(walk != other.next(300))
        // Resetting rewinds the randomness as well as the position.
        one.reset()
        one.start(at: 0)
        #expect(one.next(300) == walk)
    }

    @Test func anUnseenContextFallsBackRatherThanStopping() {
        var chain = MarkovChain(learning: [1, 2, 3], order: 2, seed: 5)
        chain.start(with: [99, 98])          // never seen, at any length
        let next = chain.next()
        #expect(next != nil)
        #expect([1, 2, 3].contains(next!))

        var empty = MarkovChain<Int>(seed: 1)
        #expect(empty.next() == nil)
        #expect(empty.isEmpty)
    }

    /// The counts a chain learned are readable, which is what lets a sketch
    /// draw one. They come back most likely first.
    @Test func whatItLearnedCanBeReadBackAsProbabilities() {
        var chain = MarkovChain<String>(seed: 1)
        chain.learn(["x", "y", "x", "y", "x", "y", "x", "z"])

        let after = chain.continuations(after: ["x"])
        #expect(after.count == 2)
        #expect(after[0].element == "y")
        #expect(abs(after[0].probability - 0.75) < 1e-9)
        #expect(abs(after[1].probability - 0.25) < 1e-9)
        #expect(abs(after.reduce(0) { $0 + $1.probability } - 1) < 1e-9)
    }

    /// Nothing a chain decides may depend on the order a dictionary happens to
    /// hand its keys back, so the vocabulary is kept in the order it was first
    /// seen and every choice is made over an array.
    @Test func theVocabularyIsInTheOrderItWasFirstSeen() {
        var chain = MarkovChain<String>(seed: 1)
        chain.learn(["c", "a", "b", "a", "c"])
        #expect(chain.vocabulary == ["c", "a", "b"])
    }

    @Test func learningTheSamePhraseTwiceMakesItTwiceAsLikely() {
        var chain = MarkovChain<Int>(seed: 1)
        chain.learn([0, 1])
        chain.learn([0, 1])
        chain.learn([0, 2])
        let after = chain.continuations(after: [0])
        #expect(after[0].element == 1)
        #expect(abs(after[0].probability - 2.0 / 3.0) < 1e-9)
    }

    // MARK: - Declared counts

    /// A table of counts and the sequence it was counted from are one chain:
    /// every transition is declared under the context a sequence would have
    /// given it, in the same order, so the two walk the same way.
    @Test func declaredCountsWalkLikeTheSequenceTheyWereCountedFrom() {
        let source = [0, 1, 0, 2, 0, 3, 1, 2, 3, 0, 2, 1, 1, 0, 3, 3, 2]
        let learned = MarkovChain(learning: source, order: 2, seed: 7)

        var declared = MarkovChain<Int>(order: 2, seed: 7)
        for (index, element) in source.enumerated() {
            declared.learn(element, after: Array(source[max(0, index - 2)..<index]))
        }

        #expect(declared.vocabulary == learned.vocabulary)
        for context in [[0, 1], [3, 0], [2], [], [9, 9]] {
            let a = declared.continuations(after: context), b = learned.continuations(after: context)
            #expect(a.map(\.element) == b.map(\.element))
            #expect(zip(a, b).allSatisfy { abs($0.probability - $1.probability) < 1e-12 })
        }
        var one = learned, two = declared
        one.start(with: [0, 1]); two.start(with: [0, 1])
        #expect(one.next(200) == two.next(200))
    }

    /// `times` is the count, not a repeat of the call's side effects: one call
    /// with 3 is three calls with 1.
    @Test func timesCountsAsThatManyOccurrences() {
        var once = MarkovChain<String>(seed: 1)
        once.learn("b", after: ["a"], times: 3)
        once.learn("c", after: ["a"])
        var thrice = MarkovChain<String>(seed: 1)
        for _ in 0..<3 { thrice.learn("b", after: ["a"]) }
        thrice.learn("c", after: ["a"])

        let after = once.continuations(after: ["a"])
        #expect(after.map(\.element) == thrice.continuations(after: ["a"]).map(\.element))
        #expect(abs(after[0].probability - 0.75) < 1e-12)
        #expect(abs(after[1].probability - 0.25) < 1e-12)

        var none = MarkovChain<String>(seed: 1)
        none.learn("b", after: ["a"], times: 0)
        none.learn("b", after: ["a"], times: -4)
        #expect(none.isEmpty)
    }

    /// A declared order-2 table backs off like a learned one: a context it
    /// never saw whole falls to what followed its last element, summed over
    /// every pair that ended there.
    @Test func aDeclaredContextBacksOffToItsShorterTails() {
        var chain = MarkovChain<String>(order: 2, seed: 2)
        chain.learn("w", after: ["r", "k"], times: 6)
        chain.learn("y", after: ["w", "k"], times: 3)
        chain.learn("w", after: ["w", "k"], times: 1)

        // Seen whole.
        let whole = chain.continuations(after: ["w", "k"])
        #expect(whole.map(\.element) == ["y", "w"])
        #expect(abs(whole[0].probability - 0.75) < 1e-12)
        // Never seen whole: "b" before "k" falls to everything after "k".
        let tail = chain.continuations(after: ["b", "k"])
        #expect(tail.map(\.element) == ["w", "y"])
        #expect(abs(tail[0].probability - 0.7) < 1e-12)
        // Nothing after "y" at all: how often each element came.
        #expect(chain.continuations(after: ["y"]).map(\.element) == ["w", "y"])
    }

    /// Only the last `order` elements of a declared context are read.
    @Test func aContextLongerThanTheOrderIsReadByItsTail() {
        var long = MarkovChain<Int>(order: 1, seed: 4)
        long.learn(5, after: [1, 2, 3])
        var short = MarkovChain<Int>(order: 1, seed: 4)
        short.learn(5, after: [3])
        #expect(long.continuations(after: [3]).map(\.element) == [5])
        #expect(short.continuations(after: [3]).map(\.element) == [5])
        #expect(long.continuations(after: [2]).map(\.element) == [5])   // the empty tail
    }
}
