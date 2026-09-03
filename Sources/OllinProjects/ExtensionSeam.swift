import Foundation

/// The seam a new extension hangs off, and the worked starter for each.
///
/// The catalog is *data*, the way the kinds and the templates are: a seam is an
/// id, a sentence, and the source it emits. A new seam is an entry here, not a
/// code path, and `GeneratedProjectBuildTests` compiles every one of them.
///
/// Only seams a third party can genuinely reach are listed. `Filter`,
/// `Generator`, and `Sim` are structs with no public initialiser, so an author
/// cannot add a case to any of them; the way in is a `Shader` through
/// `Filter.shader(_:)`, which is what the filter seam shows.
public struct ExtensionSeam: Sendable, Hashable, Identifiable {
    /// Stable slug used on the command line (`--seam filter`).
    public let id: String
    /// Short name for a menu or a list row.
    public let title: String
    /// One sentence on what this seam is for.
    public let summary: String
    /// How a sketch reaches the result, shown in the generated README.
    public let callSite: String
    /// The starter's source, with `{{NAME}}` standing for the extension's own
    /// name and `{{MODULE}}` for the module it builds.
    let source: String
    /// The starter's tests. Each seam checks something true rather than that the
    /// module loaded, since a test that cannot fail teaches the wrong habit.
    let test: String

    public init(id: String, title: String, summary: String, callSite: String,
                source: String, test: String) {
        self.id = id
        self.title = title
        self.summary = summary
        self.callSite = callSite
        self.source = source
        self.test = test
    }

    /// The starter file, with the names filled in.
    public func source(named name: String, module: String) -> String {
        filled(source, name: name, module: module)
    }

    /// The starter's test file, with the names filled in.
    public func test(named name: String, module: String) -> String {
        filled(test, name: name, module: module)
    }

    private func filled(_ text: String, name: String, module: String) -> String {
        text.replacingOccurrences(of: "{{NAME}}", with: name)
            .replacingOccurrences(of: "{{MODULE}}", with: module)
    }
}

extension ExtensionSeam {

    /// A new call a sketch makes, added the way Ollin adds its own.
    public static let drawCall = ExtensionSeam(
        id: "draw-call",
        title: "A new thing to draw",
        summary: "A drawing call added to Sketch, alongside the built-in ones. The simplest kind of extension, and the most common.",
        callSite: "drawSpiral(center: Vector2(width / 2, height / 2), radius: 320)",
        source: """
        import Foundation
        import Ollin

        /// The points of a spiral whose distance from the center grows evenly
        /// with its angle.
        ///
        /// The geometry is public and separate from the drawing on purpose. A
        /// sketch can then measure it, cut it, hatch it, or write it out to a
        /// plotter, and the drawing call below is one line over the top. It also
        /// makes the shape testable without a GPU, which is what the tests beside
        /// this file rely on.
        ///
        /// - Parameters:
        ///   - center: Where the spiral starts.
        ///   - radius: How far out the last turn reaches.
        ///   - turns: Whole and part turns to walk.
        ///   - steps: Points along the line. Raise it for a large spiral.
        public func spiralPoints(center: Vector2, radius: Double,
                                 turns: Double = 3, steps: Int = 240) -> [Vector2] {
            guard steps > 0, radius > 0 else { return [] }

            var points: [Vector2] = []
            points.reserveCapacity(steps + 1)
            for step in 0...steps {
                let along = Double(step) / Double(steps)
                let angle = along * turns * .tau
                points.append(center + Vector2(cos(angle), sin(angle)) * (along * radius))
            }
            return points
        }

        // Nothing registers this. A sketch imports the package and the call is
        // there, beside `drawCircle` and the rest, because an extension on
        // `Sketch` is how Ollin adds its own.
        //
        // A drawing call reads the current state rather than taking it as
        // arguments, so `stroke`, `strokeWeight`, and the transform stack all
        // apply with no work here.
        extension Sketch {

            /// Draws a spiral, honouring the current stroke and transform.
            public func drawSpiral(center: Vector2, radius: Double,
                                   turns: Double = 3, steps: Int = 240) {
                drawPolyline(spiralPoints(center: center, radius: radius,
                                          turns: turns, steps: steps))
            }
        }
        """,
        test: """
        import Foundation
        import Testing
        import Ollin
        @testable import {{MODULE}}

        @Suite("{{NAME}}")
        struct {{NAME}}Tests {

            @Test func theSpiralStartsAtTheCentreAndEndsAtTheRadius() {
                let center = Vector2(100, 100)
                let points = spiralPoints(center: center, radius: 50, turns: 2, steps: 64)

                #expect(points.count == 65)
                #expect((points.first! - center).length < 1e-9)
                #expect(abs((points.last! - center).length - 50) < 1e-9)
            }

            @Test func everyTurnAddsOneFullLap() {
                // Twice the turns over the same radius walks twice as far.
                let one = spiralPoints(center: .zero, radius: 100, turns: 1, steps: 2048)
                let two = spiralPoints(center: .zero, radius: 100, turns: 2, steps: 2048)

                #expect(length(of: two) > length(of: one) * 1.5)
            }

            @Test func anEmptySpiralDrawsNothing() {
                #expect(spiralPoints(center: .zero, radius: 0).isEmpty)
                #expect(spiralPoints(center: .zero, radius: 10, steps: 0).isEmpty)
            }

            private func length(of points: [Vector2]) -> Double {
                zip(points, points.dropFirst()).reduce(0) { $0 + ($1.1 - $1.0).length }
            }
        }
        """
    )

    /// A GPU effect, reached through the one seam the effect graph opens.
    public static let filter = ExtensionSeam(
        id: "filter",
        title: "A GPU effect",
        summary: "A filter run over a layer on the GPU, written as a shader and wrapped so the call site reads like a built-in one.",
        callSite: "drawImage(layer.filtered(.vignette()).image, 0, 0)",
        source: """
        import Ollin

        // `Filter` is a struct with no public initialiser, so an author cannot
        // add a case to the catalog. The way in is `Filter.shader(_:)`: write
        // the shader, wrap it once here, and the call site reads like one of the
        // built-in filters.
        //
        // The same seam is open on `Generator` (no input) and `Combine` (two).
        extension Filter {

            /// Darkens the corners, the way a lens does.
            ///
            /// - Parameter amount: 0 leaves the layer alone. 1 is a heavy edge.
            public static func vignette(amount: Double = 0.6) -> Filter {
                .shader(Shader(vignetteSource, params: [Float(amount)]))
            }
        }

        // The contract is one function. `uv` runs 0...1 with its origin at the
        // top left, `sample(info, uv)` reads the input layer, `param(info, 0)`
        // reads the first number passed in, and the returned color is straight
        // sRGB. Ollin generates everything around it.
        //
        // The shader compiles once per source, so a filter rebuilt every frame
        // costs nothing after the first.
        //
        // Left internal rather than private so the tests beside it can read it:
        // `@testable import` reaches internal, never private.
        let vignetteSource = \"""
        float4 shade(float2 uv, ShaderInfo info) {
            float4 color = sample(info, uv);

            float2 fromCentre = uv * 2.0 - 1.0;
            float falloff = 1.0 - param(info, 0) * dot(fromCentre, fromCentre) * 0.5;

            color.rgb *= clamp(falloff, 0.0, 1.0);
            return color;
        }
        \"""
        """,
        test: """
        import Testing
        import Ollin
        @testable import {{MODULE}}

        @Suite("{{NAME}}")
        struct {{NAME}}Tests {

            // What a filter is made of is Ollin's own business: `Filter.Kind` and
            // a `Shader`'s parameters are internal, so from out here a filter is
            // a value you build and hand over, never one you read back. That
            // leaves two honest kinds of check, and this seam can only do the
            // first without a GPU:
            //
            //   1. The shader source, which is this package's own property.
            //   2. What it renders, which needs a probe that draws a known layer
            //      and reads the pixels back on a machine with a GPU.

            @Test func theShaderDeclaresTheEntryPointOllinCallsFor() {
                #expect(vignetteSource.contains("float4 shade(float2 uv, ShaderInfo info)"))
            }

            @Test func theShaderReadsItsInputAndItsParameter() {
                #expect(vignetteSource.contains("sample(info, uv)"))
                #expect(vignetteSource.contains("param(info, 0)"))
            }
        }
        """
    )

    /// A new producer of frames, which every tracker and feed already accepts.
    public static let frameSource = ExtensionSeam(
        id: "frame-source",
        title: "A new source of frames",
        summary: "A producer of moving pictures. Anything that reads a frame (the vision trackers, the feeds) accepts one without knowing what it is.",
        callSite: "let source = {{NAME}}Source(); tracker.attach(to: source)",
        source: """
        import CoreGraphics
        import Ollin

        /// A source of frames a sketch can draw and any tracker can analyze.
        ///
        /// The whole contract is one property: hold a `frameTap` and call it with
        /// each new frame. That is what lets frame *analysis* run over any source
        /// of moving pictures without knowing which one it is, so a source built
        /// here works with everything already written against the protocol.
        ///
        /// Frames may arrive on any thread. The tap is `@Sendable` for exactly
        /// that reason, and a consumer hands the frame across to wherever it does
        /// its work rather than touching main-thread state.
        @MainActor
        public final class {{NAME}}Source: FrameSource {

            /// The installed consumer, or nil when nothing is reading this source.
            /// Setting it again replaces the previous one, which is the protocol's
            /// own rule: one tap per source.
            public var frameTap: FrameTap?

            public init() {}

            /// Hand a frame over. Call this from wherever the pictures come from.
            ///
            /// A real source drives this from its own capture callback. Publish at
            /// the source's natural rate, and publish nothing while idle rather
            /// than repeating the last frame.
            public func publish(_ frame: CGImage) {
                frameTap?(frame)
            }
        }
        """,
        test: """
        import CoreGraphics
        import Testing
        import Ollin
        @testable import {{MODULE}}

        @Suite("{{NAME}}")
        @MainActor
        struct {{NAME}}Tests {

            @Test func aPublishedFrameReachesTheTap() {
                let source = {{NAME}}Source()
                let seen = Counter()
                source.frameTap = { _ in seen.bump() }

                source.publish(swatch())
                source.publish(swatch())

                #expect(seen.count == 2)
            }

            @Test func nothingIsPublishedWithoutATap() {
                // The counterfactual: the same two frames with no tap installed.
                // A source must not keep frames for a reader that is not there.
                let source = {{NAME}}Source()
                source.publish(swatch())

                #expect(source.frameTap == nil)
            }

            @Test func settingTheTapAgainReplacesTheFirstOne() {
                let source = {{NAME}}Source()
                let first = Counter()
                let second = Counter()

                source.frameTap = { _ in first.bump() }
                source.frameTap = { _ in second.bump() }
                source.publish(swatch())

                #expect(first.count == 0)
                #expect(second.count == 1)
            }

            /// One opaque pixel, which is all a tap needs to be called with.
            private func swatch() -> CGImage {
                let context = CGContext(
                    data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )!
                return context.makeImage()!
            }
        }

        /// A tap is `@Sendable`, so a test counts through a reference rather than
        /// a captured `var`.
        private final class Counter: @unchecked Sendable {
            private(set) var count = 0
            func bump() { count += 1 }
        }
        """
    )

    /// A lifecycle participant on the `extend` seam.
    public static let lifecycle = ExtensionSeam(
        id: "lifecycle",
        title: "Something that runs every frame",
        summary: "A participant in the frame loop: draw over the sketch, watch its timing, or take the rendered pixels. The seam the built-in stats reader uses.",
        callSite: "extend({{NAME}}Overlay())",
        source: """
        import Ollin

        /// Runs around every frame. Register one in `setup()` with
        /// `extend({{NAME}}Overlay())`.
        ///
        /// Every hook is optional, so an extension writes only the moments it
        /// cares about:
        ///
        /// - `setup` runs once, after the sketch's own.
        /// - `beforeDraw` and `afterDraw` run inside the frame. `afterDraw` lands
        ///   before the render, so it can draw over the sketch with the ordinary
        ///   bare calls, as this one does.
        /// - `afterFrame` runs after the render and carries the frame's timing,
        ///   for something that reads rather than draws.
        /// - `frameRendered` hands over the rendered pixels once the GPU has finished
        ///   the frame, and costs a pass and a copy, so it only arrives when
        ///   `wantsRenderedFrame` asks for it.
        ///
        /// Extensions are per instance. A fresh sketch, including every live
        /// reload, starts with none, which is why one registers itself in
        /// `setup()`.
        @MainActor
        public final class {{NAME}}Overlay: SketchExtension {

            /// How long the bar takes to cross, in frames.
            public var period = 200

            private var frames = 0

            public init() {}

            public func afterDraw(_ sketch: Sketch) {
                frames += 1

                // Scoped, so nothing here leaks into the next frame's drawing.
                sketch.withState {
                    sketch.noStroke()
                    sketch.fill(Color.white.withAlpha(0.6))
                    let across = Double(frames % max(period, 1)) / Double(max(period, 1))
                    sketch.drawRect(0, 0, sketch.width * across, 4)
                }
            }
        }
        """,
        test: """
        import Testing
        import Ollin
        @testable import {{MODULE}}

        @Suite("{{NAME}}")
        @MainActor
        struct {{NAME}}Tests {

            // The hooks take a live `Sketch`, which needs a GPU, so what is
            // testable without one is the extension's own state and the opt-ins
            // it declares. Put anything that draws in a rendered probe.

            @Test func theReadbackHooksStayOffUntilAskedFor() {
                // Both cost a GPU readback, so an extension that never asks must
                // never be handed a frame.
                let overlay = {{NAME}}Overlay()

                #expect(overlay.wantsRenderedFrame == false)
                #expect(overlay.wantsRenderedTexture == false)
            }

            @Test func thePeriodIsSettable() {
                let overlay = {{NAME}}Overlay()
                #expect(overlay.period == 200)

                overlay.period = 60
                #expect(overlay.period == 60)
            }
        }
        """
    )

    /// Every seam, in the order a menu should show them.
    public static let all: [ExtensionSeam] = [.drawCall, .filter, .frameSource, .lifecycle]

    /// Look a seam up by its slug.
    public static func named(_ id: String) -> ExtensionSeam? {
        all.first { $0.id == id }
    }
}

/// Naming for an extension package, which follows a convention rather than the
/// author's taste so the packages are recognisable and searchable.
///
/// The folder and repository take `ollinx-` in lower case with dashes, and the
/// module takes `Ollinx` in camel case, because that is what each of the two is
/// allowed to be. Where the prefix comes from is in `Docs/Tools/Extensions.md`.
public enum ExtensionNaming {
    public static let packagePrefix = "ollinx-"
    public static let modulePrefix = "Ollinx"

    /// `Halftone` becomes `OllinxHalftone`.
    public static func moduleName(for name: String) -> String {
        modulePrefix + name
    }

    /// `HalftonePress` becomes `ollinx-halftone-press`.
    ///
    /// A run of capitals stays together (`SVGTools` becomes `svg-tools`), since
    /// an initialism is one word to a reader even though it is several capitals
    /// to a parser.
    public static func packageName(for name: String) -> String {
        packagePrefix + kebabCased(name)
    }

    static func kebabCased(_ name: String) -> String {
        let characters = Array(name)
        var words: [String] = []
        var current = ""

        for (index, character) in characters.enumerated() {
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil

            // A word starts at a capital that follows a lower-case letter
            // (`HalftonePress`), or at the last capital of a run when a
            // lower-case letter follows it (`SVGTools`).
            let startsWord = character.isUppercase
                && ((previous?.isLowercase ?? false)
                    || ((previous?.isUppercase ?? false) && (next?.isLowercase ?? false)))

            if startsWord, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }

        return words.map { $0.lowercased() }.joined(separator: "-")
    }
}
