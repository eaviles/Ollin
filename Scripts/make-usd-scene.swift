#!/usr/bin/env swift
import Foundation

// Generates an Ollin-original sample *scene* as a self-contained USD text file:
// a small sculpture court (a round dais, a colonnade arc, and three plinths
// carrying an orb, a gem, and a standing ring, each a child of its plinth), an
// authored camera, and a UsdLux lighting rig covering every mapped light kind
// (a distant sunset key, a sphere fill, a cone-shaped sphere beam on the gem, a
// rect backlight panel, an overhead disk pool, and a cylinder floor glow). The
// gem is two-tone: a material-binding GeomSubset gives its lower (pavilion)
// facets a garnet material while the crown keeps the mesh's own amber binding,
// so the asset exercises per-material submeshes and the subset-remainder
// inheritance. The bundled demo asset for the 3D/USDScene example; everything
// is authored here, so the asset carries no third-party license.
//
// One deliberate choice, bounded by what the platform importer exposes: diffuse
// colors are authored as the *display* values the scene reader hands back (the
// reader takes them as-is). Light colors, by contrast, are linear per UsdLux
// and re-encode on load; since Ollin normalizes each kind's brightest light to
// intensity 1, the rig's visual balance rides the authored colors.
// Re-run to regenerate:
//
//     swift Scripts/make-usd-scene.swift Examples/3D/Geometry/USDScene/stage.usda

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "Examples/3D/Geometry/USDScene/stage.usda"

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

/// An axis-aligned box spanning y 0...h, centered in x and z, faceted (each face
/// its own four vertices so the normals stay flat).
func box(width w: Float, height h: Float, depth d: Float) -> Geo {
    var g = Geo()
    let x = w / 2, z = d / 2
    // (corner order chosen so each quad winds counter-clockwise seen from outside)
    let faces: [(n: V3, corners: [V3])] = [
        ((0, 0, 1), [(-x, 0, z), (x, 0, z), (x, h, z), (-x, h, z)]),
        ((0, 0, -1), [(x, 0, -z), (-x, 0, -z), (-x, h, -z), (x, h, -z)]),
        ((1, 0, 0), [(x, 0, z), (x, 0, -z), (x, h, -z), (x, h, z)]),
        ((-1, 0, 0), [(-x, 0, -z), (-x, 0, z), (-x, h, z), (-x, h, -z)]),
        ((0, 1, 0), [(-x, h, z), (x, h, z), (x, h, -z), (-x, h, -z)]),
        ((0, -1, 0), [(-x, 0, -z), (x, 0, -z), (x, 0, z), (-x, 0, z)]),
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
            // The tube frame at ring angle a: radial (cos a, sin a, 0), axial z.
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

/// A faceted bipyramid "gem": an equatorial hexagon at height `belt`, apexes at
/// y 0 and y `height`.
func gem(radius r: Float, height h: Float, belt: Float, sides: Int) -> Geo {
    var g = Geo()
    var equator: [V3] = []
    for s in 0..<sides {
        let a = Float(s) / Float(sides) * 2 * .pi
        equator.append((cos(a) * r, belt, sin(a) * r))
    }
    let bottom: V3 = (0, 0, 0), top: V3 = (0, h, 0)
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
    // Trim trailing zeros (keeping at least one digit) so the file stays readable.
    var t = s
    while t.hasSuffix("0") { t.removeLast() }
    if t.hasSuffix(".") { t += "0" }
    return t
}

func triples(_ pts: [V3]) -> String {
    pts.map { "(\(fmt($0.x)), \(fmt($0.y)), \(fmt($0.z)))" }.joined(separator: ", ")
}

func meshPrim(_ name: String, _ geo: Geo, translate: V3? = nil,
              material: String,
              subsets: [(name: String, faces: [Int], material: String)] = [],
              indent: Int) -> String {
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
    lines.append("\(pad)    rel material:binding = </Court/Materials/\(material)>")
    // Material-binding subsets: the named faces wear their own material, the
    // rest keep the mesh's binding above.
    for subset in subsets {
        lines.append("")
        lines.append("\(pad)    def GeomSubset \"\(subset.name)\"")
        lines.append("\(pad)    {")
        lines.append("\(pad)        uniform token elementType = \"face\"")
        lines.append("\(pad)        uniform token familyName = \"materialBind\"")
        lines.append("\(pad)        int[] indices = [\(subset.faces.map(String.init).joined(separator: ", "))]")
        lines.append("\(pad)        rel material:binding = </Court/Materials/\(subset.material)>")
        lines.append("\(pad)    }")
    }
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
                token outputs:surface.connect = </Court/Materials/\(name)/pbr.outputs:surface>

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

/// A UsdLux light prim: type, transform ops (translate outermost, then rotate),
/// the shared color/intensity inputs, plus per-kind extras.
func lightPrim(_ type: String, _ name: String, color: (Float, Float, Float),
               intensity: Float, translate: V3? = nil, rotate: V3? = nil,
               extras: [String] = []) -> String {
    let pad = "        "
    var lines: [String] = []
    lines.append("\(pad)def \(type) \"\(name)\"")
    lines.append("\(pad){")
    var order: [String] = []
    if let t = translate {
        lines.append("\(pad)    double3 xformOp:translate = (\(fmt(t.x)), \(fmt(t.y)), \(fmt(t.z)))")
        order.append("\"xformOp:translate\"")
    }
    if let r = rotate {
        lines.append("\(pad)    float3 xformOp:rotateXYZ = (\(fmt(r.x)), \(fmt(r.y)), \(fmt(r.z)))")
        order.append("\"xformOp:rotateXYZ\"")
    }
    if !order.isEmpty {
        lines.append("\(pad)    uniform token[] xformOpOrder = [\(order.joined(separator: ", "))]")
    }
    lines.append("\(pad)    color3f inputs:color = (\(fmt(color.0)), \(fmt(color.1)), \(fmt(color.2)))")
    lines.append("\(pad)    float inputs:intensity = \(fmt(intensity))")
    for extra in extras { lines.append("\(pad)    \(extra)") }
    lines.append("\(pad)}")
    return lines.joined(separator: "\n")
}

// MARK: The court.

let daisHeight: Float = 0.18
let dais = cylinder(radius: 2.7, height: daisHeight, segments: 48)
let plinthLow = box(width: 0.62, height: 0.62, depth: 0.62)
let plinthTall = box(width: 0.56, height: 0.95, depth: 0.56)
let column = cylinder(radius: 0.15, height: 2.3, segments: 24)
let orb = sphere(radius: 0.42, rings: 20, segments: 32)
let ring = standingTorus(major: 0.34, minor: 0.1, segU: 36, segV: 18)
let stone = gem(radius: 0.3, height: 0.78, belt: 0.28, sides: 6)

// Five columns on an arc behind the plinths (negative z).
var columnPrims: [String] = []
for (i, degrees) in [200, 235, 270, 305, 340].enumerated() {
    let a = Float(degrees) * .pi / 180
    columnPrims.append(meshPrim("column\(i + 1)", column,
                                translate: (cos(a) * 2.2, 0, sin(a) * 2.2),
                                material: "plaster", indent: 2))
}

// The camera: eye level slightly above the court, tilted gently down. Model I/O
// derives the field of view from focal length over vertical aperture
// (2 * atan(15.2908 / 42) here, about 40 degrees; Ollin renders it square, so
// the same angle bounds the width).
let cameraPrim = """
    def Camera "view"
    {
        double3 xformOp:translate = (0, 2.5, 7.0)
        float3 xformOp:rotateXYZ = (-12, 0, 0)
        uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:rotateXYZ"]
        float focalLength = 21
        float horizontalAperture = 20.955
        float verticalAperture = 15.2908
        float2 clippingRange = (0.1, 100)
    }
"""

// The lighting rig: one light of every mapped UsdLux kind. Lights emit along
// their local -z, so each aim is a rotateXYZ swinging -z onto the wanted
// direction; the visual balance rides the linear colors (see the header note).
let lightPrims = [
    // The warm key, matching the sketch-lit look this rig replaced:
    // rotate (-49, 57.5) sends -z to about (-0.55, -0.75, -0.35).
    lightPrim("DistantLight", "sunset", color: (0.85, 0.72, 0.55), intensity: 60000,
              rotate: (-49, 57.5, 0),
              extras: ["float inputs:angle = 0.53"]),
    // A cool fill floating high on the camera's right.
    lightPrim("SphereLight", "fill", color: (0.16, 0.21, 0.37), intensity: 8,
              translate: (2.5, 3.2, 2.8),
              extras: ["float inputs:radius = 0.3"]),
    // The shaped beam: a sphere light with a cone, pitched -36 deg onto the gem.
    lightPrim("SphereLight", "beam", color: (0.9, 0.78, 0.55), intensity: 20,
              translate: (0, 3.4, 2.2), rotate: (-36, 0, 0),
              extras: ["float inputs:radius = 0.1",
                       "float inputs:shaping:cone:angle = 14",
                       "float inputs:shaping:cone:softness = 0.35"]),
    // A teal backlight panel behind the colonnade, turned back at the court.
    lightPrim("RectLight", "panel", color: (0.2, 0.3, 0.28), intensity: 5,
              translate: (-2.8, 1.5, -2.8), rotate: (-7, -135, 0),
              extras: ["float inputs:width = 2.6", "float inputs:height = 1.4"]),
    // An overhead pool centered on the dais, facing straight down.
    lightPrim("DiskLight", "halo", color: (0.32, 0.3, 0.27), intensity: 6,
              translate: (0, 4.2, 0), rotate: (-90, 0, 0),
              extras: ["float inputs:radius = 1.1"]),
    // A verdigris floor glow lying along x behind the plinths.
    lightPrim("CylinderLight", "glow", color: (0.12, 0.45, 0.36), intensity: 12,
              translate: (0, 0.12, -1.6),
              extras: ["float inputs:length = 3.2", "float inputs:radius = 0.04"]),
]

let usda = """
#usda 1.0
(
    defaultPrim = "Court"
    metersPerUnit = 1
    upAxis = "Y"
)

def Xform "Court"
{
\(meshPrim("dais", dais, material: "stone", indent: 1))

    def Xform "plinths"
    {
        double3 xformOp:translate = (0, \(fmt(daisHeight)), 0)
        uniform token[] xformOpOrder = ["xformOp:translate"]

        def Xform "plinthOrb"
        {
            double3 xformOp:translate = (-1.35, 0, 0.4)
            uniform token[] xformOpOrder = ["xformOp:translate"]

\(meshPrim("base", plinthLow, material: "stone", indent: 3))

\(meshPrim("orb", orb, translate: (0, 1.06, 0), material: "lapis", indent: 3))
        }

        def Xform "plinthGem"
        {
            double3 xformOp:translate = (0, 0, -0.55)
            uniform token[] xformOpOrder = ["xformOp:translate"]

\(meshPrim("base", plinthTall, material: "stone", indent: 3))

\(meshPrim("gem", stone, translate: (0, 0.97, 0), material: "amber",
           subsets: [("pavilion", Array(stride(from: 1, to: 12, by: 2)), "garnet")],
           indent: 3))
        }

        def Xform "plinthRing"
        {
            double3 xformOp:translate = (1.35, 0, 0.45)
            uniform token[] xformOpOrder = ["xformOp:translate"]

\(meshPrim("base", plinthLow, material: "stone", indent: 3))

\(meshPrim("ring", ring, translate: (0, 1.08, 0), material: "verdigris", indent: 3))
        }
    }

    def Xform "colonnade"
    {
        double3 xformOp:translate = (0, \(fmt(daisHeight)), 0)
        uniform token[] xformOpOrder = ["xformOp:translate"]

\(columnPrims.joined(separator: "\n\n"))
    }

\(cameraPrim)

    def Scope "Lights"
    {
\(lightPrims.joined(separator: "\n\n"))
    }

    def Scope "Materials"
    {
\(materialPrim("stone", color: (0.64, 0.62, 0.58), roughness: 0.85))

\(materialPrim("plaster", color: (0.78, 0.76, 0.72), roughness: 0.9))

\(materialPrim("lapis", color: (0.16, 0.3, 0.62), roughness: 0.35))

\(materialPrim("amber", color: (0.92, 0.62, 0.18), roughness: 0.25))

\(materialPrim("garnet", color: (0.56, 0.14, 0.2), roughness: 0.3))

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
