//  Recreation after Monir Shahroudy Farmanfarmaian - the Convertibles (2010 to
//  2016), wall reliefs of mirror and reverse-glass painting on plaster and
//  wood, each made of identical modules that can be hung in many
//  arrangements; the modules after Tir (2015, Grand Rapids Art Museum), six
//  kites around a hexagonal opening.
//  A homage, not a reproduction, and not affiliated with or endorsed by the
//  artist or her estate.
//  https://www.artmuseumgr.org/collection/tir
//  https://www.jamescohan.com/exhibitions/monir-shahroudy-farmanfarmaian2
//
//  An original Ollin interpretation, written from the works and from the
//  galleries' accounts of them. Nothing was ported: the modules were cut and
//  set by hand, in plaster on wood, by craftsmen in her Tehran studio.

import Ollin

/// After the Convertibles (Monir Shahroudy Farmanfarmaian, 2010 to 2016). A
/// Convertible is a set of identical modules of mirror and painted glass that
/// can be hung on the wall in many arrangements, "folded and unfolded
/// according to diagrams drawn by the artist", as her gallery puts it, some
/// taken from old decorative patterns and some her own. She said they let
/// her "play with ideas of infinity". Tir (2015) is six of them: six kites,
/// each with a red star at its middle, turned around a hexagonal opening
/// like the blades of a pinwheel.
///
/// Tir's kite is the hexagon's own. Cut a hexagon from its center to the
/// middle of every side and it falls into six kites, with corners of 60, 90,
/// 120, and 90 degrees, and those are the modules. The sketch starts from
/// that cut: it takes a polygon cut from the circle by her rule, as the ones
/// in `MirrorFamily` are, cuts it into one kite for every side, and searches
/// for the ways the kites can hang. An arrangement turns the whole set about
/// one point by a kite's share of the circle, so every kite hangs the way its
/// neighbor does, and every kite meets another along an edge, flush or slid
/// along it by a third, a half, or two thirds of the edge, with no two
/// overlapping. For the triangle through the heptagon that gives seven: the
/// polygon closed up, and three pinwheels around an opening, each turning
/// either way. The octagon's kite, with its corner of 45 degrees, gives
/// thirty-five, among them rings around an eight-pointed opening and stars.
///
/// The set is hung closed first, one kite at a time, and then goes through
/// the arrangements the search found, twelve at most (one of her
/// Convertibles, Aram, can be hung in twelve compositions), holding each for
/// `hold` seconds. Between two of them every kite moves as one rigid piece:
/// it comes off the wall, turns and travels, and hangs again, and the kites
/// hold at different distances from the wall on the way so no two pass
/// through each other. Where the next arrangement is the same pinwheel slid
/// further open, the kites slide along each other without leaving the wall.
/// Then the next polygon's set is hung, triangle to octagon and around again.
/// `firstSides` is the polygon the run starts on, `rings` how finely each
/// kite is cut into facets, `seconds` how long a move takes, and a press
/// moves on to the next set.
///
/// `--export-usdz set.usda --frame 560` writes the frame's meshes out as
/// text, four to a kite (the frame, the plaster, the mirror, the painted
/// glass), so the set can be read back from any frame: every kite is the same
/// piece in every arrangement, turned and moved but never bent or flipped;
/// while the kites hang no two overlap and every kite lies along another;
/// and while they travel, two whose outlines cross are at different
/// distances from the wall.
@main
final class Convertible: Sketch {
    @Param(3 ... 8, icon: "hexagon") var firstSides = 6
    @Param(3 ... 10, icon: "circle.circle") var rings = 7
    @Param(1 ... 8, icon: "arrow.triangle.2.circlepath") var seconds = 3.0
    @Param(0 ... 20, icon: "clock") var hold = 3.0

    private let wall = Color(hex: 0xE9E4DA)
    private let plaster = Color(hex: 0xF3EFE6)
    private let backing = Color(hex: 0x141414)
    private let silver = Color(hex: 0xF4F5F6)
    private let rim = Color(hex: 0xB9BDC2)
    private let floorColor = Color(hex: 0x333436)
    private let shade = Color(hex: 0x7D7870)

    /// The paint behind the glass, one set to the next: Tir's red, then the
    /// greens and blues her reliefs also carry.
    private let paints: [Color] = [
        Color(hex: 0xB8322A), Color(hex: 0x2E7D4F), Color(hex: 0x2A4FA8),
    ]

    /// A lamp, flat white so it reads the same in the room and in a mirror.
    private let glow = Image(width: 1, height: 1, color: Color(hex: 0xFFF6E6))

    /// The radius of the circle the polygon is cut from, in meters, at most.
    private nonisolated static let radius = 1.35
    /// How far from the middle the most open arrangement of a set may reach.
    private nonisolated static let fit = 2.1
    /// How far a kite stands off the wall, frame and plaster together.
    private nonisolated static let depth = 0.07
    /// How far apart the kites hold off the wall while they travel, more than
    /// a kite is deep with its facets on.
    private nonisolated static let spacing = 0.2
    /// The most arrangements one set shows.
    private nonisolated static let shown = 12
    /// How long each kite takes to be hung at the start of a set.
    private let hanging = 0.3

    /// Where one kite hangs: how far it is turned, and where its center of
    /// the polygon has gone.
    private struct Pose {
        var at: Vector2
        var turn: Double
    }

    /// One way the whole set can hang.
    private struct Arrangement {
        var poses: [Pose]
        /// Every kite is turned by the same amount as it is moved around the
        /// middle, so the set could slide open or shut without leaving the
        /// wall if its neighbor held it.
        var slide: Double
        /// Which edge of a kite lies against which edge of which neighbor,
        /// and which end of the neighbor's edge is placed: arrangements that
        /// share this differ only by how far one kite is slid along the other.
        var contact: [Int]
    }

    /// One set of kites, the meshes of one kite, and every way it hangs.
    private struct Modules {
        var sides: Int
        var outline: [Vector2]
        var mirror: Mesh
        var glass: Mesh
        var arrangements: [Arrangement]
    }

    private var set: Modules?
    private var began = 0.0
    private var index = 0
    private var program = (first: 0, rings: 0)

    override func mousePressed() {
        index += 1
        set = nil
    }

    override func draw() {
        let wanted = (first: firstSides, rings: rings)
        if program != wanted {
            program = wanted
            index = 0
            set = nil
        }
        if set == nil {
            let sides = 3 + (firstSides - 3 + index) % 6
            set = Self.cut(sides: sides, rings: rings)
            began = time
        }
        guard let set else { return }

        // The run: the kites hung one by one, then a hold for each
        // arrangement with a move between every two.
        let count = set.arrangements.count
        let hung = Double(set.sides) * hanging
        let elapsed = time - began
        let total = hung + Double(count) * hold + Double(count - 1) * seconds
        if elapsed > total + 0.6 {
            index += 1
            self.set = nil
        }
        let stage = max(0, elapsed - hung)
        let step = hold + seconds
        let from = min(count - 1, Int(stage / step))
        let into = stage - Double(from) * step
        var poses: [(pose: Pose, lift: Double)] = []
        if from < count - 1 && into > hold {
            poses = Self.travel(set.arrangements[from], set.arrangements[from + 1],
                                progress: (into - hold) / seconds)
        } else {
            poses = set.arrangements[from].poses.map { ($0, 0) }
        }

        stage3D(set)

        // The kites, each drawn as four meshes: the frame, the plaster, the
        // mirror, and the painted glass. A kite not yet hung drops into place.
        for (k, placed) in poses.enumerated() {
            let age = elapsed - Double(k) * hanging
            if age < 0 { continue }
            let drop = 0.35 * pow(max(0, 1 - age / 0.3), 2)
            withState {
                translate(placed.pose.at.x, placed.pose.at.y, placed.lift + drop)
                rotateZ(placed.pose.turn)
                withState {
                    fill(rim)
                    material(.metal(roughness: 0.35))
                    translate(0, 0, Self.depth * 0.45)
                    drawExtrude(set.outline, depth: Self.depth * 0.9)
                }
                withState {
                    fill(plaster)
                    material(.matte)
                    translate(0, 0, Self.depth * 0.95)
                    drawExtrude(Self.shrunk(set.outline, by: 0.012), depth: Self.depth * 0.1)
                }
                withState {
                    fill(silver)
                    material(.metal(roughness: 0.1))
                    drawMesh(set.mirror)
                }
                withState {
                    fill(paints[index % paints.count])
                    var painted = Material.dielectric(roughness: 0.55)
                    painted.clearcoat = 1
                    painted.clearcoatRoughness = 0.03
                    material(painted)
                    drawMesh(set.glass)
                }
            }
        }
    }

    /// The camera, the lamp, and the room the mirrors show.
    private func stage3D(_ set: Modules) {
        background(wall)
        let drift = time * 0.19
        camera(.perspective(eye: Vector3(sin(drift) * 1.2, 0.25 + sin(time * 0.13) * 0.3, 7.6),
                            target: Vector3(0, 0, 0.15), fieldOfView: 0.62, near: 0.5, far: 30))
        environment(.studio.intensified(to: 0.35))
        toneMap(.aces)
        temporalAntialiasing()
        rayTracedReflections()
        reflectionBounces(2)

        let lamp = Vector3(cos(time * 0.31) * 2.6, 2.3 + sin(time * 0.23) * 0.5, 3.4)
        pointLight(Color(hue: 0.1, saturation: 0.2, brightness: 1), at: lamp, intensity: 9)
        ambientLight(Color(white: 0.08))
        withState {
            translate(lamp.x, lamp.y, lamp.z)
            fill(.white)
            matcap(glow)
            drawSphere(radius: 0.14)
        }
        // A dark floor, a pale ceiling hung with lamps, and a doorway in the
        // wall behind the viewer.
        let room: [(size: Vector3, at: Vector3, color: Color)] = [
            (Vector3(16, 11, 0.1), Vector3(0, 1, -0.05), wall),
            (Vector3(16, 0.1, 15), Vector3(0, -3.6, 6.5), floorColor),
            (Vector3(16, 0.1, 15), Vector3(0, 5.6, 6.5), plaster),
            (Vector3(16, 11, 0.1), Vector3(0, 1, 13.5), shade),
            (Vector3(2.4, 5.6, 0.1), Vector3(0.6, -0.8, 13.4), backing),
            (Vector3(0.1, 11, 15), Vector3(-7.5, 1, 6.5), shade),
            (Vector3(0.1, 11, 15), Vector3(7.5, 1, 6.5), shade),
        ]
        for part in room {
            withState {
                fill(part.color)
                material(.matte)
                translate(part.at.x, part.at.y, part.at.z)
                drawBox(width: part.size.x, height: part.size.y, depth: part.size.z)
            }
        }
        for i in 0 ..< 7 {
            let a = (Double(i) - 3) / 3
            withState {
                translate(a * 3.4, 3.3 - a * a * 0.5 + sin(time * 0.6 + Double(i)) * 0.05,
                          5.4 + a * a * 0.8)
                fill(.white)
                matcap(glow)
                drawSphere(radius: 0.14)
            }
        }
    }

    // MARK: - Moving between two arrangements

    /// Every kite between two arrangements: which kite goes where is settled
    /// by the shortest total journey around the ring, and each kite lifts,
    /// turns and travels, and hangs again, or slides along the wall when its
    /// neighbors can carry it.
    private nonisolated static func travel(_ a: Arrangement, _ b: Arrangement,
                                           progress: Double) -> [(pose: Pose, lift: Double)] {
        let n = a.poses.count
        let targets = assignment(a, b)
        let u = max(0, min(1, progress))
        // The same pinwheel slid further open or shut: every kite keeps its
        // turn and slides in a straight line, and every stage between is
        // another slide of the same pinwheel, so none overlaps and none lifts.
        let slides = a.contact == b.contact && abs(a.slide - b.slide) > 1e-9
            && (0 ..< n).allSatisfy { k in
                abs(remainder(b.poses[targets[k]].turn - a.poses[k].turn, 2 * .pi)) < 1e-9
            }
        let ease = u * u * (3 - 2 * u)
        return (0 ..< n).map { k in
            let start = a.poses[k], end = b.poses[targets[k]]
            if slides {
                return (Pose(at: start.at + (end.at - start.at) * ease, turn: start.turn), 0)
            }
            // Off the wall in the first quarter, across in the middle half,
            // back on in the last quarter; each kite held at its own distance.
            let off = min(1, u / 0.25), on = min(1, (1 - u) / 0.25)
            let height = Double(k + 1) * spacing * min(off, on).smoothed
            let glide = max(0, min(1, (u - 0.25) / 0.5)).smoothed
            let turn = start.turn + remainder(end.turn - start.turn, 2 * .pi) * glide
            return (Pose(at: start.at + (end.at - start.at) * glide, turn: turn), height)
        }
    }

    /// Which place in `b` each kite of `a` goes to: a kite keeps its order
    /// around the ring, one way or the other, and the whole set takes the
    /// shortest journey.
    private nonisolated static func assignment(_ a: Arrangement, _ b: Arrangement) -> [Int] {
        let n = a.poses.count
        var best: [Int] = Array(0 ..< n), cost = Double.infinity
        for shift in 0 ..< n {
            for direction in [1, -1] {
                let map = (0 ..< n).map { ((shift + direction * $0) % n + n) % n }
                var journey = 0.0
                for k in 0 ..< n {
                    let s = a.poses[k], e = b.poses[map[k]]
                    journey += (e.at - s.at).lengthSquared
                        + pow(remainder(e.turn - s.turn, 2 * .pi) * 0.6, 2)
                }
                if journey < cost - 1e-12 {
                    cost = journey
                    best = map
                }
            }
        }
        return best
    }

    // MARK: - Cutting a set and finding its arrangements

    /// The kite between the center of an `n`-sided polygon and one of its
    /// corners: the center, the middle of one side, the corner, the middle of
    /// the next side, counterclockwise.
    private nonisolated static func kite(_ n: Int, radius: Double) -> [Vector2] {
        let share = 2 * Double.pi / Double(n)
        let corner = { (i: Int) in Vector2(cos(Double(i) * share), sin(Double(i) * share)) * radius }
        return [.zero, (corner(0) + corner(1)) / 2, corner(1), (corner(1) + corner(2)) / 2]
    }

    /// Cuts one set: the kite, its facets, and every arrangement of `n` of them,
    /// sized so the most open arrangement fits the wall in view.
    private nonisolated static func cut(sides n: Int, rings: Int) -> Modules {
        let unit = arrangements(kite(n, radius: 1), sides: n)
        var reach = 1.0
        for arrangement in unit {
            for pose in arrangement.poses {
                for corner in kite(n, radius: 1) {
                    reach = max(reach, (pose.at + corner.rotated(by: pose.turn)).length)
                }
            }
        }
        let size = min(radius, fit / reach)
        let outline = kite(n, radius: size)
        let (mirror, glass) = facets(outline, rings: rings)
        let placed = unit.map { a in
            var scaled = a
            scaled.poses = a.poses.map { Pose(at: $0.at * size, turn: $0.turn) }
            return scaled
        }
        return Modules(sides: n, outline: outline, mirror: mirror, glass: glass,
                       arrangements: placed)
    }

    /// Every arrangement of `n` kites turned about one point by a kite's share
    /// of the circle, where a kite meets another along an edge, flush or slid
    /// by a third, a half, or two thirds of it, and no two overlap. Found by
    /// trying every pair of edges that can lie against each other, solving
    /// for the point the set turns about, and keeping what does not overlap.
    private nonisolated static func arrangements(_ kite: [Vector2], sides n: Int) -> [Arrangement] {
        let share = 2 * Double.pi / Double(n)
        var found: [(corners: [Vector2], arrangement: Arrangement)] = []
        for sense in [1.0, -1.0] {
            let turn = sense * share
            for neighbor in 1 ..< n {
                // The kite that one is against: `neighbor` places around.
                let against = Double(neighbor) * turn
                for i in 0 ..< 4 {
                    let p0 = kite[i], p1 = kite[(i + 1) % 4], edge = p1 - p0
                    for j in 0 ..< 4 {
                        let q1 = kite[(j + 1) % 4]
                        let other = (q1 - kite[j]).rotated(by: against)
                        // The two edges must run along one line, in opposite
                        // directions, so the kites meet face to face.
                        guard abs(edge.cross(other)) < 1e-9, edge.dot(other) < 0 else { continue }
                        for slide in [0.0, 1.0 / 3, 0.5, 2.0 / 3] {
                        for end in 0 ..< 2 {
                            // One end of the other kite's edge is placed on
                            // this edge, at one end of it or slid along it:
                            // its end corner onto this edge's start, or its
                            // start corner onto this edge's end. That corner,
                            // turned about the middle `c` by `against`, lands
                            // on `target`; solving (I - R)c = target - Rq for c.
                            let q = end == 0 ? q1 : kite[j]
                            let target = end == 0 ? p0 + edge * slide : p1 - edge * slide
                            let rhs = target - q.rotated(by: against)
                            let ca = cos(against), sa = sin(against)
                            let m00 = 1 - ca, m01 = sa, m10 = -sa, m11 = 1 - ca
                            let det = m00 * m11 - m01 * m10
                            guard abs(det) > 1e-12 else { continue }
                            let c = Vector2((m11 * rhs.x - m01 * rhs.y) / det,
                                            (-m10 * rhs.x + m00 * rhs.y) / det)
                            let placed = (0 ..< n).map { k in
                                kite.map { ($0 - c).rotated(by: Double(k) * turn) }
                            }
                            guard (1 ..< n).allSatisfy({ overlap(placed[0], placed[$0]) < 1e-9 }),
                                  (1 ..< n).contains(where: { contact(placed[0], placed[$0]) > 1e-6 })
                            else { continue }
                            let poses = (0 ..< n).map { k in
                                Pose(at: (Vector2.zero - c).rotated(by: Double(k) * turn),
                                     turn: Double(k) * turn)
                            }
                            let corners = placed.flatMap { $0 }
                            if found.contains(where: { same($0.corners, corners) }) {
                                continue
                            }
                            let family = [i, j, neighbor, sense > 0 ? 1 : 0, end]
                            found.append((corners, Arrangement(poses: poses, slide: slide,
                                                           contact: family)))
                        }
                        }
                    }
                }
            }
        }
        // The order of the tour: arrangements that differ only by a slide
        // stay together, so the set slides open or shut between them; the
        // families go from the tightest to the most open, and each family
        // is walked the other way from the one before, so the polygon closed
        // up comes first. A set with more than twelve shows twelve, spread
        // evenly over the tour.
        var families: [[Int]: [Arrangement]] = [:]
        for (_, arrangement) in found { families[arrangement.contact, default: []].append(arrangement) }
        let walks = families.values.map { $0.sorted { $0.slide < $1.slide } }
            .sorted { x, y in
                let a = x.map(spread).min()!, b = y.map(spread).min()!
                if abs(a - b) > 1e-9 { return a < b }
                return x[0].contact.lexicographicallyPrecedes(y[0].contact)
            }
        var tour: [Arrangement] = []
        for (k, walk) in walks.enumerated() {
            tour += k % 2 == 0 ? walk : walk.reversed()
        }
        guard tour.count > shown else { return tour }
        return (0 ..< shown).map { tour[Int((Double($0) * Double(tour.count - 1) / Double(shown - 1)).rounded())] }
    }

    /// How far the set's corners reach from the middle, on average.
    private nonisolated static func spread(_ a: Arrangement) -> Double {
        a.poses.map(\.at.length).reduce(0, +) / Double(a.poses.count)
    }

    /// Whether two arrangements' corners are the same points turned about
    /// the middle, which a mirror image is not. The whole set is compared
    /// rather than one kite, since a square kite looks the same four ways.
    private nonisolated static func same(_ a: [Vector2], _ b: [Vector2]) -> Bool {
        let ra = a.map(\.length).sorted(), rb = b.map(\.length).sorted()
        guard ra.count == rb.count, zip(ra, rb).allSatisfy({ abs($0 - $1) < 1e-6 }),
              let far = a.max(by: { $0.length < $1.length }) else { return false }
        for q in b where abs(q.length - far.length) < 1e-6 {
            let turn = atan2(q.y, q.x) - atan2(far.y, far.x)
            if a.allSatisfy({ p in
                let r = p.rotated(by: turn)
                return b.contains { ($0 - r).length < 1e-6 }
            }) {
                return true
            }
        }
        return false
    }

    /// The area two convex outlines share.
    private nonisolated static func overlap(_ a: [Vector2], _ b: [Vector2]) -> Double {
        var out = a
        for i in 0 ..< b.count {
            let u = b[i], v = b[(i + 1) % b.count]
            let input = out
            out = []
            guard !input.isEmpty else { break }
            func inside(_ p: Vector2) -> Bool { (v - u).cross(p - u) >= -1e-12 }
            for k in 0 ..< input.count {
                let p = input[k], q = input[(k + 1) % input.count]
                let cut = { () -> Vector2 in
                    let d = q - p, e = v - u
                    let t = (u - p).cross(e) / d.cross(e)
                    return p + d * t
                }
                if inside(q) {
                    if !inside(p) { out.append(cut()) }
                    out.append(q)
                } else if inside(p) {
                    out.append(cut())
                }
            }
        }
        guard out.count > 2 else { return 0 }
        var area = 0.0
        for k in 0 ..< out.count { area += out[k].cross(out[(k + 1) % out.count]) }
        return abs(area) / 2
    }

    /// The length of edge two outlines lay against each other.
    private nonisolated static func contact(_ a: [Vector2], _ b: [Vector2]) -> Double {
        var total = 0.0
        for i in 0 ..< a.count {
            let a0 = a[i], a1 = a[(i + 1) % a.count], along = (a1 - a0).normalized
            let length = (a1 - a0).length
            for j in 0 ..< b.count {
                let b0 = b[j], b1 = b[(j + 1) % b.count]
                guard abs((b0 - a0).cross(along)) < 1e-9, abs((b1 - a0).cross(along)) < 1e-9 else {
                    continue
                }
                let s0 = (b0 - a0).dot(along), s1 = (b1 - a0).dot(along)
                total += max(0, min(length, max(s0, s1)) - max(0, min(s0, s1)))
            }
        }
        return total
    }

    // MARK: - The facets of one kite

    /// The mirror and the painted glass of one kite. The kite is cut from the
    /// middle of its inscribed circle to its four corners, and each of the
    /// four triangles into rows of small triangles, `rings * rings` of them.
    /// Every third point of that lattice is pressed up, so every piece tilts
    /// and the pieces around a raised point make a small star; the stars on
    /// the lines to the corners, out to two thirds of the way, and the one at
    /// the middle are painted glass.
    private nonisolated static func facets(_ kite: [Vector2], rings: Int) -> (Mesh, Mesh) {
        // A kite has a circle touching all four sides, centered on its axis.
        let sides = (0 ..< 4).map { (kite[($0 + 1) % 4] - kite[$0]).length }
        let area = abs(kite[1].cross(kite[2]) + kite[2].cross(kite[3])) / 2
        let inradius = area / (sides.reduce(0, +) / 2)
        let axis = kite[2].normalized
        let half = asin(max(-1, min(1, abs(axis.cross(kite[1].normalized)))))
        let middle = axis * (inradius / sin(half))

        let base = depth, dome = 0.05, peak = 0.03
        func point(_ i: Int, _ k: Int, _ p: Int) -> Vector3 {
            let from = kite[i], to = kite[(i + 1) % 4]
            let flat = k == 0 ? middle
                : middle + ((from + (to - from) * (Double(p) / Double(k))) - middle)
                    * (Double(k) / Double(rings))
            var z = base + dome * (1 - Double(k) / Double(rings))
            if raised(k, p) { z += peak }
            return Vector3(flat.x, flat.y, z)
        }
        func raised(_ k: Int, _ p: Int) -> Bool {
            guard k < rings else { return false }
            if p == 0 || p == k { return k % 3 == 0 }
            return (k + p) % 3 == 0
        }
        func painted(_ k: Int, _ p: Int) -> Bool {
            guard raised(k, p) else { return false }
            return (p == 0 || p == k) && k <= 2 * rings / 3
        }
        var mirror = Facets(), glass = Facets()
        for i in 0 ..< 4 {
            for k in 1 ... rings {
                for p in 0 ..< k {
                    var cells = [[(k, p), (k, p + 1), (k - 1, p)]]
                    if p < k - 1 { cells.append([(k - 1, p), (k, p + 1), (k - 1, p + 1)]) }
                    for cell in cells {
                        let corners = inset(cell.map { point(i, $0.0, $0.1) }, by: 0.004)
                        if cell.contains(where: { painted($0.0, $0.1) }) {
                            glass.add(corners)
                        } else {
                            mirror.add(corners)
                        }
                    }
                }
            }
        }
        return (mirror.mesh, glass.mesh)
    }

    /// Triangles gathered into one flat-shaded mesh.
    private struct Facets {
        var positions: [Vector3] = []
        var normals: [Vector3] = []

        mutating func add(_ corners: [Vector3]) {
            let normal = (corners[1] - corners[0]).cross(corners[2] - corners[0]).normalized
            positions += corners
            normals += [normal, normal, normal]
        }

        var mesh: Mesh {
            Mesh(positions: positions, normals: normals,
                 indices: (0 ..< UInt32(positions.count)).map { $0 })
        }
    }

    /// Shrinks a triangle about its incenter so a line of plaster shows the
    /// same width around every piece, and turns it to face the viewer.
    private nonisolated static func inset(_ c: [Vector3], by gap: Double) -> [Vector3] {
        let la = (c[1] - c[2]).length, lb = (c[2] - c[0]).length, lc = (c[0] - c[1]).length
        let perimeter = la + lb + lc
        let center = (c[0] * la + c[1] * lb + c[2] * lc) / perimeter
        let area = (c[1] - c[0]).cross(c[2] - c[0]).length / 2
        let inradius = 2 * area / perimeter
        let s = max(0, (inradius - gap) / inradius)
        var out = c.map { center + ($0 - center) * s }
        if (out[1] - out[0]).cross(out[2] - out[0]).z < 0 { out.swapAt(1, 2) }
        return out
    }

    /// An outline moved in toward its inscribed circle's center.
    private nonisolated static func shrunk(_ outline: [Vector2], by amount: Double) -> [Vector2] {
        let center = outline.reduce(Vector2.zero, +) / Double(outline.count)
        return outline.map { center + ($0 - center) * (1 - amount) }
    }
}

private extension Double {
    /// Eased in and out.
    var smoothed: Double { self * self * (3 - 2 * self) }
}
