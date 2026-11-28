import Foundation
import Metal
import Testing
@testable import Ollin

/// What a layer holds, read from the sketch's own code: a layer shows what this
/// frame drew into it, whichever layer the sketch opened first; a layer no
/// frame drew into is empty; a persistent layer's last frame is its last
/// frame on a frame that leaves it alone. Each reading is the linear frame, as
/// in `EffectInvariantTests`, whose probe and reader these use.
@Suite(.enabled(if: Snapshot.hasMetal))
@MainActor
struct LayerBookkeepingTests {
    typealias Probe = EffectInvariantTests.Probe
    typealias Frame = EffectInvariantTests.Frame

    private func render(side: Int = 32, _ body: @escaping @MainActor (Probe) -> Void) throws -> Frame {
        try EffectInvariantTests.render(side: side, body)
    }

    /// A sketch that runs frame after frame, every frame rendered: `tick` counts
    /// the frames drawn, and a feedback layer nothing reads keeps the drive
    /// rendering the frames before the one asked for.
    private func running(side: Int = 32, frame: Int, feedback: Bool = false, accumulator: Bool = false,
                         layers: Int = 0, notes: Notes? = nil,
                         _ body: @escaping @MainActor (Probe, Int, [RenderTarget]) -> Void) throws -> Frame {
        let probe = Probe(); probe.holds = false; probe.side = side
        defer { notes?.said = probe.drawer.drawerNotes }
        var tick = 0
        var kept: [RenderTarget] = []
        var drive: Feedback?
        probe.prepare = { s in
            if feedback { s.feedback = s.makeFeedback() }
            if accumulator { s.accumulator = s.makeAccumulator() }
            kept = (0 ..< layers).map { _ in s.makeRenderTarget() }
            drive = s.makeFeedback(scale: 0.25)
        }
        probe.body = { s in
            s.background(.clear)
            if let drive { s.withFeedback(drive) { _ in } }
            body(s, tick, kept)
            tick += 1
        }
        return try EffectInvariantTests.render(probe, frame: frame)
    }

    /// What the sketch's drawer said to its author over a run.
    final class Notes { var said: Set<String> = [] }

    private func square(_ s: Sketch, _ column: Int, row: Int = 0) {
        s.noStroke(); s.fill(.white); s.drawRect(Double(column) * 8, Double(row) * 8, 8, 8)
    }

    /// Alpha at the middle of the 8-pixel cell at `column`, `row`.
    private func cell(_ f: Frame, _ column: Int, _ row: Int = 0) -> Double {
        f.value(column * 8 + 4, row * 8 + 4, 3)
    }

    // MARK: The order layers are filled in

    /// A feedback layer that draws a plain layer opened after it shows that
    /// layer's picture of this frame.
    @Test func aFeedbackLayerCanShowALayerOpenedAfterIt() throws {
        let f = try running(frame: 2, feedback: true) { s, tick, _ in
            let fb = s.feedback!, later = s.makeRenderTarget()
            s.withFeedback(fb) { _ in s.drawImage(later.image, 0, 0) }
            s.withTarget(later) { self.square(s, tick) }
            s.drawImage(fb.image, 0, 0)
        }
        #expect(cell(f, 2) > 0.99 && cell(f, 1) == 0, "this frame's square reads \(cell(f, 2)), the frame before's \(cell(f, 1))")
    }

    /// A feedback layer's block that draws a filter's result made the same frame
    /// shows it: last frame blurred and drawn back is `previous` in a layer, that
    /// layer filtered, and the result drawn in the block.
    @Test func aFeedbackBlockShowsAFiltersResultOfTheSameFrame() throws {
        let f = try running(frame: 2, feedback: true) { s, tick, _ in
            let fb = s.feedback!, last = s.makeRenderTarget()
            s.withTarget(last) { s.drawImage(fb.previous, 0, 0) }
            s.withFeedback(fb) { _ in
                s.drawImage(last.filtered(.invert()).filtered(.invert()).image, 0, 0)
                self.square(s, tick)
            }
            s.drawImage(fb.image, 0, 0)
        }
        // Every frame's square is still there: each frame drew the one before back.
        #expect(cell(f, 0) > 0.99 && cell(f, 1) > 0.99 && cell(f, 2) > 0.99,
                "the three frames' squares read \(cell(f, 0)), \(cell(f, 1)), \(cell(f, 2))")
    }

    /// A plain layer that draws an accumulator's mean shows the mean with this
    /// frame's pass in it.
    @Test func aLayerShowsAnAccumulatorsMeanOfTheSameFrame() throws {
        func shown(throughALayer: Bool) throws -> Frame {
            try running(frame: 0, accumulator: true) { s, tick, _ in
                let acc = s.accumulator!
                let copy = s.makeRenderTarget()
                if throughALayer { s.withTarget(copy) { s.drawImage(acc.image, 0, 0) } }
                s.withAccumulator(acc) { self.square(s, 1) }
                s.drawImage(throughALayer ? copy.image : acc.image, 0, 0)
            }
        }
        let direct = try shown(throughALayer: false), copied = try shown(throughALayer: true)
        #expect(cell(direct, 1) > 0.99)
        #expect(copied.worst(against: direct).by == 0, "through a layer the first frame's mean reads \(cell(copied, 1))")
    }

    /// A chain of three layers opened in the reverse of the order they read in
    /// shows the last link's picture in the first, with a filter in the chain
    /// or without one.
    @Test(arguments: [true, false])
    func aChainOpenedBackwardsIsFilledForwards(throughAFilter: Bool) throws {
        let f = try render { s in
            s.background(.clear)
            let a = s.makeRenderTarget(), b = s.makeRenderTarget(), c = s.makeRenderTarget()
            s.withTarget(a) { s.drawImage(b.image, 0, 0); self.square(s, 0) }
            s.withTarget(b) {
                s.drawImage((throughAFilter ? c.filtered(.invert()).filtered(.invert()) : c).image, 0, 0)
                self.square(s, 1)
            }
            s.withTarget(c) { self.square(s, 2) }
            s.drawImage(a.image, 0, 0)
        }
        #expect(cell(f, 0) > 0.99 && cell(f, 1) > 0.99 && cell(f, 2) > 0.99,
                "the three squares read \(cell(f, 0)), \(cell(f, 1)), \(cell(f, 2))")
    }

    /// Two layers that draw each other's image are not a hang: the one opened
    /// first is drawn first and shows the other as the frame before left it.
    @Test func twoLayersThatDrawEachOtherAreAFrameLateOnOneEdge() throws {
        let notes = Notes()
        let f = try running(frame: 2, layers: 2, notes: notes) { s, tick, kept in
            let a = kept[0], b = kept[1]
            s.withTarget(a) { s.drawImage(b.image, 0, 8); self.square(s, tick, row: 0) }
            s.withTarget(b) { s.drawImage(a.image, 0, 16); self.square(s, tick, row: 0) }
            s.drawImage(b.image, 0, 0)
        }
        // b holds its own square of this frame (row 0), a's of this frame (row 2),
        // and through a, its own of the frame before (row 3, a column back).
        #expect(cell(f, 2, 0) > 0.99, "b's own square")
        #expect(cell(f, 2, 2) > 0.99, "a's square of this frame, read through b: \(cell(f, 2, 2))")
        #expect(cell(f, 1, 3) > 0.99 && cell(f, 2, 3) == 0,
                "b as a saw it: the frame before's square reads \(cell(f, 1, 3)), this frame's \(cell(f, 2, 3))")
        // The author is told once which layer went first, over three frames.
        let said = notes.said.filter { $0.hasPrefix("Two layers draw each other's picture in one frame") }
        #expect(said.count == 1 && said.first?.contains("a plain layer (32 by 32) is drawn first here") == true, "\(notes.said)")
    }

    // MARK: A layer nothing drew into

    /// A layer kept from `setup()` that a frame draws nothing into is empty on
    /// that frame, on the canvas and as the other layer of a combine.
    @Test func aKeptLayerNoFrameDrewIntoIsEmpty() throws {
        let f = try running(frame: 1, layers: 1) { s, tick, kept in
            if tick == 0 { s.withTarget(kept[0]) { self.square(s, 0) } }
            s.drawImage(kept[0].image, 0, 0)
            let base = s.makeRenderTarget()
            s.withTarget(base) { self.square(s, 3, row: 3) }
            s.drawImage(base.combined(with: kept[0], .mix(amount: 0.5)).image, 0, 8)
        }
        #expect(cell(f, 0, 0) == 0, "the kept layer's last picture reads \(cell(f, 0, 0)) on the canvas")
        #expect(cell(f, 0, 1) == 0, "and \(cell(f, 0, 1)) through a mix of a half")
    }

    /// A filter over a layer nothing drew into is the filter over a layer whose
    /// block drew nothing.
    @Test func aFilterOverALayerNothingDrewIntoIsTheFilterOverAnEmptyLayer() throws {
        func shown(opened: Bool) throws -> Frame {
            try render { s in
                s.background(.clear)
                let layer = s.makeRenderTarget()
                if opened { s.withTarget(layer) {} }
                s.drawImage(layer.filtered(.develop(exposure: 1, ground: Color(linear: 0.25, green: 0.25, blue: 0.25))).image, 0, 0)
            }
        }
        let opened = try shown(opened: true), never = try shown(opened: false)
        #expect(opened.value(16, 16, 3) > 0.99, "the ground reaches an empty layer")
        #expect(never.worst(against: opened).by == 0, "over a layer never opened the ground reads \(never.value(16, 16, 3))")
    }

    // MARK: A persistent layer on a frame that leaves it alone

    /// `previous` on a frame with no block is what the last block drew.
    @Test func previousOnAFrameWithNoBlockIsTheLastFrameDrawn() throws {
        let f = try running(frame: 3, feedback: true) { s, tick, _ in
            let fb = s.feedback!
            if tick < 3 { s.withFeedback(fb) { _ in self.square(s, tick) } }
            s.drawImage(fb.previous, 0, 0)
            s.drawImage(fb.image, 0, 8)
        }
        #expect(cell(f, 2, 1) > 0.99, "`image` holds the last block's square")
        #expect(cell(f, 2, 0) > 0.99 && cell(f, 1, 0) == 0,
                "`previous` reads the last block's square at \(cell(f, 2, 0)) and the one before at \(cell(f, 1, 0))")
    }

    /// What `previous` names at the top of an encode: the front of the pair,
    /// and on a second encode of a frame whose first encode drew the block and
    /// flipped the pair, the texture that first encode read.
    @Test func previousIsResolvedBeforeAnyPassOfTheFrame() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        let sketch = Probe(), drawer = sketch.drawer
        let fb = sketch.makeFeedback(width: 4, height: 4)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 4, height: 4,
                                                                  mipmapped: false)
        let a = try #require(device.makeTexture(descriptor: descriptor))
        let b = try #require(device.makeTexture(descriptor: descriptor))
        let slot = MetalRenderer.FeedbackSlot(a: a, b: b, w: 4, h: 4, format: .rgba16Float, owner: fb)
        renderer.feedbackSlots[ObjectIdentifier(fb)] = slot
        func begin(frame: UInt32) {
            drawer.setComputeFrame(resolution: SIMD2(4, 4), mouse: .zero, time: 0, dt: 0, frameCount: frame)
            renderer.beginStatefulEncode(drawer)
            renderer.resolveFeedbackFronts()
        }
        begin(frame: 0)
        #expect(fb.previousLayer.texture === a, "the front of a fresh pair")
        // As the frame's block does: draw into the back, stamp the pair, flip it.
        slot.writtenIn = renderer.statefulEncodeSerial
        slot.flipped.toggle()
        begin(frame: 0)
        #expect(renderer.statefulEncodeIsRepeat)
        #expect(fb.previousLayer.texture === a, "a second encode of the frame reads what the first read")
        begin(frame: 1)
        #expect(fb.previousLayer.texture === b, "the next frame, with or without a block, reads what the block drew")
        begin(frame: 1)
        #expect(fb.previousLayer.texture === b, "and its second encode too, when no block flipped the pair")
    }

    /// A feedback layer's `background` holds through a second block of the frame.
    @Test func aFeedbackLayersBackgroundHoldsThroughASecondBlock() throws {
        let f = try running(frame: 1, feedback: true) { s, tick, _ in
            let fb = s.feedback!
            s.withFeedback(fb) { _ in s.background(Color(linear: 0, green: 0, blue: 0.5)) }
            s.withFeedback(fb) { _ in self.square(s, 0) }
            s.drawImage(fb.image, 0, 0)
        }
        #expect(cell(f, 0) > 0.99, "the second block's square")
        #expect(abs(f.value(20, 20, 2) - 0.5) < 0.002, "the first block's background reads \(f.value(20, 20, 2)) after the second")
    }

    // MARK: compose under a transform

    /// A `compose` block under a rotation, a scale, or a symmetry draws where
    /// the same drawing would without it.
    @Test(arguments: [0, 1, 2])
    func composeUnderAnyTransformDrawsWhereTheDrawingWould(which: Int) throws {
        func shown(composed: Bool) throws -> Frame {
            try render(side: 64) { s in
                s.background(.clear)
                @MainActor func mark() { s.noStroke(); s.fill(.white); s.drawRect(8, 4, 12, 6) }
                @MainActor func drawn() { if composed { s.compose { s.layer { mark() } } } else { mark() } }
                switch which {
                case 0: s.translate(32, 32); s.rotate(.pi / 2); drawn()
                case 1: s.scale(2); drawn()
                default: s.translate(32, 32); s.symmetry(4); drawn()
                }
            }
        }
        let direct = try shown(composed: false), composed = try shown(composed: true)
        #expect(direct.sum(3) > 50)
        #expect(composed.mean(against: direct) < 0.002,
                "compose strays from the drawing by a mean of \(composed.mean(against: direct)), holding \(composed.sum(3)) of alpha against \(direct.sum(3))")
    }

    // MARK: background inside a layer

    /// A wipe in a layer's second block takes the layer's earlier marks and
    /// nothing of the canvas's, drawn before, between, or after its blocks.
    @Test func aWipeInALaterBlockLeavesTheCanvasItsRuns() throws {
        let f = try render { s in
            s.background(.clear)
            let layer = s.makeRenderTarget()
            self.square(s, 0)
            s.withTarget(layer) { self.square(s, 1) }
            self.square(s, 2)
            s.withTarget(layer) { s.background(.clear); self.square(s, 3) }
            s.drawImage(layer.image, 0, 8)
        }
        #expect(cell(f, 0) > 0.99 && cell(f, 2) > 0.99, "the canvas's own squares read \(cell(f, 0)) and \(cell(f, 2))")
        #expect(cell(f, 1) == 0 && cell(f, 3) == 0, "nothing of the layer's is on the canvas's row")
        #expect(cell(f, 3, 1) > 0.99 && cell(f, 1, 1) == 0,
                "the layer holds its second block's square (\(cell(f, 3, 1))) and not its first's (\(cell(f, 1, 1)))")
    }

    /// A wipe inside a clip leaves the clip in force for what the block draws
    /// next, in the block that opened the clip and with another layer's runs
    /// recorded inside it.
    @Test(arguments: [false, true])
    func aWipeInsideAClipKeepsTheClip(aroundAnotherLayer: Bool) throws {
        let f = try render { s in
            s.background(.clear)
            let layer = s.makeRenderTarget(), inner = s.makeRenderTarget()
            s.withTarget(layer) {
                s.withClip(Rectangle(x: 0, y: 0, width: 16, height: 16)) {
                    self.square(s, 0)
                    if aroundAnotherLayer { s.withTarget(inner) { self.square(s, 3, row: 3) } }
                    s.background(.clear)
                    s.noStroke(); s.fill(.white); s.drawRect(0, 0, 32, 32)
                }
            }
            s.drawImage(layer.image, 0, 0)
            s.drawImage(inner.image, 0, 0)
        }
        #expect(cell(f, 0, 0) > 0.99 && cell(f, 1, 1) > 0.99, "inside the clip the fill reads \(cell(f, 0, 0))")
        #expect(cell(f, 2, 0) == 0 && cell(f, 0, 2) == 0, "outside the clip it reads \(cell(f, 2, 0)) and \(cell(f, 0, 2))")
        #expect(cell(f, 3, 3) == (aroundAnotherLayer ? 1 : 0), "the other layer's square reads \(cell(f, 3, 3))")
    }

    /// A wipe in a feedback layer's second block takes the first block's marks.
    @Test func aWipeInAFeedbackLayersSecondBlockTakesTheFirst() throws {
        let f = try running(frame: 1, feedback: true) { s, _, _ in
            let fb = s.feedback!
            s.withFeedback(fb) { _ in self.square(s, 0) }
            s.withFeedback(fb) { _ in s.background(.clear); self.square(s, 1) }
            s.drawImage(fb.image, 0, 0)
        }
        #expect(cell(f, 1) > 0.99 && cell(f, 0) == 0, "the second block's square reads \(cell(f, 1)), the first's \(cell(f, 0))")
    }

    // MARK: A layer the renderer makes

    /// A block on a filter's result, a generated pattern, or a layer's depth
    /// is skipped, and the sketch's author is told once why.
    @Test func drawingIntoALayerTheRendererMakesIsSkippedAndSaid() throws {
        var ran = 0
        func shown(drawingIntoTheResult: Bool) throws -> (Frame, Set<String>) {
            let probe = Probe(); probe.side = 32
            probe.body = { s in
                s.background(.clear)
                let layer = s.makeRenderTarget()
                s.withTarget(layer) { self.square(s, 0) }
                let result = layer.filtered(.invert())
                if drawingIntoTheResult {
                    s.withTarget(result) { ran += 1; self.square(s, 2) }
                    s.withTarget(layer.combined(with: result, .mix())) { ran += 1 }
                    s.withTarget(layer.depth) { ran += 1 }
                    s.withTarget(s.generate(.checkers())) { ran += 1 }
                }
                s.drawImage(result.image, 0, 0)
            }
            let frame = try EffectInvariantTests.render(probe)
            return (frame, probe.drawer.drawerNotes)
        }
        let (plain, quiet) = try shown(drawingIntoTheResult: false)
        let (drawn, notes) = try shown(drawingIntoTheResult: true)
        #expect(ran == 0, "\(ran) of the four blocks ran")
        #expect(drawn.worst(against: plain).by == 0, "the result is the filter's alone")
        let said = notes.filter { $0.hasPrefix("withTarget on a layer the renderer makes") }
        #expect(said.count == 1 && quiet.allSatisfy { !$0.hasPrefix("withTarget on") }, "the notes read \(notes)")
    }

    // MARK: An accumulator's reset

    /// `passes` after a `reset()`: nothing when the reset comes ahead of the
    /// frame's block or between frames, the frame's own passes when it comes
    /// after the block.
    @Test func resetKeepsOnlyThePassesOfTheFrameItIsCalledIn() {
        let sketch = Probe(), drawer = sketch.drawer
        let acc = sketch.makeAccumulator()
        drawer.beginFrame()
        drawer.withAccumulator(acc, passes: 1) {}
        drawer.endFrame()
        #expect(acc.passes == 1)
        acc.reset()   // between frames, as an input hook would
        #expect(acc.passes == 0 && acc.passesAtRecord == 0 && acc.needsClear)
        drawer.beginFrame()
        drawer.withAccumulator(acc, passes: 1) {}
        #expect(acc.passes == 1)
        drawer.withAccumulator(acc, passes: 2) {}
        acc.reset()   // after the frame's blocks
        #expect(acc.passes == 3 && acc.passesAtRecord == 3 && acc.needsClear, "the frame's own three passes: \(acc.passes)")
        drawer.endFrame()
        drawer.beginFrame()
        acc.reset()   // ahead of the block
        #expect(acc.passes == 0)
        drawer.withAccumulator(acc, passes: 1) {}
        #expect(acc.passes == 1 && acc.passesAtRecord == 1)
        drawer.endFrame()
    }

    // MARK: The fill order, as recorded

    /// One frame recorded on a fresh sketch, and the order its layers fill in.
    private func scheduled(_ record: (Probe, Drawer) -> Void) -> LayerSchedule {
        let sketch = Probe(), drawer = sketch.drawer
        drawer.beginFrame()
        record(sketch, drawer)
        drawer.endFrame()
        return drawer.layerSchedule()
    }

    private func same(_ got: [RenderTarget], _ want: [RenderTarget]) -> Bool {
        got.map(ObjectIdentifier.init) == want.map(ObjectIdentifier.init)
    }

    /// A frame in which no layer reads a later one is filled by kind (plain
    /// layers, feedback layers, accumulators, then filters), in recorded order
    /// within a kind.
    @Test func aFrameWithNothingToWaitForIsFilledByKind() {
        var want: [RenderTarget] = []
        let schedule = scheduled { s, d in
            let a = s.makeRenderTarget(), b = s.makeRenderTarget()
            let fb = s.makeFeedback(), acc = s.makeAccumulator()
            d.withFeedback(fb) { _ in }
            d.withTarget(a) {}
            let op = a.filtered(.invert())
            d.withAccumulator(acc, passes: 1) {}
            d.withTarget(b) {}
            want = [a, b, fb.writeLayer, acc.writeLayer, op]
        }
        #expect(same(schedule.order, want))
        #expect(schedule.early.isEmpty && schedule.unopened.isEmpty && schedule.earlyNote == nil)
    }

    /// A layer goes after the layers it reads, whatever was opened first, and
    /// a filter of it after that.
    @Test func aLayerIsFilledAfterTheLayersItReads() {
        var want: [RenderTarget] = []
        let schedule = scheduled { s, d in
            let a = s.makeRenderTarget(), b = s.makeRenderTarget(), acc = s.makeAccumulator()
            d.withTarget(a) { s.drawImage(b.image, 0, 0); s.drawImage(acc.image, 0, 0) }
            let op = a.filtered(.invert())
            d.withTarget(b) {}
            d.withAccumulator(acc, passes: 1) {}
            want = [b, acc.writeLayer, a, op]
        }
        #expect(same(schedule.order, want))
        #expect(schedule.early.isEmpty)
    }

    /// Two layers that read each other: the one that comes first by kind and
    /// record order goes early, and the note names it.
    @Test func layersThatReadEachOtherPutOneEarlyAndSayWhich() {
        var want: [RenderTarget] = [], first: [RenderTarget] = []
        let plain = scheduled { s, d in
            let a = s.makeRenderTarget(), b = s.makeRenderTarget()
            d.withTarget(a) { s.drawImage(b.image, 0, 0) }
            d.withTarget(b) { s.drawImage(a.image, 0, 0) }
            want = [a, b]; first = [a]
        }
        #expect(same(plain.order, want) && same(plain.early, first))
        let note = plain.earlyNote ?? ""
        #expect(note.contains("a plain layer (") && note.contains(") is drawn first here"), "\(note)")
        // A feedback layer opened first still goes after the plain layer it
        // reads, as it does in a frame with nothing to wait for.
        let mixed = scheduled { s, d in
            let fb = s.makeFeedback(), a = s.makeRenderTarget()
            d.withFeedback(fb) { _ in s.drawImage(a.image, 0, 0) }
            d.withTarget(a) { s.drawImage(fb.image, 0, 0) }
            want = [a, fb.writeLayer]; first = [a]
        }
        #expect(same(mixed.order, want) && same(mixed.early, first))
    }

    /// A feedback layer's last frame is ready before the frame starts, so a
    /// layer that draws `previous` waits on nothing and the loop is no cycle.
    @Test func readingPreviousWaitsOnNothing() {
        var want: [RenderTarget] = []
        let schedule = scheduled { s, d in
            let fb = s.makeFeedback(), a = s.makeRenderTarget()
            d.withFeedback(fb) { _ in s.drawImage(a.image, 0, 0) }
            d.withTarget(a) { s.drawImage(fb.previous, 0, 0) }
            want = [a, fb.writeLayer]
        }
        #expect(same(schedule.order, want) && schedule.early.isEmpty)
    }

    /// A plain layer the frame reads and never opened is in the order, to be
    /// filled empty, with the clear color of a frame before taken off it; read
    /// through its depth it is the layer that joins.
    @Test func aLayerReadAndNeverOpenedIsFilledEmpty() {
        var want: [RenderTarget] = []
        var kept: RenderTarget!
        let onCanvas = scheduled { s, _ in
            kept = s.makeRenderTarget()
            kept.clearColor = .red
            s.drawImage(kept.image, 0, 0)
            want = [kept]
        }
        #expect(same(onCanvas.order, want) && same(onCanvas.unopened, want))
        #expect(kept.clearColor.alpha == 0, "the kept color reads \(kept.clearColor)")
        let throughDepth = scheduled { s, d in
            let base = s.makeRenderTarget(), scene = s.makeRenderTarget()
            d.withTarget(base) {}
            let op = base.combined(with: scene.depth, .mix())
            want = [base, scene, op]
        }
        #expect(same(throughDepth.order, want) && throughDepth.unopened.count == 1)
    }

    /// A run a wipe took reads nothing: the layer it drew is nothing to wait
    /// for, and a layer only such a run read is not filled on its account.
    @Test func aWipedRunReadsNothing() {
        var want: [RenderTarget] = []
        let schedule = scheduled { s, d in
            let a = s.makeRenderTarget(), b = s.makeRenderTarget(), never = s.makeRenderTarget()
            // The first block's runs cannot be cut off the lists once another
            // layer has drawn, so the wipe hands them to no surface in place.
            d.withTarget(a) { s.drawImage(b.image, 0, 0); s.drawImage(never.image, 0, 0) }
            d.withTarget(b) { s.drawImage(a.image, 0, 0) }
            d.withTarget(a) { s.background(.clear) }
            want = [a, b]
        }
        #expect(same(schedule.order, want), "the order")
        #expect(schedule.early.isEmpty, "\(schedule.early.count) layers went early")
        #expect(schedule.unopened.isEmpty, "\(schedule.unopened.count) layers were filled empty for a wiped run")
    }
}
