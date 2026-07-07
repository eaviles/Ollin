import Foundation
import COllinShaders

/// A composable, animated procedural image: a chain of per-pixel sources and
/// transforms that compiles into a single GPU pass. Start from a source, chain
/// transforms, and mix chains into one another; the whole expression renders as
/// one fragment shader however deep it grows.
///
/// ```swift
/// override func draw() {
///     drawVisual(
///         .oscillator(frequency: 40, colorShift: 0.15)
///             .rotated(0.4)
///             .kaleidoscope(6)
///             .displaced(by: .noise(scale: 3), amount: 0.08)
///     )
/// }
/// ```
///
/// A `Visual` is a value describing the chain, rebuilt each `draw()` like any
/// other Ollin drawing. Its *structure* decides the shader (compiled once and
/// cached); its *numbers* ride a uniform buffer, so animating any argument
/// (`.rotated(time * 0.2)`, an `@Param` knob) costs no recompile.
///
/// Chains fall into five families:
/// - **Sources** make color from nothing (`.oscillator`, `.noise`, `.voronoi`,
///   `.shape`, `.gradient`, `.solid`) or read a layer (`.layer(_:)`, including a
///   `Feedback`'s previous frame).
/// - **Coordinate transforms** warp *where* the chain samples (`.rotated`,
///   `.scaled`, `.pixelated`, `.repeated`, `.kaleidoscope`, `.scrolled`); they
///   compose the way transforms read, so `.rotated(a).repeated(x: 3)` tiles the
///   rotated image.
/// - **Color adjustments** rewrite the color after sampling (`.brightness`,
///   `.contrast`, `.saturation`, `.inverted`, `.posterized`, `.thresholded`,
///   `.luma`, `.hueShifted`, `.tinted`, `.colorCycled`, `.channel`).
/// - **Combines** blend two chains per pixel (`.blended(with:_:amount:)` over
///   the standard `BlendMode`s, `.mixed(with:)`, `.differenced(with:)`,
///   `.masked(by:)`).
/// - **Modulations** let one chain's *color* drive another's *coordinates*: the
///   analog-video idea that any signal can patch into any input. `.displaced(by:)`
///   is the general form; `.rotated(by:)`, `.scaled(by:)`, `.pixelated(by:)`, and
///   `.kaleidoscope(by:)` drive those warps per pixel.
///
/// Realize a chain with `drawVisual(_:)` (fills the canvas) or `generate(_:)`
/// (returns a `RenderTarget` to filter, combine, or draw like any layer).
/// Coordinates are aspect-corrected: shapes stay round, rotation stays angle-true,
/// and pattern cells stay square at any canvas size. Colors are straight sRGB,
/// like a user `Shader`'s.
public struct Visual {

    /// A color channel a chain can broadcast as a grayscale signal, the adapter
    /// between a colorful chain and a scalar-driven modulation.
    public enum Channel: Sendable {
        case red, green, blue, alpha, luminance

        /// The selector the shader's channel op reads.
        var rawIndex: Int {
            switch self {
            case .red: 0
            case .green: 1
            case .blue: 2
            case .alpha: 3
            case .luminance: 4
            }
        }
    }

    /// Source leaves: where a chain's color comes from.
    enum Source {
        case oscillator(frequency: Double, speed: Double, colorShift: Double)
        case noise(scale: Double, speed: Double)
        case voronoi(scale: Double, speed: Double, blending: Double)
        case shape(sides: Double, radius: Double, smoothing: Double)
        case gradient(speed: Double)
        case solid(Color)
        case layer(RenderTarget)
    }

    /// Coordinate warps: rewrite where the chain beneath them samples.
    enum Warp {
        case rotate(angle: Double, speed: Double)
        case scale(amount: Double, x: Double, y: Double)
        case pixelate(x: Double, y: Double)
        case repeatTiles(x: Double, y: Double, offsetX: Double, offsetY: Double)
        case kaleid(sides: Double)
        case scroll(x: Double, y: Double, speedX: Double, speedY: Double)
    }

    /// Color adjustments: rewrite the color a chain produced.
    enum Adjust {
        case brightness(Double)
        case contrast(Double)
        case saturation(Double)
        case invert(Double)
        case posterize(bins: Double, gamma: Double)
        case threshold(threshold: Double, tolerance: Double)
        case luma(threshold: Double, tolerance: Double)
        case hueShift(Double)
        case tint(Color)
        case colorCycle(Double)
        case channel(Channel, scale: Double, offset: Double)
    }

    /// Two-chain color combines.
    enum CombineOp {
        case blend(BlendMode, amount: Double)
        case mixAmount(Double)
        case difference
        case mask
    }

    /// Modulations: the driver chain's color perturbs the base chain's coordinate.
    enum Modulate {
        case displace(amount: Double)
        case rotate(amount: Double, offset: Double)
        case scale(amount: Double, offset: Double)
        case pixelate(amount: Double, offset: Double)
        case kaleid(sides: Double, amount: Double)
    }

    indirect enum Node {
        case source(Source)
        case warp(Warp, Visual)
        case adjust(Adjust, Visual)
        case combine(CombineOp, Visual, Visual)     // base, other
        case modulate(Modulate, Visual, Visual)     // base, driver
    }

    var node: Node
    init(_ node: Node) { self.node = node }
}

// MARK: - Sources

public extension Visual {
    /// Sine bands: `frequency` waves across the field, drifting at `speed`
    /// (phase per second). `colorShift` phase-offsets the green and blue
    /// channels for a chromatic fringe.
    static func oscillator(frequency: Double = 40, speed: Double = 2,
                           colorShift: Double = 0) -> Visual {
        Visual(.source(.oscillator(frequency: frequency, speed: speed, colorShift: colorShift)))
    }
    /// An evolving noise field, `scale` features across, drifting at `speed`.
    /// Signed (-1…1), so it reads dark on its own but modulates symmetrically;
    /// chain `.brightness(0.5)` to view it as a mid-gray cloud.
    static func noise(scale: Double = 8, speed: Double = 0.3) -> Visual {
        Visual(.source(.noise(scale: scale, speed: speed)))
    }
    /// Animated cellular shading: `scale` cells across, each a random gray, the
    /// points wandering at `speed`; `blending` darkens toward the cell borders.
    static func voronoi(scale: Double = 5, speed: Double = 0.3,
                        blending: Double = 0.3) -> Visual {
        Visual(.source(.voronoi(scale: scale, speed: speed, blending: blending)))
    }
    /// A soft-edged regular polygon, centered, one vertex up: white inside,
    /// transparent outside. `radius` is in field units (0.5 reaches the top edge);
    /// `smoothing` is the edge width. High `sides` (60+) reads as a circle.
    static func shape(sides: Double = 3, radius: Double = 0.3,
                      smoothing: Double = 0.01) -> Visual {
        Visual(.source(.shape(sides: sides, radius: radius, smoothing: smoothing)))
    }
    /// The coordinate gradient (red = x, green = y), its blue channel breathing
    /// with time at `speed`.
    static func gradient(speed: Double = 0) -> Visual {
        Visual(.source(.gradient(speed: speed)))
    }
    /// A flat color.
    static func solid(_ color: Color) -> Visual {
        Visual(.source(.solid(color)))
    }
    /// Read a layer: a `RenderTarget` you drew, generated, or filtered. The chain
    /// samples it wherever its (possibly warped) coordinate lands, wrapping at the
    /// edges. A chain may read up to two distinct layers.
    static func layer(_ target: RenderTarget) -> Visual {
        Visual(.source(.layer(target)))
    }
    /// Read a feedback layer's *previous frame*: the video-feedback source. Zoom,
    /// rotate, or displace it and draw the result back into the same `Feedback`
    /// for trails and tunnels.
    static func layer(_ feedback: Feedback) -> Visual {
        Visual(.source(.layer(feedback.previousLayer)))
    }
}

// MARK: - Coordinate transforms

public extension Visual {
    /// Rotate the image by `angle` radians about the center (plus `speed`
    /// radians per second), aspect-true.
    func rotated(_ angle: Double, speed: Double = 0) -> Visual {
        Visual(.warp(.rotate(angle: angle, speed: speed), self))
    }
    /// Zoom about the center: `amount` above 1 magnifies, below 1 shrinks.
    /// `x`/`y` multiply per axis (a negative value mirrors that axis).
    func scaled(_ amount: Double, x: Double = 1, y: Double = 1) -> Visual {
        Visual(.warp(.scale(amount: amount, x: x, y: y), self))
    }
    /// Snap sampling to a coarse grid: `cells` cells across both axes.
    func pixelated(_ cells: Double) -> Visual { pixelated(x: cells, y: cells) }
    /// Snap sampling to an `x` by `y` grid of cells.
    func pixelated(x: Double, y: Double) -> Visual {
        Visual(.warp(.pixelate(x: x, y: y), self))
    }
    /// Tile the image `x` by `y` times; `offsetX`/`offsetY` stagger alternate
    /// rows/columns by that fraction of a tile (a brick layout).
    func repeated(x: Double = 3, y: Double = 3,
                  offsetX: Double = 0, offsetY: Double = 0) -> Visual {
        Visual(.warp(.repeatTiles(x: x, y: y, offsetX: offsetX, offsetY: offsetY), self))
    }
    /// Fold the image into `sides` mirrored wedges about the center.
    func kaleidoscope(_ sides: Double = 4) -> Visual {
        Visual(.warp(.kaleid(sides: sides), self))
    }
    /// Slide the image by `x`/`y` (fractions of the field), drifting at
    /// `speedX`/`speedY` per second, wrapping at the edges.
    func scrolled(x: Double = 0, y: Double = 0,
                  speedX: Double = 0, speedY: Double = 0) -> Visual {
        Visual(.warp(.scroll(x: x, y: y, speedX: speedX, speedY: speedY), self))
    }
}

// MARK: - Color adjustments

public extension Visual {
    /// Add `amount` to every channel (negative darkens).
    func brightness(_ amount: Double = 0.4) -> Visual {
        Visual(.adjust(.brightness(amount), self))
    }
    /// Scale contrast about mid-gray (1 leaves it alone).
    func contrast(_ amount: Double = 1.6) -> Visual {
        Visual(.adjust(.contrast(amount), self))
    }
    /// Scale saturation (0 grays out, 1 leaves it alone, above 1 enriches).
    func saturation(_ amount: Double = 2) -> Visual {
        Visual(.adjust(.saturation(amount), self))
    }
    /// Invert the color by `amount` (1 is a full negative).
    func inverted(_ amount: Double = 1) -> Visual {
        Visual(.adjust(.invert(amount), self))
    }
    /// Quantize into `bins` levels per channel; `gamma` biases where the levels
    /// fall (below 1 favors the darks).
    func posterized(bins: Double = 3, gamma: Double = 0.6) -> Visual {
        Visual(.adjust(.posterize(bins: bins, gamma: gamma), self))
    }
    /// Split to black and white about a luminance `threshold`, with a
    /// `tolerance`-wide soft edge.
    func thresholded(_ threshold: Double = 0.5, tolerance: Double = 0.04) -> Visual {
        Visual(.adjust(.threshold(threshold: threshold, tolerance: tolerance), self))
    }
    /// Key by luminance: keep what reads brighter than `threshold` and turn the
    /// dark side transparent (soft edge `tolerance`).
    func luma(threshold: Double = 0.5, tolerance: Double = 0.1) -> Visual {
        Visual(.adjust(.luma(threshold: threshold, tolerance: tolerance), self))
    }
    /// Rotate the hue by `amount`, a fraction of the color wheel (0.5 lands on
    /// the complementary color).
    func hueShifted(_ amount: Double) -> Visual {
        Visual(.adjust(.hueShift(amount), self))
    }
    /// Multiply by a color (white leaves the chain alone).
    func tinted(_ color: Color) -> Visual {
        Visual(.adjust(.tint(color), self))
    }
    /// Cycle hue, saturation, and value together by `amount`, wrapping. Feed it
    /// a growing value (`time * 0.1`) for an endless color crawl.
    func colorCycled(_ amount: Double = 0.005) -> Visual {
        Visual(.adjust(.colorCycle(amount), self))
    }
    /// Broadcast one channel (or the luminance) as grayscale, times `scale` plus
    /// `offset`: the adapter that turns a colorful chain into a clean scalar
    /// signal for masking or modulation.
    func channel(_ channel: Channel, scale: Double = 1, offset: Double = 0) -> Visual {
        Visual(.adjust(.channel(channel, scale: scale, offset: offset), self))
    }
}

// MARK: - Combines

public extension Visual {
    /// Blend another chain onto this one with a standard `BlendMode` (`.normal`
    /// composites by the other's alpha; `.add`, `.multiply`, `.screen`, … mix
    /// like the canvas blend modes). `amount` fades the effect (0 keeps this
    /// chain untouched).
    func blended(with other: Visual, _ mode: BlendMode = .normal,
                 amount: Double = 1) -> Visual {
        Visual(.combine(.blend(mode, amount: amount), self, other))
    }
    /// Cross-dissolve toward another chain (0 keeps this one, 1 becomes the other).
    func mixed(with other: Visual, amount: Double = 0.5) -> Visual {
        Visual(.combine(.mixAmount(amount), self, other))
    }
    /// The absolute per-channel difference against another chain.
    func differenced(with other: Visual) -> Visual {
        Visual(.combine(.difference, self, other))
    }
    /// Keep this chain where the other reads bright and opaque, fading it out
    /// elsewhere (the other chain acts as a mask).
    func masked(by other: Visual) -> Visual {
        Visual(.combine(.mask, self, other))
    }
}

// MARK: - Modulations

public extension Visual {
    /// Push this chain's sampling coordinate by the driver's red/green channels,
    /// up to `amount` of the field: the general modulation, and the classic
    /// "melt one image with another" move.
    func displaced(by driver: Visual, amount: Double = 0.1) -> Visual {
        Visual(.modulate(.displace(amount: amount), self, driver))
    }
    /// Rotate per pixel by the driver: angle = `offset` + driver red × `amount`.
    func rotated(by driver: Visual, amount: Double = 1, offset: Double = 0) -> Visual {
        Visual(.modulate(.rotate(amount: amount, offset: offset), self, driver))
    }
    /// Zoom per pixel by the driver: scale = `offset` + driver red × `amount`.
    func scaled(by driver: Visual, amount: Double = 1, offset: Double = 1) -> Visual {
        Visual(.modulate(.scale(amount: amount, offset: offset), self, driver))
    }
    /// Vary the pixelation grid per pixel by the driver: cells = `offset` +
    /// driver red/green × `amount`.
    func pixelated(by driver: Visual, amount: Double = 10, offset: Double = 3) -> Visual {
        Visual(.modulate(.pixelate(amount: amount, offset: offset), self, driver))
    }
    /// Kaleidoscope whose fold radius shifts with the driver's red channel
    /// (times `amount`), warping the wedges organically.
    func kaleidoscope(by driver: Visual, sides: Double = 4,
                      amount: Double = 0.1) -> Visual {
        Visual(.modulate(.kaleid(sides: sides, amount: amount), self, driver))
    }
}

// MARK: - Compilation

/// The result of compiling a `Visual` chain: the generated shader source (the
/// body of `shade`), the animatable values it reads from the params buffer, and
/// the layers it samples, in bind order.
struct VisualProgram {
    var source: String
    var params: [Float]
    var layers: [RenderTarget]
    /// True when the chain carried more animatable values than the params buffer
    /// holds; the overflow was baked into the source as literals (still renders,
    /// but changing those values recompiles).
    var paramsOverflowed: Bool
    /// Layers beyond the two the shader wrapper can bind (sampled as black).
    var layersDropped: Int
    /// Total chain nodes, for the "very large chain" advisory.
    var nodeCount: Int
}

extension Visual {

    /// Compile the chain to MSL: walk the tree once, emitting one statement per
    /// op into a `shade(uv, info)` body. The *structure* alone decides the source
    /// text (so identical structures share one cached pipeline); every numeric
    /// argument is poured into the params buffer and read back with
    /// `param(info, i)`, so animating a value never recompiles.
    func compile() -> VisualProgram {
        var compiler = VisualCompiler()
        let result = compiler.emit(self, st: "st0")
        var body = "float4 shade(float2 uv, ShaderInfo info) {\n"
        body += "    float aspect = info.resolution.x / max(info.resolution.y, 1.0);\n"
        body += "    float2 st0 = uv;\n"
        for line in compiler.lines { body += "    \(line)\n" }
        body += "    return \(result);\n"
        body += "}\n"
        return VisualProgram(source: body, params: compiler.params,
                             layers: compiler.layers,
                             paramsOverflowed: compiler.overflowed,
                             layersDropped: compiler.layersDropped,
                             nodeCount: compiler.nodeCount)
    }
}

/// The tree walker behind `Visual.compile()`.
private struct VisualCompiler {
    var lines: [String] = []
    var params: [Float] = []
    var layers: [RenderTarget] = []
    var overflowed = false
    var layersDropped = 0
    var nodeCount = 0
    private var nextVar = 1   // 0 is the root `st0` the shade body declares

    mutating func fresh(_ prefix: String) -> String {
        defer { nextVar += 1 }
        return "\(prefix)\(nextVar)"
    }

    /// An animatable value: a params-buffer slot when one is free, otherwise a
    /// literal baked into the source (renders the same; changing it recompiles).
    mutating func slot(_ v: Double) -> String {
        if params.count < Int(OLLIN_SHADER_PARAM_COUNT) {
            params.append(Float(v))
            return "param(info, \(params.count - 1))"
        }
        overflowed = true
        return literal(v)
    }

    /// A structural value spelled into the source (selectors, not knobs).
    func literal(_ v: Double) -> String {
        let f = Float(v)
        return f == f.rounded() && abs(f) < 1e7 ? "\(Int(f)).0" : "\(f)"
    }

    mutating func colorSlot(_ c: Color) -> String {
        "float4(\(slot(c.red)), \(slot(c.green)), \(slot(c.blue)), \(slot(c.alpha)))"
    }

    /// Emit `visual` sampling at the coordinate variable `st` (which the chain's
    /// warps rewrite in place); returns the name of the resulting color variable.
    mutating func emit(_ visual: Visual, st: String) -> String {
        nodeCount += 1
        switch visual.node {

        case .source(let source):
            let c = fresh("c")
            switch source {
            case let .oscillator(f, speed, shift):
                lines.append("float4 \(c) = ollin_vis_osc(\(st), \(slot(f)), \(slot(speed)), \(slot(shift)), info.time, aspect);")
            case let .noise(scale, speed):
                lines.append("float4 \(c) = ollin_vis_noise(\(st), \(slot(scale)), \(slot(speed)), info.time, aspect);")
            case let .voronoi(scale, speed, blending):
                lines.append("float4 \(c) = ollin_vis_voronoi(\(st), \(slot(scale)), \(slot(speed)), \(slot(blending)), info.time, aspect);")
            case let .shape(sides, radius, smoothing):
                lines.append("float4 \(c) = ollin_vis_shape(\(st), \(slot(sides)), \(slot(radius)), \(slot(smoothing)), aspect);")
            case let .gradient(speed):
                lines.append("float4 \(c) = ollin_vis_gradient(\(st), \(slot(speed)), info.time);")
            case let .solid(color):
                lines.append("float4 \(c) = \(colorSlot(color));")
            case let .layer(target):
                let index: Int
                if let existing = layers.firstIndex(where: { $0 === target }) {
                    index = existing
                } else if layers.count < 2 {
                    layers.append(target)
                    index = layers.count - 1
                } else {
                    layersDropped += 1
                    lines.append("float4 \(c) = float4(0.0);")
                    return c
                }
                let read = index == 0 ? "sample" : "sampleAux"
                lines.append("float4 \(c) = \(read)(info, fract(\(st)));")
            }
            return c

        case .warp(let warp, let child):
            switch warp {
            case let .rotate(angle, speed):
                lines.append("\(st) = ollin_vis_rotate(\(st), float2(0.5), \(slot(angle)) + \(slot(speed)) * info.time, aspect);")
            case let .scale(amount, x, y):
                lines.append("\(st) = ollin_vis_scale(\(st), float2(0.5), \(slot(amount)), float2(\(slot(x)), \(slot(y))));")
            case let .pixelate(x, y):
                lines.append("\(st) = ollin_vis_pixelate(\(st), float2(\(slot(x)), \(slot(y))));")
            case let .repeatTiles(x, y, ox, oy):
                lines.append("\(st) = ollin_vis_repeat(\(st), float2(\(slot(x)), \(slot(y))), float2(\(slot(ox)), \(slot(oy))));")
            case let .kaleid(sides):
                lines.append("\(st) = ollin_vis_kaleid(\(st), float2(0.5), \(slot(sides)), 0.0, aspect);")
            case let .scroll(x, y, sx, sy):
                lines.append("\(st) = ollin_vis_scroll(\(st), float2(\(slot(x)), \(slot(y))), float2(\(slot(sx)), \(slot(sy))), info.time);")
            }
            return emit(child, st: st)

        case .adjust(let adjust, let child):
            let c = emit(child, st: st)
            switch adjust {
            case let .brightness(v):
                lines.append("\(c) = ollin_vis_brightness(\(c), \(slot(v)));")
            case let .contrast(v):
                lines.append("\(c) = ollin_vis_contrast(\(c), \(slot(v)));")
            case let .saturation(v):
                lines.append("\(c) = ollin_vis_saturate(\(c), \(slot(v)));")
            case let .invert(v):
                lines.append("\(c) = ollin_vis_invert(\(c), \(slot(v)));")
            case let .posterize(bins, gamma):
                lines.append("\(c) = ollin_vis_posterize(\(c), \(slot(bins)), \(slot(gamma)));")
            case let .threshold(t, tol):
                lines.append("\(c) = ollin_vis_threshold(\(c), \(slot(t)), \(slot(tol)));")
            case let .luma(t, tol):
                lines.append("\(c) = ollin_vis_luma(\(c), \(slot(t)), \(slot(tol)));")
            case let .hueShift(v):
                lines.append("\(c) = ollin_vis_hueShift(\(c), \(slot(v)));")
            case let .tint(color):
                lines.append("\(c) = ollin_vis_tint(\(c), \(colorSlot(color)));")
            case let .colorCycle(v):
                lines.append("\(c) = ollin_vis_colorCycle(\(c), \(slot(v)));")
            case let .channel(ch, scale, offset):
                lines.append("\(c) = ollin_vis_channel(\(c), \(ch.rawIndex), \(slot(scale)), \(slot(offset)));")
            }
            return c

        case .combine(let op, let base, let other):
            let stB = fresh("st")
            lines.append("float2 \(stB) = \(st);")
            let cB = emit(other, st: stB)
            let cA = emit(base, st: st)
            switch op {
            case let .blend(mode, amount):
                lines.append("\(cA) = ollin_vis_blend(\(cA), \(cB), \(mode.visualIndex), \(slot(amount)));")
            case let .mixAmount(amount):
                lines.append("\(cA) = mix(\(cA), \(cB), \(slot(amount)));")
            case .difference:
                lines.append("\(cA) = ollin_vis_difference(\(cA), \(cB));")
            case .mask:
                lines.append("\(cA) = ollin_vis_mask(\(cA), \(cB));")
            }
            return cA

        case .modulate(let mod, let base, let driver):
            let stD = fresh("st")
            lines.append("float2 \(stD) = \(st);")
            let cD = emit(driver, st: stD)
            switch mod {
            case let .displace(amount):
                lines.append("\(st) += \(cD).xy * \(slot(amount));")
            case let .rotate(amount, offset):
                lines.append("\(st) = ollin_vis_rotate(\(st), float2(0.5), \(slot(offset)) + \(cD).x * \(slot(amount)), aspect);")
            case let .scale(amount, offset):
                lines.append("\(st) = ollin_vis_scale(\(st), float2(0.5), \(slot(offset)) + \(cD).x * \(slot(amount)), float2(1.0));")
            case let .pixelate(amount, offset):
                lines.append("\(st) = ollin_vis_pixelate(\(st), float2(\(slot(offset))) + \(cD).xy * \(slot(amount)));")
            case let .kaleid(sides, amount):
                lines.append("\(st) = ollin_vis_kaleid(\(st), float2(0.5), \(slot(sides)), \(cD).x * \(slot(amount)), aspect);")
            }
            return emit(base, st: st)
        }
    }
}

// MARK: - Drawing a chain

public extension Sketch {

    /// Realize a `Visual` chain as a layer: compile it (once per structure; the
    /// pipeline is cached) and run it on the GPU, returning the `RenderTarget` it
    /// filled, ready to draw (`.image`), filter (`.filtered(_:)`), or feed into
    /// another effect (including another chain, via `.layer(_:)`).
    ///
    /// A sourceless chain fills a full-canvas layer (at `scale` of the canvas
    /// resolution); a chain that reads layers runs at its first layer's size.
    func generate(_ visual: Visual, scale: Double = 1) -> RenderTarget {
        let program = visual.compile()
        warnOnce(about: program)
        let shader = Shader(program.source, params: program.params)
        switch program.layers.count {
        case 0:  return generate(.shader(shader), scale: scale)
        case 1:  return program.layers[0].filtered(.shader(shader))
        default: return program.layers[0].combined(with: program.layers[1], .shader(shader))
        }
    }

    /// Realize a `Visual` chain as a layer of an explicit size (rather than the
    /// canvas size): the chain aspect-corrects for that size, so a tile or panel
    /// isn't a squashed full-canvas render. A chain that reads layers still runs
    /// at its first layer's size.
    func generate(_ visual: Visual, width: Int, height: Int, scale: Double = 1) -> RenderTarget {
        let program = visual.compile()
        warnOnce(about: program)
        let shader = Shader(program.source, params: program.params)
        switch program.layers.count {
        case 0:  return generate(.shader(shader), width: width, height: height, scale: scale)
        case 1:  return program.layers[0].filtered(.shader(shader))
        default: return program.layers[0].combined(with: program.layers[1], .shader(shader))
        }
    }

    /// Draw a `Visual` chain over the whole canvas: the one-line way to put a
    /// chain on screen. Sugar for `generate(_:)` + `drawImage`; it honors the
    /// current transform, `tint`, and blend mode like any image draw.
    func drawVisual(_ visual: Visual) {
        drawImage(generate(visual).image, in: bounds)
    }

    /// Surface a chain's compile-time compromises once per sketch run (the
    /// chain still renders; these are advisories, not errors).
    private func warnOnce(about program: VisualProgram) {
        if program.paramsOverflowed, VisualWarnings.raise(.paramsOverflow) {
            print("Ollin: a Visual chain carries more than \(OLLIN_SHADER_PARAM_COUNT) animatable values; the extras are baked into the shader, so changing them recompiles it.")
        }
        if program.layersDropped > 0, VisualWarnings.raise(.tooManyLayers) {
            print("Ollin: a Visual chain reads more than 2 distinct layers; the extras sample as transparent black. Flatten a sub-chain with generate(_:) and read that instead.")
        }
        if program.nodeCount > 256, VisualWarnings.raise(.hugeChain) {
            print("Ollin: a Visual chain has \(program.nodeCount) steps; it still renders as one pass, but a chain this large compiles slowly.")
        }
    }
}

/// Once-per-run advisory latch for `drawVisual`/`generate` chains.
@MainActor
private enum VisualWarnings {
    enum Kind: Hashable { case paramsOverflow, tooManyLayers, hugeChain }
    static var raised: Set<Kind> = []
    /// True the first time a kind is raised (the caller prints), false after.
    static func raise(_ kind: Kind) -> Bool { raised.insert(kind).inserted }
}

extension BlendMode {
    /// The selector `ollin_vis_blend` switches on (kept in step with the shader).
    var visualIndex: Int {
        switch self {
        case .normal: 0
        case .add: 1
        case .subtract: 2
        case .multiply: 3
        case .screen: 4
        case .lightest: 5
        case .darkest: 6
        }
    }
}
