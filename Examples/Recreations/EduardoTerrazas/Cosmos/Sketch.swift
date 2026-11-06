//  Recreation after Eduardo Terrazas - Posibilidades de una estructura,
//  subserie Cosmos (from the early 1970s; wool yarn on a wooden board covered
//  with Campeche wax, the Huichol technique, made with Santos Motoaaopohua de
//  la Torre de Santiago). A homage, not a reproduction of any one tabla, and
//  not affiliated with or endorsed by the artist or his galleries.
//  https://eduardoterrazas.com/index.php/cosmos/
//  https://eduardoterrazas.com/index.php/possibilities-of-a-structure/
//
//  An original Ollin interpretation, written from the structure as the artist
//  states it and from photographs of the tablas. Nothing was ported: the work
//  is yarn pressed into wax.

import Foundation
import Ollin

/// Cosmos (Eduardo Terrazas, from the early 1970s). One
/// structure, drawn once and filled again and again: a square, the circle
/// that fills it, the horizontal and the vertical through the middle, the two
/// diagonals from corner to corner, a second square turned 45 degrees with
/// its corners where the circle touches the first, and a small circle at the
/// center. He reads it as a diagram of the universe: the two axes are X and
/// Y, the large circle the celestial dome, the turned square a frame for the
/// four forces, the small circle the Earth, and the diagonals, which cross
/// and run on past the dome, the infinite. Those lines wall the square into
/// thirty-two fields, eight to a quarter, and every tabla of the subseries
/// is one way of filling them.
///
/// The tablas are yarn. A board is spread with wax and wool is pressed into
/// it a strand at a time, each field begun along its own edges and worked
/// inward, so the strands turn where two edges' rows meet and leave a crease
/// along the line between them. This sketch lays the yarn the same way. A
/// field's strands follow whichever of its edges is nearest, `pitch` pixels
/// apart, counted in from the edge; where two neighbors take the same color
/// they are one field and are laid as one, their shared line gone, which is
/// where the long creases come from. `lines` lays the structure's own lines
/// as bands of white or black yarn, `lineStrands` strands wide, running
/// lengthwise, and then every field stands alone inside its bands.
///
/// The seed deals the possibility: `colors` wools, a field at a time from
/// the center out, each taking a color none of its neighbors has, or, with
/// chance `sharing`, a neighbor's. `earth` is the small circle's radius as a
/// part of the large one's; the artist gives no number, and his diagram
/// measures 0.41, which is the square root of two less one. Over one cycle
/// of `seconds` the finished tabla is taken back to the bare waxed board,
/// the lines scored in it, and laid again one color after another, which is
/// also the export loop.
///
/// `--export-svg` writes the thirty-two fields as closed outlines in their
/// colors, cut by `regions(enclosedBy:)` from the structure's own lines, and
/// the lines over them when they are laid as bands.
@main
final class Cosmos: Sketch {
    enum Lines: String, CaseIterable, ParamOption { case none, white, black }
    enum Wools: String, CaseIterable, ParamOption { case dyed, keyed }

    /// How many colors of wool the tabla is laid in.
    @Param(2 ... 8, icon: "paintpalette") var colors = 7
    /// The chance a field takes a neighbor's color and joins it.
    @Param(0 ... 1, icon: "square.on.square") var sharing = 0.3
    /// The structure's lines as bands of yarn.
    @Param(icon: "line.diagonal") var lines = Lines.none
    /// How many strands wide a line's band is.
    @Param(1 ... 8, icon: "line.3.horizontal") var lineStrands = 4
    /// One strand of yarn, in pixels.
    @Param(2 ... 10, icon: "ruler") var pitch = 4.0
    /// The small circle's radius as a part of the large one's.
    @Param(0.3 ... 0.55, icon: "circle.circle") var earth = 0.414
    /// How round the strands read: 0 is flat color.
    @Param(0 ... 1, icon: "sun.max") var relief = 0.7
    /// The dyed wools, or a set built around one hue.
    @Param(icon: "swatchpalette") var wools = Wools.dyed
    /// The hue the keyed set is built around.
    @Param(0 ... 1, icon: "dial.low") var keyHue = 0.58
    /// One cycle: the tabla, taken back to the board, and laid again.
    @Param(6 ... 60, icon: "clock") var seconds = 24.0

    override var canvasSize: CanvasSize { .square(1080) }
    override var loopDuration: Double? { seconds }

    /// Half the tabla's side, in pixels, and where its middle sits.
    nonisolated static let half = 420.0
    nonisolated static let center = Vector2(540, 540)

    private let wall = Color(hex: 0xE9E6DF)
    private let maple = Color(hex: 0xD9C19A)
    private let recess = Color(hex: 0x2B2622)
    private let wax = Color(hex: 0x8B6B3D)
    private let dyed: [Color] = [
        Color(hex: 0xC8102E), Color(hex: 0x1D4E9E), Color(hex: 0xF2C230), Color(hex: 0x1E7A46),
        Color(hex: 0xF28C28), Color(hex: 0xD12C8A), Color(hex: 0x4BA3D9), Color(hex: 0x6A3FA0),
    ]
    private let white = Color(hex: 0xF4F1EA)
    private let black = Color(hex: 0x16161A)

    // MARK: - The structure

    /// The field a point of the tabla lies in: its ring, counted out from the
    /// center (the small circle, the turned square, the large circle, the
    /// corners), times eight, plus its eighth of a turn. `q` is measured
    /// from the middle in half-sides, so the square is -1 to 1.
    nonisolated static func field(at q: Vector2, earth: Double) -> Int {
        var turn = atan2(q.y, q.x) / (.pi / 4)
        if turn < 0 { turn += 8 }
        let eighth = min(7, Int(turn))
        let r = q.length
        let ring = r < earth ? 0 : (abs(q.x) + abs(q.y) < 1 ? 1 : (r < 1 ? 2 : 3))
        return ring * 8 + eighth
    }

    /// The fields that share an edge with a field. Two eighths of one ring
    /// share the ray between them, except in the two outer rings across the
    /// horizontal and the vertical, where they only touch at a point; and a
    /// field shares an arc or a side with the ring inside it and the ring
    /// outside it.
    nonisolated static func neighbors(of field: Int) -> [Int] {
        let ring = field / 8, eighth = field % 8
        var found: [Int] = []
        // The ray after this eighth is ray `eighth + 1`; the one before it
        // is ray `eighth`. The odd rays are the diagonals.
        if ring <= 1 || (eighth + 1) % 2 == 1 { found.append(ring * 8 + (eighth + 1) % 8) }
        if ring <= 1 || eighth % 2 == 1 { found.append(ring * 8 + (eighth + 7) % 8) }
        if ring > 0 { found.append((ring - 1) * 8 + eighth) }
        if ring < 3 { found.append((ring + 1) * 8 + eighth) }
        return found
    }

    /// The structure's lines as outlines, in pixels: the square, the large
    /// circle, the turned square, the small circle, the two axes, and the
    /// two diagonals.
    nonisolated static func outlines(earth: Double) -> [Contour] {
        let c = center, h = half
        return [
            Rectangle(x: c.x - h, y: c.y - h, width: 2 * h, height: 2 * h).contour,
            Circle(center: c, radius: h).contour(segments: 256),
            Contour([Vector2(c.x + h, c.y), Vector2(c.x, c.y + h),
                     Vector2(c.x - h, c.y), Vector2(c.x, c.y - h)], closed: true),
            Circle(center: c, radius: h * earth).contour(segments: 256),
            Contour([Vector2(c.x - h, c.y), Vector2(c.x + h, c.y)], closed: false),
            Contour([Vector2(c.x, c.y - h), Vector2(c.x, c.y + h)], closed: false),
            Contour([Vector2(c.x - h, c.y - h), Vector2(c.x + h, c.y + h)], closed: false),
            Contour([Vector2(c.x - h, c.y + h), Vector2(c.x + h, c.y - h)], closed: false),
        ]
    }

    /// One possibility: a color for each of the thirty-two fields, as an
    /// index into the wools. The fields are taken from the center out, an
    /// eighth at a time, and each takes a color no neighbor already has, or
    /// with chance `sharing` the color of one that does.
    nonisolated static func deal(colors: Int, sharing: Double, seed: Int) -> [Int] {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed &* 1_000_003 &+ 171)))
        func unit() -> Double { Double(rng.next() >> 11) / Double(1 << 53) }
        var dealt = [Int](repeating: -1, count: 32)
        for field in 0 ..< 32 {
            let taken = neighbors(of: field).map { dealt[$0] }.filter { $0 >= 0 }
            if !taken.isEmpty, unit() < sharing {
                dealt[field] = taken[Int(unit() * Double(taken.count)) % taken.count]
                continue
            }
            let free = (0 ..< colors).filter { !taken.contains($0) }
            let pool = free.isEmpty ? Array(0 ..< colors) : free
            dealt[field] = pool[Int(unit() * Double(pool.count)) % pool.count]
        }
        return dealt
    }

    /// How deep a point lies in what it is part of, in half-sides: its
    /// distance to the nearest edge of the structure that matters, every
    /// edge when the lines are bands half of `band` wide (and then less that
    /// half), else the edges where the color changes. It is the walk the
    /// yarn program makes at every pixel, made here so the sketch knows how
    /// many strands each wool's deepest field takes.
    nonisolated static func depth(at q: Vector2, dealt: [Int], earth: Double, band: Double) -> Double {
        func toSegment(_ a: Vector2, _ b: Vector2) -> Double {
            let ab = b - a
            let t = max(0, min(1, (q - a).dot(ab) / max(ab.dot(ab), 1e-12)))
            return (q - (a + ab * t)).length
        }
        func toArc(_ radius: Double, _ from: Double) -> Double {
            var rel = atan2(q.y, q.x) - from
            rel -= 2 * .pi * (rel / (2 * .pi)).rounded(.down)
            if rel <= .pi / 4 { return abs(q.length - radius) }
            let e0 = Vector2(angle: from, length: radius)
            let e1 = Vector2(angle: from + .pi / 4, length: radius)
            return min((q - e0).length, (q - e1).length)
        }
        var nearest = Double.infinity
        let root = 2.0.squareRoot()
        for k in 0 ..< 8 {
            let from = Double(k) * .pi / 4
            let ray = Vector2(angle: from, length: 1), next = Vector2(angle: from + .pi / 4, length: 1)
            let diagonal = k % 2 == 1
            // Where ray k meets the small circle, the turned square, the
            // large circle, and the square.
            let stops = [0, earth, diagonal ? 1 / root : 1, 1, diagonal ? root : 1]
            let nextSide = diagonal ? 1 : 1 / root, nextEdge = diagonal ? 1 : root
            for edge in 0 ..< 8 {
                let d: Double, a: Int, b: Int
                switch edge {
                case 0 ..< 4:
                    guard stops[edge + 1] - stops[edge] > 1e-9 else { continue }
                    d = toSegment(ray * stops[edge], ray * stops[edge + 1])
                    a = edge * 8 + (k + 7) % 8; b = edge * 8 + k
                case 4: d = toArc(earth, from); a = k; b = 8 + k
                case 5: d = toSegment(ray * stops[2], next * nextSide); a = 8 + k; b = 16 + k
                case 6: d = toArc(1, from); a = 16 + k; b = 24 + k
                default:
                    let inset = 1 - band
                    d = toSegment(ray * stops[4] * inset, next * nextEdge * inset); a = 24 + k; b = -1
                }
                if band <= 0, b >= 0, dealt[a] == dealt[b] { continue }
                nearest = min(nearest, d)
            }
        }
        return band > 0 ? nearest - band : nearest
    }

    /// How deep the deepest field of each wool goes, in half-sides, read off
    /// a grid of points over the tabla. A wool's turn lays that many strands,
    /// so its last strand goes down as its turn ends.
    nonisolated static func reaches(dealt: [Int], wools: Int, earth: Double, band: Double) -> [Double] {
        var deepest = [Double](repeating: 0, count: wools)
        let across = 96
        for j in 0 ..< across {
            for i in 0 ..< across {
                let q = Vector2((Double(i) + 0.5) / Double(across) * 2 - 1,
                                (Double(j) + 0.5) / Double(across) * 2 - 1)
                let wool = dealt[field(at: q, earth: earth)] % wools
                deepest[wool] = max(deepest[wool], depth(at: q, dealt: dealt, earth: earth, band: band))
            }
        }
        return deepest
    }

    // MARK: - The yarn

    /// The whole tabla as one program, run at every pixel of every field.
    /// It finds the edge of the structure nearest the pixel among the edges
    /// that matter (every edge when the lines are bands, else the edges
    /// where the color changes), counts strands in from that edge, and
    /// shades the strand it lands on as a round thread of two twisted plies
    /// lit from the upper left.
    private static let yarn = """
    static float3 terrazasWool(float v) {
        float r = floor(v / 65536.0);
        float g = floor((v - r * 65536.0) / 256.0);
        float b = v - r * 65536.0 - g * 256.0;
        return float3(r, g, b) / 255.0;
    }

    static float2 terrazasFootOnSegment(float2 p, float2 a, float2 b) {
        float2 ab = b - a;
        float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-9), 0.0, 1.0);
        return a + ab * t;
    }

    // The nearest point of an eighth of a circle about the origin, from the
    // angle `from` on.
    static float2 terrazasFootOnArc(float2 p, float radius, float from) {
        float rel = atan2(p.y, p.x) - from;
        rel -= 6.2831853 * floor(rel / 6.2831853);
        float2 e0 = float2(cos(from), sin(from)) * radius;
        if (rel <= 0.78539816) {
            float r = length(p);
            return r > 1e-5 ? p / r * radius : e0;
        }
        float2 e1 = float2(cos(from + 0.78539816), sin(from + 0.78539816)) * radius;
        return distance(p, e0) < distance(p, e1) ? e0 : e1;
    }

    // One strand: `x` counts strands in from the edge, `away` points the way
    // the count runs, `along` runs down the strand in strands.
    static float3 terrazasStrand(float3 wool, float x, float2 away, float along,
                                 float relief, float crease) {
        float strand = floor(x);
        float u = fract(x) * 2.0 - 1.0;
        float lot = hash12(float2(strand, 17.0));
        float rise = sqrt(max(0.0, 1.0 - u * u));
        float3 normal = normalize(float3(away * u, rise + 0.35));
        float2 run = float2(-away.y, away.x);
        float ply = sin((along / 3.0 + u * 0.5 + lot) * 6.2831853);
        normal = normalize(normal + float3(run * ply * 0.35, 0.0));
        float lit = max(dot(normal, normalize(float3(-0.45, -0.6, 0.66))), 0.0);
        float groove = smoothstep(1.0, 0.72, abs(u));
        float fiber = valueNoise(float2(along * 0.9 + lot * 40.0, x * 7.0)) - 0.5;
        float tone = mix(1.0, (0.50 + 0.58 * lit) * mix(0.66, 1.0, groove), relief);
        tone *= 1.0 + relief * (0.10 * fiber + 0.07 * (lot - 0.5));
        tone *= 1.0 - 0.38 * relief * crease;
        return srgbToLinear(wool) * tone;
    }

    float4 shade(float2 uv, ShaderInfo info) {
        float2 p = info.position - float2(param(info, 0), param(info, 1));
        float h = param(info, 2);
        float earth = param(info, 3) * h;
        float pitch = param(info, 4);
        float band = param(info, 5);
        float laid = param(info, 7);
        float relief = param(info, 8);

        // Each field's wool, as an index: four fields to a number.
        int wool[32];
        for (int f = 0; f < 32; f++) {
            float packed = param(info, 12 + f / 4);
            wool[f] = int(floor(packed / pow(16.0, float(f % 4)))) % 16;
        }

        // The field this pixel is in.
        float turn = atan2(p.y, p.x) / 0.78539816;
        if (turn < 0.0) turn += 8.0;
        int eighth = min(7, int(turn));
        float r = length(p);
        int ring = r < earth ? 0 : (abs(p.x) + abs(p.y) < h ? 1 : (r < h ? 2 : 3));
        int mine = ring * 8 + eighth;

        // The nearest edge that matters, the next nearest that runs another
        // way, and the nearest edge of all.
        float d1 = 1.0e9, d2 = 1.0e9, dAll = 1.0e9;
        float2 foot1 = float2(0.0), foot2 = float2(0.0);
        float arc1 = 0.0;
        int other = -1;
        for (int k = 0; k < 8; k++) {
            float a0 = float(k) * 0.78539816;
            float2 ray = float2(cos(a0), sin(a0));
            float2 next = float2(cos(a0 + 0.78539816), sin(a0 + 0.78539816));
            bool diagonal = (k % 2) == 1;
            // Where ray k meets the small circle, the turned square, the
            // large circle, and the square.
            float stops[5] = { 0.0, earth, diagonal ? h * 0.70710678 : h, h,
                               diagonal ? h * 1.41421356 : h };
            float nextSide = diagonal ? h : h * 0.70710678;
            float nextEdge = diagonal ? h : h * 1.41421356;
            for (int e = 0; e < 8; e++) {
                float2 foot;
                int a, b;
                float isArc = 0.0;
                if (e < 4) {
                    // The ray between the eighth before and this one, ring e.
                    if (stops[e + 1] - stops[e] < 1e-4) continue;
                    foot = terrazasFootOnSegment(p, ray * stops[e], ray * stops[e + 1]);
                    a = e * 8 + (k + 7) % 8; b = e * 8 + k;
                } else if (e == 4) {
                    foot = terrazasFootOnArc(p, earth, a0); isArc = 1.0;
                    a = k; b = 8 + k;
                } else if (e == 5) {
                    foot = terrazasFootOnSegment(p, ray * stops[2], next * nextSide);
                    a = 8 + k; b = 16 + k;
                } else if (e == 6) {
                    foot = terrazasFootOnArc(p, h, a0); isArc = 1.0;
                    a = 16 + k; b = 24 + k;
                } else {
                    // The square's own line lies wholly inside the square
                    // when it is a band: its middle is half a band in.
                    float inset = (h - band) / h;
                    foot = terrazasFootOnSegment(p, ray * stops[4] * inset, next * nextEdge * inset);
                    a = 24 + k; b = -1;
                }
                float d = distance(p, foot);
                dAll = min(dAll, d);
                if (band <= 0.0 && b >= 0 && wool[a] == wool[b]) continue;
                if (d < d1) {
                    if (distance(foot, foot1) > 0.75) { d2 = d1; foot2 = foot1; }
                    d1 = d; foot1 = foot; arc1 = isArc;
                    other = (a == mine) ? b : a;
                } else if (d < d2 && distance(foot, foot1) > 0.75) {
                    d2 = d; foot2 = foot;
                }
            }
        }

        float2 away = d1 > 1e-4 ? (p - foot1) / d1 : float2(0.0, 1.0);
        float2 away2 = d2 < 1.0e8 ? normalize(p - foot2) : away;
        float crease = (1.0 - smoothstep(0.0, 1.4, d2 - d1))
                     * smoothstep(0.02, 0.3, 1.0 - dot(away, away2));
        float along = (arc1 > 0.5 ? atan2(p.y, p.x) * r : dot(p, float2(-away.y, away.x))) / pitch;

        // The bare board: wax, with the structure scored into it.
        float3 board = srgbToLinear(terrazasWool(param(info, 10)));
        board *= 0.92 + 0.16 * fbm(p * 0.035);
        board *= 1.0 - 0.45 * (1.0 - smoothstep(0.4, 1.3, dAll));

        // What is laid here, and when its turn comes: the lines first, then
        // one wool after another.
        bool inBand = band > 0.0 && d1 < band;
        float depth = band > 0.0 ? abs(d1 - band) : d1;
        float x = depth / pitch;
        float3 woolHere = inBand ? terrazasWool(param(info, 6))
                                 : terrazasWool(param(info, 20 + wool[mine]));
        float order = inBand ? 0.0 : float(wool[mine]) + (band > 0.0 ? 1.0 : 0.0);
        // How deep this wool's deepest field goes: its turn lays that much.
        float reach = inBand ? band : param(info, 28 + wool[mine]);
        // Strands are counted toward the middle of what they fill: into a
        // field from its edge, and into a band from its side.
        float2 inward = inBand ? -away : away;
        float3 laidWool = terrazasStrand(woolHere, x, inward, along, relief, crease);

        // The far side of the nearest edge, for the pixel the edge crosses.
        float3 across = laidWool;
        float acrossOrder = order;
        float acrossReach = reach;
        if (band > 0.0) {
            float3 farWool = inBand ? terrazasWool(param(info, 20 + wool[mine]))
                                    : terrazasWool(param(info, 6));
            across = terrazasStrand(farWool, x, inward, along, relief, crease);
            acrossOrder = inBand ? float(wool[mine]) + 1.0 : 0.0;
            acrossReach = inBand ? param(info, 28 + wool[mine]) : band;
        } else if (other >= 0) {
            across = terrazasStrand(terrazasWool(param(info, 20 + wool[other])), x, inward, along,
                                    relief, crease);
            acrossOrder = float(wool[other]);
            acrossReach = param(info, 28 + wool[other]);
        }

        float done = clamp(laid - order, 0.0, 1.0);
        float cover = done >= 1.0 ? 1.0 : clamp((floor(done * reach / pitch) - x) * pitch + 0.5, 0.0, 1.0);
        float3 here = mix(board, laidWool, cover);
        float acrossDone = clamp(laid - acrossOrder, 0.0, 1.0);
        float3 there = mix(board, across, acrossDone >= 1.0 || acrossDone * acrossReach / pitch >= 1.0 ? 1.0 : 0.0);
        bool edged = band > 0.0 || other >= 0;
        float3 color = edged ? mix(there, here, clamp(depth + 0.5, 0.0, 1.0)) : here;
        return float4(linearToSrgb(color), 1.0);
    }
    """

    // MARK: - Drawing

    private var fields: [Shape] = []
    private var builtEarth = -1.0
    private var deepest: [Double] = []
    private var deepestFor = ""

    /// The thirty-two fields as shapes, cut from the structure's own lines
    /// and put in the order `field(at:earth:)` numbers them.
    private func cutFields() {
        guard builtEarth != earth else { return }
        var byNumber = [Shape?](repeating: nil, count: 32)
        for region in regions(enclosedBy: Cosmos.outlines(earth: earth)) {
            let q = (region.centroid - Cosmos.center) / Cosmos.half
            byNumber[Cosmos.field(at: q, earth: earth)] = region
        }
        fields = byNumber.compactMap { $0 }
        builtEarth = earth
    }

    private var palette: [Color] {
        switch wools {
        case .dyed: return Array(dyed.prefix(colors))
        case .keyed:
            return Palette.scheme(.vividAndDark, key: Color.mostVivid(hue: keyHue), count: colors,
                                  seed: variation).colors
        }
    }

    /// How much is laid, in turns: every wool down at the start of the
    /// cycle, taken back to the board, and laid again.
    private func laid(turns: Double) -> Double {
        let p = loopProgress(over: seconds)
        func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }
        switch p {
        case ..<0.36: return turns
        case ..<0.52: return turns * (1 - ease((p - 0.36) / 0.16))
        case ..<0.57: return 0
        case ..<0.97: return turns * ((p - 0.57) / 0.40)
        default: return turns
        }
    }

    override func draw() {
        cutFields()
        let dealt = Cosmos.deal(colors: colors, sharing: sharing, seed: variation)
        let wool = palette
        let c = Cosmos.center, h = Cosmos.half

        background(wall)
        noStroke()
        fill(maple)
        drawRect(center: c, width: 2 * h + 64, height: 2 * h + 64)
        fill(recess)
        drawRect(center: c, width: 2 * h + 36, height: 2 * h + 36)

        let bandColor = lines == .black ? black : white
        let bandWidth = lines == .none ? 0 : Double(lineStrands) * pitch

        if isVectorExporting {
            for (number, shape) in fields.enumerated() {
                fill(wool[dealt[number] % wool.count])
                drawShape(shape)
            }
            if bandWidth > 0 {
                noFill()
                stroke(bandColor)
                strokeWeight(bandWidth)
                // The square's own band lies wholly inside the square.
                let inside = h - bandWidth / 2
                drawRect(center: c, width: 2 * inside, height: 2 * inside)
                for outline in Cosmos.outlines(earth: earth).dropFirst() {
                    drawPolyline(outline.points, closed: outline.isClosed)
                }
            }
            return
        }

        func packed(_ color: Color) -> Float {
            let r = (color.red * 255).rounded(), g = (color.green * 255).rounded()
            let b = (color.blue * 255).rounded()
            return Float(r * 65536 + g * 256 + b)
        }
        let turns = Double(wool.count) + (bandWidth > 0 ? 1 : 0)
        // How deep each wool's deepest field goes, found once for a deal.
        let name = "\(variation)/\(colors)/\(sharing)/\(earth)/\(bandWidth)"
        if deepestFor != name {
            deepest = Cosmos.reaches(dealt: dealt, wools: wool.count, earth: earth, band: bandWidth / 2 / h)
            deepestFor = name
        }
        var params: [Float] = [
            Float(c.x), Float(c.y), Float(h), Float(earth), Float(pitch), Float(bandWidth / 2),
            packed(bandColor), Float(laid(turns: turns)), Float(relief), 0,
            packed(wax), 0,
        ]
        for group in 0 ..< 8 {
            var value = 0.0
            for digit in 0 ..< 4 { value += Double(dealt[group * 4 + digit] % wool.count) * pow(16, Double(digit)) }
            params.append(Float(value))
        }
        params += (0 ..< 8).map { $0 < wool.count ? packed(wool[$0]) : 0 }
        // A wool's turn lays its deepest field's strands and a little over,
        // since the depth was read off a grid.
        params += (0 ..< 8).map { $0 < deepest.count ? Float(deepest[$0] * h + 9 + pitch) : 0 }
        fill(Shader(Cosmos.yarn, params: params))
        for shape in fields { drawShape(shape) }
    }
}
