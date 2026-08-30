import Foundation
import simd

/// Fuses a stream of point clouds, each a single moment seen from one camera pose,
/// into one cloud of the whole scene. Feed it a depth feed's per-frame cloud together
/// with that frame's camera→world transform and sweep the camera around: the room
/// builds up as a single cloud you can orbit and keep.
///
/// A live depth feed only ever sees the slice of the world in front of the lens, and
/// drawn alone each frame replaces the last. The missing piece is the camera's 6DoF
/// **pose**, where it was when it took the frame. A depth source that reports one
/// (the iPhone capture app's `latestPose`, a tethered depth device's pose) lets every
/// frame be placed in the same fixed world space, so the slices stack into a whole.
///
/// ```swift
/// var world = WorldCloud(voxelSize: 0.02)        // fuse at 2 cm
/// // each new frame, in draw():
/// if let frame = device.latestFrame, let pose = device.latestPose {
///     world.add(frame.pointCloud(...), transformedBy: pose)
/// }
/// drawPointCloud(world.cloud)                     // the accumulated room
/// ```
///
/// Fusion is by a **voxel grid**: space is divided into cubes `voxelSize` on a side,
/// and the cloud keeps the most recent point seen in each cube. So re-observing a
/// surface refreshes it in place rather than piling up duplicates, and the cloud's
/// size is bounded by the scene's surface area, not the number of frames, so a sweep
/// can run indefinitely. A smaller `voxelSize` keeps more detail and more points;
/// a larger one is coarser and lighter.
public struct WorldCloud {

    /// The fused cloud, in the depth feed's world space (meters). Pass it straight
    /// to `drawPointCloud`.
    public private(set) var cloud = PointCloud()

    /// The cube edge length (world units, meters for a depth feed) the scene is
    /// fused at: one kept point per occupied cube.
    public var voxelSize: Double

    /// The fix `add(_:correcting:)` has built up between the pose a depth source
    /// reports and the space this cloud is fused in: `placed = correction * reported`.
    ///
    /// It stays the identity until a frame is lined up, and it holds the whole drift
    /// found so far. Apply it to anything else the same source reports in the same
    /// space (the camera's own position, a room mesh, a hit test) so that it lands
    /// where the fused cloud does.
    public internal(set) var correction: simd_float4x4 = matrix_identity_float4x4

    /// Maps an occupied voxel to its point's index in `cloud.points`, so a repeat
    /// observation overwrites in place instead of appending.
    private var occupied: [Voxel: Int] = [:]

    /// One surface normal per fused point, fitted on demand rather than up front:
    /// only the points a fit actually matches ever need one.
    private var normals: [Vector3] = []

    /// How many neighbors each normal was fitted through. Zero means never fitted,
    /// and a thin count is refitted later, once the neighborhood has filled in.
    private var normalEvidence: [Int32] = []

    /// Create an empty accumulator that fuses at `voxelSize` (meters).
    public init(voxelSize: Double = 0.02) {
        self.voxelSize = max(voxelSize, 1e-6)
    }

    /// Merge an **already world-space** cloud, keeping one point per voxel.
    public mutating func add(_ source: PointCloud) {
        cloud.points.reserveCapacity(cloud.points.count + source.points.count)
        for point in source.points { insert(point) }
    }

    /// Place a **camera-space** cloud into world space with `transform` (a camera→world
    /// pose) and merge it. The same as `add(source.transformed(by: transform))`, but
    /// without building the intermediate cloud.
    public mutating func add(_ source: PointCloud, transformedBy transform: simd_float4x4) {
        cloud.points.reserveCapacity(cloud.points.count + source.points.count)
        for point in source.points {
            var moved = point
            moved.position = transform.transforming(point.position)
            insert(moved)
        }
    }

    /// Drop every fused point, keeping the allocation, and start a fresh scan. The
    /// drift `correction` goes back to the identity with it.
    public mutating func reset() {
        cloud.removeAll()
        occupied.removeAll(keepingCapacity: true)
        normals.removeAll(keepingCapacity: true)
        normalEvidence.removeAll(keepingCapacity: true)
        correction = matrix_identity_float4x4
    }

    /// The number of fused points (one per occupied voxel).
    public var count: Int { cloud.count }
    /// Whether anything has been fused yet.
    public var isEmpty: Bool { cloud.isEmpty }

    private mutating func insert(_ point: PointCloud.Point) {
        let key = Voxel(point.position, size: voxelSize)
        if let index = occupied[key] {
            // Refresh the cube's point in place. The normal fitted here still stands:
            // the surface has not moved, only the sample of it inside the cube.
            cloud.points[index] = point
        } else {
            occupied[key] = cloud.points.count
            cloud.points.append(point)
            normals.append(.zero)
            normalEvidence.append(0)
        }
    }

    /// An integer voxel coordinate: a position quantized to the fusion grid.
    private struct Voxel: Hashable {
        let x: Int, y: Int, z: Int
        init(_ p: Vector3, size: Double) {
            x = Int((p.x / size).rounded(.down))
            y = Int((p.y / size).rounded(.down))
            z = Int((p.z / size).rounded(.down))
        }
        init(x: Int, y: Int, z: Int) { self.x = x; self.y = y; self.z = z }
    }

    // MARK: - What the fit asks of the fused scene

    /// The fused point nearest `p` and the surface normal there, or nil if nothing is
    /// fused within `rings` cubes or `reachSquared`.
    ///
    /// The answer is the nearest point of the cubes it looks in, which is not always
    /// the nearest point of the whole cloud. That is deliberate and it is what makes
    /// the search cheap: the grid keeps exactly one point per cube, so a point that
    /// lands on a surface already fused is answered by one lookup, and the wider
    /// shells are paid only by the points that miss. The error that buys is bounded
    /// by one cube, which is the same size as the grid the model was fused at.
    mutating func surface(near p: Vector3, rings: Int,
                          within reachSquared: Double) -> (position: Vector3, normal: Vector3?)? {
        let home = Voxel(p, size: voxelSize)
        if let index = occupied[home],
           cloud.points[index].position.distanceSquared(to: p) <= reachSquared {
            return (cloud.points[index].position, normal(at: index, in: home))
        }

        // Nothing in this cube, so widen a shell at a time and stop at the first
        // shell that holds anything. A point that lands where nothing has been fused
        // is the case that pays here, and every shell costs more than the last.
        var best = -1
        var bestVoxel = home
        var bestDistance = reachSquared
        for ring in 1 ... Swift.max(rings, 1) {
            for dz in -ring ... ring {
                let onZ = dz == ring || dz == -ring
                for dy in -ring ... ring {
                    let onYZ = onZ || dy == ring || dy == -ring
                    for dx in -ring ... ring where onYZ || dx == ring || dx == -ring {
                        let voxel = Voxel(x: home.x + dx, y: home.y + dy, z: home.z + dz)
                        guard let index = occupied[voxel] else { continue }
                        let distance = cloud.points[index].position.distanceSquared(to: p)
                        if distance < bestDistance {
                            bestDistance = distance
                            best = index
                            bestVoxel = voxel
                        }
                    }
                }
            }
            if best >= 0 { break }
        }
        guard best >= 0 else { return nil }
        return (cloud.points[best].position, normal(at: best, in: bestVoxel))
    }

    /// The surface normal at a fused point, fitted through the points in the cubes
    /// around it and kept.
    ///
    /// The fit is the direction the neighborhood spreads *least* along, which for
    /// points sampled off a surface is the direction out of it. Its sign is not
    /// settled and does not need to be: the fit squares the distance to the plane, so
    /// a normal and its opposite give the same answer.
    private mutating func normal(at index: Int, in voxel: Voxel) -> Vector3? {
        if normalEvidence[index] >= 6 { return normals[index] }

        // One ring of cubes is enough wherever the feed is denser than the grid, which
        // is the ordinary case. Where it is not, widen once rather than give up: a
        // thinly-covered patch still has a surface.
        var found: [Vector3] = []
        found.reserveCapacity(27)
        for rings in 1 ... 2 {
            found.removeAll(keepingCapacity: true)
            for dz in -rings ... rings {
                for dy in -rings ... rings {
                    for dx in -rings ... rings {
                        let key = Voxel(x: voxel.x + dx, y: voxel.y + dy, z: voxel.z + dz)
                        if let neighbor = occupied[key] {
                            found.append(cloud.points[neighbor].position)
                        }
                    }
                }
            }
            if found.count >= 5 { break }
        }
        normalEvidence[index] = Int32(found.count)
        guard found.count >= 5 else { return nil }

        var center = Vector3.zero
        for position in found { center += position }
        center /= Double(found.count)

        var xx = 0.0, xy = 0.0, xz = 0.0, yy = 0.0, yz = 0.0, zz = 0.0
        for position in found {
            let d = position - center
            xx += d.x * d.x; xy += d.x * d.y; xz += d.x * d.z
            yy += d.y * d.y; yz += d.y * d.z; zz += d.z * d.z
        }
        let fitted = smallestEigenvector(xx: xx, xy: xy, xz: xz, yy: yy, yz: yz, zz: zz)
        normals[index] = fitted
        return fitted
    }
}
