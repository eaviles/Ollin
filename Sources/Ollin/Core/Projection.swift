import Foundation

public extension Installation {

    /// How the picture is shaped to fit what it is thrown onto.
    ///
    /// A projector is almost never square to its wall. It hangs off a beam, or
    /// sits on a shelf to one side, and the picture lands as a trapezoid a few
    /// degrees out of true. Corner-pinning is the answer: you say where the
    /// four corners of the picture actually belong, and everything between them
    /// follows. You do not type those numbers. You run the piece, press
    /// Command-K, and drag the corners onto the wall; they are kept per display
    /// and read back on the next launch.
    ///
    /// What you do declare is how this machine's picture sits in a bigger one.
    /// Two projectors covering one long wall each carry a part of the canvas
    /// and overlap in the middle, so each says which part it carries and how
    /// wide the shared band is:
    ///
    /// ```swift
    /// override var installation: Installation {
    ///     Installation(projection: .init(shows: Rectangle(x: 0, y: 0, width: 0.55, height: 1),
    ///                                    blend: Insets(right: 0.1)))
    /// }
    /// ```
    ///
    /// The machine on the right declares the mirror of that. Both fade out
    /// across the same tenth of the canvas, so the two beams add up to one
    /// picture with no bright bar down the join.
    ///
    /// The warp is on the screen only. An export re-renders the canvas and
    /// never carries it, because a file has no wall to fit.
    struct Projection: Sendable, Equatable {

        /// Straight out: the whole canvas, nothing shaped. The default, and the
        /// one value that costs nothing, since the present pass is untouched.
        ///
        /// A saved calibration still applies to a piece that declares this. The
        /// corners belong to the room rather than to the work.
        public static let direct = Projection()

        /// The whole canvas, which is what one machine on its own carries.
        public static let wholeCanvas = Rectangle(x: 0, y: 0, width: 1, height: 1)

        /// Which part of the canvas this machine puts on the wall, in fractions
        /// of the canvas. The whole of it by default.
        public var shows: Rectangle

        /// Where that part lands on the output, in fractions of the display.
        /// ``Corners/fit`` keeps its proportions and centers it, which is what
        /// you see before anybody drags anything.
        public var corners: Corners

        /// How wide the band is where this machine's picture fades out, on each
        /// edge, in fractions of the canvas. Zero on an edge nothing overlaps.
        ///
        /// The same units as ``shows`` on purpose: both machines sharing a band
        /// are then told the same number, so their two fades are the same
        /// function of the same wall, and add to exactly one coat.
        public var blend: Insets

        /// How the fade is shaped: 1 is a straight line, 2 an S that spends
        /// longer at full brightness and longer at nothing. Two is the number
        /// the published work uses, and the one to leave alone until you see a
        /// band you do not like.
        public var blendCurve: Double

        /// What your projector does with the standard curve. 2.2 is that curve,
        /// and with it the fades add up exactly, because the light a projector
        /// makes is then proportional to the numbers this sends it.
        ///
        /// It is the dial to reach for when a calibrated overlap still reads
        /// brighter or darker than the picture beside it: a real projector
        /// answers its own way, and this says which way.
        public var gamma: Double

        public init(shows: Rectangle = Projection.wholeCanvas,
                    corners: Corners = .fit,
                    blend: Insets = Insets(),
                    blendCurve: Double = 2,
                    gamma: Double = Projection.standardGamma) {
            self.shows = shows
            self.corners = corners
            self.blend = blend
            self.blendCurve = blendCurve
            self.gamma = gamma
        }

        /// The curve every display is meant to answer, and the value that makes
        /// the fade exact.
        public static let standardGamma = 2.2

        /// Whether the sketch declared nothing here. A saved calibration can
        /// still put a warp on the run, so this is not the same as "no warp".
        var isDirect: Bool { self == .direct }

        /// Where the four corners of the picture land on the output, in
        /// fractions of the display, with (0, 0) the top left.
        ///
        /// You do not usually build one of these. Command-K on a running piece
        /// gives you handles to drag, and what you drag is kept.
        public struct Corners: Sendable, Equatable, Codable {

            /// Keep the picture's own proportions, as large as it can be,
            /// centered. What every run starts from.
            public static let fit = Corners()

            /// Stretch the picture to the whole output, proportions and all.
            /// For a display whose shape already matches the wall.
            public static let filling = Corners(topLeft: Vector2(0, 0),
                                                topRight: Vector2(1, 0),
                                                bottomRight: Vector2(1, 1),
                                                bottomLeft: Vector2(0, 1))

            /// The four points, clockwise from the top left, or nil for
            /// ``fit``, which has no numbers of its own until it meets an
            /// output to be worked out against.
            private var points: [Vector2]?

            public init() { points = nil }

            public init(topLeft: Vector2, topRight: Vector2,
                        bottomRight: Vector2, bottomLeft: Vector2) {
                points = [topLeft, topRight, bottomRight, bottomLeft]
            }

            /// Whether these are still the proportions-keeping default.
            public var isFit: Bool { points == nil }

            /// The four points, clockwise from the top left, once ``fit`` has
            /// been worked out against an output.
            ///
            /// - Parameters:
            ///   - outputAspect: the display's width over its height.
            ///   - pictureAspect: the shown part of the canvas, the same way.
            func resolved(outputAspect: Double, pictureAspect: Double) -> [Vector2] {
                if let points { return points }
                guard outputAspect > 0, pictureAspect > 0 else {
                    return Corners.filling.points ?? []
                }
                // The largest box of the picture's shape inside a unit box of
                // the display's, then centered in what is left over.
                let wide = pictureAspect > outputAspect
                let width = wide ? 1 : pictureAspect / outputAspect
                let height = wide ? outputAspect / pictureAspect : 1
                let x = (1 - width) / 2, y = (1 - height) / 2
                return [Vector2(x, y), Vector2(x + width, y),
                        Vector2(x + width, y + height), Vector2(x, y + height)]
            }

            /// The same corners with one of them moved, for a hand dragging a
            /// handle. A ``fit`` becomes its own four numbers on the first drag,
            /// which is why this takes the aspects.
            func moving(_ index: Int, to point: Vector2,
                        outputAspect: Double, pictureAspect: Double) -> Corners {
                var moved = resolved(outputAspect: outputAspect, pictureAspect: pictureAspect)
                guard moved.indices.contains(index) else { return self }
                moved[index] = point
                return Corners(topLeft: moved[0], topRight: moved[1],
                               bottomRight: moved[2], bottomLeft: moved[3])
            }
        }
    }
}

// MARK: - Working the declaration out against a display

/// A projection resolved against one canvas and one display: the map itself,
/// and the numbers the present pass reads.
///
/// Held apart from the declaration because it depends on the display, which the
/// sketch knows nothing about, and changes under the run when a monitor does.
struct ProjectionPlacement: Equatable {

    /// The unit square onto the four corners, in output fractions.
    let homography: Homography
    /// The part of the canvas this output carries, in canvas fractions.
    let source: Rectangle
    /// The four corners it was built from, in output fractions.
    let corners: [Vector2]
    /// How far in the fade reaches from each edge, in fractions of the shown
    /// part rather than of the canvas, since that is the space the map runs in.
    let fade: Insets
    /// The shape of the fade, and the projector's answer to the standard curve
    /// as the power to raise a fade by.
    let curve: Double
    let gammaExponent: Double

    /// Nil when the four corners make no shape with an inside, or when the
    /// declared part of the canvas has no area. A run then presents as it
    /// always did rather than showing nothing.
    init?(_ projection: Installation.Projection, canvas: Vector2, output: Vector2) {
        let shows = projection.shows
        guard shows.width > 0, shows.height > 0, canvas.x > 0, canvas.y > 0,
              output.x > 0, output.y > 0 else { return nil }

        let pictureAspect = (shows.width * canvas.x) / (shows.height * canvas.y)
        let points = projection.corners.resolved(outputAspect: output.x / output.y,
                                                 pictureAspect: pictureAspect)
        guard points.count == 4,
              let map = Homography(unitSquareTo: points[0], points[1], points[2], points[3])
        else { return nil }

        homography = map
        source = shows
        corners = points
        // Canvas fractions into fractions of what this output shows: the same
        // physical band, measured against the part rather than the whole.
        fade = Insets(top: min(1, projection.blend.top / shows.height),
                      right: min(1, projection.blend.right / shows.width),
                      bottom: min(1, projection.blend.bottom / shows.height),
                      left: min(1, projection.blend.left / shows.width))
        curve = max(0.01, projection.blendCurve)
        gammaExponent = projection.gamma > 0
            ? Installation.Projection.standardGamma / projection.gamma : 1
    }

    /// Where a point on the display, in output fractions, sits on the canvas,
    /// in canvas fractions. What the pointer goes through, so a sketch reading
    /// `mouseX` reads the picture rather than the screen.
    func canvasPoint(fromOutput point: Vector2) -> Vector2 {
        let q = homography.unmap(point)
        return Vector2(source.x + q.x * source.width, source.y + q.y * source.height)
    }

    /// The same journey the other way: where a point on the canvas, in canvas
    /// fractions, lands on the display. What a described part goes through, so a
    /// screen reader points at the piece of wall it is talking about.
    func outputPoint(fromCanvas point: Vector2) -> Vector2 {
        guard source.width > 0, source.height > 0 else { return point }
        return homography.map(Vector2((point.x - source.x) / source.width,
                                      (point.y - source.y) / source.height))
    }
}
