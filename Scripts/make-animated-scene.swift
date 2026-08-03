#!/usr/bin/env swift
import Foundation

// Generates an Ollin-original *animated* sample scene as a self-contained glTF
// 2.0 file: a small desk orrery. A planet arm swings around the sun hub (LINEAR
// quaternion keyframes), a moon arm counter-spins faster on the planet (LINEAR),
// a marker orb bobs above the sun on a cubic-spline translation (CUBICSPLINE
// with zero end tangents, so it eases at each extreme), and a pointer on the
// base ticks through twelve stepped positions (STEP). One 8-second animation
// named "spin" carries all four channels and wraps seamlessly. Plus an authored
// camera, a warm point light inside the sun, a key spot, and a cool directional
// fill. The bundled demo asset for the 3D/AnimatedScene example; everything is
// authored here, so the asset carries no third-party license. Re-run to
// regenerate:
//
//     swift Scripts/make-animated-scene.swift Examples/3D/Geometry/AnimatedScene/scene.gltf

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "Examples/3D/Geometry/AnimatedScene/scene.gltf"

// MARK: Small vector helpers (Float triples, enough for authoring).

typealias V3 = (x: Float, y: Float, z: Float)
func sub(_ a: V3, _ b: V3) -> V3 { (a.x - b.x, a.y - b.y, a.z - b.z) }
func cross(_ a: V3, _ b: V3) -> V3 {
    (a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}
func norm(_ a: V3) -> V3 {
    let l = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
    return l > 0 ? (a.x / l, a.y / l, a.z / l) : (0, 0, 1)
}

/// The quaternion (x, y, z, w) whose rotation sends local -z to look from `eye`
/// toward `target` (the glTF camera/light aiming convention), y staying up.
func lookRotation(eye: V3, target: V3, up: V3 = (0, 1, 0)) -> [Float] {
    let back = norm(sub(eye, target))                 // local +z
    let right = norm(cross(up, back))
    let trueUp = cross(back, right)
    let m00 = right.x, m01 = trueUp.x, m02 = back.x
    let m10 = right.y, m11 = trueUp.y, m12 = back.y
    let m20 = right.z, m21 = trueUp.z, m22 = back.z
    let trace = m00 + m11 + m22
    var q: [Float]
    if trace > 0 {
        let s = (trace + 1).squareRoot() * 2
        q = [(m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25 * s]
    } else if m00 > m11 && m00 > m22 {
        let s = (1 + m00 - m11 - m22).squareRoot() * 2
        q = [0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s]
    } else if m11 > m22 {
        let s = (1 + m11 - m00 - m22).squareRoot() * 2
        q = [(m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s]
    } else {
        let s = (1 + m22 - m00 - m11).squareRoot() * 2
        q = [(m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s]
    }
    return q
}

/// The quaternion for a rotation of `angle` radians about the y axis.
func yRotation(_ angle: Float) -> [Float] { [0, sin(angle / 2), 0, cos(angle / 2)] }

/// sRGB display color -> the linear color glTF stores (base colors, light colors).
func linear(_ r: Double, _ g: Double, _ b: Double) -> [Double] {
    func lin(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return [(lin(r) * 10000).rounded() / 10000,
            (lin(g) * 10000).rounded() / 10000,
            (lin(b) * 10000).rounded() / 10000]
}

// MARK: Geometry builders (positions + normals + triangle indices).

struct Geometry {
    var positions: [Float] = []   // xyz triples
    var normals: [Float] = []
    var indices: [UInt16] = []

    mutating func vertex(_ p: V3, _ n: V3) -> UInt16 {
        let i = UInt16(positions.count / 3)
        positions += [p.x, p.y, p.z]
        normals += [n.x, n.y, n.z]
        return i
    }
    mutating func quad(_ a: UInt16, _ b: UInt16, _ c: UInt16, _ d: UInt16) {
        indices += [a, b, c, a, c, d]
    }
}

/// A box centered at the origin with flat per-face normals.
func box(_ w: Float, _ h: Float, _ d: Float) -> Geometry {
    var g = Geometry()
    let x = w / 2, y = h / 2, z = d / 2
    let faces: [(n: V3, verts: [V3])] = [
        ((1, 0, 0),  [(x, -y, z), (x, -y, -z), (x, y, -z), (x, y, z)]),
        ((-1, 0, 0), [(-x, -y, -z), (-x, -y, z), (-x, y, z), (-x, y, -z)]),
        ((0, 1, 0),  [(-x, y, z), (x, y, z), (x, y, -z), (-x, y, -z)]),
        ((0, -1, 0), [(-x, -y, -z), (x, -y, -z), (x, -y, z), (-x, -y, z)]),
        ((0, 0, 1),  [(-x, -y, z), (x, -y, z), (x, y, z), (-x, y, z)]),
        ((0, 0, -1), [(x, -y, -z), (-x, -y, -z), (-x, y, -z), (x, y, -z)]),
    ]
    for f in faces {
        let i = f.verts.map { g.vertex($0, f.n) }
        g.quad(i[0], i[1], i[2], i[3])
    }
    return g
}

/// A y-axis cylinder (optionally tapered: `rTop` differs) centered at the origin,
/// smooth around the side, flat caps.
func cylinder(rBottom: Float, rTop: Float, height: Float, segments: Int) -> Geometry {
    var g = Geometry()
    let y = height / 2
    let slope = (rBottom - rTop) / height
    var ring: [(bottom: UInt16, top: UInt16)] = []
    for s in 0...segments {
        let a = Float(s) / Float(segments) * 2 * .pi
        let c = cos(a), sn = sin(a)
        let n = norm((c, slope, sn))
        let b = g.vertex((rBottom * c, -y, rBottom * sn), n)
        let t = g.vertex((rTop * c, y, rTop * sn), n)
        ring.append((b, t))
    }
    for s in 0..<segments {
        g.quad(ring[s].bottom, ring[s].top, ring[s + 1].top, ring[s + 1].bottom)
    }
    for (r, yy, n, flip) in [(rBottom, -y, (0, -1, 0) as V3, false), (rTop, y, (0, 1, 0), true)] {
        let center = g.vertex((0, yy, 0), n)
        var rim: [UInt16] = []
        for s in 0...segments {
            let a = Float(s) / Float(segments) * 2 * .pi
            rim.append(g.vertex((r * cos(a), yy, r * sin(a)), n))
        }
        for s in 0..<segments {
            if flip { g.indices += [center, rim[s], rim[s + 1]] }
            else { g.indices += [center, rim[s + 1], rim[s]] }
        }
    }
    return g
}

/// A UV sphere centered at the origin, smooth normals.
func sphere(radius: Float, segments: Int, rings: Int) -> Geometry {
    var g = Geometry()
    var grid: [[UInt16]] = []
    for r in 0...rings {
        let phi = Float(r) / Float(rings) * .pi
        var row: [UInt16] = []
        for s in 0...segments {
            let theta = Float(s) / Float(segments) * 2 * .pi
            let n: V3 = (sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
            row.append(g.vertex((radius * n.x, radius * n.y, radius * n.z), n))
        }
        grid.append(row)
    }
    for r in 0..<rings {
        for s in 0..<segments {
            g.quad(grid[r][s], grid[r][s + 1], grid[r + 1][s + 1], grid[r + 1][s])
        }
    }
    return g
}

// MARK: Assemble the buffer, accessors, meshes, and materials.

var buffer = Data()
var bufferViews: [[String: Any]] = []
var accessors: [[String: Any]] = []
var meshes: [[String: Any]] = []
var materials: [[String: Any]] = []

func putFloats(_ f: [Float]) -> Int {
    let offset = buffer.count
    f.withUnsafeBufferPointer { buffer.append(Data(buffer: $0)) }
    bufferViews.append(["buffer": 0, "byteOffset": offset, "byteLength": f.count * 4])
    return bufferViews.count - 1
}
func putIndices(_ idx: [UInt16]) -> Int {
    let offset = buffer.count
    idx.withUnsafeBufferPointer { buffer.append(Data(buffer: $0)) }
    bufferViews.append(["buffer": 0, "byteOffset": offset, "byteLength": idx.count * 2])
    if buffer.count % 4 != 0 { buffer.append(Data(repeating: 0, count: 2)) }   // realign floats
    return bufferViews.count - 1
}

func addMaterial(name: String, srgb: (Double, Double, Double),
                 metallic: Double = 0, roughness: Double = 0.85) -> Int {
    let c = linear(srgb.0, srgb.1, srgb.2)
    materials.append(["name": name, "pbrMetallicRoughness": [
        "baseColorFactor": [c[0], c[1], c[2], 1.0],
        "metallicFactor": metallic, "roughnessFactor": roughness,
    ]])
    return materials.count - 1
}

func addMesh(_ g: Geometry, material: Int) -> Int {
    let count = g.positions.count / 3
    var lo: [Float] = [.infinity, .infinity, .infinity]
    var hi: [Float] = [-.infinity, -.infinity, -.infinity]
    for i in 0..<count {
        for a in 0..<3 {
            lo[a] = min(lo[a], g.positions[i * 3 + a])
            hi[a] = max(hi[a], g.positions[i * 3 + a])
        }
    }
    let posView = putFloats(g.positions)
    accessors.append(["bufferView": posView, "componentType": 5126, "count": count,
                      "type": "VEC3", "min": lo, "max": hi])
    let posAcc = accessors.count - 1
    let normView = putFloats(g.normals)
    accessors.append(["bufferView": normView, "componentType": 5126, "count": count, "type": "VEC3"])
    let normAcc = accessors.count - 1
    let idxView = putIndices(g.indices)
    accessors.append(["bufferView": idxView, "componentType": 5123,
                      "count": g.indices.count, "type": "SCALAR"])
    let idxAcc = accessors.count - 1
    meshes.append(["primitives": [[
        "attributes": ["POSITION": posAcc, "NORMAL": normAcc],
        "indices": idxAcc, "mode": 4, "material": material,
    ]]])
    return meshes.count - 1
}

// MARK: Animation accessor helpers.

/// A SCALAR float accessor of keyframe times (the spec requires min/max on
/// animation inputs).
func addTimes(_ t: [Float]) -> Int {
    let view = putFloats(t)
    accessors.append(["bufferView": view, "componentType": 5126, "count": t.count,
                      "type": "SCALAR", "min": [t.min()!], "max": [t.max()!]])
    return accessors.count - 1
}

/// A VEC3 float accessor of animation output values (flat xyz triples).
func addVec3s(_ v: [[Float]]) -> Int {
    let view = putFloats(v.flatMap { $0 })
    accessors.append(["bufferView": view, "componentType": 5126, "count": v.count, "type": "VEC3"])
    return accessors.count - 1
}

/// A VEC4 float accessor of animation output values (flat xyzw quadruples).
func addVec4s(_ v: [[Float]]) -> Int {
    let view = putFloats(v.flatMap { $0 })
    accessors.append(["bufferView": view, "componentType": 5126, "count": v.count, "type": "VEC4"])
    return accessors.count - 1
}

let baseMat = addMaterial(name: "Base", srgb: (0.2, 0.2, 0.23), roughness: 0.7)
let pylonMat = addMaterial(name: "Pylon", srgb: (0.55, 0.5, 0.42), metallic: 1, roughness: 0.45)
let sunMat = addMaterial(name: "Sun", srgb: (0.95, 0.72, 0.25), metallic: 1, roughness: 0.3)
let armMat = addMaterial(name: "Arm", srgb: (0.3, 0.3, 0.34), metallic: 1, roughness: 0.5)
let planetMat = addMaterial(name: "Planet", srgb: (0.22, 0.55, 0.58), roughness: 0.4)
let moonMat = addMaterial(name: "Moon", srgb: (0.8, 0.8, 0.82), roughness: 0.6)
let bobMat = addMaterial(name: "Marker", srgb: (0.85, 0.4, 0.32), roughness: 0.35)
let tickerMat = addMaterial(name: "Ticker", srgb: (0.75, 0.3, 0.25), roughness: 0.6)

let baseMesh = addMesh(cylinder(rBottom: 0.6, rTop: 0.52, height: 0.12, segments: 40), material: baseMat)
let pylonMesh = addMesh(cylinder(rBottom: 0.06, rTop: 0.04, height: 1.1, segments: 24), material: pylonMat)
let sunMesh = addMesh(sphere(radius: 0.3, segments: 32, rings: 16), material: sunMat)
let armMesh = addMesh(box(1.35, 0.035, 0.035), material: armMat)
let planetMesh = addMesh(sphere(radius: 0.15, segments: 28, rings: 14), material: planetMat)
let moonArmMesh = addMesh(box(0.42, 0.025, 0.025), material: armMat)
let moonMesh = addMesh(sphere(radius: 0.065, segments: 20, rings: 10), material: moonMat)
let bobMesh = addMesh(sphere(radius: 0.085, segments: 24, rings: 12), material: bobMat)
let pointerMesh = addMesh(box(0.42, 0.025, 0.09), material: tickerMat)

// MARK: Nodes, camera, and lights.

let cameraEye: V3 = (2.9, 2.1, 3.6)
let cameraTarget: V3 = (0, 1.0, 0)
let spotPos: V3 = (2.1, 3.0, 1.7)
let spotTarget: V3 = (0, 1.1, 0)
let sunDirFrom: V3 = (-1.3, 2.4, 1.5)   // aimed at the origin

let nodes: [[String: Any]] = [
    ["name": "base", "mesh": baseMesh, "translation": [0, 0.06, 0]],                    // 0
    ["name": "pylon", "mesh": pylonMesh, "translation": [0, 0.67, 0]],                  // 1
    ["name": "hub", "translation": [0, 1.32, 0], "children": [3, 4]],                   // 2
    ["name": "sunBall", "mesh": sunMesh, "children": [10]],                             // 3
    ["name": "arm", "children": [5, 6]],                                                // 4  LINEAR rotation
    ["name": "armRod", "mesh": armMesh, "translation": [0.8, 0, 0]],                    // 5
    ["name": "planet", "mesh": planetMesh, "translation": [1.5, 0, 0],
     "children": [7]],                                                                  // 6
    ["name": "moonArm", "children": [8, 9]],                                            // 7  LINEAR rotation (faster)
    ["name": "moonRod", "mesh": moonArmMesh, "translation": [0.24, 0, 0]],              // 8
    ["name": "moon", "mesh": moonMesh, "translation": [0.46, 0, 0]],                    // 9
    ["name": "sunGlow", "extensions": ["KHR_lights_punctual": ["light": 0]]],           // 10
    ["name": "marker", "mesh": bobMesh, "translation": [0, 1.95, 0]],                   // 11  CUBICSPLINE translation
    ["name": "ticker", "translation": [0, 0.15, 0], "children": [13]],                  // 12  STEP rotation
    ["name": "pointer", "mesh": pointerMesh, "translation": [0.27, 0, 0]],              // 13
    ["name": "camera", "camera": 0,
     "translation": [cameraEye.x, cameraEye.y, cameraEye.z],
     "rotation": lookRotation(eye: cameraEye, target: cameraTarget)],                   // 14
    ["name": "keySpot", "translation": [spotPos.x, spotPos.y, spotPos.z],
     "rotation": lookRotation(eye: spotPos, target: spotTarget),
     "extensions": ["KHR_lights_punctual": ["light": 1]]],                              // 15
    ["name": "fill", "rotation": lookRotation(eye: sunDirFrom, target: (0, 0, 0)),
     "extensions": ["KHR_lights_punctual": ["light": 2]]],                              // 16
]

let lights: [[String: Any]] = [
    ["name": "sunGlow", "type": "point", "color": linear(1.0, 0.8, 0.55), "intensity": 25],
    ["name": "key", "type": "spot", "color": linear(1.0, 0.98, 0.94), "intensity": 120,
     "spot": ["innerConeAngle": 0.4, "outerConeAngle": 0.62]],
    ["name": "fill", "type": "directional", "color": linear(0.6, 0.68, 0.9), "intensity": 2],
]

let cameras: [[String: Any]] = [
    ["name": "main", "type": "perspective",
     "perspective": ["yfov": 0.62, "znear": 0.1, "zfar": 100]],
]

// MARK: The "spin" animation (8 s, wraps seamlessly).

let period: Float = 8

// The planet arm: one full turn, LINEAR quaternion keys every quarter turn (the
// spherical lerp between neighbors is exact for arcs under a half turn).
let armTimes = addTimes([0, 2, 4, 6, 8])
let armValues = addVec4s((0...4).map { yRotation(Float($0) / 4 * 2 * .pi) })

// The moon arm: three turns the other way, keys every quarter of its own cycle.
let moonTimes = addTimes((0...12).map { Float($0) / 12 * period })
let moonValues = addVec4s((0...12).map { yRotation(-Float($0) / 12 * 3 * 2 * .pi) })

// The marker: a cubic-spline bob between two heights, zero tangents at every
// keyframe so it eases at each extreme (and the wrap is seamless). CUBICSPLINE
// output groups in-tangent, value, out-tangent per keyframe.
let bobTimes = addTimes([0, 2, 4, 6, 8])
let bobHeights: [Float] = [1.95, 2.28, 1.95, 2.28, 1.95]
let bobValues = addVec3s(bobHeights.flatMap { y -> [[Float]] in
    [[0, 0, 0], [0, y, 0], [0, 0, 0]]
})

// The ticker: twelve 30-degree steps; the 13th key lands the full turn exactly
// at the period, so the wrap is seamless.
let tickerTimes = addTimes((0...12).map { Float($0) / 12 * period })
let tickerValues = addVec4s((0...12).map { yRotation(-Float($0) / 12 * 2 * .pi) })

let animations: [[String: Any]] = [[
    "name": "spin",
    "channels": [
        ["sampler": 0, "target": ["node": 4, "path": "rotation"]],
        ["sampler": 1, "target": ["node": 7, "path": "rotation"]],
        ["sampler": 2, "target": ["node": 11, "path": "translation"]],
        ["sampler": 3, "target": ["node": 12, "path": "rotation"]],
    ],
    "samplers": [
        ["input": armTimes, "output": armValues, "interpolation": "LINEAR"],
        ["input": moonTimes, "output": moonValues, "interpolation": "LINEAR"],
        ["input": bobTimes, "output": bobValues, "interpolation": "CUBICSPLINE"],
        ["input": tickerTimes, "output": tickerValues, "interpolation": "STEP"],
    ],
]]

let gltf: [String: Any] = [
    "asset": ["version": "2.0", "generator": "Ollin make-animated-scene.swift"],
    "extensionsUsed": ["KHR_lights_punctual"],
    "extensions": ["KHR_lights_punctual": ["lights": lights]],
    "scene": 0,
    "scenes": [["name": "Orrery", "nodes": [0, 1, 2, 11, 12, 14, 15, 16]]],
    "nodes": nodes,
    "meshes": meshes,
    "materials": materials,
    "cameras": cameras,
    "animations": animations,
    "accessors": accessors,
    "bufferViews": bufferViews,
    "buffers": [["uri": "data:application/octet-stream;base64,\(buffer.base64EncodedString())",
                 "byteLength": buffer.count]],
]

let json = try! JSONSerialization.data(withJSONObject: gltf,
                                       options: [.prettyPrinted, .sortedKeys])
try! json.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(json.count) bytes; \(buffer.count)-byte buffer, \(meshes.count) meshes, \(nodes.count) nodes, \(animations.count) animation)")
