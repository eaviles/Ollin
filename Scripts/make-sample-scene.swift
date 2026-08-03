#!/usr/bin/env swift
import Foundation

// Generates an Ollin-original sample *scene* as a self-contained glTF 2.0 file:
// a small studio stage (floor, a pedestal carrying a torus sculpture as its child
// node, an orb, and a floor lamp whose warm point light is a child of the lamp
// group), plus an authored camera, a key spot, and a cool directional fill via the
// punctual-lights extension. The bundled demo asset for the 3D/LoadedScene example;
// everything is authored here, so the asset carries no third-party license.
// Re-run to regenerate:
//
//     swift Scripts/make-sample-scene.swift Examples/3D/Geometry/LoadedScene/scene.gltf

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "Examples/3D/Geometry/LoadedScene/scene.gltf"

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
    // Column-major rotation matrix [right, trueUp, back] -> quaternion.
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

/// A torus around the y axis, centered at the origin, smooth normals.
func torus(radius: Float, tube: Float, segments: Int, rings: Int) -> Geometry {
    var g = Geometry()
    var grid: [[UInt16]] = []
    for r in 0...rings {
        let a = Float(r) / Float(rings) * 2 * .pi
        var row: [UInt16] = []
        for s in 0...segments {
            let b = Float(s) / Float(segments) * 2 * .pi
            let cx = cos(b), cz = sin(b)
            let n: V3 = (cos(a) * cx, sin(a), cos(a) * cz)
            let p: V3 = ((radius + tube * cos(a)) * cx, tube * sin(a),
                         (radius + tube * cos(a)) * cz)
            row.append(g.vertex(p, n))
        }
        grid.append(row)
    }
    for r in 0..<rings {
        for s in 0..<segments {
            g.quad(grid[r][s], grid[r + 1][s], grid[r + 1][s + 1], grid[r][s + 1])
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

let floorMat = addMaterial(name: "Floor", srgb: (0.23, 0.23, 0.26), roughness: 0.95)
let pedestalMat = addMaterial(name: "Pedestal", srgb: (0.76, 0.72, 0.65))
let sculptureMat = addMaterial(name: "Sculpture", srgb: (0.87, 0.63, 0.21),
                               metallic: 1, roughness: 0.35)
let orbMat = addMaterial(name: "Orb", srgb: (0.22, 0.55, 0.55), roughness: 0.4)
let postMat = addMaterial(name: "LampPost", srgb: (0.16, 0.16, 0.18), roughness: 0.6)
let shadeMat = addMaterial(name: "LampShade", srgb: (0.85, 0.42, 0.3), roughness: 0.8)

let floorMesh = addMesh(box(6, 0.1, 6), material: floorMat)
let pedestalMesh = addMesh(box(0.8, 1.0, 0.8), material: pedestalMat)
let sculptureMesh = addMesh(torus(radius: 0.34, tube: 0.13, segments: 48, rings: 24),
                            material: sculptureMat)
let orbMesh = addMesh(sphere(radius: 0.22, segments: 32, rings: 16), material: orbMat)
let postMesh = addMesh(cylinder(rBottom: 0.05, rTop: 0.035, height: 1.5, segments: 24),
                       material: postMat)
let shadeMesh = addMesh(cylinder(rBottom: 0.16, rTop: 0.24, height: 0.28, segments: 24),
                        material: shadeMat)

// MARK: Nodes, camera, and lights.

let cameraEye: V3 = (2.6, 1.9, 3.3)
let cameraTarget: V3 = (0, 0.85, 0)
let spotPos: V3 = (1.9, 2.7, 1.6)
let spotTarget: V3 = (0, 1.2, 0)
let sunDirFrom: V3 = (-1.2, 2.6, 1.4)   // aimed at the origin

// A standing ring: the torus is authored flat (around y), so tip it up 90 deg
// about x. sin/cos of 45 deg give the half-angle quaternion.
let tipUp: [Float] = [0.7071068, 0, 0, 0.7071068]

let nodes: [[String: Any]] = [
    ["name": "floor", "mesh": floorMesh, "translation": [0, -0.05, 0]],                 // 0
    ["name": "pedestal", "mesh": pedestalMesh, "translation": [0, 0.5, 0],
     "children": [2]],                                                                  // 1
    ["name": "sculpture", "mesh": sculptureMesh, "translation": [0, 0.98, 0],
     "rotation": tipUp],                                                                // 2
    ["name": "orb", "mesh": orbMesh, "translation": [1.35, 0.22, 0.7]],                 // 3
    ["name": "lamp", "translation": [-1.45, 0, -0.55], "children": [5, 6, 7]],          // 4
    ["name": "lampPost", "mesh": postMesh, "translation": [0, 0.75, 0]],                // 5
    ["name": "lampShade", "mesh": shadeMesh, "translation": [0, 1.55, 0]],              // 6
    ["name": "lampLight", "translation": [0, 1.45, 0],
     "extensions": ["KHR_lights_punctual": ["light": 0]]],                              // 7
    ["name": "camera", "camera": 0,
     "translation": [cameraEye.x, cameraEye.y, cameraEye.z],
     "rotation": lookRotation(eye: cameraEye, target: cameraTarget)],                   // 8
    ["name": "keySpot", "translation": [spotPos.x, spotPos.y, spotPos.z],
     "rotation": lookRotation(eye: spotPos, target: spotTarget),
     "extensions": ["KHR_lights_punctual": ["light": 1]]],                              // 9
    ["name": "sun", "rotation": lookRotation(eye: sunDirFrom, target: (0, 0, 0)),
     "extensions": ["KHR_lights_punctual": ["light": 2]]],                              // 10
]

let lights: [[String: Any]] = [
    ["name": "lampGlow", "type": "point", "color": linear(1.0, 0.78, 0.5), "intensity": 30],
    ["name": "key", "type": "spot", "color": linear(1.0, 0.98, 0.94), "intensity": 120,
     "spot": ["innerConeAngle": 0.35, "outerConeAngle": 0.55]],
    ["name": "fill", "type": "directional", "color": linear(0.62, 0.7, 0.9), "intensity": 2],
]

let cameras: [[String: Any]] = [
    ["name": "main", "type": "perspective",
     "perspective": ["yfov": 0.68, "znear": 0.1, "zfar": 100]],
]

let gltf: [String: Any] = [
    "asset": ["version": "2.0", "generator": "Ollin make-sample-scene.swift"],
    "extensionsUsed": ["KHR_lights_punctual"],
    "extensions": ["KHR_lights_punctual": ["lights": lights]],
    "scene": 0,
    "scenes": [["name": "Stage", "nodes": [0, 1, 3, 4, 8, 9, 10]]],
    "nodes": nodes,
    "meshes": meshes,
    "materials": materials,
    "cameras": cameras,
    "accessors": accessors,
    "bufferViews": bufferViews,
    "buffers": [["uri": "data:application/octet-stream;base64,\(buffer.base64EncodedString())",
                 "byteLength": buffer.count]],
]

let json = try! JSONSerialization.data(withJSONObject: gltf,
                                       options: [.prettyPrinted, .sortedKeys])
try! json.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(json.count) bytes; \(buffer.count)-byte buffer, \(meshes.count) meshes, \(nodes.count) nodes)")
