import Foundation

/// Single-line drawing: connect a set of points into one continuous tour, the
/// traveling-salesman rendering of an image. Stipple a picture, tour the dots,
/// and the one unbroken line reads as the picture: dark regions pull the line
/// into tight meanders, light regions let it stride. The technique is Bosch
/// and Kaplan's TSP art; the tour here is a nearest-neighbor construction
/// polished by 2-opt, which also removes the crossings that would muddy the
/// tone.
///
/// ```swift
/// let dots = stipple(picture, count: 4000, in: frame)
/// let line = singleLine(through: dots)
/// drawPolyline(line.points, closed: line.isClosed)
/// ```
///
/// The output is a `Contour`, so it feeds `drawPolyline`, `drawCurve` (for
/// the smoothed reading), hatching, and SVG export; a single closed line is
/// the friendliest thing a pen plotter can be handed. Deterministic given the
/// points, and setup-time-shaped: tour once and hold the result.

/// One continuous tour through `points`, nearest-neighbor built and 2-opt
/// improved. `closed` returns to the start (the classic reading); an open
/// tour instead cuts the longest edge and walks end to end. Deterministic.
/// Quadratic-ish work: thousands of points are comfortable, hundreds of
/// thousands are not.
public func singleLine(through points: [Vector2], closed: Bool = true) -> Contour {
    let n = points.count
    guard n >= 3 else { return Contour(points, closed: false) }

    // Bucket the points so nearest-unvisited queries scan a neighborhood.
    var minX = points[0].x, maxX = points[0].x
    var minY = points[0].y, maxY = points[0].y
    for p in points {
        minX = Swift.min(minX, p.x); maxX = Swift.max(maxX, p.x)
        minY = Swift.min(minY, p.y); maxY = Swift.max(maxY, p.y)
    }
    let extentX = Swift.max(maxX - minX, 1e-9)
    let extentY = Swift.max(maxY - minY, 1e-9)
    // The area term sizes buckets for a balanced cloud; the extent term
    // floors them for a degenerate strip (collinear points), where the area
    // collapses and would otherwise explode the grid to millions of cells.
    let bucketSide = Swift.max((extentX * extentY / Double(n)).squareRoot(),
                               Swift.max(extentX, extentY) / Double(n),
                               1e-9)
    let cols = Swift.max(Int((extentX / bucketSide).rounded(.up)), 1)
    let rows = Swift.max(Int((extentY / bucketSide).rounded(.up)), 1)
    let maxRing = Swift.max(cols, rows)

    var buckets = [[Int]](repeating: [], count: cols * rows)
    func bucketOf(_ p: Vector2) -> (Int, Int) {
        (Swift.min(Swift.max(Int((p.x - minX) / bucketSide), 0), cols - 1),
         Swift.min(Swift.max(Int((p.y - minY) / bucketSide), 0), rows - 1))
    }
    for (i, p) in points.enumerated() {
        let (bx, by) = bucketOf(p)
        buckets[by * cols + bx].append(i)
    }

    /// Nearest point to `from` that passes `admit`, by expanding-ring search.
    /// A point in ring r is at least (r−1)·bucketSide away, so the scan stops
    /// once the best find beats that bound. Ties break on the lower index.
    func nearest(to from: Vector2, admit: (Int) -> Bool) -> Int {
        let (bx, by) = bucketOf(from)
        var best = -1
        var bestDistance = Double.infinity
        var ring = 0
        while ring <= maxRing {
            if best >= 0, bestDistance.squareRoot() <= Double(ring - 1) * bucketSide { break }
            let yLo = by - ring, yHi = by + ring
            // Clamped to the grid, so an off-grid stretch of ring is skipped
            // in one step rather than walked cell by cell.
            for cy in Swift.max(yLo, 0) ... Swift.min(yHi, rows - 1) {
                func scan(_ cx: Int) {
                    guard cx >= 0, cx < cols else { return }
                    for i in buckets[cy * cols + cx] where admit(i) {
                        let d = points[i].distanceSquared(to: from)
                        if d < bestDistance || (d == bestDistance && i < best) {
                            bestDistance = d
                            best = i
                        }
                    }
                }
                if cy == yLo || cy == yHi || ring == 0 {
                    for cx in Swift.max(bx - ring, 0) ... Swift.min(bx + ring, cols - 1) {
                        scan(cx)
                    }
                } else {
                    // Interior rows visit only the ring's two edge columns.
                    scan(bx - ring)
                    scan(bx + ring)
                }
            }
            ring += 1
        }
        return best
    }

    // Nearest-neighbor construction from the first point.
    var tour = [Int]()
    tour.reserveCapacity(n)
    var visited = [Bool](repeating: false, count: n)
    var current = 0
    visited[0] = true
    tour.append(0)
    for _ in 1 ..< n {
        let next = nearest(to: points[current]) { !visited[$0] }
        guard next >= 0 else { break }
        visited[next] = true
        tour.append(next)
        current = next
    }

    // Candidate lists for 2-opt: each point's k nearest others.
    let k = Swift.min(8, n - 1)
    var neighbors = [[Int]](repeating: [], count: n)
    for i in 0 ..< n {
        var found: [(d: Double, index: Int)] = []
        let (bx, by) = bucketOf(points[i])
        var ring = 0
        while ring <= maxRing {
            // Safe to stop before ring r once the kth-best find is closer
            // than anything ring r could hold.
            if found.count >= k,
               found[k - 1].d.squareRoot() <= Double(ring - 1) * bucketSide { break }
            let yLo = by - ring, yHi = by + ring
            for cy in Swift.max(yLo, 0) ... Swift.min(yHi, rows - 1) {
                func scan(_ cx: Int) {
                    guard cx >= 0, cx < cols else { return }
                    for j in buckets[cy * cols + cx] where j != i {
                        found.append((points[i].distanceSquared(to: points[j]), j))
                    }
                }
                if cy == yLo || cy == yHi || ring == 0 {
                    for cx in Swift.max(bx - ring, 0) ... Swift.min(bx + ring, cols - 1) {
                        scan(cx)
                    }
                } else {
                    scan(bx - ring)
                    scan(bx + ring)
                }
            }
            found.sort { $0.d != $1.d ? $0.d < $1.d : $0.index < $1.index }
            if found.count > k * 2 { found.removeLast(found.count - k * 2) }
            ring += 1
        }
        neighbors[i] = found.prefix(k).map(\.index)
    }

    // 2-opt: uncross edge pairs while any candidate swap shortens the tour.
    var position = [Int](repeating: 0, count: n)
    for (index, point) in tour.enumerated() { position[point] = index }
    func distance(_ a: Int, _ b: Int) -> Double { points[a].distance(to: points[b]) }

    var pass = 0
    var improved = true
    while improved && pass < 50 {
        improved = false
        pass += 1
        for i in 0 ..< n {
            let a = tour[i]
            let b = tour[(i + 1) % n]
            let dab = distance(a, b)
            for c in neighbors[a] {
                let j = position[c]
                guard j > i, c != b else { continue }
                let d = tour[(j + 1) % n]
                guard d != a else { continue }
                let delta = distance(a, c) + distance(b, d) - dab - distance(c, d)
                if delta < -1e-9 {
                    // Reverse tour[i+1 ... j] and fix the position index.
                    var lo = i + 1, hi = j
                    while lo < hi {
                        tour.swapAt(lo, hi)
                        position[tour[lo]] = lo
                        position[tour[hi]] = hi
                        lo += 1
                        hi -= 1
                    }
                    if lo == hi { position[tour[lo]] = lo }
                    improved = true
                    break   // b changed; move to the next tour edge
                }
            }
        }
    }

    if closed { return Contour(tour.map { points[$0] }, closed: true) }

    // Open line: cut the tour's longest edge and walk from there.
    var cutAfter = 0
    var longest = -1.0
    for i in 0 ..< n {
        let d = distance(tour[i], tour[(i + 1) % n])
        if d > longest {
            longest = d
            cutAfter = i
        }
    }
    let start = (cutAfter + 1) % n
    let walked = (0 ..< n).map { points[tour[(start + $0) % n]] }
    return Contour(walked, closed: false)
}

// MARK: - Sketch sugar

public extension Sketch {
    /// The single-line rendering of `image`: stipple it with `points` dots,
    /// then tour them into one continuous line. The image is stretched over
    /// `bounds` (the whole canvas by default); pass a `Rectangle(fitting:in:)`
    /// of the image's size to keep its aspect. Driven by the seeded `random`,
    /// so `seed(_:)` reproduces the drawing. Setup-time work: tour once and
    /// hold the contour.
    ///
    /// `cutoff` rounds bright grays up to paper: pixels lighter than it place
    /// no dots, so light regions stay genuinely empty instead of collecting a
    /// thin wandering line. Lower it toward `1` ... `0.7` for high-key images.
    func singleLine(of image: Image,
                    points count: Int,
                    in bounds: Rectangle? = nil,
                    iterations: Int = 40,
                    cutoff: Double = 0.85,
                    closed: Bool = true) -> Contour {
        let rect = bounds ?? canvasRectangle
        guard image.width > 0, image.height > 0 else { return Contour([], closed: false) }
        let cutoffLinear = Color.srgbToLinear(Swift.min(Swift.max(cutoff, 0), 1))
        let dots = stipple(count: count, in: rect, iterations: iterations) { p in
            let px = Swift.min(Swift.max(Int((p.x - rect.x) / rect.width * Double(image.width)), 0),
                               image.width - 1)
            let py = Swift.min(Swift.max(Int((p.y - rect.y) / rect.height * Double(image.height)), 0),
                               image.height - 1)
            let c = image[px, py]
            let tone = c.luminance
            guard tone < cutoffLinear else { return 0 }
            return (1 - tone) * c.alpha
        }
        return Ollin.singleLine(through: dots, closed: closed)
    }

    /// The tour itself, over points you already have: a stipple, a blue-noise
    /// scatter, cluster centers, hand-placed anchors. `closed` returns to the
    /// start; an open tour cuts the longest edge and walks end to end.
    ///
    /// Mirrors the free function of the same name, which the `of:points:` form
    /// above would otherwise shadow inside a `Sketch`.
    func singleLine(through points: [Vector2], closed: Bool = true) -> Contour {
        Ollin.singleLine(through: points, closed: closed)
    }
}
