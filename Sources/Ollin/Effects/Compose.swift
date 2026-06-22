/// The declarative surface over layered effects: declare a stack of layers, each
/// with its own drawing, post-filters, and blend mode, as a single block. It's
/// sugar over the off-screen-layer substrate (`renderTarget` / `withTarget` /
/// `filtered` / `blendMode` / `drawImage`): `compose { }` makes a layer for each
/// `layer { }`, draws into it, runs its filters, and composites it onto what's
/// beneath, so a multi-layer effect reads as one block instead of the same
/// targets, filters, and composites threaded out by hand.
///
/// ```swift
/// override func draw() {
///     background(.black)
///     compose {
///         layer {                                  // a soft, blurred backdrop
///             noStroke(); fill(.indigo)
///             drawCircle(width / 2, height / 2, 300)
///         }
///         .post(.gaussianBlur(radius: 40))
///
///         layer {                                  // crisp marks that glow…
///             noStroke(); fill(.cyan)
///             drawCircle(mouseX, mouseY, 60)
///         }
///         .post(.bloom(intensity: 1.6))
///         .blend(.add)                             // …added as light
///     }
/// }
/// ```
///
/// Each `layer { }` clears to transparent unless it draws its own `background(_:)`,
/// so a layer that draws one shape composites just that shape. Layers stack in the
/// order written (first is drawn first, beneath the rest). Call `compose` near the
/// top of `draw()`: like `withTarget`, the active transform carries into each
/// layer's drawing.

/// One layer of a `compose { }` block: what to draw, the post-filters to run over
/// it, and how it composites. Build it with `layer { }` and tune it with the
/// chainable modifiers (`.post(_:)`, `.blend(_:)`, `.scale(_:)`) in any order:
///
/// ```swift
/// layer { … }.post(.colorGrade(saturation: 1.4)).post(.vignette()).blend(.screen)
/// ```
public struct ComposeLayer {

    /// One processing step run over the finished layer before it composites, in the
    /// order added: either a single-input `Filter`, or a two-input `Combine` with an
    /// `aside` layer drawn only to feed it (a mask, a displacement map, the other
    /// half of a cross-dissolve). Both `.post(_:)` and the combine modifiers append
    /// here, so filters and combines interleave in call order.
    enum Step {
        case filter(Filter)
        case combine(aside: ComposeLayer, op: Combine)
    }

    /// What to draw into this layer's off-screen surface, in canvas coordinates:
    /// the body of the `layer { }` block. Runs inside a `withTarget` during `compose`.
    let content: () -> Void

    /// The post-processing steps run over the finished layer, in order, before it
    /// composites — filters and aside combines interleaved as added.
    var steps: [Step] = []

    /// How the finished layer composites onto what's already drawn beneath it.
    /// (Ignored when the layer is used as an `aside` — an aside is never composited,
    /// only sampled by the combine it feeds.)
    var blend: BlendMode = .normal

    /// The layer's internal resolution as a fraction of the canvas (1 = full), the
    /// `RenderTarget.scale` of its backing layer. Drop it for a cheaper, softer
    /// layer (a blurred or glowing one rarely needs full detail).
    var renderScale: Double = 1

    /// Run `filter` over this layer before it composites. Chain calls to stack
    /// filters: `.post(.threshold()).post(.bloom())` runs the threshold, then blooms
    /// the result.
    public func post(_ filter: Filter) -> ComposeLayer {
        var copy = self
        copy.steps.append(.filter(filter))
        return copy
    }

    /// Run several filters over this layer, in the order given; shorthand for
    /// chaining `.post(_:)`.
    public func post(_ filters: Filter...) -> ComposeLayer {
        var copy = self
        copy.steps.append(contentsOf: filters.map { .filter($0) })
        return copy
    }

    /// Mask this layer by an `aside` layer: keep it where the aside reads bright (or,
    /// with `channel: .alpha`, opaque), fading to transparent elsewhere. The aside is
    /// drawn only to feed the mask, not composited; build it with `aside { }` (and it
    /// can carry its own `.post` filters, e.g. a blurred edge):
    ///
    /// ```swift
    /// layer { drawImage(photo, 0, 0) }
    ///     .masked(by: aside { fill(.white); drawCircle(mouseX, mouseY, 200) })
    /// ```
    public func masked(by aside: ComposeLayer,
                       channel: Combine.MaskChannel = .luminance,
                       invert: Bool = false) -> ComposeLayer {
        var copy = self
        copy.steps.append(.combine(aside: aside, op: .mask(channel: channel, invert: invert)))
        return copy
    }

    /// Displace this layer's pixels by an `aside` layer read as a vector field (red →
    /// horizontal, green → vertical, mid-gray = no shift), up to `amount` of the
    /// layer. The aside — often a noise or gradient — is drawn only to feed the
    /// displacement, not composited.
    public func displaced(by aside: ComposeLayer, amount: Double = 0.05) -> ComposeLayer {
        var copy = self
        copy.steps.append(.combine(aside: aside, op: .displace(amount: amount)))
        return copy
    }

    /// Cross-dissolve this layer toward an `aside` layer by `amount` (0 = this layer,
    /// 1 = the aside). The aside is drawn only to feed the mix, not composited.
    public func mixed(with aside: ComposeLayer, amount: Double = 0.5) -> ComposeLayer {
        var copy = self
        copy.steps.append(.combine(aside: aside, op: .mix(amount: amount)))
        return copy
    }

    /// Composite this layer with `mode` instead of the default `.normal` (so a glow
    /// layer can add as light, a shade layer can multiply, and so on).
    public func blend(_ mode: BlendMode) -> ComposeLayer {
        var copy = self
        copy.blend = mode
        return copy
    }

    /// Render this layer at `fraction` of the canvas resolution (1 = full), the way
    /// `renderTarget(scale:)` does. The result upsamples when it composites, so a
    /// blurred or glowing layer can render cheaply without a visible difference.
    public func scale(_ fraction: Double) -> ComposeLayer {
        var copy = self
        copy.renderScale = fraction
        return copy
    }
}

/// Collects the `layer { }` statements inside a `compose { }` block into the layer
/// stack, in written order. Being a result builder is what lets the block read as
/// a sequence of declarations (with `if`/`for` to build layers conditionally or in
/// a loop) rather than an array literal.
@resultBuilder
public enum ComposeBuilder {
    public static func buildExpression(_ layer: ComposeLayer) -> [ComposeLayer] { [layer] }
    public static func buildExpression(_ layers: [ComposeLayer]) -> [ComposeLayer] { layers }
    public static func buildBlock(_ parts: [ComposeLayer]...) -> [ComposeLayer] { parts.flatMap { $0 } }
    public static func buildOptional(_ part: [ComposeLayer]?) -> [ComposeLayer] { part ?? [] }
    public static func buildEither(first part: [ComposeLayer]) -> [ComposeLayer] { part }
    public static func buildEither(second part: [ComposeLayer]) -> [ComposeLayer] { part }
    public static func buildArray(_ parts: [[ComposeLayer]]) -> [ComposeLayer] { parts.flatMap { $0 } }
}

public extension Sketch {

    /// Declare one layer of a `compose { }` block: the drawing goes in the closure,
    /// and the chainable modifiers (`.post`, `.blend`, `.scale`) tune it. Used only
    /// inside `compose { }`; outside it, draw straight to the canvas or use
    /// `renderTarget` / `withTarget` directly.
    ///
    /// The closure runs synchronously inside `compose` (it doesn't outlive the call),
    /// so bare drawing calls need no `self.` even though it's stored until then.
    func layer(@_implicitSelfCapture _ content: @escaping () -> Void) -> ComposeLayer {
        ComposeLayer(content: content)
    }

    /// Declare a helper layer that *feeds* another layer's combine — a mask, a
    /// displacement map, the other half of a cross-dissolve — rather than
    /// compositing on its own. It's the same as `layer { }` (and takes the same
    /// `.post(_:)` / `.scale(_:)` modifiers), just named for how it's used: hand it
    /// to `.masked(by:)`, `.displaced(by:)`, or `.mixed(with:)`. The compositor draws
    /// it into its own off-screen surface and manages the texture; nothing is
    /// threaded by hand, and its `.blend(_:)` is unused (an aside never composites).
    ///
    /// ```swift
    /// layer { drawImage(scene, 0, 0) }
    ///     .displaced(by: aside { fill(.gray); drawImage(noise, 0, 0) }.post(.gaussianBlur(radius: 6)),
    ///                amount: 0.03)
    /// ```
    func aside(@_implicitSelfCapture _ content: @escaping () -> Void) -> ComposeLayer {
        ComposeLayer(content: content)
    }

    /// Composite a stack of layers as one block. Each `layer { }` is drawn into its
    /// own off-screen layer, run through its post-filters, and composited (in its
    /// blend mode) onto whatever is already on the canvas, in the order written, so
    /// the first layer sits beneath the rest. The intermediate layers and their
    /// filters are managed for you; nothing leaves the GPU between steps.
    ///
    /// This is the declarative form of the per-call substrate it's built on: the
    /// same `renderTarget` / `withTarget` / `filtered` / `drawImage` it would take
    /// to do by hand, gathered into one readable block.
    func compose(@ComposeBuilder _ build: () -> [ComposeLayer]) {
        for composeLayer in build() {
            let result = resolveComposeLayer(composeLayer)
            withState {
                blendMode(composeLayer.blend)
                drawImage(result.image, 0, 0)
            }
        }
    }

    /// Draw a `ComposeLayer` into its own off-screen layer and run its steps in order
    /// — filters via `filtered(_:)`, combines by first resolving the aside (itself a
    /// `ComposeLayer`, so this recurses) and feeding it to `combined(with:_:)`.
    /// Returns the finished layer. Used for both the top-level layers `compose`
    /// composites and the asides those layers reference; an aside is resolved here
    /// but never composited, which is the whole of "drawn only to feed another".
    private func resolveComposeLayer(_ cl: ComposeLayer) -> RenderTarget {
        let target = renderTarget(scale: cl.renderScale)
        withTarget(target) { cl.content() }
        var result = target
        for step in cl.steps {
            switch step {
            case .filter(let filter):
                result = result.filtered(filter)
            case let .combine(aside, op):
                result = result.combined(with: resolveComposeLayer(aside), op)
            }
        }
        return result
    }
}
