import Foundation

/// A rectangular grid of terrain heights: the working surface for generated
/// landscapes. Fill one from any per-point field (the sketch's `fbm` is the
/// classic), or grow one with `diamondSquare`; sculpt it with `eroded(_:seed:)`
/// (particle hydraulic erosion carving ravines and fans, thermal relaxation
/// settling scree); then read it out as a `mesh(...)` for [3D mode], a
/// grayscale `image()`, or per-point samples for contours and fields.
///
/// ```swift
/// var land = Heightfield(columns: 257, rows: 257) { u, v in
///     fbm(u * 3, v * 3, octaves: 6)
/// }
/// land = land.eroded(.hydraulic(), seed: 7).eroded(.thermal())
/// drawMesh(land.mesh(width: 600, depth: 600, height: 140))
/// ```
///
/// Heights are plain `Double`s, `0…1` by convention (the generators emit that
/// range and the erosion defaults assume it; `normalized()` restores it after
/// hand edits). Everything is deterministic: the generators and the eroders
/// draw only from the seed you pass, so a terrain reproduces exactly.
public struct Heightfield: Sendable {

    /// Sample columns (the grid's width in samples, x / u direction).
    public let columns: Int
    /// Sample rows (the grid's depth in samples, y / v direction).
    public let rows: Int
    /// The heights, row-major (`values[y * columns + x]`), `0…1` by convention.
    public var values: [Double]

    /// A flat field of `height` everywhere.
    public init(columns: Int, rows: Int, repeating height: Double = 0) {
        self.columns = max(2, columns)
        self.rows = max(2, rows)
        values = [Double](repeating: height, count: self.columns * self.rows)
    }

    /// A field from explicit row-major heights (`values.count` must be
    /// `columns * rows`).
    public init(columns: Int, rows: Int, values: [Double]) {
        precondition(values.count == columns * rows,
                     "Heightfield needs columns * rows values")
        precondition(columns >= 2 && rows >= 2, "Heightfield needs at least 2×2 samples")
        self.columns = columns
        self.rows = rows
        self.values = values
    }

    /// A field sampled from a function of normalized coordinates: `field(u, v)`
    /// is called once per sample with `u`, `v` in `0…1` across the grid.
    ///
    /// ```swift
    /// let land = Heightfield(columns: 257, rows: 257) { u, v in
    ///     fbm(u * 3, v * 3, octaves: 6)
    /// }
    /// ```
    public init(columns: Int, rows: Int, _ field: (Double, Double) -> Double) {
        let cols = max(2, columns), rws = max(2, rows)
        var values = [Double]()
        values.reserveCapacity(cols * rws)
        for y in 0 ..< rws {
            let v = Double(y) / Double(rws - 1)
            for x in 0 ..< cols {
                values.append(field(Double(x) / Double(cols - 1), v))
            }
        }
        self.init(columns: cols, rows: rws, values: values)
    }

    /// Direct sample access (`x` across, `y` down; both must be in bounds).
    public subscript(x: Int, y: Int) -> Double {
        get { values[y * columns + x] }
        set { values[y * columns + x] = newValue }
    }

    /// The height at normalized coordinates (`u`, `v` in `0…1`, clamped),
    /// bilinearly interpolated between the surrounding samples.
    public func value(atU u: Double, v: Double) -> Double {
        let fx = min(max(u, 0), 1) * Double(columns - 1)
        let fy = min(max(v, 0), 1) * Double(rows - 1)
        let x0 = min(Int(fx), columns - 2), y0 = min(Int(fy), rows - 2)
        let tx = fx - Double(x0), ty = fy - Double(y0)
        let a = self[x0, y0], b = self[x0 + 1, y0]
        let c = self[x0, y0 + 1], d = self[x0 + 1, y0 + 1]
        return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
    }

    /// The field rescaled so its lowest sample sits at 0 and its highest at 1
    /// (a flat field maps to all zeros).
    public func normalized() -> Heightfield {
        guard let lo = values.min(), let hi = values.max(), hi > lo else {
            return Heightfield(columns: columns, rows: rows, repeating: 0)
        }
        let span = hi - lo
        return Heightfield(columns: columns, rows: rows,
                           values: values.map { ($0 - lo) / span })
    }
}

// MARK: - Diamond-square

public extension Heightfield {

    /// Fractal terrain by **diamond-square** subdivision: seed the corners,
    /// then alternately set each square's center (the diamond step) and each
    /// edge midpoint (the square step) to the average of its neighbors plus a
    /// random offset, halving the grid step as the offsets shrink by
    /// `roughness` per level. The classic plasma/terrain fractal.
    ///
    /// `size` rounds up to the next power-of-two-plus-one the algorithm needs
    /// (129, 257, 513, …). `roughness` runs 0…1: low values roll smoothly,
    /// high values stay jagged at every scale (0.5 is a natural landscape).
    /// The result is normalized to `0…1` and reproduces exactly from `seed`.
    static func diamondSquare(size: Int, roughness: Double = 0.5,
                              seed: UInt64 = 1) -> Heightfield {
        var rng = SplitMix64(seed: seed)
        return diamondSquare(size: size, roughness: roughness, using: &rng)
    }

    /// The generic form of `diamondSquare(size:roughness:seed:)`, drawing from
    /// any random generator you supply.
    static func diamondSquare<R: RandomNumberGenerator>(
        size: Int, roughness: Double = 0.5, using rng: inout R
    ) -> Heightfield {
        // Round up to 2^k + 1.
        var side = 3
        while side < max(3, size) { side = (side - 1) * 2 + 1 }
        let rough = min(max(roughness, 0), 1)

        var field = Heightfield(columns: side, rows: side)
        field[0, 0] = Double.random(in: 0 ... 1, using: &rng)
        field[side - 1, 0] = Double.random(in: 0 ... 1, using: &rng)
        field[0, side - 1] = Double.random(in: 0 ... 1, using: &rng)
        field[side - 1, side - 1] = Double.random(in: 0 ... 1, using: &rng)

        var step = side - 1
        var amplitude = 1.0
        while step >= 2 {
            let half = step / 2

            // Diamond step: every square's center from its four corners.
            for y in stride(from: half, to: side, by: step) {
                for x in stride(from: half, to: side, by: step) {
                    let mean = (field[x - half, y - half] + field[x + half, y - half]
                              + field[x - half, y + half] + field[x + half, y + half]) / 4
                    field[x, y] = mean + Double.random(in: -0.5 ... 0.5, using: &rng) * amplitude
                }
            }

            // Square step: every edge midpoint from its orthogonal neighbors
            // (three of them along the border, no wrapping).
            for y in stride(from: 0, to: side, by: half) {
                let xStart = (y / half).isMultiple(of: 2) ? half : 0
                for x in stride(from: xStart, to: side, by: step) {
                    var sum = 0.0, count = 0.0
                    if x >= half { sum += field[x - half, y]; count += 1 }
                    if x + half < side { sum += field[x + half, y]; count += 1 }
                    if y >= half { sum += field[x, y - half]; count += 1 }
                    if y + half < side { sum += field[x, y + half]; count += 1 }
                    field[x, y] = sum / count + Double.random(in: -0.5 ... 0.5, using: &rng) * amplitude
                }
            }

            step = half
            amplitude *= rough
        }
        return field.normalized()
    }
}

// MARK: - Erosion

/// A weathering pass for a `Heightfield`, applied with `eroded(_:seed:)`.
/// Two processes, usually run in that order: `.hydraulic` rain carving ravines
/// and building sediment fans, then `.thermal` relaxation settling slopes that
/// stand too steep.
public struct Erosion: Sendable {

    enum Kind: Sendable {
        case hydraulic(drops: Int, inertia: Double, capacity: Double,
                       deposition: Double, erosion: Double, evaporation: Double,
                       minSlope: Double, radius: Double, gravity: Double,
                       maxSteps: Int)
        case thermal(talus: Double, amount: Double, iterations: Int)
    }

    let kind: Kind

    /// **Hydraulic erosion** by simulated raindrops (the particle method):
    /// each drop lands at a random point, rolls downhill steered by `inertia`,
    /// picks up sediment while it runs fast and full (`capacity` scales how
    /// much it can hold, `erosion` how fast it takes it) and lays it down as
    /// it slows, fills pits, or dries up (`deposition`, `evaporation`). The
    /// result is the ravine-and-fan language of real rain on real slopes.
    ///
    /// - Parameters:
    ///   - drops: How many raindrops to run. More drops, deeper carving;
    ///     tens of thousands suit a 257² field.
    ///   - inertia: 0…1, how much a drop keeps its heading against the pull of
    ///     the slope. Low values follow every wrinkle (dense fine ravines),
    ///     high values plow straighter.
    ///   - capacity: Sediment a fast, wet drop can carry. Higher carves
    ///     harder, more rugged terrain per drop.
    ///   - deposition: 0…1, the fraction of surplus sediment a drop lays down
    ///     per step once over capacity. Around 0.1–0.3 forms smooth fans.
    ///   - erosion: 0…1, the fraction of its free capacity a drop fills per
    ///     step. Low values pick up sediment over long paths (stronger ravine
    ///     formation).
    ///   - evaporation: 0…1 per-step water loss; faster evaporation makes
    ///     shorter, shallower marks.
    ///   - minSlope: The floor on the slope entering the capacity rule, so
    ///     flat terrain still erodes a little instead of stalling.
    ///   - radius: The brush radius (in cells) sediment is taken from when a
    ///     drop erodes. 1 cuts wire-thin ravines; 3–4 reads naturally.
    ///   - gravity: How strongly downhill drops accelerate (speed feeds the
    ///     capacity rule; the look barely changes, the pacing does).
    ///   - maxSteps: A drop's lifetime cap in grid steps.
    public static func hydraulic(drops: Int = 60_000, inertia: Double = 0.3,
                                 capacity: Double = 8, deposition: Double = 0.2,
                                 erosion: Double = 0.7, evaporation: Double = 0.02,
                                 minSlope: Double = 0.01, radius: Double = 3,
                                 gravity: Double = 10, maxSteps: Int = 64) -> Erosion {
        Erosion(kind: .hydraulic(drops: max(0, drops),
                                 inertia: min(max(inertia, 0), 1),
                                 capacity: max(0, capacity),
                                 deposition: min(max(deposition, 0), 1),
                                 erosion: min(max(erosion, 0), 1),
                                 evaporation: min(max(evaporation, 0), 1),
                                 minSlope: max(0.0001, minSlope),
                                 radius: max(1, radius),
                                 gravity: max(0, gravity),
                                 maxSteps: max(1, maxSteps)))
    }

    /// **Thermal erosion** (talus slippage): wherever a slope stands steeper
    /// than loose material can rest, a share of the excess slides to the lower
    /// neighbors, one relaxation per iteration, until cliffs shed into scree
    /// aprons. `talus` is the resting height difference between neighboring
    /// cells (≈ 0.015 suits a 257² field with `0…1` heights: smaller settles
    /// flatter), `amount` (0…1) is the share of the excess moved per
    /// iteration.
    public static func thermal(talus: Double = 0.015, amount: Double = 0.5,
                               iterations: Int = 60) -> Erosion {
        Erosion(kind: .thermal(talus: max(0.0001, talus),
                               amount: min(max(amount, 0), 1),
                               iterations: max(1, iterations)))
    }
}

public extension Heightfield {

    /// The field weathered by an `Erosion` pass. Deterministic: the same
    /// field, parameters, and `seed` always erode identically (thermal
    /// relaxation uses no randomness at all). Heights never drop below 0, so
    /// runoff cannot dig unbounded drains at the borders.
    func eroded(_ erosion: Erosion, seed: UInt64 = 1) -> Heightfield {
        var rng = SplitMix64(seed: seed)
        return eroded(erosion, using: &rng)
    }

    /// The generic form of `eroded(_:seed:)`, drawing from any random
    /// generator you supply.
    func eroded<R: RandomNumberGenerator>(_ erosion: Erosion, using rng: inout R) -> Heightfield {
        switch erosion.kind {
        case let .hydraulic(drops, inertia, capacity, deposition, erosionRate,
                            evaporation, minSlope, radius, gravity, maxSteps):
            return hydraulicallyEroded(drops: drops, inertia: inertia, capacity: capacity,
                                       deposition: deposition, erosionRate: erosionRate,
                                       evaporation: evaporation, minSlope: minSlope,
                                       radius: radius, gravity: gravity,
                                       maxSteps: maxSteps, using: &rng)
        case let .thermal(talus, amount, iterations):
            return thermallyEroded(talus: talus, amount: amount, iterations: iterations)
        }
    }

    // MARK: Hydraulic (droplet) erosion

    /// The bilinear height and gradient under a drop at continuous position
    /// (`px`, `py`), from the four surrounding samples.
    private func heightAndGradient(_ px: Double, _ py: Double)
        -> (height: Double, gx: Double, gy: Double) {
        let x0 = min(max(Int(px), 0), columns - 2)
        let y0 = min(max(Int(py), 0), rows - 2)
        let u = px - Double(x0), v = py - Double(y0)
        let h00 = self[x0, y0], h10 = self[x0 + 1, y0]
        let h01 = self[x0, y0 + 1], h11 = self[x0 + 1, y0 + 1]
        let gx = (h10 - h00) * (1 - v) + (h11 - h01) * v
        let gy = (h01 - h00) * (1 - u) + (h11 - h10) * u
        let h = (h00 * (1 - u) + h10 * u) * (1 - v) + (h01 * (1 - u) + h11 * u) * v
        return (h, gx, gy)
    }

    private func hydraulicallyEroded<R: RandomNumberGenerator>(
        drops: Int, inertia: Double, capacity: Double, deposition: Double,
        erosionRate: Double, evaporation: Double, minSlope: Double,
        radius: Double, gravity: Double, maxSteps: Int, using rng: inout R
    ) -> Heightfield {
        var field = self
        let reach = Int(radius.rounded(.up))

        for _ in 0 ..< drops {
            var px = Double.random(in: 0 ..< Double(columns - 1), using: &rng)
            var py = Double.random(in: 0 ..< Double(rows - 1), using: &rng)
            var dirX = 0.0, dirY = 0.0
            var speed = 1.0, water = 1.0, sediment = 0.0

            for _ in 0 ..< maxSteps {
                let here = field.heightAndGradient(px, py)

                // Steer: blend the old heading against the downhill pull; a
                // zero direction re-rolls at random (a drop born on a flat).
                dirX = dirX * inertia - here.gx * (1 - inertia)
                dirY = dirY * inertia - here.gy * (1 - inertia)
                let len = (dirX * dirX + dirY * dirY).squareRoot()
                if len < 1e-9 {
                    let angle = Double.random(in: 0 ..< .tau, using: &rng)
                    dirX = cos(angle); dirY = sin(angle)
                } else {
                    dirX /= len; dirY /= len
                }

                let nx = px + dirX, ny = py + dirY
                if nx < 0 || ny < 0 || nx >= Double(columns - 1) || ny >= Double(rows - 1) {
                    break   // ran off the map, sediment and all
                }
                let ahead = field.heightAndGradient(nx, ny)
                let hdif = ahead.height - here.height

                let x0 = min(max(Int(px), 0), columns - 2)
                let y0 = min(max(Int(py), 0), rows - 2)
                let u = px - Double(x0), v = py - Double(y0)

                if hdif > 0 {
                    // Ran uphill into a pit wall: fill the pit behind it.
                    let fill = min(sediment, hdif)
                    sediment -= fill
                    field.depositBilinear(fill, x0: x0, y0: y0, u: u, v: v)
                } else {
                    let want = max(-hdif, minSlope) * speed * water * capacity
                    if sediment > want {
                        // Over capacity: lay down a share of the surplus.
                        let drop = (sediment - want) * deposition
                        sediment -= drop
                        field.depositBilinear(drop, x0: x0, y0: y0, u: u, v: v)
                    } else {
                        // Under capacity: take sediment from the brush disc,
                        // never more than the step's own descent.
                        let take = min((want - sediment) * erosionRate, -hdif)
                        sediment += field.erodeBrush(take, px: px, py: py,
                                                     radius: radius, reach: reach)
                    }
                }

                // Downhill legs speed the drop up, uphill legs bleed it off
                // (the energy form), and the drop dries a little each step.
                speed = max(0, speed * speed - hdif * gravity).squareRoot()
                water *= 1 - evaporation
                px = nx; py = ny
            }
        }
        return field
    }

    /// Add `amount` at the four samples around a continuous position, split
    /// bilinearly (a depositing drop fills a pit its own cell wide; spreading
    /// wider would lift the pit's rim instead of filling it).
    private mutating func depositBilinear(_ amount: Double, x0: Int, y0: Int,
                                          u: Double, v: Double) {
        self[x0, y0] += amount * (1 - u) * (1 - v)
        self[x0 + 1, y0] += amount * u * (1 - v)
        self[x0, y0 + 1] += amount * (1 - u) * v
        self[x0 + 1, y0 + 1] += amount * u * v
    }

    /// Remove up to `amount` from the samples within `radius` of a continuous
    /// position, weighted by distance (wider brushes cut naturalistic ravines;
    /// radius 1 cuts wire). Heights clamp at 0, so the take can fall short;
    /// returns what was actually removed.
    private mutating func erodeBrush(_ amount: Double, px: Double, py: Double,
                                     radius: Double, reach: Int) -> Double {
        guard amount > 0 else { return 0 }
        let cx = Int(px), cy = Int(py)
        var weights: [(index: Int, weight: Double)] = []
        var total = 0.0
        for dy in -reach ... reach {
            let y = cy + dy
            guard y >= 0, y < rows else { continue }
            for dx in -reach ... reach {
                let x = cx + dx
                guard x >= 0, x < columns else { continue }
                let ddx = Double(x) - px, ddy = Double(y) - py
                let w = radius - (ddx * ddx + ddy * ddy).squareRoot()
                if w > 0 { weights.append((y * columns + x, w)); total += w }
            }
        }
        guard total > 0 else { return 0 }
        var removed = 0.0
        for (index, weight) in weights {
            let share = amount * weight / total
            let take = min(share, values[index])
            values[index] -= take
            removed += take
        }
        return removed
    }

    // MARK: Thermal erosion

    private func thermallyEroded(talus: Double, amount: Double, iterations: Int) -> Heightfield {
        var field = self
        let neighbors: [(Int, Int)] = [(-1, -1), (0, -1), (1, -1), (-1, 0),
                                       (1, 0), (-1, 1), (0, 1), (1, 1)]
        var delta = [Double](repeating: 0, count: values.count)

        for _ in 0 ..< iterations {
            // Gather every transfer against the frozen field, then apply all
            // at once, so the pass is order-free and deterministic.
            for i in delta.indices { delta[i] = 0 }
            for y in 0 ..< rows {
                for x in 0 ..< columns {
                    let h = field[x, y]
                    var excesses: [(index: Int, excess: Double)] = []
                    var maxExcess = 0.0, totalExcess = 0.0
                    for (dx, dy) in neighbors {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < columns, ny >= 0, ny < rows else { continue }
                        let d = h - field[nx, ny]
                        if d > talus {
                            let excess = d - talus
                            excesses.append((ny * columns + nx, excess))
                            totalExcess += excess
                            maxExcess = max(maxExcess, excess)
                        }
                    }
                    guard totalExcess > 0 else { continue }
                    // Move a share of the steepest excess, split among the
                    // low neighbors by how far below the resting angle each
                    // sits. Halved so a symmetric pair cannot overshoot.
                    let moved = amount * 0.5 * maxExcess
                    delta[y * columns + x] -= moved
                    for (index, excess) in excesses {
                        delta[index] += moved * excess / totalExcess
                    }
                }
            }
            for i in delta.indices { field.values[i] += delta[i] }
        }
        return field
    }
}

// MARK: - Mesh & image

public extension Heightfield {

    /// The field as a solid terrain `Mesh`: a `width` × `depth` grid centered
    /// on the origin in the ground plane, each sample lifted to
    /// `height · value` on +y, with smooth normals and `0…1` UVs. Draw it with
    /// `drawMesh`, light it, or hand it to any of the mesh tools.
    func mesh(width: Double = 500, depth: Double = 500, height: Double = 100) -> Mesh {
        var positions = [Vector3](); positions.reserveCapacity(values.count)
        var normals = [Vector3](); normals.reserveCapacity(values.count)
        var uvs = [Vector2](); uvs.reserveCapacity(values.count)

        let cellW = width / Double(columns - 1)
        let cellD = depth / Double(rows - 1)
        for y in 0 ..< rows {
            let v = Double(y) / Double(rows - 1)
            for x in 0 ..< columns {
                let u = Double(x) / Double(columns - 1)
                positions.append(Vector3((u - 0.5) * width,
                                         self[x, y] * height,
                                         (v - 0.5) * depth))
                // Central differences, clamped at the borders.
                let hl = self[max(x - 1, 0), y], hr = self[min(x + 1, columns - 1), y]
                let hu = self[x, max(y - 1, 0)], hd = self[x, min(y + 1, rows - 1)]
                let spanX = Double(min(x + 1, columns - 1) - max(x - 1, 0)) * cellW
                let spanZ = Double(min(y + 1, rows - 1) - max(y - 1, 0)) * cellD
                let n = Vector3(-(hr - hl) * height / spanX, 1, -(hd - hu) * height / spanZ)
                normals.append(n.normalized)
                uvs.append(Vector2(u, v))
            }
        }

        var indices = [UInt32]()
        indices.reserveCapacity((columns - 1) * (rows - 1) * 6)
        for y in 0 ..< rows - 1 {
            for x in 0 ..< columns - 1 {
                let i00 = UInt32(y * columns + x)
                let i10 = i00 + 1
                let i01 = i00 + UInt32(columns)
                let i11 = i01 + 1
                indices.append(contentsOf: [i00, i01, i11, i00, i11, i10])
            }
        }
        return Mesh(positions: positions, normals: normals, indices: indices, uvs: uvs)
    }

    /// The field as a grayscale image (black at 0, white at 1, one pixel per
    /// sample): a heightmap to inspect, dither, contour with the image form of
    /// `isolines`, or export.
    func image() -> Image {
        var pixels = [UInt8](); pixels.reserveCapacity(values.count * 4)
        for value in values {
            let gray = UInt8((min(max(value, 0), 1) * 255).rounded())
            pixels.append(contentsOf: [gray, gray, gray, 255])
        }
        return Image(width: columns, height: rows, premultipliedRGBA: pixels)
            ?? Image(width: columns, height: rows, color: .black)
    }
}
