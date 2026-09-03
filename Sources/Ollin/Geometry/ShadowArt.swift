import Foundation

/// A solid carved so that it throws the shadows it was asked for: one shape from
/// the front, another from the side, a third from above.
///
/// The construction is one line of reasoning. A lit point casts a shadow along the
/// light's direction, so a point can only be in the solid if it lands inside the
/// shadow in *every* direction it is lit from. Keep exactly those points and the
/// answer is the largest solid that could cast them, which is the visual hull.
///
/// ```swift
/// let art = shadowArt(fromFront: circle, fromSide: square, resolution: 64)
/// for center in art.boxes { drawBox(at: center, size: art.voxelSize) }
/// ```
///
/// **The shadows it really casts are never larger than the ones asked for, and can
/// be smaller.** The catch is that two views share an axis: the front and the side
/// are seen from either end of the same vertical, so a row that is empty in one
/// empties it in the other, and no solid can throw a shadow where nothing is lit.
/// A pair comes out exact when the two are solid in the same rows, which is why
/// the classic circle-and-square works and why a shape reaching further down than
/// its partner has its bottom cut off. Three silhouettes agree even less often: a
/// point of one shadow may have nothing behind it that survives the other two.
///
/// `shadow(from:)` hands back what the carved solid actually throws, which is the
/// honest thing to compare against.
public struct ShadowArt: Sendable {
    /// Which way the light travels. A shadow from the front is cast along z, from
    /// the side along x, and from above along y.
    public enum Side: Sendable, CaseIterable {
        case front, side, above
    }

    /// How many voxels along each edge.
    public let resolution: Int
    /// One flag per voxel, indexed `x + y * resolution + z * resolution * resolution`.
    public let occupied: [Bool]
    /// The cube the solid is carved out of.
    public let bounds: Box3

    /// How wide one voxel is.
    public var voxelSize: Double {
        bounds.size.x / Double(Swift.max(1, resolution))
    }

    /// Whether the voxel at these whole-number coordinates survived.
    public func isSolid(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        guard x >= 0, x < resolution, y >= 0, y < resolution, z >= 0, z < resolution else {
            return false
        }
        return occupied[x + y * resolution + z * resolution * resolution]
    }

    /// How many voxels survived.
    public var count: Int { occupied.lazy.filter { $0 }.count }

    /// The middle of every surviving voxel, in the bounds' own units.
    public var boxes: [Vector3] {
        var out: [Vector3] = []
        out.reserveCapacity(count)
        let step = voxelSize
        for z in 0 ..< resolution {
            for y in 0 ..< resolution {
                for x in 0 ..< resolution where isSolid(x, y, z) {
                    out.append(Vector3(bounds.min.x + (Double(x) + 0.5) * step,
                                       bounds.min.y + (Double(y) + 0.5) * step,
                                       bounds.min.z + (Double(z) + 0.5) * step))
                }
            }
        }
        return out
    }

    /// The shadow the carved solid really throws from one side, as a grid of flags
    /// `resolution` on a side, row-major from the top-left of that view.
    ///
    /// Compare it with the silhouette that was asked for. Where the two differ, the
    /// shadows could not all be cast by one solid, and this is the one that is
    /// true.
    public func shadow(from side: Side) -> [Bool] {
        var out = [Bool](repeating: false, count: resolution * resolution)
        for z in 0 ..< resolution {
            for y in 0 ..< resolution {
                for x in 0 ..< resolution where isSolid(x, y, z) {
                    switch side {
                    case .front: out[x + y * resolution] = true
                    case .side: out[z + y * resolution] = true
                    case .above: out[x + z * resolution] = true
                    }
                }
            }
        }
        return out
    }

    /// The carved solid as a surface, built by marching the occupancy field.
    ///
    /// The field is 1 inside a voxel and 0 outside, so the surface lands halfway
    /// between: a stepped skin over the voxels rather than a smooth guess at what
    /// they stand for.
    public var mesh: Mesh {
        let step = voxelSize
        return isosurface(at: 0.5, in: bounds, resolution: resolution) { point in
            let x = Int(((point.x - bounds.min.x) / step).rounded(.down))
            let y = Int(((point.y - bounds.min.y) / step).rounded(.down))
            let z = Int(((point.z - bounds.min.z) / step).rounded(.down))
            return isSolid(x, y, z) ? 1 : 0
        }
    }
}

/// Carve the largest solid that casts these shadows.
///
/// Each picture is read as a silhouette: **bright means solid** (a white shape on
/// black), and `threshold` is where the line falls. A side left out places no
/// constraint at all, so one picture alone gives a prism.
///
/// - Parameters:
///   - front: the shadow cast along z, seen looking at the xy face.
///   - side: the shadow cast along x, seen looking at the zy face.
///   - above: the shadow cast along y, seen looking at the xz face.
///   - resolution: voxels along each edge. The cost is the cube of it.
///   - threshold: how bright a pixel has to be to count as solid.
///   - inverted: read dark as solid instead.
public func shadowArt(fromFront front: Image? = nil,
                      fromSide side: Image? = nil,
                      fromAbove above: Image? = nil,
                      resolution: Int = 48,
                      threshold: Double = 0.5,
                      inverted: Bool = false,
                      in bounds: Box3? = nil) -> ShadowArt {
    let n = Swift.max(1, resolution)
    let box = bounds ?? Box3(min: Vector3(-1, -1, -1), max: Vector3(1, 1, 1))
    let frontMask = mask(front, resolution: n, threshold: threshold, inverted: inverted)
    let sideMask = mask(side, resolution: n, threshold: threshold, inverted: inverted)
    let aboveMask = mask(above, resolution: n, threshold: threshold, inverted: inverted)

    var occupied = [Bool](repeating: false, count: n * n * n)
    for z in 0 ..< n {
        for y in 0 ..< n {
            for x in 0 ..< n {
                // A point survives only where every light finds it inside the
                // shadow that light casts.
                if let frontMask, !frontMask[x + y * n] { continue }
                if let sideMask, !sideMask[z + y * n] { continue }
                if let aboveMask, !aboveMask[x + z * n] { continue }
                if frontMask == nil, sideMask == nil, aboveMask == nil { continue }
                occupied[x + y * n + z * n * n] = true
            }
        }
    }
    return ShadowArt(resolution: n, occupied: occupied, bounds: box)
}

/// A picture read as a grid of flags `resolution` on a side, or nil when there is
/// no picture (which is no constraint at all).
private func mask(_ picture: Image?, resolution: Int, threshold: Double,
                  inverted: Bool) -> [Bool]? {
    guard let picture, picture.width > 0, picture.height > 0 else { return nil }
    var out = [Bool](repeating: false, count: resolution * resolution)
    for row in 0 ..< resolution {
        for column in 0 ..< resolution {
            // Sample the middle of each cell, so a small picture stretches rather
            // than dropping detail off its right and bottom edges.
            let x = Int((Double(column) + 0.5) / Double(resolution) * Double(picture.width))
            let y = Int((Double(row) + 0.5) / Double(resolution) * Double(picture.height))
            let color = picture[Swift.min(x, picture.width - 1), Swift.min(y, picture.height - 1)]
            let level = color.luminance * color.alpha
            out[column + row * resolution] = inverted ? level < threshold : level >= threshold
        }
    }
    return out
}

public extension Sketch {
    /// Carve the solid that casts these shadows, using the sketch's canvas-free
    /// default bounds of a two-unit cube about the origin.
    func shadowArt(fromFront front: Image? = nil, fromSide side: Image? = nil,
                   fromAbove above: Image? = nil, resolution: Int = 48,
                   threshold: Double = 0.5, inverted: Bool = false) -> ShadowArt {
        Ollin.shadowArt(fromFront: front, fromSide: side, fromAbove: above,
                        resolution: resolution, threshold: threshold, inverted: inverted)
    }
}
