#!/usr/bin/env swift
import Foundation

// Generates an Ollin-original skinned *figure* as a self-contained glTF 2.0
// file: a sixteen-joint humanoid rig (hips, spine, chest, head, two arms with
// forearms and hands, two legs with shins and feet) wearing one skinned mesh of
// tapered tubes, plus a 2.4-second looping "wave" animation. Everything is
// authored here, so the asset carries no third-party license. It is the figure
// the 3D/Physics/Ragdoll example gives weight to. Re-run to regenerate:
//
//     swift Scripts/make-ragdoll-scene.swift Examples/3D/Physics/Ragdoll/figure.gltf

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "Examples/3D/Physics/Ragdoll/figure.gltf"

// MARK: Small vector helpers (Float triples, enough for authoring).

typealias V3 = (x: Float, y: Float, z: Float)
func add(_ a: V3, _ b: V3) -> V3 { (a.x + b.x, a.y + b.y, a.z + b.z) }
func sub(_ a: V3, _ b: V3) -> V3 { (a.x - b.x, a.y - b.y, a.z - b.z) }
func mul(_ a: V3, _ s: Float) -> V3 { (a.x * s, a.y * s, a.z * s) }
func cross(_ a: V3, _ b: V3) -> V3 {
    (a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}
func length(_ a: V3) -> Float { (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot() }
func norm(_ a: V3) -> V3 {
    let l = length(a)
    return l > 0 ? (a.x / l, a.y / l, a.z / l) : (0, 1, 0)
}
func lerp(_ a: V3, _ b: V3, _ t: Float) -> V3 {
    (a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
}

/// The quaternion (x, y, z, w) for a rotation of `angle` radians about `axis`.
func axisRotation(_ axis: V3, _ angle: Float) -> [Float] {
    let a = norm(axis), s = sin(angle / 2)
    return [a.x * s, a.y * s, a.z * s, cos(angle / 2)]
}

/// Multiply two (x, y, z, w) quaternions.
func mulQuat(_ a: [Float], _ b: [Float]) -> [Float] {
    [a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
     a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
     a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
     a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2]]
}

/// sRGB display color -> the linear color glTF stores.
func linear(_ r: Double, _ g: Double, _ b: Double) -> [Double] {
    func lin(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return [(lin(r) * 10000).rounded() / 10000, (lin(g) * 10000).rounded() / 10000,
            (lin(b) * 10000).rounded() / 10000]
}

func smoothstep(_ t: Float) -> Float {
    let u = max(0, min(1, t))
    return u * u * (3 - 2 * u)
}

// MARK: Buffer assembly.

var buffer = Data()
var bufferViews: [[String: Any]] = []
var accessors: [[String: Any]] = []

func align4() { while buffer.count % 4 != 0 { buffer.append(0) } }
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
        acc["min"] = lo
        acc["max"] = hi
    }
    accessors.append(acc)
    return accessors.count - 1
}

func addIndexAccessor(_ idx: [UInt16]) -> Int {
    let view = putShorts(idx)
    accessors.append(["bufferView": view, "componentType": 5123, "count": idx.count,
                      "type": "SCALAR"])
    return accessors.count - 1
}

func addTimes(_ t: [Float]) -> Int {
    let view = putFloats(t)
    accessors.append(["bufferView": view, "componentType": 5126, "count": t.count,
                      "type": "SCALAR", "min": [t.min()!], "max": [t.max()!]])
    return accessors.count - 1
}

func addVec4s(_ v: [[Float]]) -> Int {
    let view = putFloats(v.flatMap { $0 })
    accessors.append(["bufferView": view, "componentType": 5126, "count": v.count,
                      "type": "VEC4"])
    return accessors.count - 1
}

// MARK: The skeleton.

struct Joint {
    var name: String
    var world: V3
    var parent: Int
}

let joints: [Joint] = [
    Joint(name: "hips", world: (0, 0.95, 0), parent: -1),
    Joint(name: "spine", world: (0, 1.16, 0), parent: 0),
    Joint(name: "chest", world: (0, 1.38, 0), parent: 1),
    Joint(name: "head", world: (0, 1.56, 0), parent: 2),
    Joint(name: "armL", world: (0.15, 1.48, 0), parent: 2),
    Joint(name: "forearmL", world: (0.42, 1.48, 0), parent: 4),
    Joint(name: "handL", world: (0.66, 1.48, 0), parent: 5),
    Joint(name: "armR", world: (-0.15, 1.48, 0), parent: 2),
    Joint(name: "forearmR", world: (-0.42, 1.48, 0), parent: 7),
    Joint(name: "handR", world: (-0.66, 1.48, 0), parent: 8),
    Joint(name: "legL", world: (0.10, 0.90, 0), parent: 0),
    Joint(name: "shinL", world: (0.10, 0.48, 0), parent: 10),
    Joint(name: "footL", world: (0.10, 0.07, 0), parent: 11),
    Joint(name: "legR", world: (-0.10, 0.90, 0), parent: 0),
    Joint(name: "shinR", world: (-0.10, 0.48, 0), parent: 13),
    Joint(name: "footR", world: (-0.10, 0.07, 0), parent: 14),
]
func jointIndex(_ name: String) -> Int { joints.firstIndex { $0.name == name }! }

// MARK: The skin: tubes along the bones, blobs at the ends.

var positions: [Float] = []
var normals: [Float] = []
var jointBytes: [UInt8] = []
var weightFloats: [Float] = []
var indices: [UInt16] = []

/// Write one vertex, weighted to at most two joints.
func vertex(_ p: V3, _ n: V3, _ a: Int, _ wa: Float, _ b: Int = 0, _ wb: Float = 0) {
    positions.append(contentsOf: [p.x, p.y, p.z])
    normals.append(contentsOf: [n.x, n.y, n.z])
    jointBytes.append(contentsOf: [UInt8(a), UInt8(b), 0, 0])
    let total = wa + wb
    weightFloats.append(contentsOf: [wa / total, wb / total, 0, 0])
}

/// A tapered tube from joint `a` to joint `b`, its flesh owned by `a` and
/// softened into `a`'s parent at the near end and into `b` at the far end, the
/// way a real rig blends across a joint.
func addTube(_ a: Int, _ b: Int, radiusA: Float, radiusB: Float,
             sides: Int = 12, rings: Int = 8) {
    let p0 = joints[a].world, p1 = joints[b].world
    let axis = norm(sub(p1, p0))
    let helper: V3 = abs(axis.y) < 0.9 ? (0, 1, 0) : (1, 0, 0)
    let right = norm(cross(helper, axis))
    let up = cross(axis, right)
    let parent = joints[a].parent

    let base = UInt16(positions.count / 3)
    for ring in 0...rings {
        let u = Float(ring) / Float(rings)
        let center = lerp(p0, p1, u)
        let radius = radiusA + (radiusB - radiusA) * u
        // Rigid to `a` through the middle, blending only near the two joints.
        var (jointA, weightA) = (a, Float(1))
        var (jointB, weightB) = (a, Float(0))
        if u < 0.18, parent >= 0 {
            weightB = 0.45 * (1 - smoothstep(u / 0.18))
            jointB = parent
            weightA = 1 - weightB
        } else if u > 0.82 {
            weightB = 0.45 * smoothstep((u - 0.82) / 0.18)
            jointB = b
            weightA = 1 - weightB
        }
        for side in 0..<sides {
            let angle = Float(side) / Float(sides) * 2 * .pi
            let radial = add(mul(right, cos(angle)), mul(up, sin(angle)))
            vertex(add(center, mul(radial, radius)), radial,
                   jointA, weightA, jointB, weightB)
        }
    }
    for ring in 0..<rings {
        for side in 0..<sides {
            let next = (side + 1) % sides
            let r0 = base + UInt16(ring * sides), r1 = base + UInt16((ring + 1) * sides)
            indices.append(contentsOf: [r0 + UInt16(side), r1 + UInt16(side),
                                        r1 + UInt16(next)])
            indices.append(contentsOf: [r0 + UInt16(side), r1 + UInt16(next),
                                        r0 + UInt16(next)])
        }
    }
}

/// A ball of flesh at a joint (the head), rigid to it.
func addBall(_ joint: Int, offset: V3, radius: Float, squash: V3 = (1, 1, 1),
             rows: Int = 12, columns: Int = 16) {
    let center = add(joints[joint].world, offset)
    let base = UInt16(positions.count / 3)
    for row in 0...rows {
        let phi = Float(row) / Float(rows) * .pi
        for column in 0...columns {
            let theta = Float(column) / Float(columns) * 2 * .pi
            let n: V3 = (sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
            let p: V3 = (center.x + n.x * radius * squash.x,
                         center.y + n.y * radius * squash.y,
                         center.z + n.z * radius * squash.z)
            vertex(p, n, joint, 1)
        }
    }
    let stride = UInt16(columns + 1)
    for row in 0..<UInt16(rows) {
        for column in 0..<UInt16(columns) {
            let a = base + row * stride + column
            let b = a + stride
            indices.append(contentsOf: [a, b, b + 1, a, b + 1, a + 1])
        }
    }
}

// The torso, from the hips up through the neck.
addTube(jointIndex("hips"), jointIndex("spine"), radiusA: 0.145, radiusB: 0.140)
addTube(jointIndex("spine"), jointIndex("chest"), radiusA: 0.140, radiusB: 0.150)
addTube(jointIndex("chest"), jointIndex("head"), radiusA: 0.150, radiusB: 0.062)
// The pelvis: two short stubs out to the hip joints, meeting the thighs at the
// radius they start with so the seam does not step.
addTube(jointIndex("hips"), jointIndex("legL"), radiusA: 0.118, radiusB: 0.095, rings: 3)
addTube(jointIndex("hips"), jointIndex("legR"), radiusA: 0.118, radiusB: 0.095, rings: 3)
// Arms and legs.
for side in ["L", "R"] {
    addTube(jointIndex("arm\(side)"), jointIndex("forearm\(side)"),
            radiusA: 0.072, radiusB: 0.052)
    addTube(jointIndex("forearm\(side)"), jointIndex("hand\(side)"),
            radiusA: 0.052, radiusB: 0.040)
    addTube(jointIndex("leg\(side)"), jointIndex("shin\(side)"),
            radiusA: 0.095, radiusB: 0.065)
    addTube(jointIndex("shin\(side)"), jointIndex("foot\(side)"),
            radiusA: 0.065, radiusB: 0.048)
}
// The head, the hands, and the feet: the ends of the chain, which have no bone
// below them and so carry a shape of their own.
addBall(jointIndex("head"), offset: (0, 0.105, 0), radius: 0.115,
        squash: (0.92, 1.05, 1.0))
// The seat, which fills the space the two thigh stubs leave between them.
addBall(jointIndex("hips"), offset: (0, -0.035, 0), radius: 0.155,
        squash: (1.0, 0.62, 0.86), rows: 10, columns: 14)
addBall(jointIndex("handL"), offset: (0.055, 0, 0), radius: 0.055,
        squash: (1.25, 0.8, 1.0), rows: 8, columns: 10)
addBall(jointIndex("handR"), offset: (-0.055, 0, 0), radius: 0.055,
        squash: (1.25, 0.8, 1.0), rows: 8, columns: 10)
addBall(jointIndex("footL"), offset: (0, -0.005, 0.055), radius: 0.070,
        squash: (0.75, 0.5, 1.7), rows: 8, columns: 10)
addBall(jointIndex("footR"), offset: (0, -0.005, 0.055), radius: 0.070,
        squash: (0.75, 0.5, 1.7), rows: 8, columns: 10)

// MARK: Accessors.

let positionAccessor = addVec3Accessor(positions, withBounds: true)
let normalAccessor = addVec3Accessor(normals, withBounds: false)
let jointView = putBytes(jointBytes)
accessors.append(["bufferView": jointView, "componentType": 5121,
                  "count": jointBytes.count / 4, "type": "VEC4"])
let jointAccessor = accessors.count - 1
let weightView = putFloats(weightFloats)
accessors.append(["bufferView": weightView, "componentType": 5126,
                  "count": weightFloats.count / 4, "type": "VEC4"])
let weightAccessor = accessors.count - 1
let indexAccessor = addIndexAccessor(indices)

// Inverse bind matrices: every joint is a pure translation in the bind pose, so
// each one is the translation back to the origin, column-major.
var inverseBinds: [Float] = []
for joint in joints {
    inverseBinds.append(contentsOf: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0,
                                     -joint.world.x, -joint.world.y, -joint.world.z, 1])
}
let inverseBindView = putFloats(inverseBinds)
accessors.append(["bufferView": inverseBindView, "componentType": 5126,
                  "count": joints.count, "type": "MAT4"])
let inverseBindAccessor = accessors.count - 1

// MARK: The animation: a 2.4-second wave that wraps.

let period: Float = 2.4
let keyCount = 25
let times = (0..<keyCount).map { Float($0) / Float(keyCount - 1) * period }

/// One rotation channel, sampled from a closure over the loop phase.
struct Channel {
    var joint: Int
    var values: [[Float]]
}
var channels: [Channel] = []

func animate(_ name: String, _ rotation: (Float) -> [Float]) {
    channels.append(Channel(joint: jointIndex(name),
                            values: times.map { rotation($0 / period * 2 * .pi) }))
}

// A slow sway through the spine, and a right arm that lifts and waves.
animate("spine") { phase in
    mulQuat(axisRotation((0, 1, 0), 0.10 * sin(phase)),
            axisRotation((0, 0, 1), 0.05 * sin(2 * phase)))
}
animate("chest") { phase in axisRotation((1, 0, 0), -0.06 + 0.05 * sin(phase)) }
animate("head") { phase in axisRotation((0, 1, 0), 0.16 * sin(phase)) }
// The right arm points along -x, so a negative turn about +z lifts it.
animate("armR") { _ in axisRotation((0, 0, 1), -1.15) }
animate("forearmR") { phase in
    mulQuat(axisRotation((0, 0, 1), -0.55),
            axisRotation((1, 0, 0), 0.45 * sin(3 * phase)))
}
// The left arm rests down at its side.
animate("armL") { _ in axisRotation((0, 0, 1), -1.35) }
animate("forearmL") { _ in axisRotation((0, 0, 1), -0.25) }
// A little weight shift in the legs.
animate("legL") { phase in axisRotation((1, 0, 0), 0.10 * sin(phase)) }
animate("legR") { phase in axisRotation((1, 0, 0), -0.10 * sin(phase)) }

let timeAccessor = addTimes(times)
var samplers: [[String: Any]] = []
var animationChannels: [[String: Any]] = []
for channel in channels {
    samplers.append(["input": timeAccessor, "output": addVec4s(channel.values),
                     "interpolation": "LINEAR"])
    animationChannels.append(["sampler": samplers.count - 1,
                              "target": ["node": channel.joint, "path": "rotation"]])
}

// MARK: Nodes: the joint tree, then the skinned mesh beside it.

var nodes: [[String: Any]] = joints.enumerated().map { index, joint in
    let parentWorld = joint.parent >= 0 ? joints[joint.parent].world : (0, 0, 0)
    let local = sub(joint.world, parentWorld)
    var node: [String: Any] = ["name": joint.name,
                               "translation": [local.x, local.y, local.z]]
    let children = joints.enumerated().filter { $0.element.parent == index }.map(\.offset)
    if !children.isEmpty { node["children"] = children }
    return node
}
nodes.append(["name": "figure", "mesh": 0, "skin": 0])
let meshNode = nodes.count - 1

let gltf: [String: Any] = [
    "asset": ["version": "2.0", "generator": "Ollin make-ragdoll-scene"],
    "scene": 0,
    "scenes": [["name": "figure", "nodes": [0, meshNode]]],
    "nodes": nodes,
    "skins": [["name": "rig", "joints": Array(0..<joints.count),
               "skeleton": 0, "inverseBindMatrices": inverseBindAccessor]],
    "meshes": [["name": "body", "primitives": [[
        "attributes": ["POSITION": positionAccessor, "NORMAL": normalAccessor,
                       "JOINTS_0": jointAccessor, "WEIGHTS_0": weightAccessor],
        "indices": indexAccessor, "material": 0,
    ]]]],
    "materials": [["name": "skin", "pbrMetallicRoughness": [
        "baseColorFactor": linear(0.86, 0.72, 0.58) + [1.0],
        "metallicFactor": 0.0, "roughnessFactor": 0.75,
    ]]],
    "animations": [["name": "wave", "samplers": samplers,
                    "channels": animationChannels]],
    "bufferViews": bufferViews,
    "accessors": accessors,
    "buffers": [["byteLength": buffer.count,
                 "uri": "data:application/octet-stream;base64,"
                     + buffer.base64EncodedString()]],
]

let json = try JSONSerialization.data(withJSONObject: gltf,
                                      options: [.prettyPrinted, .sortedKeys])
try json.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath): \(joints.count) joints, \(positions.count / 3) vertices, "
    + "\(indices.count / 3) triangles, \(json.count) bytes")
