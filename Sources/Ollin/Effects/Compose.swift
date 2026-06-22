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

    /// What to draw into this layer's off-screen surface, in canvas coordinates:
    /// the body of the `layer { }` block. Runs inside a `withTarget` during `compose`.
    let content: () -> Void

    /// Filters run over the finished layer, in order, before it composites. Each
    /// `.post(_:)` appends one, so they chain like `filtered(_:).filtered(_:)`.
    var posts: [Filter] = []

    /// How the finished layer composites onto what's already drawn beneath it.
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
        copy.posts.append(filter)
        return copy
    }

    /// Run several filters over this layer, in the order given; shorthand for
    /// chaining `.post(_:)`.
    public func post(_ filters: Filter...) -> ComposeLayer {
        var copy = self
        copy.posts.append(contentsOf: filters)
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
            let target = renderTarget(scale: composeLayer.renderScale)
            withTarget(target) { composeLayer.content() }
            var result = target
            for filter in composeLayer.posts { result = result.filtered(filter) }
            withState {
                blendMode(composeLayer.blend)
                drawImage(result.image, 0, 0)
            }
        }
    }
}
