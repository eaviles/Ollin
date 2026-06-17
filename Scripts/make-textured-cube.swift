#!/usr/bin/env swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Generates an Ollin-original textured cube as a self-contained glTF 2.0 file
// (geometry + a procedural UV-grid texture, both embedded as data-URIs), used as the
// bundled demo asset for the 3D/LoadedMesh example. Both the geometry and the texture
// are authored here, so the asset carries no third-party license. Re-run to regenerate:
//
//     swift Scripts/make-textured-cube.swift Examples/3D/LoadedMesh/model.gltf

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "Examples/3D/LoadedMesh/model.gltf"

// MARK: Geometry — a unit cube, 4 verts per face with flat normals and per-face UVs.

struct Face { let normal: (Float, Float, Float); let verts: [(Float, Float, Float)] }
let h: Float = 0.5
let faces = [
    Face(normal: (1, 0, 0),  verts: [(h, -h, h), (h, -h, -h), (h, h, -h), (h, h, h)]),
    Face(normal: (-1, 0, 0), verts: [(-h, -h, -h), (-h, -h, h), (-h, h, h), (-h, h, -h)]),
    Face(normal: (0, 1, 0),  verts: [(-h, h, h), (h, h, h), (h, h, -h), (-h, h, -h)]),
    Face(normal: (0, -1, 0), verts: [(-h, -h, -h), (h, -h, -h), (h, -h, h), (-h, -h, h)]),
    Face(normal: (0, 0, 1),  verts: [(-h, -h, h), (h, -h, h), (h, h, h), (-h, h, h)]),
    Face(normal: (0, 0, -1), verts: [(h, -h, -h), (-h, -h, -h), (-h, h, -h), (h, h, -h)]),
]
let faceUV: [(Float, Float)] = [(0, 1), (1, 1), (1, 0), (0, 0)]

var positions = Data(), normals = Data(), uvs = Data(), indices = Data()
func putF(_ d: inout Data, _ f: Float) { withUnsafeBytes(of: f) { d.append(contentsOf: $0) } }
for (fi, face) in faces.enumerated() {
    for (vi, v) in face.verts.enumerated() {
        putF(&positions, v.0); putF(&positions, v.1); putF(&positions, v.2)
        putF(&normals, face.normal.0); putF(&normals, face.normal.1); putF(&normals, face.normal.2)
        putF(&uvs, faceUV[vi].0); putF(&uvs, faceUV[vi].1)
    }
    let base = UInt16(fi * 4)
    for i in [base, base + 1, base + 2, base, base + 2, base + 3] {
        withUnsafeBytes(of: i) { indices.append(contentsOf: $0) }
    }
}
// Pad each section to a 4-byte boundary (the index section follows the float ones).
var buffer = positions + normals + uvs + indices
let posLen = positions.count, normLen = normals.count, uvLen = uvs.count, idxLen = indices.count

// MARK: Texture — a procedural UV grid (hue by u, brightness checker, dark gridlines).

func uvGridPNG(_ n: Int) -> Data {
    let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8,
                        bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let cell = n / 8
    for y in 0..<n {
        for x in 0..<n {
            let onGrid = x % cell == 0 || y % cell == 0
            if onGrid {
                ctx.setFillColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1)
            } else {
                let checker = ((x / cell) + (y / cell)) % 2 == 0
                let hue = Double(x) / Double(n - 1)
                let (r, g, b) = hsb(hue, 0.7, checker ? 0.95 : 0.55)
                ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
            }
            ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
    let image = ctx.makeImage()!
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    return out as Data
}
func hsb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
    let i = Int(h * 6) % 6, f = h * 6 - Double(Int(h * 6))
    let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
    switch i {
    case 0: return (v, t, p); case 1: return (q, v, p); case 2: return (p, v, t)
    case 3: return (p, q, v); case 4: return (t, p, v); default: return (v, p, q)
    }
}
let png = uvGridPNG(256)

// MARK: glTF JSON.

let bufB64 = buffer.base64EncodedString()
let pngB64 = png.base64EncodedString()
let json = """
{
  "asset": {"version": "2.0", "generator": "Ollin make-textured-cube.swift"},
  "scene": 0,
  "scenes": [{"nodes": [0]}],
  "nodes": [{"mesh": 0}],
  "meshes": [{"primitives": [{
    "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
    "indices": 3, "mode": 4, "material": 0
  }]}],
  "materials": [{"name": "UVGrid", "pbrMetallicRoughness": {
    "baseColorFactor": [1, 1, 1, 1],
    "baseColorTexture": {"index": 0}
  }}],
  "textures": [{"source": 0}],
  "images": [{"uri": "data:image/png;base64,\(pngB64)"}],
  "accessors": [
    {"bufferView": 0, "componentType": 5126, "count": 24, "type": "VEC3"},
    {"bufferView": 1, "componentType": 5126, "count": 24, "type": "VEC3"},
    {"bufferView": 2, "componentType": 5126, "count": 24, "type": "VEC2"},
    {"bufferView": 3, "componentType": 5123, "count": 36, "type": "SCALAR"}
  ],
  "bufferViews": [
    {"buffer": 0, "byteOffset": 0, "byteLength": \(posLen)},
    {"buffer": 0, "byteOffset": \(posLen), "byteLength": \(normLen)},
    {"buffer": 0, "byteOffset": \(posLen + normLen), "byteLength": \(uvLen)},
    {"buffer": 0, "byteOffset": \(posLen + normLen + uvLen), "byteLength": \(idxLen)}
  ],
  "buffers": [{"uri": "data:application/octet-stream;base64,\(bufB64)", "byteLength": \(buffer.count)}]
}
"""
try! json.write(toFile: outPath, atomically: true, encoding: .utf8)
print("wrote \(outPath) (\(json.count) bytes; \(buffer.count)-byte buffer, \(png.count)-byte texture)")
