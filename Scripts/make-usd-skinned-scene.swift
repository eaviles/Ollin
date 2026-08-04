#!/usr/bin/env swift
import Foundation

// Generates an Ollin-original *deforming* USD scene as a self-contained text
// file: a pond where a sea serpent sways on a five-joint UsdSkel chain and a
// lotus breathes on blend shapes, the bundled demo asset for the
// 3D/USDSkinnedScene example. Everything is authored here, so the asset
// carries no third-party license.
//
// The rig exercises the whole UsdSkel envelope the loader reads, and the
// timeline loops seamlessly over 8 seconds (timeCodesPerSecond 24, samples
// 0...192, every sampled channel's last key equal to its first):
//
//   serpent   a tapered tube skinned to a five-joint chain (Spine/S1/.../Head)
//             with two blended influences per point (elementSize 2), points
//             authored in the prim's local frame mapped by a
//             geomBindTransform, joints swaying on a traveling wave of
//             quaternion keys (a SkelAnimation bound on the Skeleton)
//   lotus     eight petals opening and closing on two blend shapes: "bloom"
//             (dense offsets with normal offsets) and "curl" (a sparse
//             pointIndices shape bending just the tips), their weights
//             driven by a SkelAnimation bound by an inherited
//             skel:animationSource with no skeleton at all
//   pond      a plain still-water disc (and the lotus heart), read by the
//             platform importer like any unskinned mesh
//
// A camera and two UsdLux lights (a warm distant key, a cool sphere fill)
// complete the stage; diffuse colors are authored as display values, light
// colors are linear per UsdLux. Re-run to regenerate:
//
//     swift Scripts/make-usd-skinned-scene.swift Examples/3D/Geometry/USDSkinnedScene/stage.usda

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "Examples/3D/Geometry/USDSkinnedScene/stage.usda"

// MARK: Small helpers.

typealias V3 = (x: Double, y: Double, z: Double)

func fmt(_ v: Double) -> String {
    let s = String(format: "%.5f", v)
    var t = s
    while t.hasSuffix("0") { t.removeLast() }
    if t.hasSuffix(".") { t += "0" }
    return t
}

func triples(_ pts: [V3]) -> String {
    pts.map { "(\(fmt($0.x)), \(fmt($0.y)), \(fmt($0.z)))" }.joined(separator: ", ")
}

/// A quaternion (w, x, y, z) for a rotation of `radians` about `axis`.
func quat(_ radians: Double, axis: V3) -> [Double] {
    let l = (axis.x * axis.x + axis.y * axis.y + axis.z * axis.z).squareRoot()
    let s = sin(radians / 2)
    return [cos(radians / 2), axis.x / l * s, axis.y / l * s, axis.z / l * s]
}

/// Hamilton product a·b of two (w, x, y, z) quaternions.
func mul(_ a: [Double], _ b: [Double]) -> [Double] {
    [a[0] * b[0] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
     a[0] * b[1] + a[1] * b[0] + a[2] * b[3] - a[3] * b[2],
     a[0] * b[2] - a[1] * b[3] + a[2] * b[0] + a[3] * b[1],
     a[0] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[0]]
}

func quatString(_ q: [Double]) -> String {
    "(\(fmt(q[0])), \(fmt(q[1])), \(fmt(q[2])), \(fmt(q[3])))"
}

/// A `time: value` sample block body at one line per sample.
func samples(_ pairs: [(Int, String)], indent: Int) -> String {
    let pad = String(repeating: "    ", count: indent)
    return pairs.map { "\(pad)    \($0.0): \($0.1)" }.joined(separator: ",\n")
}

// MARK: The serpent: a tapered tube around a straight vertical rest chain.

let lap = 192
let jointCount = 5
let jointSpacing = 0.55
let serpentPos: V3 = (-0.72, 0.02, 0.3)

// Rings of 12 points from the waterline to the head, radius tapering, plus a
// nose tip. Heights run 0...2.3, one ring every 0.115.
let ringSegments = 12
let ringCount = 21
let serpentTop = 2.3
var serpentPoints: [V3] = []
var serpentCounts: [Int] = []
var serpentIndices: [Int] = []
var serpentInfluences: [(j0: Int, w0: Double, j1: Int, w1: Double)] = []

/// The two-joint blend for a height on the rest chain.
func influences(at h: Double) -> (Int, Double, Int, Double) {
    let t = h / jointSpacing
    let k = min(Int(t), jointCount - 2)
    let f = min(max(t - Double(k), 0), 1)
    return (k, 1 - f, k + 1, f)
}

for ring in 0..<ringCount {
    let v = Double(ring) / Double(ringCount - 1)
    let h = v * serpentTop
    // A gentle belly, a taper to the neck, and a swell for the head.
    let head = 0.55 * exp(-pow((v - 0.88) / 0.08, 2))
    let radius = 0.16 * (1 - v * 0.72) * (0.85 + 0.3 * sin(v * .pi * 0.9)) * (1 + head)
    for s in 0..<ringSegments {
        let a = Double(s) / Double(ringSegments) * 2 * .pi
        serpentPoints.append((cos(a) * radius, h, sin(a) * radius))
        let (j0, w0, j1, w1) = influences(at: h)
        serpentInfluences.append((j0, w0, j1, w1))
    }
}
for ring in 0..<(ringCount - 1) {
    for s in 0..<ringSegments {
        let t = (s + 1) % ringSegments
        let a = ring * ringSegments + s, b = ring * ringSegments + t
        let c = (ring + 1) * ringSegments + t, d = (ring + 1) * ringSegments + s
        serpentCounts.append(4)
        // Wound so the computed smooth normals face outward.
        serpentIndices += [a, d, c, b]
    }
}
// The nose: a tip vertex closing the last ring, fully on the head joint.
let tipIndex = serpentPoints.count
serpentPoints.append((0, serpentTop + 0.14, 0))
serpentInfluences.append((jointCount - 1, 1, 0, 0))
for s in 0..<ringSegments {
    let t = (s + 1) % ringSegments
    serpentCounts.append(3)
    serpentIndices += [(ringCount - 1) * ringSegments + t, (ringCount - 1) * ringSegments + s, tipIndex]
}

let jointNames = ["Spine", "Spine/S1", "Spine/S1/S2", "Spine/S1/S2/S3", "Spine/S1/S2/S3/Head"]

/// Rest transforms are local: the root at the skeleton origin, each joint one
/// spacing up its parent. Bind transforms are world space, so they carry the
/// serpent's pond position.
func identityRow(_ t: V3) -> String {
    "((1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (\(fmt(t.x)), \(fmt(t.y)), \(fmt(t.z)), 1))"
}
let restRows = (0..<jointCount).map { k in
    identityRow((0, k == 0 ? 0 : jointSpacing, 0))
}.joined(separator: ", ")
let bindRows = (0..<jointCount).map { k in
    identityRow((serpentPos.x, serpentPos.y + Double(k) * jointSpacing, serpentPos.z))
}.joined(separator: ", ")

/// The sway: a traveling wave of z-bends with a slighter x-tilt, phase
/// stepping down the chain, two full cycles per lap so it closes.
var rotationSamples: [(Int, String)] = []
for step in stride(from: 0, through: lap, by: 8) {
    let phase = Double(step) / Double(lap) * 2 * .pi
    let perJoint = (0..<jointCount).map { k -> String in
        let amp = (k == 0 ? 5.0 : 11.0) * .pi / 180
        let bend = amp * sin(2 * phase - Double(k) * 0.9)
        let tilt = 4.5 * .pi / 180 * sin(phase - Double(k) * 0.6 + .pi / 3)
        return quatString(mul(quat(bend, axis: (0, 0, 1)), quat(tilt, axis: (1, 0, 0))))
    }.joined(separator: ", ")
    rotationSamples.append((step, "[\(perJoint)]"))
}
let translationRow = "[" + (0..<jointCount).map { k in
    "(0, \(fmt(k == 0 ? 0 : jointSpacing)), 0)"
}.joined(separator: ", ") + "]"
let scaleRow = "[" + Array(repeating: "(1, 1, 1)", count: jointCount).joined(separator: ", ") + "]"

let serpentJointIndices = serpentInfluences.flatMap { [$0.j0, $0.j1] }
    .map(String.init).joined(separator: ", ")
let serpentJointWeights = serpentInfluences.flatMap { [$0.w0, $0.w1] }
    .map(fmt).joined(separator: ", ")

// MARK: The lotus: eight petal blades plus two blend shapes.

let lotusPos: V3 = (0.78, 0.06, -0.24)
let petals = 8
var lotusPoints: [V3] = []
var lotusCounts: [Int] = []
var lotusIndices: [Int] = []
var bloomOffsets: [V3] = []      // dense: one offset per point
var bloomNormals: [V3] = []
var curlTips: [Int] = []         // sparse: the tip points only
var curlOffsets: [V3] = []

for p in 0..<petals {
    let a = Double(p) / Double(petals) * 2 * .pi
    let dir: V3 = (cos(a), 0, sin(a))
    let side: V3 = (-sin(a), 0, cos(a))
    let base = lotusPoints.count
    // A flat diamond blade: base, left, tip, right, resting nearly open.
    lotusPoints.append((dir.x * 0.10, 0.02, dir.z * 0.10))
    lotusPoints.append((dir.x * 0.30 + side.x * 0.11, 0.06, dir.z * 0.30 + side.z * 0.11))
    lotusPoints.append((dir.x * 0.52, 0.10, dir.z * 0.52))
    lotusPoints.append((dir.x * 0.30 - side.x * 0.11, 0.06, dir.z * 0.30 - side.z * 0.11))
    lotusCounts.append(4)
    lotusIndices += [base, base + 1, base + 2, base + 3]
    // "bloom" folds the petal up and inward (weight 1 = closed bud): sides
    // rise, the tip lifts high and pulls toward the axis.
    bloomOffsets.append((0, 0.01, 0))
    bloomOffsets.append((-dir.x * 0.12 + -side.x * 0.06, 0.16, -dir.z * 0.12 - side.z * 0.06))
    bloomOffsets.append((-dir.x * 0.34, 0.34, -dir.z * 0.34))
    bloomOffsets.append((-dir.x * 0.12 + side.x * 0.06, 0.16, -dir.z * 0.12 + side.z * 0.06))
    bloomNormals.append((0, 0, 0))
    bloomNormals.append((dir.x * 0.3, -0.1, dir.z * 0.3))
    bloomNormals.append((dir.x * 0.6, -0.2, dir.z * 0.6))
    bloomNormals.append((dir.x * 0.3, -0.1, dir.z * 0.3))
    // "curl" flicks just the tip outward and down, the sparse form.
    curlTips.append(base + 2)
    curlOffsets.append((dir.x * 0.10, -0.05, dir.z * 0.10))
}

/// The bloom weight breathes closed and open once per lap; the curl flicks
/// twice, out of phase, so the two shapes never move in lockstep.
var weightSamples: [(Int, String)] = []
for step in stride(from: 0, through: lap, by: 8) {
    let phase = Double(step) / Double(lap) * 2 * .pi
    let bloom = 0.5 - 0.5 * cos(phase)          // 0 open, 1 closed bud
    let curl = max(0, 0.6 * sin(2 * phase + .pi / 5))
    weightSamples.append((step, "[\(fmt(bloom)), \(fmt(curl))]"))
}

// MARK: The pond and the lotus heart (plain unskinned meshes).

func discPrim(_ name: String, radius: Double, height: Double, segments: Int,
              translate: V3, material: String) -> String {
    var pts: [V3] = []
    var counts: [Int] = []
    var idx: [Int] = []
    for s in 0..<segments {
        let a = Double(s) / Double(segments) * 2 * .pi
        pts.append((cos(a) * radius, 0, sin(a) * radius))
        pts.append((cos(a) * radius, height, sin(a) * radius))
    }
    for s in 0..<segments {
        let t = (s + 1) % segments
        counts.append(4)
        // Wound outward (the platform importer's crease normals follow the
        // winding too).
        idx += [s * 2, s * 2 + 1, t * 2 + 1, t * 2]
    }
    let topCenter = pts.count
    pts.append((0, height, 0))
    for s in 0..<segments {
        let t = (s + 1) % segments
        counts.append(3)
        idx += [topCenter, t * 2 + 1, s * 2 + 1]
    }
    return """
        def Mesh "\(name)" (
            prepend apiSchemas = ["MaterialBindingAPI"]
        )
        {
            double3 xformOp:translate = (\(fmt(translate.x)), \(fmt(translate.y)), \(fmt(translate.z)))
            uniform token[] xformOpOrder = ["xformOp:translate"]
            uniform token subdivisionScheme = "none"
            point3f[] points = [\(triples(pts))]
            int[] faceVertexCounts = [\(counts.map(String.init).joined(separator: ", "))]
            int[] faceVertexIndices = [\(idx.map(String.init).joined(separator: ", "))]
            rel material:binding = </Pond/Materials/\(material)>
        }
    """
}

/// A designed display (sRGB) component re-encoded to the linear value a
/// preview surface authors; readers re-encode it back, so the designed look
/// holds.
func linear(_ x: Double) -> Double {
    x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
}

func materialPrim(_ name: String, color: (Double, Double, Double), roughness: Double,
                  metallic: Double = 0) -> String {
    """
            def Material "\(name)"
            {
                token outputs:surface.connect = </Pond/Materials/\(name)/pbr.outputs:surface>

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

// MARK: The stage.

let usda = """
#usda 1.0
(
    defaultPrim = "Pond"
    metersPerUnit = 1
    upAxis = "Y"
    startTimeCode = 0
    endTimeCode = \(lap)
    timeCodesPerSecond = 24
)

def Xform "Pond"
{
\(discPrim("water", radius: 2.6, height: 0.05, segments: 48, translate: (0, 0, 0), material: "water"))

\(discPrim("lilyPad", radius: 0.42, height: 0.015, segments: 24, translate: (lotusPos.x - 0.06, 0.052, lotusPos.z + 0.08), material: "pad"))

\(discPrim("lotusHeart", radius: 0.09, height: 0.09, segments: 12, translate: lotusPos, material: "gold"))

    def SkelRoot "Serpent" (
        prepend apiSchemas = ["SkelBindingAPI"]
    )
    {
        double3 xformOp:translate = (\(fmt(serpentPos.x)), \(fmt(serpentPos.y)), \(fmt(serpentPos.z)))
        uniform token[] xformOpOrder = ["xformOp:translate"]

        def Skeleton "SerpentSkel" (
            prepend apiSchemas = ["SkelBindingAPI"]
        )
        {
            uniform token[] joints = [\(jointNames.map { "\"\($0)\"" }.joined(separator: ", "))]
            uniform matrix4d[] bindTransforms = [\(bindRows)]
            uniform matrix4d[] restTransforms = [\(restRows)]
            rel skel:animationSource = </Pond/Serpent/SerpentSkel/SerpentAnim>

            def SkelAnimation "SerpentAnim"
            {
                uniform token[] joints = [\(jointNames.map { "\"\($0)\"" }.joined(separator: ", "))]
                float3[] translations.timeSamples = {
                    0: \(translationRow),
                    \(lap): \(translationRow),
                }
                quatf[] rotations.timeSamples = {
\(samples(rotationSamples, indent: 4))
                }
                half3[] scales.timeSamples = {
                    0: \(scaleRow),
                    \(lap): \(scaleRow),
                }
            }
        }

        def Mesh "SerpentBody" (
            prepend apiSchemas = ["SkelBindingAPI", "MaterialBindingAPI"]
        )
        {
            uniform token subdivisionScheme = "none"
            point3f[] points = [\(triples(serpentPoints))]
            int[] faceVertexCounts = [\(serpentCounts.map(String.init).joined(separator: ", "))]
            int[] faceVertexIndices = [\(serpentIndices.map(String.init).joined(separator: ", "))]
            rel skel:skeleton = </Pond/Serpent/SerpentSkel>
            matrix4d primvars:skel:geomBindTransform = \(identityRow(serpentPos))
            int[] primvars:skel:jointIndices = [\(serpentJointIndices)] (
                elementSize = 2
                interpolation = "vertex"
            )
            float[] primvars:skel:jointWeights = [\(serpentJointWeights)] (
                elementSize = 2
                interpolation = "vertex"
            )
            rel material:binding = </Pond/Materials/scales>
        }
    }

    def SkelRoot "Lotus" (
        prepend apiSchemas = ["SkelBindingAPI"]
    )
    {
        double3 xformOp:translate = (\(fmt(lotusPos.x)), \(fmt(lotusPos.y)), \(fmt(lotusPos.z)))
        uniform token[] xformOpOrder = ["xformOp:translate"]
        rel skel:animationSource = </Pond/Lotus/LotusAnim>

        def SkelAnimation "LotusAnim"
        {
            uniform token[] blendShapes = ["bloom", "curl"]
            float[] blendShapeWeights.timeSamples = {
\(samples(weightSamples, indent: 3))
            }
        }

        def Mesh "LotusPetals" (
            prepend apiSchemas = ["SkelBindingAPI", "MaterialBindingAPI"]
        )
        {
            uniform token subdivisionScheme = "none"
            point3f[] points = [\(triples(lotusPoints))]
            int[] faceVertexCounts = [\(lotusCounts.map(String.init).joined(separator: ", "))]
            int[] faceVertexIndices = [\(lotusIndices.map(String.init).joined(separator: ", "))]
            uniform token[] skel:blendShapes = ["bloom", "curl"]
            rel skel:blendShapeTargets = [</Pond/Lotus/LotusPetals/bloom>, </Pond/Lotus/LotusPetals/curl>]
            rel material:binding = </Pond/Materials/petal>

            def BlendShape "bloom"
            {
                uniform vector3f[] offsets = [\(triples(bloomOffsets))]
                uniform vector3f[] normalOffsets = [\(triples(bloomNormals))]
            }

            def BlendShape "curl"
            {
                uniform vector3f[] offsets = [\(triples(curlOffsets))]
                uniform int[] pointIndices = [\(curlTips.map(String.init).joined(separator: ", "))]
            }
        }
    }

    def Camera "view"
    {
        double3 xformOp:translate = (0, 2.1, 6.6)
        float3 xformOp:rotateXYZ = (-12, 0, 0)
        uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:rotateXYZ"]
        float focalLength = 24
        float horizontalAperture = 20.955
        float verticalAperture = 15.2908
        float2 clippingRange = (0.1, 100)
    }

    def Scope "Lights"
    {
        def DistantLight "key"
        {
            float3 xformOp:rotateXYZ = (-38, 32, 0)
            uniform token[] xformOpOrder = ["xformOp:rotateXYZ"]
            color3f inputs:color = (0.9, 0.78, 0.6)
            float inputs:intensity = 3000
            float inputs:angle = 0.53
        }

        def SphereLight "fill"
        {
            double3 xformOp:translate = (-2.4, 2.4, 2.8)
            uniform token[] xformOpOrder = ["xformOp:translate"]
            color3f inputs:color = (0.13, 0.2, 0.35)
            float inputs:intensity = 10
            float inputs:radius = 0.3
        }
    }

    def Scope "Materials"
    {
\(materialPrim("water", color: (0.1, 0.2, 0.26), roughness: 0.18, metallic: 0.1))

\(materialPrim("scales", color: (0.22, 0.55, 0.46), roughness: 0.42, metallic: 0.25))

\(materialPrim("petal", color: (0.93, 0.56, 0.62), roughness: 0.55))

\(materialPrim("pad", color: (0.2, 0.42, 0.24), roughness: 0.6))

\(materialPrim("gold", color: (0.85, 0.68, 0.28), roughness: 0.35, metallic: 0.6))
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
