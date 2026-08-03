#!/usr/bin/env swift
import Foundation

// Generates an Ollin-original *deforming* sample scene as a self-contained glTF
// 2.0 file: a small tidepool. Three kelp strands sway on skins (a four-joint
// chain each, per-vertex JOINTS_0/WEIGHTS_0 blends, LINEAR rotation keyframes
// with a phase offset per strand and per joint, so a wave travels up each
// blade), and an anemone dome pulses on two morph targets (a "puff" that
// swells it and a "ripple" that scallops its rim, the ripple stored as a
// *sparse* accessor since most of its displacements are zero) driven by a
// morph-weights track. One 6-second animation named "sway" carries every
// channel and wraps seamlessly. Plus an authored camera, a warm point light,
// a key spot, and a cool directional fill. The bundled demo asset for the
// 3D/SkinnedScene example; everything is authored here, so the asset carries
// no third-party license. Re-run to regenerate:
//
//     swift Scripts/make-skinned-scene.swift Examples/3D/Geometry/SkinnedScene/scene.gltf

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "Examples/3D/Geometry/SkinnedScene/scene.gltf"

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

/// The quaternion for a rotation of `angle` radians about a horizontal `axis`.
func axisRotation(_ axis: V3, _ angle: Float) -> [Float] {
    let a = norm(axis), s = sin(angle / 2)
    return [a.x * s, a.y * s, a.z * s, cos(angle / 2)]
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

// MARK: Buffer assembly.

var buffer = Data()
var bufferViews: [[String: Any]] = []
var accessors: [[String: Any]] = []
var meshes: [[String: Any]] = []
var materials: [[String: Any]] = []
var skins: [[String: Any]] = []

func align4() {
    while buffer.count % 4 != 0 { buffer.append(0) }
}
func putFloats(_ f: [Float]) -> Int {
    align4()
    let offset = buffer.count
    f.withUnsafeBufferPointer { buffer.append(Data(buffer: $0)) }
    bufferViews.append(["buffer": 0, "byteOffset": offset, "byteLength": f.count * 4])
    return bufferViews.count - 1
}
func putShorts(_ v: [UInt16]) -> Int {
    align4()
    let offset = buffer.count
    v.withUnsafeBufferPointer { buffer.append(Data(buffer: $0)) }
    bufferViews.append(["buffer": 0, "byteOffset": offset, "byteLength": v.count * 2])
    return bufferViews.count - 1
}
func putBytes(_ v: [UInt8]) -> Int {
    align4()
    let offset = buffer.count
    buffer.append(contentsOf: v)
    bufferViews.append(["buffer": 0, "byteOffset": offset, "byteLength": v.count])
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

/// A float VEC3 accessor over flat xyz triples, with min/max (required on
/// POSITION-shaped data, harmless elsewhere).
func addVec3Accessor(_ flat: [Float], withBounds: Bool) -> Int {
    let view = putFloats(flat)
    var acc: [String: Any] = ["bufferView": view, "componentType": 5126,
                              "count": flat.count / 3, "type": "VEC3"]
    if withBounds {
        var lo: [Float] = [.infinity, .infinity, .infinity]
        var hi: [Float] = [-.infinity, -.infinity, -.infinity]
        for i in 0..<(flat.count / 3) {
            for a in 0..<3 {
                lo[a] = min(lo[a], flat[i * 3 + a])
                hi[a] = max(hi[a], flat[i * 3 + a])
            }
        }
        acc["min"] = lo; acc["max"] = hi
    }
    accessors.append(acc)
    return accessors.count - 1
}

func addIndexAccessor(_ idx: [UInt16]) -> Int {
    let view = putShorts(idx)
    accessors.append(["bufferView": view, "componentType": 5123,
                      "count": idx.count, "type": "SCALAR"])
    return accessors.count - 1
}

/// A SCALAR float accessor of keyframe times (the spec requires min/max on
/// animation inputs).
func addTimes(_ t: [Float]) -> Int {
    let view = putFloats(t)
    accessors.append(["bufferView": view, "componentType": 5126, "count": t.count,
                      "type": "SCALAR", "min": [t.min()!], "max": [t.max()!]])
    return accessors.count - 1
}

/// A VEC4 float accessor of animation output values (flat xyzw quadruples).
func addVec4s(_ v: [[Float]]) -> Int {
    let view = putFloats(v.flatMap { $0 })
    accessors.append(["bufferView": view, "componentType": 5126, "count": v.count, "type": "VEC4"])
    return accessors.count - 1
}

/// A SCALAR float accessor of morph-weight animation output (k weights per key).
func addScalars(_ v: [Float]) -> Int {
    let view = putFloats(v)
    accessors.append(["bufferView": view, "componentType": 5126, "count": v.count, "type": "SCALAR"])
    return accessors.count - 1
}

// MARK: The kelp: a tapered tube skinned to a four-joint chain.

/// Joint heights along the chain, *chain-local* (excluding the strand root's
/// own translation): j0 just above the sand, then 0.4 apart. The inverse bind
/// matrices are the matching pure translations down, shared by every strand.
let jointHeights: [Float] = [0.02, 0.42, 0.82, 1.22]

/// Blend a vertex at height `y` between the two joints bracketing it,
/// smoothstepped so a bend spreads organically instead of creasing.
func jointBlend(_ y: Float) -> (joints: [UInt8], weights: [Float]) {
    if y <= jointHeights[0] { return ([0, 0, 0, 0], [1, 0, 0, 0]) }
    if y >= jointHeights[3] { return ([3, 0, 0, 0], [1, 0, 0, 0]) }
    for k in 0..<3 where y < jointHeights[k + 1] {
        let u = (y - jointHeights[k]) / (jointHeights[k + 1] - jointHeights[k])
        let t = u * u * (3 - 2 * u)
        return ([UInt8(k), UInt8(k + 1), 0, 0], [1 - t, t, 0, 0])
    }
    return ([3, 0, 0, 0], [1, 0, 0, 0])
}

/// One kelp blade: a tapered tube from the sand to `height`, plus a tip vertex,
/// authored at the origin (the skin places it at the strand's spot).
func addKelpMesh(height: Float, baseRadius: Float, material: Int) -> Int {
    var positions: [Float] = [], normals: [Float] = []
    var jointBytes: [UInt8] = [], weightFloats: [Float] = []
    var indices: [UInt16] = []
    let sides = 10, rings = 16
    let tipRadius: Float = 0.016
    let slope = (baseRadius - tipRadius) / height
    for r in 0...rings {
        let f = Float(r) / Float(rings)
        let y = 0.02 + f * (height - 0.02)
        let radius = baseRadius + (tipRadius - baseRadius) * f
        let blend = jointBlend(y)
        for s in 0...sides {
            let a = Float(s) / Float(sides) * 2 * .pi
            let c = cos(a), sn = sin(a)
            positions += [radius * c, y, radius * sn]
            let n = norm((c, slope, sn))
            normals += [n.x, n.y, n.z]
            jointBytes += blend.joints
            weightFloats += blend.weights
        }
    }
    let stride = UInt16(sides + 1)
    for r in 0..<rings {
        for s in 0..<sides {
            let a = UInt16(r) * stride + UInt16(s)
            let b = a + stride
            indices += [a, b, a + 1, a + 1, b, b + 1]
        }
    }
    // The tip: one vertex riding the last joint, fanned to the top ring.
    let tip = UInt16(positions.count / 3)
    positions += [0, height + 0.05, 0]
    normals += [0, 1, 0]
    let tipBlend = jointBlend(height + 0.05)
    jointBytes += tipBlend.joints
    weightFloats += tipBlend.weights
    let topStart = UInt16(rings) * stride
    for s in 0..<sides {
        indices += [topStart + UInt16(s), tip, topStart + UInt16(s) + 1]
    }

    let posAcc = addVec3Accessor(positions, withBounds: true)
    let normAcc = addVec3Accessor(normals, withBounds: false)
    let jointView = putBytes(jointBytes)
    accessors.append(["bufferView": jointView, "componentType": 5121,
                      "count": jointBytes.count / 4, "type": "VEC4"])
    let jointAcc = accessors.count - 1
    let weightView = putFloats(weightFloats)
    accessors.append(["bufferView": weightView, "componentType": 5126,
                      "count": weightFloats.count / 4, "type": "VEC4"])
    let weightAcc = accessors.count - 1
    let idxAcc = addIndexAccessor(indices)
    meshes.append(["primitives": [[
        "attributes": ["POSITION": posAcc, "NORMAL": normAcc,
                       "JOINTS_0": jointAcc, "WEIGHTS_0": weightAcc],
        "indices": idxAcc, "mode": 4, "material": material,
    ]]])
    return meshes.count - 1
}

// MARK: The anemone: a squashed dome with two morph targets.

/// The dome with target 0 ("puff": swells out and settles down) stored dense
/// and target 1 ("ripple": scallops the rim) stored as a sparse accessor,
/// since only the equatorial band moves.
func addAnemoneMesh(material: Int) -> Int {
    var positions: [Float] = [], normals: [Float] = []
    var indices: [UInt16] = []
    let segments = 24, rings = 12
    let radius: Float = 0.26, squash: Float = 0.72, centerY: Float = 0.19
    for r in 0...rings {
        let phi = Float(r) / Float(rings) * .pi
        for s in 0...segments {
            let theta = Float(s) / Float(segments) * 2 * .pi
            let n: V3 = (sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
            positions += [radius * n.x, squash * radius * n.y + centerY, radius * n.z]
            let sn = norm((n.x / 1, n.y / squash, n.z / 1))   // squashed-sphere normal
            normals += [sn.x, sn.y, sn.z]
        }
    }
    let stride = UInt16(segments + 1)
    for r in 0..<rings {
        for s in 0..<segments {
            let a = UInt16(r) * stride + UInt16(s)
            let b = a + stride
            indices += [a, a + 1, b + 1, a, b + 1, b]
        }
    }
    let count = positions.count / 3

    // Target 0, "puff": swell outward in xz, settle slightly in y.
    var puff: [Float] = []
    for i in 0..<count {
        let x = positions[i * 3], y = positions[i * 3 + 1], z = positions[i * 3 + 2]
        puff += [x * 0.30, -(y - centerY) * 0.20, z * 0.30]
    }

    // Target 1, "ripple": scallop the equatorial band radially; most vertices
    // don't move, so only the moved ones are stored (a sparse accessor).
    var rippleIdx: [UInt16] = [], rippleVals: [Float] = []
    var rippleLo: [Float] = [.infinity, .infinity, .infinity]
    var rippleHi: [Float] = [-.infinity, -.infinity, -.infinity]
    for i in 0..<count {
        let x = positions[i * 3], y = positions[i * 3 + 1], z = positions[i * 3 + 2]
        let horiz = (x * x + z * z).squareRoot()
        guard horiz > 1e-4 else { continue }
        let envelope = max(0, 1 - abs(y - centerY) / (squash * radius * 0.8))
        guard envelope > 0.05 else { continue }
        let angle = atan2(z, x)
        let amount = sin(6 * angle) * 0.05 * envelope
        guard abs(amount) > 1e-5 else { continue }
        rippleIdx.append(UInt16(i))
        rippleVals += [amount * x / horiz, 0, amount * z / horiz]
    }
    for i in 0..<rippleIdx.count {
        for a in 0..<3 {
            rippleLo[a] = min(rippleLo[a], rippleVals[i * 3 + a])
            rippleHi[a] = max(rippleHi[a], rippleVals[i * 3 + a])
        }
    }
    // Zero rides in the sparse gaps, so the bounds must include it.
    for a in 0..<3 { rippleLo[a] = min(rippleLo[a], 0); rippleHi[a] = max(rippleHi[a], 0) }

    let posAcc = addVec3Accessor(positions, withBounds: true)
    let normAcc = addVec3Accessor(normals, withBounds: false)
    let idxAcc = addIndexAccessor(indices)
    let puffAcc = addVec3Accessor(puff, withBounds: true)
    let rippleIdxView = putShorts(rippleIdx)
    let rippleValView = putFloats(rippleVals)
    accessors.append(["componentType": 5126, "count": count, "type": "VEC3",
                      "min": rippleLo, "max": rippleHi,
                      "sparse": ["count": rippleIdx.count,
                                 "indices": ["bufferView": rippleIdxView, "componentType": 5123],
                                 "values": ["bufferView": rippleValView]]])
    let rippleAcc = accessors.count - 1
    meshes.append(["primitives": [[
        "attributes": ["POSITION": posAcc, "NORMAL": normAcc],
        "indices": idxAcc, "mode": 4, "material": material,
        "targets": [["POSITION": puffAcc], ["POSITION": rippleAcc]],
    ]],
    "weights": [0.0, 0.0]])
    return meshes.count - 1
}

// MARK: Plain props.

func addSphereMesh(radius: Float, squashY: Float, material: Int) -> Int {
    var positions: [Float] = [], normals: [Float] = []
    var indices: [UInt16] = []
    let segments = 20, rings = 10
    for r in 0...rings {
        let phi = Float(r) / Float(rings) * .pi
        for s in 0...segments {
            let theta = Float(s) / Float(segments) * 2 * .pi
            let n: V3 = (sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
            positions += [radius * n.x, squashY * radius * n.y, radius * n.z]
            let sn = norm((n.x, n.y / squashY, n.z))
            normals += [sn.x, sn.y, sn.z]
        }
    }
    let stride = UInt16(segments + 1)
    for r in 0..<rings {
        for s in 0..<segments {
            let a = UInt16(r) * stride + UInt16(s)
            let b = a + stride
            indices += [a, a + 1, b + 1, a, b + 1, b]
        }
    }
    let posAcc = addVec3Accessor(positions, withBounds: true)
    let normAcc = addVec3Accessor(normals, withBounds: false)
    let idxAcc = addIndexAccessor(indices)
    meshes.append(["primitives": [[
        "attributes": ["POSITION": posAcc, "NORMAL": normAcc],
        "indices": idxAcc, "mode": 4, "material": material,
    ]]])
    return meshes.count - 1
}

func addDiskMesh(radius: Float, height: Float, material: Int) -> Int {
    var positions: [Float] = [], normals: [Float] = []
    var indices: [UInt16] = []
    let segments = 40
    let y = height / 2
    // Side.
    for s in 0...segments {
        let a = Float(s) / Float(segments) * 2 * .pi
        let c = cos(a), sn = sin(a)
        positions += [radius * c, -y, radius * sn, radius * c, y, radius * sn]
        normals += [c, 0, sn, c, 0, sn]
    }
    for s in 0..<segments {
        let a = UInt16(s * 2), b = a + 1, c = a + 2, d = a + 3
        indices += [a, b, d, a, d, c]
    }
    // Top cap.
    let capCenter = UInt16(positions.count / 3)
    positions += [0, y, 0]; normals += [0, 1, 0]
    let rimStart = UInt16(positions.count / 3)
    for s in 0...segments {
        let a = Float(s) / Float(segments) * 2 * .pi
        positions += [radius * cos(a), y, radius * sin(a)]
        normals += [0, 1, 0]
    }
    for s in 0..<segments {
        indices += [capCenter, rimStart + UInt16(s), rimStart + UInt16(s) + 1]
    }
    let posAcc = addVec3Accessor(positions, withBounds: true)
    let normAcc = addVec3Accessor(normals, withBounds: false)
    let idxAcc = addIndexAccessor(indices)
    meshes.append(["primitives": [[
        "attributes": ["POSITION": posAcc, "NORMAL": normAcc],
        "indices": idxAcc, "mode": 4, "material": material,
    ]]])
    return meshes.count - 1
}

// MARK: Materials and meshes.

let sandMat = addMaterial(name: "Sand", srgb: (0.74, 0.66, 0.5), roughness: 0.9)
let rockMat = addMaterial(name: "Rock", srgb: (0.44, 0.44, 0.48), roughness: 0.8)
let anemoneMat = addMaterial(name: "Anemone", srgb: (0.85, 0.48, 0.62), roughness: 0.35)
let kelpMats = [addMaterial(name: "Kelp1", srgb: (0.2, 0.5, 0.3), roughness: 0.55),
                addMaterial(name: "Kelp2", srgb: (0.16, 0.44, 0.37), roughness: 0.55),
                addMaterial(name: "Kelp3", srgb: (0.28, 0.54, 0.24), roughness: 0.55)]

let sandMesh = addDiskMesh(radius: 1.15, height: 0.12, material: sandMat)
let rockMesh = addSphereMesh(radius: 0.16, squashY: 0.62, material: rockMat)
let anemoneMesh = addAnemoneMesh(material: anemoneMat)
let kelpHeights: [Float] = [1.32, 1.46, 1.12]
let kelpMeshes = (0..<3).map {
    addKelpMesh(height: kelpHeights[$0], baseRadius: [0.055, 0.05, 0.06][$0],
                material: kelpMats[$0])
}

// The inverse bind matrices: pure translations down the chain, shared by every
// strand's skin (column-major MAT4s).
let ibmFlat: [Float] = jointHeights.flatMap { h -> [Float] in
    [1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, -h, 0, 1]
}
let ibmView = putFloats(ibmFlat)
accessors.append(["bufferView": ibmView, "componentType": 5126, "count": 4, "type": "MAT4"])
let ibmAcc = accessors.count - 1

// MARK: Nodes, skins, camera, and lights.

let cameraEye: V3 = (2.35, 1.65, 2.9)
let cameraTarget: V3 = (0, 0.62, 0)
let spotPos: V3 = (1.9, 2.6, 1.4)
let sunDirFrom: V3 = (-1.2, 2.2, 1.6)   // aimed at the origin

let kelpSpots: [V3] = [(-0.5, 0.1, 0.18), (0.05, 0.1, -0.38), (0.6, 0.1, -0.1)]

var nodes: [[String: Any]] = [
    ["name": "sand", "mesh": sandMesh, "translation": [0, 0.06, 0]],                    // 0
    ["name": "rock", "mesh": rockMesh, "translation": [-0.62, 0.14, -0.42]],            // 1
    ["name": "anemone", "mesh": anemoneMesh, "translation": [0.52, 0.12, 0.38]],        // 2  weights track
    ["name": "camera", "camera": 0,
     "translation": [cameraEye.x, cameraEye.y, cameraEye.z],
     "rotation": lookRotation(eye: cameraEye, target: cameraTarget)],                   // 3
    ["name": "keySpot", "translation": [spotPos.x, spotPos.y, spotPos.z],
     "rotation": lookRotation(eye: spotPos, target: cameraTarget),
     "extensions": ["KHR_lights_punctual": ["light": 0]]],                              // 4
    ["name": "fill", "rotation": lookRotation(eye: sunDirFrom, target: (0, 0, 0)),
     "extensions": ["KHR_lights_punctual": ["light": 1]]],                              // 5
    ["name": "glow", "translation": [0.52, 0.75, 0.38],
     "extensions": ["KHR_lights_punctual": ["light": 2]]],                              // 6
]

/// Per strand: a root at its spot, the four-joint chain under it, and the
/// skinned blade node beside the chain (the blade's own placement comes from
/// the joints, which ride the root, so moving the root moves the strand).
var jointIndices: [[Int]] = []   // per strand, the four joint node indices
for s in 0..<3 {
    let rootIndex = nodes.count
    let j0 = rootIndex + 1
    jointIndices.append([j0, j0 + 1, j0 + 2, j0 + 3])
    let spot = kelpSpots[s]
    nodes.append(["name": "kelp\(s + 1)", "translation": [spot.x, spot.y, spot.z],
                  "children": [j0, j0 + 4]])
    nodes.append(["name": "kelp\(s + 1)-j0", "translation": [0, jointHeights[0], 0],
                  "children": [j0 + 1]])
    for k in 1...3 {
        var joint: [String: Any] = ["name": "kelp\(s + 1)-j\(k)",
                                    "translation": [0, jointHeights[k] - jointHeights[k - 1], 0]]
        if k < 3 { joint["children"] = [j0 + k + 1] }
        nodes.append(joint)
    }
    skins.append(["name": "kelp\(s + 1)-skin", "joints": jointIndices[s],
                  "inverseBindMatrices": ibmAcc])
    nodes.append(["name": "kelp\(s + 1)-blade", "mesh": kelpMeshes[s], "skin": s])
}

let lights: [[String: Any]] = [
    ["name": "key", "type": "spot", "color": linear(0.85, 0.95, 1.0), "intensity": 110,
     "spot": ["innerConeAngle": 0.35, "outerConeAngle": 0.6]],
    ["name": "fill", "type": "directional", "color": linear(0.45, 0.62, 0.78), "intensity": 2],
    ["name": "glow", "type": "point", "color": linear(1.0, 0.75, 0.7), "intensity": 10],
]

let cameras: [[String: Any]] = [
    ["name": "main", "type": "perspective",
     "perspective": ["yfov": 0.6, "znear": 0.1, "zfar": 100]],
]

// MARK: The "sway" animation (6 s, wraps seamlessly).

let period: Float = 6

// Each joint sways about a fixed horizontal axis, the phase advancing up the
// chain so a wave travels up the blade; per-strand phase and axis offsets keep
// the three from moving in lockstep. 13 LINEAR keys per joint; the last key
// repeats the first (sin wraps exactly over the period).
let swayTimes = addTimes((0...12).map { Float($0) / 12 * period })
let strandPhases: [Float] = [0, 2.1, 4.2]
let strandAxes: [V3] = [(cos(Float(0.3)), 0, sin(Float(0.3))),
                        (cos(Float(1.8)), 0, sin(Float(1.8))),
                        (cos(Float(3.5)), 0, sin(Float(3.5)))]
let jointAmplitudes: [Float] = [0.05, 0.12, 0.18, 0.22]

var channels: [[String: Any]] = []
var samplers: [[String: Any]] = []
for s in 0..<3 {
    for k in 0..<4 {
        let values = addVec4s((0...12).map { i -> [Float] in
            let t = Float(i) / 12 * period
            let angle = jointAmplitudes[k]
                * sin(2 * .pi * t / period + strandPhases[s] + Float(k) * 0.9)
            return axisRotation(strandAxes[s], angle)
        })
        samplers.append(["input": swayTimes, "output": values, "interpolation": "LINEAR"])
        channels.append(["sampler": samplers.count - 1,
                         "target": ["node": jointIndices[s][k], "path": "rotation"]])
    }
}

// The anemone: both targets' weights in one channel, two scalars per keyframe.
// The puff pulses twice per loop, the ripple wobbles four times; both cosines
// land back at zero at the period, so the wrap is seamless.
let weightTimes = addTimes((0...24).map { Float($0) / 24 * period })
let weightValues = addScalars((0...24).flatMap { i -> [Float] in
    let t = Float(i) / 24 * period
    let puff = 0.5 - 0.5 * cos(2 * .pi * t / (period / 2))
    let ripple = 0.5 - 0.5 * cos(2 * .pi * t / (period / 4))
    return [puff, ripple]
})
samplers.append(["input": weightTimes, "output": weightValues, "interpolation": "LINEAR"])
channels.append(["sampler": samplers.count - 1, "target": ["node": 2, "path": "weights"]])

let animations: [[String: Any]] = [[
    "name": "sway", "channels": channels, "samplers": samplers,
]]

let gltf: [String: Any] = [
    "asset": ["version": "2.0", "generator": "Ollin make-skinned-scene.swift"],
    "extensionsUsed": ["KHR_lights_punctual"],
    "extensions": ["KHR_lights_punctual": ["lights": lights]],
    "scene": 0,
    "scenes": [["name": "Tidepool",
                "nodes": [0, 1, 2, 3, 4, 5, 6, 7, 13, 19]]],
    "nodes": nodes,
    "meshes": meshes,
    "materials": materials,
    "skins": skins,
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
print("wrote \(outPath) (\(json.count) bytes; \(buffer.count)-byte buffer, \(meshes.count) meshes, \(nodes.count) nodes, \(skins.count) skins, \(animations.count) animation)")
