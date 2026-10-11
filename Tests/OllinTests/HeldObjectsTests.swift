import Foundation
import Testing
@testable import Ollin

/// What a sketch holds is read through everything it holds. An eased value, an
/// instrument, or anything else the sketch advances or exports is found in a
/// stored property, and inside a struct, an array, an optional, a dictionary,
/// or an object of the sketch's own that a stored property holds; each is found
/// once, the direct properties first, and a million plain values beside them
/// cost one look.
@Suite(.serialized)
@MainActor
struct HeldObjectsTests {
    final class Holder: Sketch {
        struct Pair { let glide: Eased; let count: Int }
        final class Rig { let glide = Eased(wrappedValue: 0) }
        @Eased var direct = 0.0
        var pairs: [Pair] = []
        var inArray: [Eased] = []
        var optional: Eased?
        var byName: [String: Eased] = [:]
        let rig = Rig()
        /// The same object as the one in the array.
        var twice: Eased?
        var points: [Vector2] = []
        override var canvasSize: CanvasSize { .square(16) }
        override func setup() {
            pairs = [Pair(glide: Eased(wrappedValue: 0), count: 1)]
            inArray = [Eased(wrappedValue: 0)]
            optional = Eased(wrappedValue: 0)
            byName = ["x": Eased(wrappedValue: 0)]
            twice = inArray[0]
            points = (0..<1_000_000).map { Vector2(Double($0), 0) }
        }
        override func draw() {}
    }

    @Test func everyValueTheSketchHoldsIsFoundOnce() {
        let sketch = Holder()
        sketch.runSetup()
        let started = Date()
        let found = sketch.heldObjects(of: (any FrameAdvancing).self)
        let took = Date().timeIntervalSince(started)
        // The direct one, the struct's, the array's, the optional, the
        // dictionary's, and the object's: six, with the one held twice once.
        #expect(found.count == 6, "found \(found.count) advancing values")
        #expect(found.first === sketch.$direct, "the direct property was not first")
        #expect(found.contains { $0 === sketch.pairs[0].glide })
        #expect(found.contains { $0 === sketch.rig.glide })
        #expect(found.contains { $0 === sketch.byName["x"]! })
        #expect(took < 2, "reading the sketch took \(took) s beside a million points")
    }

    /// The sketch advances what it finds, so a value inside an array, a
    /// struct, a dictionary, or an object of the sketch's own moves once it is
    /// given somewhere to go.
    @Test func anEasedValueInsideWhatTheSketchHoldsMoves() {
        let sketch = Holder()
        sketch.runSetup()
        sketch.pairs[0].glide.wrappedValue = 100
        sketch.inArray[0].wrappedValue = 100
        sketch.byName["x"]!.wrappedValue = 100
        sketch.rig.glide.wrappedValue = 100
        for frame in 0..<6 {
            sketch.advance(time: Double(frame) / 60, deltaTime: 1.0 / 60, frameRate: 60)
        }
        #expect(sketch.pairs[0].glide.wrappedValue > 0, "the value in the struct did not move")
        #expect(sketch.inArray[0].wrappedValue > 0, "the value in the array did not move")
        #expect(sketch.byName["x"]!.wrappedValue > 0, "the value in the dictionary did not move")
        #expect(sketch.rig.glide.wrappedValue > 0, "the value in the sketch's own object did not move")
        // Held twice, it is advanced once: six frames of a half-second ease
        // from 0 toward 100, the same as a value held once.
        #expect(abs(sketch.inArray[0].wrappedValue - sketch.byName["x"]!.wrappedValue) < 1e-9,
                "the value held twice moved \(sketch.inArray[0].wrappedValue) against \(sketch.byName["x"]!.wrappedValue)")
    }
}
