#!/usr/bin/env swift
import Foundation

// Generates an Ollin-original *animated* USD scene as a self-contained text
// file: a hanging kinetic mobile whose xformOps carry timeSamples, the bundled
// demo asset for the 3D/USDAnimatedScene example. Everything is authored here,
// so the asset carries no third-party license.
//
// The rig exercises every authored form the animation bake handles, one per
// named part, and the whole timeline loops seamlessly over 8 seconds
// (timeCodesPerSecond 24, samples 0...192, every animated op's last sample
// equal to its first up to a full turn):
//
//   beamA     a slow full-turn spin (float3 rotateXYZ timeSamples)
//   beamB     a counter-spinning child riding beamA (rotation composes)
//   moon      a bobbing sphere (double3 translate timeSamples, a sampled sine)
//   gem       a tumble about a tilted axis (quatf orient timeSamples)
//   swing     a pendulum ring on the pivot idiom (translate:pivot + animated
//             rotateZ + !invert!translate:pivot, so the baked track *orbits*)
//   pulse     a breathing counterweight (float3 scale timeSamples)
//
// A camera and two UsdLux lights (a warm distant key, a cool sphere fill)
// complete the stage; diffuse colors are authored as display values (the
// platform reader takes them as-is), light colors are linear per UsdLux.
// Re-run to regenerate:
//
//     swift Scripts/make-usd-animated-scene.swift Examples/3D/Geometry/USDAnimatedScene/stage.usda

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "Examples/3D/Geometry/USDAnimatedScene/stage.usda"

// MARK: Small vector helpers.

typealias V3 = (x: Float, y: Float, z: Float)
func norm(_ a: V3) -> V3 {
    let l = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
    return l > 0 ? (a.x / l, a.y / l, a.z / l) : (0, 1, 0)
}

// MARK: Geometry builders (points + vertex normals + mixed quad/triangle faces).

struct Geo {
    var points: [V3] = []
    var normals: [V3] = []
    var counts: [Int] = []    // vertices per face (3 or 4)
    var indices: [Int] = []

    mutating func vertex(_ p: V3, _ n: V3) -> Int {
        points.append(p)
        normals.append(norm(n))
        return points.count - 1
    }
    mutating func quad(_ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        counts.append(4); indices += [a, b, c, d]
    }
    mutating func tri(_ a: Int, _ b: Int, _ c: Int) {
        counts.append(3); indices += [a, b, c]
    }
}

/// An axis-aligned box centered at the origin, faceted (each face its own four
/// vertices so the normals stay flat).
func box(width w: Float, height h: Float, depth d: Float) -> Geo {
    var g = Geo()
    let x = w / 2, y = h / 2, z = d / 2
    let faces: [(n: V3, corners: [V3])] = [
        ((0, 0, 1), [(-x, -y, z), (x, -y, z), (x, y, z), (-x, y, z)]),
        ((0, 0, -1), [(x, -y, -z), (-x, -y, -z), (-x, y, -z), (x, y, -z)]),
        ((1, 0, 0), [(x, -y, z), (x, -y, -z), (x, y, -z), (x, y, z)]),
        ((-1, 0, 0), [(-x, -y, -z), (-x, -y, z), (-x, y, z), (-x, y, -z)]),
        ((0, 1, 0), [(-x, y, z), (x, y, z), (x, y, -z), (-x, y, -z)]),
        ((0, -1, 0), [(-x, -y, -z), (x, -y, -z), (x, -y, z), (-x, -y, z)]),
    ]
    for f in faces {
        let ids = f.corners.map { g.vertex($0, f.n) }
        g.quad(ids[0], ids[1], ids[2], ids[3])
    }
    return g
}

/// An upright cylinder spanning y 0...h: smooth-shaded side quads plus flat
/// triangle-fan caps.
func cylinder(radius r: Float, height h: Float, segments: Int) -> Geo {
    var g = Geo()
    var lower: [Int] = [], upper: [Int] = []
    for s in 0..<segments {
        let a = Float(s) / Float(segments) * 2 * .pi
        let n: V3 = (cos(a), 0, sin(a))
        lower.append(g.vertex((n.x * r, 0, n.z * r), n))
        upper.append(g.vertex((n.x * r, h, n.z * r), n))
    }
    for s in 0..<segments {
        let t = (s + 1) % segments
        g.quad(lower[s], lower[t], upper[t], upper[s])
    }
    let bottomCenter = g.vertex((0, 0, 0), (0, -1, 0))
    let topCenter = g.vertex((0, h, 0), (0, 1, 0))
    var bottomRim: [Int] = [], topRim: [Int] = []
    for s in 0..<segments {
        let a = Float(s) / Float(segments) * 2 * .pi
        bottomRim.append(g.vertex((cos(a) * r, 0, sin(a) * r), (0, -1, 0)))
        topRim.append(g.vertex((cos(a) * r, h, sin(a) * r), (0, 1, 0)))
    }
    for s in 0..<segments {
        let t = (s + 1) % segments
        g.tri(bottomCenter, bottomRim[s], bottomRim[t])
        g.tri(topCenter, topRim[t], topRim[s])
    }
    return g
}

/// A UV sphere centered at the origin, smooth-shaded quads (triangles at the
/// poles).
func sphere(radius r: Float, rings: Int, segments: Int) -> Geo {
    var g = Geo()
    var grid: [[Int]] = []
    for ring in 0...rings {
        let v = Float(ring) / Float(rings)
        let phi = v * .pi
        var row: [Int] = []
        for s in 0..<segments {
            let a = Float(s) / Float(segments) * 2 * .pi
            let n: V3 = (sin(phi) * cos(a), cos(phi), sin(phi) * sin(a))
            row.append(g.vertex((n.x * r, n.y * r, n.z * r), n))
        }
        grid.append(row)
    }
    for ring in 0..<rings {
        for s in 0..<segments {
            let t = (s + 1) % segments
            let a = grid[ring][s], b = grid[ring][t]
            let c = grid[ring + 1][t], d = grid[ring + 1][s]
            if ring == 0 { g.tri(a, c, d) }
            else if ring == rings - 1 { g.tri(a, b, d) }
            else { g.quad(a, b, c, d) }
        }
    }
    return g
}

/// A torus standing upright (the ring in the x-y plane), smooth-shaded quads.
func standingTorus(major R: Float, minor r: Float, segU: Int, segV: Int) -> Geo {
    var g = Geo()
    var grid: [[Int]] = []
    for u in 0..<segU {
        let a = Float(u) / Float(segU) * 2 * .pi
        let center: V3 = (cos(a) * R, sin(a) * R, 0)
        var row: [Int] = []
        for v in 0..<segV {
            let b = Float(v) / Float(segV) * 2 * .pi
            let n: V3 = (cos(a) * cos(b), sin(a) * cos(b), sin(b))
            row.append(g.vertex((center.x + n.x * r, center.y + n.y * r, center.z + n.z * r), n))
        }
        grid.append(row)
    }
    for u in 0..<segU {
        let u2 = (u + 1) % segU
        for v in 0..<segV {
            let v2 = (v + 1) % segV
            g.quad(grid[u][v], grid[u2][v], grid[u2][v2], grid[u][v2])
        }
    }
    return g
}

/// A faceted bipyramid "gem" centered at the origin: an equatorial hexagon,
/// apexes at y ±h/2.
func gem(radius r: Float, height h: Float, sides: Int) -> Geo {
    var g = Geo()
    var equator: [V3] = []
    for s in 0..<sides {
        let a = Float(s) / Float(sides) * 2 * .pi
        equator.append((cos(a) * r, 0, sin(a) * r))
    }
    let bottom: V3 = (0, -h / 2, 0), top: V3 = (0, h / 2, 0)
    func facet(_ a: V3, _ b: V3, _ c: V3) {
        let u: V3 = (b.x - a.x, b.y - a.y, b.z - a.z)
        let v: V3 = (c.x - a.x, c.y - a.y, c.z - a.z)
        let n: V3 = (u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
        let ia = g.vertex(a, n), ib = g.vertex(b, n), ic = g.vertex(c, n)
        g.tri(ia, ib, ic)
    }
    for s in 0..<sides {
        let t = (s + 1) % sides
        facet(top, equator[t], equator[s])
        facet(bottom, equator[s], equator[t])
    }
    return g
}

// MARK: USD text emission.

func fmt(_ v: Float) -> String {
    let s = String(format: "%.5f", v)
    var t = s
    while t.hasSuffix("0") { t.removeLast() }
    if t.hasSuffix(".") { t += "0" }
    return t
}

func fmt(_ v: Double) -> String { fmt(Float(v)) }

func triples(_ pts: [V3]) -> String {
    pts.map { "(\(fmt($0.x)), \(fmt($0.y)), \(fmt($0.z)))" }.joined(separator: ", ")
}

func meshPrim(_ name: String, _ geo: Geo, translate: V3? = nil,
              material: String, indent: Int) -> String {
    let pad = String(repeating: "    ", count: indent)
    var lines: [String] = []
    lines.append("\(pad)def Mesh \"\(name)\"")
    lines.append("\(pad){")
    if let t = translate {
        lines.append("\(pad)    double3 xformOp:translate = (\(fmt(t.x)), \(fmt(t.y)), \(fmt(t.z)))")
        lines.append("\(pad)    uniform token[] xformOpOrder = [\"xformOp:translate\"]")
    }
    lines.append("\(pad)    uniform token subdivisionScheme = \"none\"")
    lines.append("\(pad)    point3f[] points = [\(triples(geo.points))]")
    lines.append("\(pad)    normal3f[] normals = [\(triples(geo.normals))] (")
    lines.append("\(pad)        interpolation = \"vertex\"")
    lines.append("\(pad)    )")
    lines.append("\(pad)    int[] faceVertexCounts = [\(geo.counts.map(String.init).joined(separator: ", "))]")
    lines.append("\(pad)    int[] faceVertexIndices = [\(geo.indices.map(String.init).joined(separator: ", "))]")
    lines.append("\(pad)    rel material:binding = </Mobile/Materials/\(material)>")
    lines.append("\(pad)}")
    return lines.joined(separator: "\n")
}

/// A designed display (sRGB) component re-encoded to the linear value a
/// preview surface authors; readers re-encode it back, so the designed look
/// holds.
func linear(_ c: Float) -> Float {
    let x = Double(c)
    return Float(x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4))
}

func materialPrim(_ name: String, color: (Float, Float, Float), roughness: Float,
                  metallic: Float = 0) -> String {
    """
            def Material "\(name)"
            {
                token outputs:surface.connect = </Mobile/Materials/\(name)/pbr.outputs:surface>

                def Shader "pbr"
                {
                    uniform token info:id = "UsdPreviewSurface"
                    color3f inputs:diffuseColor = (\(fmt(linear(color.0))), \(fmt(linear(color.1))), \(fmt(linear(color.2))))
                    float inputs:roughness = \(fmt(roughness))
                    float inputs:metallic = \(fmt(metallic))
                    token outputs:surface
                }
            }
    """
}

/// A `time: value` sample block body at one line per sample.
func samples(_ pairs: [(Int, String)], indent: Int) -> String {
    let pad = String(repeating: "    ", count: indent)
    return pairs.map { "\(pad)    \($0.0): \($0.1)" }.joined(separator: ",\n")
}

// MARK: The animation (192 time codes at 24 per second = one 8-second lap).

let lap = 192

/// The bobbing moon: a sampled sine, first sample equal to the last so the
/// lap closes.
let moonBob: [(Int, String)] = stride(from: 0, through: lap, by: 8).map { t in
    let phase = Double(t) / Double(lap) * 2 * .pi
    let y = 0.62 + 0.16 * sin(phase)
    return (t, "(0, \(fmt(y)), 0)")
}

/// The pendulum swing: two full periods per lap, sampled densely.
let swingAngles: [(Int, String)] = stride(from: 0, through: lap, by: 8).map { t in
    let phase = Double(t) / Double(lap) * 2 * .pi
    return (t, fmt(26 * cos(2 * phase)))
}

/// The counterweight pulse: one slow breath per lap.
let pulseScale: [(Int, String)] = stride(from: 0, through: lap, by: 16).map { t in
    let phase = Double(t) / Double(lap) * 2 * .pi
    let s = 1 + 0.13 * sin(phase)
    return (t, "(\(fmt(s)), \(fmt(s)), \(fmt(s)))")
}

/// The gem tumble: a full turn about a tilted axis in eighth-turn quaternion
/// keys, authored real-first. The final key is the axis full turn (-1, 0, 0, 0),
/// the same rotation as the first, so the lap closes.
let gemTumble: [(Int, String)] = (0...8).map { k in
    let axis = norm((0.3, 1, 0.18))
    let half = Double(k) / 8 * .pi   // half the turn angle
    let s = sin(half)
    return (k * lap / 8, "(\(fmt(cos(half))), \(fmt(Double(axis.x) * s)), \(fmt(Double(axis.y) * s)), \(fmt(Double(axis.z) * s)))")
}

/// beamA: one slow turn per lap; beamB: two counter-turns, keyed each quarter.
let beamATurn: [(Int, String)] = [(0, "(0, 0, 0)"), (96, "(0, 180, 0)"), (192, "(0, 360, 0)")]
let beamBTurn: [(Int, String)] = (0...8).map { k in
    (k * lap / 8, "(0, \(fmt(-90 * Double(k))), 0)")
}

// MARK: Geometry.

let stemGeo = cylinder(radius: 0.03, height: 0.5, segments: 16)
let beamAGeo = box(width: 3.0, height: 0.06, depth: 0.06)
let beamBGeo = box(width: 1.7, height: 0.05, depth: 0.05)
let wireGeo = cylinder(radius: 0.015, height: 0.55, segments: 12)
let moonGeo = sphere(radius: 0.26, rings: 18, segments: 28)
let gemGeo = gem(radius: 0.24, height: 0.6, sides: 6)
let ringGeo = standingTorus(major: 0.24, minor: 0.07, segU: 32, segV: 16)
let pulseGeo = sphere(radius: 0.3, rings: 18, segments: 28)
let floorGeo = cylinder(radius: 2.6, height: 0.06, segments: 48)

let usda = """
#usda 1.0
(
    defaultPrim = "Mobile"
    metersPerUnit = 1
    upAxis = "Y"
    startTimeCode = 0
    endTimeCode = \(lap)
    timeCodesPerSecond = 24
)

def Xform "Mobile"
{
\(meshPrim("floorDisk", floorGeo, material: "stone", indent: 1))

\(meshPrim("stem", stemGeo, translate: (0, 2.72, 0), material: "brass", indent: 1))

    def Xform "pulse"
    {
        double3 xformOp:translate = (0, 0.36, 0)
        float3 xformOp:scale.timeSamples = {
\(samples(pulseScale, indent: 2))
        }
        uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:scale"]

\(meshPrim("weight", pulseGeo, material: "lapis", indent: 2))
    }

    def Xform "beamA"
    {
        double3 xformOp:translate = (0, 2.72, 0)
        float3 xformOp:rotateXYZ.timeSamples = {
\(samples(beamATurn, indent: 2))
        }
        uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:rotateXYZ"]

\(meshPrim("barA", beamAGeo, material: "brass", indent: 2))

        def Xform "moonRig"
        {
            double3 xformOp:translate = (-1.45, -0.9, 0)
            uniform token[] xformOpOrder = ["xformOp:translate"]

\(meshPrim("moonWire", wireGeo, translate: (0, 0.35, 0), material: "brass", indent: 3))

            def Xform "moon"
            {
                double3 xformOp:translate.timeSamples = {
\(samples(moonBob, indent: 4))
                }
                uniform token[] xformOpOrder = ["xformOp:translate"]

\(meshPrim("moonBall", moonGeo, material: "silver", indent: 4))
            }
        }

        def Xform "beamB"
        {
            double3 xformOp:translate = (1.45, -0.42, 0)
            float3 xformOp:rotateXYZ.timeSamples = {
\(samples(beamBTurn, indent: 3))
            }
            uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:rotateXYZ"]

\(meshPrim("barB", beamBGeo, translate: (0, 0.42, 0), material: "brass", indent: 3))

            def Xform "gem"
            {
                double3 xformOp:translate = (-0.82, 0.05, 0)
                quatf xformOp:orient.timeSamples = {
\(samples(gemTumble, indent: 4))
                }
                uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:orient"]

\(meshPrim("gemStone", gemGeo, material: "amber", indent: 4))
            }

            def Xform "swing"
            {
                double3 xformOp:translate = (0.82, -0.13, 0)
                double3 xformOp:translate:pivot = (0, 0.55, 0)
                float xformOp:rotateZ.timeSamples = {
\(samples(swingAngles, indent: 4))
                }
                uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:translate:pivot", "xformOp:rotateZ", "!invert!xformOp:translate:pivot"]

\(meshPrim("swingRing", ringGeo, material: "verdigris", indent: 4))
            }
        }
    }

    def Camera "view"
    {
        double3 xformOp:translate = (0, 2.05, 7.4)
        float3 xformOp:rotateXYZ = (-7, 0, 0)
        uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:rotateXYZ"]
        float focalLength = 21
        float horizontalAperture = 20.955
        float verticalAperture = 15.2908
        float2 clippingRange = (0.1, 100)
    }

    def Scope "Lights"
    {
        def DistantLight "key"
        {
            float3 xformOp:rotateXYZ = (-42, 38, 0)
            uniform token[] xformOpOrder = ["xformOp:rotateXYZ"]
            color3f inputs:color = (0.88, 0.76, 0.58)
            float inputs:intensity = 3000
            float inputs:angle = 0.53
        }

        def SphereLight "fill"
        {
            double3 xformOp:translate = (-2.6, 2.6, 3.0)
            uniform token[] xformOpOrder = ["xformOp:translate"]
            color3f inputs:color = (0.14, 0.19, 0.34)
            float inputs:intensity = 10
            float inputs:radius = 0.3
        }
    }

    def Scope "Materials"
    {
\(materialPrim("stone", color: (0.6, 0.59, 0.56), roughness: 0.85))

\(materialPrim("brass", color: (0.72, 0.58, 0.3), roughness: 0.4, metallic: 0.7))

\(materialPrim("silver", color: (0.75, 0.77, 0.8), roughness: 0.3, metallic: 0.8))

\(materialPrim("lapis", color: (0.17, 0.3, 0.6), roughness: 0.35))

\(materialPrim("amber", color: (0.92, 0.62, 0.18), roughness: 0.25))

\(materialPrim("verdigris", color: (0.35, 0.62, 0.55), roughness: 0.4, metallic: 0.6))
    }
}
"""

do {
    try usda.write(toFile: outPath, atomically: true, encoding: .utf8)
    print("Wrote \(outPath) (\(usda.utf8.count) bytes)")
} catch {
    print("Failed to write \(outPath): \(error)")
    exit(1)
}
