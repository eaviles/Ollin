import Foundation

/// String art: one continuous thread wound between pins on a circular rim,
/// chord after chord, until the crossings reproduce a picture. Dark regions
/// collect many crossings and light regions few, so a portrait emerges from
/// nothing but straight lines. The craft is Petros Vrellis's knitted
/// portraits; the choice of each chord here is the standard greedy step:
/// from the pin the thread is on, score every allowed next pin by how much
/// darkness its chord still covers, take the best one, and pay the ink down
/// so the next chords look elsewhere.
///
/// It's a stateful stepper you hold and draw *incrementally*: `step()` winds
/// one more chord and returns it, ready to lay onto an accumulating canvas
/// (`noClear()`), so the picture knits itself over the first seconds of the
/// run. Fully deterministic: the same picture and settings always wind the
/// same thread, no seed involved.
///
/// ```swift
/// let art = StringArt(of: picture, center: canvasCenter, radius: 460)
///
/// override func setup() { noClear() }
///
/// override func draw() {
///     if frameCount == 1 { background(.white) }
///     stroke(Color.black.withAlpha(0.45))
///     for chord in art.step(8) {
///         drawLine(chord.from, chord.to)
///     }
/// }
/// ```
///
/// `thread` is the whole winding so far as one open `Contour`, the
/// friendliest thing a pen plotter can be handed; `sequence` is the pin
/// order, which *is* the piece if you ever wind it by hand.
public final class StringArt {
    /// One wound chord: the pins it spans and their canvas positions.
    public struct Chord {
        /// The pin the thread left.
        public let fromPin: Int
        /// The pin the thread arrived at.
        public let toPin: Int
        /// The canvas position of `fromPin`.
        public let from: Vector2
        /// The canvas position of `toPin`.
        public let to: Vector2
    }

    /// The pins on the rim, in canvas coordinates. Pin `0` sits at the top;
    /// indices run clockwise.
    public let pins: [Vector2]

    /// The pin visit order so far, starting at pin `0`. Each adjacent pair is
    /// one chord of thread.
    public private(set) var sequence: [Int]

    /// The number of chords wound so far.
    public var chordCount: Int { sequence.count - 1 }

    /// `true` once the winding has stopped: the chord cap is reached, or no
    /// remaining chord would cover enough darkness to be worth its ink.
    public private(set) var isFinished = false

    /// The whole winding so far as one open polyline through the pins, for
    /// `drawPolyline` and the vector exports.
    public var thread: Contour {
        Contour(sequence.map { pins[$0] }, closed: false)
    }

    private let pinCount: Int
    private let maxChords: Int
    private let ink: Double
    private let minimumSpan: Int
    private let diameter: Int
    private var residual: [Double]        // darkness left to cover, per grid cell
    private let gridPins: [Vector2]       // pin positions in grid coordinates
    private var usedPairs = Set<Int>()    // unordered pin pairs already wound

    /// A winding of `image` over a circle of pins on the canvas.
    ///
    /// The picture's largest centered square is what the circle reads (crop
    /// beforehand to choose a different region); tone is the linear-light
    /// darkness `(1 - luminance) * alpha`, so transparency reads as paper.
    /// A texture-backed image has no CPU pixels, so it winds nothing; read a
    /// video frame through its snapshot first.
    ///
    /// - Parameters:
    ///   - image: the picture to reproduce.
    ///   - center: the circle's center on the canvas.
    ///   - radius: the circle's radius on the canvas.
    ///   - pins: how many pins ring the rim.
    ///   - chords: the winding stops at this many chords, the craft's "how
    ///     much thread" dial.
    ///   - ink: how much darkness one pass of thread pays down (`0...1`).
    ///     Lower ink winds more, finer chords before a region reads as done;
    ///     it pairs with the stroke alpha the chords are drawn at.
    ///   - minimumSpan: the shortest chord allowed, measured in pins around
    ///     the rim, so the thread crosses the picture instead of hugging the
    ///     rim. Defaults to a tenth of the pins.
    ///   - inverted: wind the light instead of the dark, for bright thread
    ///     on a dark ground.
    ///   - resolution: the side of the internal working grid the scoring
    ///     runs on. The default suits canvas-sized work; raise it for fine
    ///     detail at a cost in setup and per-chord time.
    public init(of image: Image, center: Vector2, radius: Double,
                pins: Int = 200, chords: Int = 4000, ink: Double = 0.055,
                minimumSpan: Int? = nil, inverted: Bool = false,
                resolution: Int = 300) {
        self.pinCount = Swift.max(pins, 3)
        self.maxChords = Swift.max(chords, 0)
        self.ink = Swift.min(Swift.max(ink, 0.001), 1)
        let span = minimumSpan ?? self.pinCount / 10
        self.minimumSpan = Swift.min(Swift.max(span, 1), (self.pinCount - 1) / 2)
        self.diameter = Swift.max(resolution, 16)
        self.sequence = [0]

        // The pins: 0 at the top, clockwise, on the canvas and on the grid.
        let gridCenter = Double(diameter) / 2
        let gridRadius = gridCenter - 1
        var rim: [Vector2] = []
        var gridRim: [Vector2] = []
        rim.reserveCapacity(pinCount)
        gridRim.reserveCapacity(pinCount)
        for i in 0 ..< pinCount {
            let angle = -Double.pi / 2 + .tau * Double(i) / Double(pinCount)
            let direction = Vector2(cos(angle), sin(angle))
            rim.append(center + direction * radius)
            gridRim.append(Vector2(gridCenter, gridCenter) + direction * gridRadius)
        }
        self.pins = rim
        self.gridPins = gridRim

        self.residual = StringArt.sampleDarkness(of: image, diameter: diameter,
                                                 inverted: inverted)
        if maxChords == 0 { isFinished = true }
    }

    /// Wind one more chord. Returns `nil` once the winding is finished: the
    /// chord cap is reached, or no allowed chord still covers enough darkness.
    @discardableResult
    public func step() -> Chord? {
        guard !isFinished else { return nil }
        guard chordCount < maxChords else { isFinished = true; return nil }

        let from = sequence[sequence.count - 1]
        var bestPin = -1
        var bestScore = ink / 2   // a chord must beat over-inking to be wound
        residual.withUnsafeBufferPointer { grid in
            for candidate in 0 ..< pinCount {
                let gap = abs(candidate - from)
                guard Swift.min(gap, pinCount - gap) >= minimumSpan else { continue }
                guard !usedPairs.contains(pairKey(from, candidate)) else { continue }
                let score = meanDarkness(from: gridPins[from], to: gridPins[candidate],
                                         in: grid)
                if score > bestScore {
                    bestScore = score
                    bestPin = candidate
                }
            }
        }
        guard bestPin >= 0 else { isFinished = true; return nil }

        bleach(from: gridPins[from], to: gridPins[bestPin])
        usedPairs.insert(pairKey(from, bestPin))
        sequence.append(bestPin)
        return Chord(fromPin: from, toPin: bestPin,
                     from: pins[from], to: pins[bestPin])
    }

    /// Wind up to `count` more chords, collecting them. Returns fewer once
    /// the winding finishes.
    @discardableResult
    public func step(_ count: Int) -> [Chord] {
        var chords: [Chord] = []
        chords.reserveCapacity(Swift.max(count, 0))
        for _ in 0 ..< Swift.max(count, 0) {
            guard let chord = step() else { break }
            chords.append(chord)
        }
        return chords
    }

    // MARK: - Internals

    private func pairKey(_ a: Int, _ b: Int) -> Int {
        Swift.min(a, b) * pinCount + Swift.max(a, b)
    }

    /// The mean remaining darkness along the chord, sampled one grid cell at
    /// a time. The mean (not the sum) keeps a short dark chord competitive
    /// with a long gray one.
    private func meanDarkness(from a: Vector2, to b: Vector2,
                              in grid: UnsafeBufferPointer<Double>) -> Double {
        let steps = Swift.max(Int(a.distance(to: b).rounded()), 1)
        let dx = (b.x - a.x) / Double(steps)
        let dy = (b.y - a.y) / Double(steps)
        var x = a.x, y = a.y
        var sum = 0.0
        for _ in 0 ... steps {
            sum += grid[Swift.min(Swift.max(Int(y), 0), diameter - 1) * diameter
                        + Swift.min(Swift.max(Int(x), 0), diameter - 1)]
            x += dx
            y += dy
        }
        return sum / Double(steps + 1)
    }

    /// Pay the chord's ink down along the same samples the score walked, so
    /// the next chords look elsewhere.
    private func bleach(from a: Vector2, to b: Vector2) {
        let steps = Swift.max(Int(a.distance(to: b).rounded()), 1)
        let dx = (b.x - a.x) / Double(steps)
        let dy = (b.y - a.y) / Double(steps)
        let ink = self.ink
        let diameter = self.diameter
        residual.withUnsafeMutableBufferPointer { grid in
            var x = a.x, y = a.y
            for _ in 0 ... steps {
                let i = Swift.min(Swift.max(Int(y), 0), diameter - 1) * diameter
                        + Swift.min(Swift.max(Int(x), 0), diameter - 1)
                grid[i] = Swift.max(grid[i] - ink, 0)
                x += dx
                y += dy
            }
        }
    }

    /// The working grid: the image's largest centered square resampled to
    /// `diameter` cells a side, each cell the linear-light darkness of its
    /// pixel, zero outside the inscribed circle. Walks the premultiplied
    /// bytes the way the other picture renderings do.
    private static func sampleDarkness(of image: Image, diameter: Int,
                                       inverted: Bool) -> [Double] {
        var grid = [Double](repeating: 0, count: diameter * diameter)
        guard image.width > 0, image.height > 0 else { return grid }
        guard let pixels = image.premultipliedPixels() else {
            print("Ollin: string art needs CPU pixels; a texture-backed image has none. "
                  + "Read a video frame through its snapshot first.")
            return grid
        }

        let side = Swift.min(image.width, image.height)
        let x0 = (image.width - side) / 2
        let y0 = (image.height - side) / 2
        let scale = Double(side) / Double(diameter)
        let center = Double(diameter) / 2
        let reach = center - 1
        let reachSquared = reach * reach

        for gy in 0 ..< diameter {
            let dy = Double(gy) + 0.5 - center
            let py = Swift.min(y0 + Int((Double(gy) + 0.5) * scale), y0 + side - 1)
            for gx in 0 ..< diameter {
                let dx = Double(gx) + 0.5 - center
                guard dx * dx + dy * dy <= reachSquared else { continue }
                let px = Swift.min(x0 + Int((Double(gx) + 0.5) * scale), x0 + side - 1)
                let i = (py * image.width + px) * 4
                let alphaByte = Int(pixels[i + 3])
                guard alphaByte > 0 else { continue }   // transparent reads as paper
                let alpha = Double(alphaByte) / 255
                // Straight bytes back out of the premultiplied store, then
                // linear-light luminance, the ink rule the dot screens use.
                let red = Swift.min(Int(pixels[i]) * 255 / alphaByte, 255)
                let green = Swift.min(Int(pixels[i + 1]) * 255 / alphaByte, 255)
                let blue = Swift.min(Int(pixels[i + 2]) * 255 / alphaByte, 255)
                let luma = 0.2126 * Color.srgbToLinear(Double(red) / 255)
                         + 0.7152 * Color.srgbToLinear(Double(green) / 255)
                         + 0.0722 * Color.srgbToLinear(Double(blue) / 255)
                grid[gy * diameter + gx] = inverted ? luma * alpha : (1 - luma) * alpha
            }
        }
        return grid
    }
}
