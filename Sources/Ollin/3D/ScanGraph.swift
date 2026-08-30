import Foundation
import simd

/// Fuses a depth sweep into one cloud, corrects the camera's drift as it goes, and
/// recognizes a place it has already scanned so the whole scan can be straightened.
///
/// `WorldCloud` on its own places every frame where the camera said it was, and
/// `add(_:correcting:)` slides each arriving frame onto the surfaces already fused so
/// the error stops piling up. Neither can do anything about the error already piled up
/// behind them. Walk all the way around a room and back to the door, and the far wall
/// has bent away from where it really is: every frame agreed with the frame before it,
/// and the whole chain still leans.
///
/// This is the answer to that. Along the way it keeps a **keyframe** every so often: the
/// pose it was placed at and a thinned copy of what it saw. When a new keyframe lands
/// near an old one, the two are matched against each other directly. A match is one more
/// measurement, and unlike all the others it ties a late pose to an early one, so the
/// chain becomes a loop that does not quite close. Sharing that gap out over every pose
/// between them is what straightens the scan, and the fused cloud is rebuilt from the
/// keyframes where they now stand.
///
/// ```swift
/// var scan = ScanGraph(voxelSize: 0.025)
///
/// // each new frame, in draw():
/// if let frame = device.latestFrame, let pose = device.latestPose {
///     let update = scan.add(frame.pointCloud(pointSize: 0.01), correcting: pose)
///     if let loop = update.loop { print("been here before, map moved \(loop.moved) m") }
/// }
/// drawPointCloud(scan.cloud)
/// ```
///
/// What it will and will not do. It recognizes a place by standing near it and looking a
/// similar way, so `searchRadius` is the envelope: a scan that has drifted further than
/// that before coming back has drifted out of its own reach. Every match is checked by
/// fitting the two clouds together and is refused unless they really do agree, since one
/// place mistaken for another is the only failure here that can wreck a whole scan.
public struct ScanGraph {

    /// One kept moment of the sweep: where the camera stood and a thinned copy of what
    /// it saw from there.
    public struct Keyframe {
        /// Where this frame now stands, as a camera→world transform. Straightening the
        /// scan rewrites it.
        public internal(set) var pose: simd_float4x4
        /// The pose the depth source reported for it, before any correction.
        public let reportedPose: simd_float4x4
        /// What the camera saw, in **camera space**, thinned to `keyframeDetail`. It is
        /// kept in camera space so that moving the keyframe is one transform.
        public let cloud: PointCloud
        /// How far away what this keyframe saw typically was, in world units. It is the
        /// arm a turn acts through: an error of one radian here drags the surfaces the
        /// camera was looking at by this much.
        public let reach: Double
    }

    /// A place the scan recognized, and what recognizing it did to the map.
    public struct Loop {
        /// The keyframe that arrived and turned out to be somewhere already scanned.
        public var keyframe: Int
        /// The older keyframe it matched.
        public var recognized: Int
        /// The share of the arriving cloud that found a surface in the older one, 0 to 1.
        public var overlap: Double
        /// What the match left over, in world units.
        public var error: Double
        /// How far the furthest keyframe moved when the scan was straightened. Zero when
        /// the match agreed with where things already stood, which is the happy case: the
        /// scan was right and now it is also *known* to be right.
        public var moved: Double
    }

    /// What one added frame did.
    public struct Update {
        /// How the frame lined up against the scene already fused.
        public var alignment: CloudAlignment
        /// The keyframe this frame became, if it was far enough from the last one to be
        /// worth keeping.
        public var keyframe: Int?
        /// The place it turned out to be, if the scan recognized one.
        public var loop: Loop?
    }

    /// The knobs. The defaults suit a hand-held sweep of a room, in meters.
    public struct Settings: Sendable {

        /// How far the camera has to move before the sweep keeps another keyframe.
        public var keyframeDistance: Double = 0.3

        /// How far it has to turn before the sweep keeps another keyframe, in radians.
        public var keyframeTurn: Double = .pi / 10

        /// The cube edge a keyframe's own copy of what it saw is thinned to. **A
        /// straightened scan is rebuilt from these copies**, so this is the detail the
        /// finished scan keeps, and it is also what the keyframes cost in memory. Near
        /// the fusion `voxelSize` keeps the most; a few times it is much lighter.
        public var keyframeDetail: Double = 0.04

        /// How near an old keyframe has to be before it is worth asking whether this is
        /// the same place, in world units. It is the whole envelope: drift bigger than
        /// this has carried the scan out of its own reach.
        public var searchRadius: Double = 1.5

        /// How many keyframes back to start looking. The ones just behind are neighbors,
        /// not a place returned to, and matching them says nothing new.
        public var separation: Int = 15

        /// The most old keyframes to test against one new one.
        public var candidates: Int = 3

        /// How many keyframes either side of a candidate are folded in with it, so the
        /// match is made against a patch of the room rather than one narrow view.
        public var neighborhood: Int = 2

        /// The least the two clouds have to overlap for a match to be believed, 0 to 1.
        public var minOverlap: Double = 0.55

        /// The most a believed match may leave over, in world units.
        public var maxError: Double = 0.05

        /// How differently the camera may have been facing, in radians. Two views of one
        /// place from opposite sides share almost no surface, so a match between them is
        /// far more likely to be a mistake than a memory.
        public var maxViewAngle: Double = .pi / 2

        /// How much a match has to disagree with where things already stand before the
        /// scan is straightened, in world units. Below it the match is kept as a
        /// measurement and nothing is moved.
        public var minSnap: Double = 0.01

        /// How far from the camera a turn is weighed when the scan is straightened, in
        /// world units. Turns are measured in radians and moves in meters, and the two
        /// have to be made comparable before they can be added up.
        ///
        /// Leave it nil to take it from the scan itself, which is the typical distance of
        /// what the camera actually saw. Set too small in a big room, the straightening
        /// trades a turn it should have fixed for a move it should not have made, and the
        /// scan comes out square but turned.
        public var turnScale: Double?

        /// How much wider the first of the two matching passes looks than the second.
        /// It is what decides the biggest drift a match can still find: roughly
        /// `matching.range` times this.
        public var reach: Double = 4

        /// The fit each arriving frame gets against the scene already fused.
        public var alignment = CloudAlignment.Settings()

        /// The fit a candidate place gets. It reaches further and works harder than the
        /// per-frame one, because it is looking for an error a whole sweep long rather
        /// than one frame's worth, and it runs rarely.
        ///
        /// It also asks for `minStability`, which the per-frame fit does not. A match
        /// is kept as a measurement and believed from then on, so one taken against a
        /// bare wall is worse than no match at all: it would hand the scan three measured
        /// numbers and three that are simply the drift, written down as though they had
        /// been measured.
        public var matching: CloudAlignment.Settings = {
            var settings = CloudAlignment.Settings()
            settings.samples = 900
            settings.passes = 14
            settings.range = 0.2
            settings.maxShift = 1.5
            settings.maxTurn = .pi / 4
            settings.minStability = 0.005
            return settings
        }()

        public init() {}
    }

    /// The knobs, live: changing one takes effect on the next frame.
    public var settings: Settings

    /// The fused cloud and the drift correction under it. Everything `WorldCloud` can do
    /// is reachable here; `cloud` is the shortcut to the points themselves.
    public private(set) var world: WorldCloud

    /// The moments the sweep kept, oldest first.
    public private(set) var keyframes: [Keyframe] = []

    /// Every place the scan has recognized so far.
    public private(set) var loops: [Loop] = []

    /// The measured moves between keyframes, including the ones a recognized place added.
    private var edges: [PoseGraph.Edge] = []

    /// Create an empty scan that fuses at `voxelSize` (meters).
    public init(voxelSize: Double = 0.02, settings: Settings = .init()) {
        world = WorldCloud(voxelSize: voxelSize)
        self.settings = settings
    }

    /// The fused cloud, in world space. Pass it straight to `drawPointCloud`.
    public var cloud: PointCloud { world.cloud }
    /// The number of fused points.
    public var count: Int { world.count }
    /// Whether anything has been fused yet.
    public var isEmpty: Bool { world.isEmpty }
    /// The cube edge the scene is fused at.
    public var voxelSize: Double { world.voxelSize }

    /// The fix between the pose the depth source reports and the space this scan is
    /// fused in: `placed = correction * reported`. It holds both the drift taken out
    /// frame by frame and whatever the last straightening moved.
    public var correction: simd_float4x4 { world.correction }

    /// Drop everything and start a fresh scan.
    public mutating func reset() {
        world.reset()
        keyframes.removeAll(keepingCapacity: true)
        loops.removeAll(keepingCapacity: true)
        edges.removeAll(keepingCapacity: true)
    }

    // MARK: - Adding a frame

    /// Line a frame up against the scene already fused, merge it, and straighten the
    /// whole scan whenever the frame lands somewhere already scanned.
    ///
    /// `reportedPose` is the camera→world transform the depth source reports.
    @discardableResult
    public mutating func add(_ source: PointCloud,
                             correcting reportedPose: simd_float4x4) -> Update {
        let alignment = world.add(source, correcting: reportedPose, settings: settings.alignment)
        guard worthKeeping(alignment.pose) else {
            return Update(alignment: alignment, keyframe: nil, loop: nil)
        }

        var thin = WorldCloud(voxelSize: Swift.max(settings.keyframeDetail, world.voxelSize))
        thin.add(source)
        keyframes.append(Keyframe(pose: alignment.pose, reportedPose: reportedPose,
                                  cloud: thin.cloud, reach: typicalDistance(of: thin.cloud)))
        let index = keyframes.count - 1
        if index > 0 {
            // Every step of the chain counts the same. Weighing them by how well each
            // one's own fit was pinned down was built and measured on two scenes, and it
            // helped one and hurt the other: a step measured against poor geometry is not
            // reliably the step the error entered at. With nothing to choose between
            // them, the plainer one stands.
            edges.append(.init(from: index - 1, to: index,
                               measured: keyframes[index - 1].pose.inverse * alignment.pose))
        }

        let loop = lookForAPlaceAlreadyScanned(from: index)
        if let loop { loops.append(loop) }
        return Update(alignment: alignment, keyframe: index, loop: loop)
    }

    /// How far away a camera-space cloud typically sits from the lens.
    private func typicalDistance(of cloud: PointCloud) -> Double {
        guard !cloud.isEmpty else { return 0 }
        var total = 0.0
        for point in cloud.points { total += point.position.length }
        return total / Double(cloud.count)
    }

    /// Whether the camera has moved or turned enough since the last keyframe to be worth
    /// keeping another.
    private func worthKeeping(_ pose: simd_float4x4) -> Bool {
        guard let last = keyframes.last else { return true }
        let since = last.pose.inverse * pose
        return since.shift >= settings.keyframeDistance || since.turn >= settings.keyframeTurn
    }

    // MARK: - Recognizing a place

    /// Test the newest keyframe against the older ones it is standing among, and if one
    /// of them really is the same place, tie the two together and straighten the scan.
    private mutating func lookForAPlaceAlreadyScanned(from index: Int) -> Loop? {
        for candidate in candidates(for: index) {
            guard let match = fit(index, against: candidate) else { continue }

            edges.append(.init(from: candidate, to: index, measured: match.measured,
                               weight: match.overlap, robust: true))

            // How far the match disagrees with where the two keyframes already stand. A
            // match that agrees is still worth keeping as a measurement, but there is
            // nothing to move.
            let standing = keyframes[candidate].pose.inverse * keyframes[index].pose
            let disagreement = match.measured.inverse * standing
            var moved = 0.0
            let lever = Swift.max(turnWeighing(), 1e-6)
            if disagreement.shift >= settings.minSnap
                || disagreement.turn >= settings.minSnap / lever {
                moved = straighten()
            }
            return Loop(keyframe: index, recognized: candidate, overlap: match.overlap,
                        error: match.error, moved: moved)
        }
        return nil
    }

    /// The old keyframes near enough, and facing enough the same way, to be worth
    /// testing, nearest first.
    private func candidates(for index: Int) -> [Int] {
        let reach = index - Swift.max(settings.separation, 1)
        guard reach > 0 else { return [] }
        let here = keyframes[index]
        let position = place(here.pose)
        let looking = facing(here.pose)
        let widest = cos(Swift.max(settings.maxViewAngle, 0))

        var near: [(index: Int, distance: Double)] = []
        for other in 0 ..< reach {
            let distance = place(keyframes[other].pose).distance(to: position)
            guard distance <= settings.searchRadius else { continue }
            guard looking.dot(facing(keyframes[other].pose)) >= widest else { continue }
            near.append((other, distance))
        }
        near.sort { $0.distance < $1.distance }
        return near.prefix(Swift.max(settings.candidates, 0)).map(\.index)
    }

    /// Fit the newest keyframe's cloud against a patch of the room built around an older
    /// one, and report the move between them if the two really do agree.
    private func fit(_ index: Int, against candidate: Int)
        -> (measured: simd_float4x4, overlap: Double, error: Double)? {
        let low = Swift.max(0, candidate - settings.neighborhood)
        let high = Swift.min(Swift.min(keyframes.count - 1, candidate + settings.neighborhood),
                             index - 1)
        guard low <= high else { return nil }

        var patch = WorldCloud(voxelSize: Swift.max(settings.keyframeDetail, world.voxelSize))
        for other in low ... high {
            patch.add(keyframes[other].cloud, transformedBy: keyframes[other].pose)
        }
        guard !patch.isEmpty else { return nil }

        // Twice, wide then narrow. A fit only ever looks a fixed distance for the surface
        // a point belongs to, so it can only find an error smaller than that reach: hand
        // it a bigger one and it matches each point to the wrong part of the room and
        // settles somewhere confident and wrong. The wide pass gets close enough for the
        // narrow one to be looking at the right surfaces, and only the narrow one is
        // judged, because only it was working to the accuracy being asked for.
        var wide = settings.matching
        wide.range = settings.matching.range * settings.reach
        wide.passes = Swift.max(4, settings.matching.passes / 2)
        wide.minStability = 0
        let rough = patch.align(keyframes[index].cloud, from: keyframes[index].pose,
                                settings: wide)

        let alignment = patch.align(keyframes[index].cloud, from: rough.pose,
                                    settings: settings.matching)
        guard alignment.applied,
              alignment.overlap >= settings.minOverlap,
              alignment.error <= settings.maxError else { return nil }
        // However it got there, the answer still has to be a place this keyframe could
        // plausibly be. The wide pass is allowed to move a long way, so this is what
        // stops it from moving somewhere absurd.
        guard place(alignment.pose).distance(to: place(keyframes[index].pose))
                <= settings.searchRadius else { return nil }
        return (keyframes[candidate].pose.inverse * alignment.pose,
                alignment.overlap, alignment.error)
    }

    // MARK: - Straightening, and putting the scan back together

    /// How far from the camera a turn is weighed: what was asked for, or failing that
    /// the typical distance of what this scan actually saw.
    private func turnWeighing() -> Double {
        if let asked = settings.turnScale { return asked }
        let reaches = keyframes.map(\.reach).filter { $0 > 0 }.sorted()
        guard !reaches.isEmpty else { return 2 }
        return reaches[reaches.count / 2]
    }

    /// Move every keyframe until the measurements agree as well as they can, then rebuild
    /// the fused cloud from where the keyframes now stand. Returns how far the furthest
    /// one moved.
    private mutating func straighten() -> Double {
        var graph = PoseGraph(poses: keyframes.map(\.pose))
        graph.edges = edges
        var solving = PoseGraph.Settings()
        solving.turnScale = turnWeighing()
        let report = graph.straighten(solving)
        for (index, pose) in graph.poses.enumerated() { keyframes[index].pose = pose }
        rebuild()
        return report.moved
    }

    /// Lay the scan out again from the keyframes at their new poses.
    ///
    /// The frames since the last keyframe are not kept, so they are not laid back down;
    /// the sweep puts their detail back as it carries on. The rebuilt cloud holds what
    /// the keyframes kept, which is what `keyframeDetail` decides.
    private mutating func rebuild() {
        world.reset()
        for keyframe in keyframes {
            world.add(keyframe.cloud, transformedBy: keyframe.pose)
        }
        // The next frame arrives with the pose the source reports, and that pose has to
        // land in the space the scan was just straightened into. Without this the feed
        // goes on adding frames at the places the map has just moved away from, and the
        // snap smears itself out again over the following seconds.
        if let last = keyframes.last {
            world.correction = last.pose * last.reportedPose.inverse
        }
    }

    // MARK: - Reading a pose

    private func place(_ pose: simd_float4x4) -> Vector3 {
        Vector3(Double(pose.columns.3.x), Double(pose.columns.3.y), Double(pose.columns.3.z))
    }

    /// The direction the camera is pointed along, as a unit vector. Which end of the axis
    /// it is does not matter here: this is only ever used to compare two cameras with
    /// each other, and both are read the same way.
    private func facing(_ pose: simd_float4x4) -> Vector3 {
        Vector3(Double(pose.columns.2.x), Double(pose.columns.2.y),
                Double(pose.columns.2.z)).normalized
    }
}
