@testable import Ollin
import Testing
import simd
import Foundation

/// Pure CPU checks on the scan that recognizes a place it has already been: the
/// keyframes it keeps, the match it will and will not believe, the straightening that
/// follows, and the fused cloud being laid out again afterwards. No Metal device, so
/// these run everywhere.
@Suite
struct ScanGraphTests {

    // MARK: - A room, and a sweep that walks all the way round it

    static let roomWidth = 6.0
    static let roomDepth = 4.0
    static let roomHeight = 2.6

    /// Four walls, a floor, and eight boxes standing around the edge, on a lattice about
    /// as dense as a depth camera returns.
    ///
    /// The boxes are not decoration. A camera facing one bare wall can slide along it and
    /// turn about its normal and fit exactly as well, so three of the six numbers a fit
    /// answers would not be measured at all. Anything standing off the wall pins them.
    static func room(spacing: Double = 0.07, furniture: Bool = true) -> [Vector3] {
        var points: [Vector3] = []
        let halfWidth = roomWidth / 2, halfDepth = roomDepth / 2
        func sheet(_ u: Double, _ v: Double, _ place: (Double, Double) -> Vector3) {
            var a = 0.0
            while a <= u {
                var b = 0.0
                while b <= v {
                    points.append(place(a, b))
                    b += spacing
                }
                a += spacing
            }
        }
        sheet(roomWidth, roomHeight) { Vector3($0 - halfWidth, $1, -halfDepth) }
        sheet(roomWidth, roomHeight) { Vector3($0 - halfWidth, $1, halfDepth) }
        sheet(roomDepth, roomHeight) { Vector3(-halfWidth, $1, $0 - halfDepth) }
        sheet(roomDepth, roomHeight) { Vector3(halfWidth, $1, $0 - halfDepth) }
        sheet(roomWidth, roomDepth) { Vector3($0 - halfWidth, 0, $1 - halfDepth) }

        guard furniture else { return points }
        for corner in 0 ..< 8 {
            let angle = 2 * .pi * Double(corner) / 8
            let middle = Vector3(cos(angle) * 2.35, 0, sin(angle) * 1.45)
            let size = 0.5 + 0.1 * Double(corner % 3)
            sheet(size, size) { middle + Vector3($0 - size / 2, size, $1 - size / 2) }
            sheet(size, size) { middle + Vector3($0 - size / 2, $1, -size / 2) }
            sheet(size, size) { middle + Vector3($0 - size / 2, $1, size / 2) }
            sheet(size, size) { middle + Vector3(-size / 2, $1, $0 - size / 2) }
            sheet(size, size) { middle + Vector3(size / 2, $1, $0 - size / 2) }
        }
        return points
    }

    /// How far a point sits off the nearest wall or the floor. A scan that stayed
    /// registered keeps this small; a bent one smears it out.
    static func offTheSurface(_ p: Vector3) -> Double {
        min(abs(p.x + roomWidth / 2), abs(p.x - roomWidth / 2),
            abs(p.z + roomDepth / 2), abs(p.z - roomDepth / 2), abs(p.y))
    }

    static func thickness(of cloud: PointCloud) -> Double {
        var squared = 0.0
        for point in cloud.points {
            let gap = offTheSurface(point.position)
            squared += gap * gap
        }
        return (squared / Double(max(cloud.count, 1))).squareRoot()
    }

    /// Where the camera really stands at `t`, 0 to 1: walking a circle inside the room,
    /// facing outward the whole way and tilted down the way a phone is held, so it comes
    /// back to where it started with the floor in every frame.
    static func truePose(at t: Double, laps: Double = 1, tilt: Double = 0.38) -> simd_float4x4 {
        let angle = t * laps * 2 * .pi
        let radius = 1.4
        let stand = Vector3(cos(angle) * radius, 1.4, sin(angle) * radius)
        // Face outward: turn about y so the camera's own -z points away from the middle,
        // then tip it down about its own x. Held level it sees nothing but wall.
        let outward = simd_quatf(angle: Float(-angle - .pi / 2), axis: SIMD3<Float>(0, 1, 0))
        let down = simd_quatf(angle: Float(-tilt), axis: SIMD3<Float>(1, 0, 0))
        var pose = simd_float4x4(outward * down)
        pose.columns.3 = SIMD4<Float>(Float(stand.x), Float(stand.y), Float(stand.z), 1)
        return pose
    }

    /// What the tracking gets wrong each frame: always the same lean, which is what makes
    /// the error pile up instead of averaging out.
    static func driftStep(_ scale: Double = 1) -> simd_float4x4 {
        let turn = simd_quatf(angle: Float(0.0026 * scale),
                              axis: simd_normalize(SIMD3<Float>(0.1, 1, 0.1)))
        var step = simd_float4x4(turn)
        step.columns.3 = SIMD4<Float>(Float(0.0022 * scale), Float(0.0004 * scale),
                                      Float(-0.0016 * scale), 1)
        return step
    }

    /// The slice of the room in front of the lens, in camera space.
    static func seen(from pose: simd_float4x4, of room: [Vector3]) -> PointCloud {
        let eye = Vector3.zero.transformed(by: pose)
        let forward = Vector3(0, 0, -1).transformed(by: pose) - eye
        let cone = cos(0.55)
        let inverse = pose.inverse
        var cloud = PointCloud()
        cloud.points.reserveCapacity(room.count / 4)
        for position in room {
            let toward = position - eye
            let distance = toward.length
            guard distance > 0.4, distance < 7 else { continue }
            guard forward.dot(toward) / distance > cone else { continue }
            cloud.points.append(PointCloud.Point(position: position.transformed(by: inverse),
                                                 color: .white, size: 0.02))
        }
        return cloud
    }

    static func place(_ m: simd_float4x4) -> Vector3 {
        Vector3(Double(m.columns.3.x), Double(m.columns.3.y), Double(m.columns.3.z))
    }

    static func disagreement(_ a: simd_float4x4, _ b: simd_float4x4) -> Double {
        let probes = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]
        var worst = 0.0
        for probe in probes {
            worst = Swift.max(worst, a.transforming(probe).distance(to: b.transforming(probe)))
        }
        return worst
    }

    /// The worst distance any kept pose stands from where the camera really was.
    static func worst(_ poses: [simd_float4x4], against truths: [simd_float4x4]) -> Double {
        var found = 0.0
        for index in 0 ..< Swift.min(poses.count, truths.count) {
            found = Swift.max(found, disagreement(truths[index], poses[index]))
        }
        return found
    }

    /// One whole sweep and what happened along it.
    struct Sweep {
        var scan: ScanGraph
        /// The true pose of every keyframe, in step with `scan.keyframes`.
        var truths: [simd_float4x4] = []
        var loops: [ScanGraph.Loop] = []
        /// The worst keyframe error over the keyframes the sweep had kept when it first
        /// recognized a place, read on either side of the straightening that followed.
        var worstBefore = 0.0
        var worstAfter = 0.0
    }

    static func sweep(frames: Int = 110, laps: Double = 1.15, drift: Double = 1,
                      settings: ScanGraph.Settings = .init(),
                      voxelSize: Double = 0.03, furniture: Bool = true,
                      tilt: Double = 0.38) -> Sweep {
        let points = room(furniture: furniture)
        var result = Sweep(scan: ScanGraph(voxelSize: voxelSize, settings: settings))
        var slip = matrix_identity_float4x4

        for frame in 0 ..< frames {
            let t = Double(frame) / Double(frames - 1)
            let truth = truePose(at: t, laps: laps, tilt: tilt)
            // Read where the keyframes stand before this frame is added, since adding it
            // is what may move them.
            let standing = result.scan.keyframes.map(\.pose)
            let update = result.scan.add(seen(from: truth, of: points), correcting: slip * truth)
            if update.keyframe != nil { result.truths.append(truth) }
            if let loop = update.loop {
                if result.loops.isEmpty {
                    // Both readings are over the same keyframes: the ones the sweep had
                    // kept when it recognized the place. Later ones drift on afterwards
                    // and would drown the thing being measured.
                    let settled = Array(result.scan.keyframes.prefix(standing.count).map(\.pose))
                    result.worstBefore = worst(standing, against: result.truths)
                    result.worstAfter = worst(settled, against: result.truths)
                }
                result.loops.append(loop)
            }
            slip = slip * driftStep(drift)
        }
        return result
    }

    // MARK: - Keeping the moments

    @Test func aSweepKeepsKeyframesAsTheCameraMoves() {
        let run = ScanGraphTests.sweep(frames: 60, laps: 0.5)
        #expect(run.scan.keyframes.count > 5)
        #expect(run.scan.keyframes.count < 60, "not every frame is worth keeping")
        for index in 1 ..< run.scan.keyframes.count {
            let step = run.scan.keyframes[index - 1].pose.inverse * run.scan.keyframes[index].pose
            #expect(step.shift >= run.scan.settings.keyframeDistance * 0.9
                        || step.turn >= run.scan.settings.keyframeTurn * 0.9)
        }
    }

    @Test func aKeyframeKeepsWhatItSawInItsOwnSpace() {
        let run = ScanGraphTests.sweep(frames: 40, laps: 0.35)
        guard let first = run.scan.keyframes.first else { return }
        #expect(!first.cloud.isEmpty)
        // Camera space, so what it saw sits in front of the lens, not out in the room.
        let middle = first.cloud.points.reduce(Vector3.zero) { $0 + $1.position }
            / Double(first.cloud.count)
        #expect(middle.length < 7)
        #expect(middle.z < 0, "the camera looks along its own negative z")
    }

    // MARK: - Recognizing a place, or refusing to

    /// A sweep that never comes back to anywhere has nothing to recognize, and must not
    /// invent one. A place mistaken for another is the only failure here that can wreck a
    /// whole scan.
    @Test func aSweepThatNeverReturnsFindsNoPlace() {
        let run = ScanGraphTests.sweep(frames: 90, laps: 0.55)
        #expect(run.loops.isEmpty, "recognized a place it had never been")
        #expect(run.scan.loops.isEmpty)
    }

    @Test func aSweepThatComesBackRecognizesWhereItStarted() {
        let run = ScanGraphTests.sweep()
        #expect(!run.loops.isEmpty, "walked a full lap and recognized nothing")
        guard let first = run.loops.first else { return }
        #expect(first.recognized < first.keyframe)
        #expect(first.overlap >= run.scan.settings.minimumOverlap)
        #expect(first.error <= run.scan.settings.maximumError)
        // It has to be the beginning of the sweep it recognized, not just anywhere.
        let start = ScanGraphTests.place(run.truths[0])
        let found = ScanGraphTests.place(run.truths[first.recognized])
        #expect(found.distance(to: start) < 1.0,
                "matched keyframe \(first.recognized), which is not where it started")
    }

    /// Both measures of a match have to be consulted before it is believed. The staged
    /// room is perfect, so a match here scores perfectly; asking for better than perfect
    /// is what proves each guard is read at all.
    @Test func aMatchThatDoesNotMeasureUpIsRefused() {
        var overlap = ScanGraph.Settings()
        overlap.minimumOverlap = 1.01
        #expect(ScanGraphTests.sweep(settings: overlap).loops.isEmpty,
                "believed a match that did not overlap enough")

        var exact = ScanGraph.Settings()
        exact.maximumError = 0
        #expect(ScanGraphTests.sweep(settings: exact).loops.isEmpty,
                "believed a match that left something over")
    }

    /// A camera held level in a bare room sees one flat wall and nothing else. It can
    /// slide along that wall and turn about its normal and fit it exactly as well every
    /// time, so three of the six numbers a match reports were never measured: they are
    /// the drift, written down as though they had been. That is worse than no match,
    /// because the scan then believes them, and neither the overlap nor the leftover
    /// error can see it. Only the fit's own conditioning can.
    @Test func aMatchTheGeometryCannotPinDownIsRefused() {
        var alone = ScanGraph.Settings()
        alone.alignment.samples = 0
        let level = ScanGraphTests.sweep(drift: 0.3, settings: alone,
                                         furniture: false, tilt: 0)
        #expect(level.loops.isEmpty,
                "believed a match the geometry could not have pinned down")

        // The same sweep, tipped down so the floor comes into frame, does close. So what
        // was refused was the geometry, not the sweep.
        let tipped = ScanGraphTests.sweep(drift: 0.3, settings: alone, furniture: false)
        #expect(!tipped.loops.isEmpty)
    }

    /// Past its reach the match has to give up rather than settle somewhere confident and
    /// wrong, because a wrong measurement believed forever is worse than none.
    @Test func aScanTooFarGoneIsLeftAloneRatherThanGuessed() {
        var alone = ScanGraph.Settings()
        alone.alignment.samples = 0
        let lost = ScanGraphTests.sweep(drift: 1.5, settings: alone)
        #expect(lost.loops.isEmpty, "believed a match from further away than it can see")
    }

    @Test func aPlaceOutOfReachIsNeverLookedFor() {
        var short = ScanGraph.Settings()
        short.searchRadius = 0
        let run = ScanGraphTests.sweep(settings: short)
        #expect(run.loops.isEmpty)
    }

    // MARK: - What recognizing it does

    /// The frame-by-frame fit is switched off here, so what is measured is the
    /// straightening alone. With it running the two corrections overlap: in a room this
    /// small nearly every frame can see something already fused, so the per-frame fit has
    /// taken most of the drift out before the lap closes and there is less left to find.
    @Test func recognizingThePlaceStraightensTheWholeScan() {
        var alone = ScanGraph.Settings()
        alone.alignment.samples = 0
        let run = ScanGraphTests.sweep(drift: 0.3, settings: alone)
        #expect(!run.loops.isEmpty)
        #expect(run.worstBefore > 0.15, "the drift has to be worth fixing")
        #expect(run.worstAfter < run.worstBefore * 0.35,
                "worst pose error went from \(run.worstBefore) to \(run.worstAfter)")
    }

    /// With the frame-by-frame fit running as well, the two together still leave the scan
    /// better than either alone.
    @Test func theTwoCorrectionsWorkTogether() {
        let run = ScanGraphTests.sweep()
        #expect(!run.loops.isEmpty)
        #expect(run.worstAfter < run.worstBefore,
                "worst pose error went from \(run.worstBefore) to \(run.worstAfter)")
    }

    @Test func aStraightenedScanHasThinnerWalls() {
        let closing = ScanGraphTests.sweep()
        var open = ScanGraph.Settings()
        open.searchRadius = 0                              // nothing is ever near enough
        let bent = ScanGraphTests.sweep(settings: open)
        #expect(bent.loops.isEmpty)
        let closed = ScanGraphTests.thickness(of: closing.scan.cloud)
        let smeared = ScanGraphTests.thickness(of: bent.scan.cloud)
        #expect(closed < smeared,
                "walls measured \(closed) closed against \(smeared) left bent")
    }

    /// The scan is laid out again from the keyframes once it has been straightened, so
    /// the next frame has to arrive in the space it was straightened into. Miss that and
    /// the feed goes on adding frames where the map used to be, and the snap smears
    /// itself back out over the following seconds.
    @Test func theFeedCarriesOnInTheStraightenedSpace() {
        let points = ScanGraphTests.room()
        var scan = ScanGraph(voxelSize: 0.03)
        var slip = matrix_identity_float4x4
        var closed = false
        var frame = 0
        let frames = 150

        while frame < frames {
            let t = Double(frame) / Double(frames - 1)
            let truth = ScanGraphTests.truePose(at: t, laps: 1.15)
            let update = scan.add(ScanGraphTests.seen(from: truth, of: points),
                                  correcting: slip * truth)
            slip = slip * ScanGraphTests.driftStep()
            frame += 1
            if update.loop != nil { closed = true; break }
        }
        #expect(closed, "the sweep never closed, so there is nothing to check")

        // One more frame, placed the way the next live frame would be.
        let t = Double(frame) / Double(frames - 1)
        let truth = ScanGraphTests.truePose(at: t, laps: 1.15)
        let update = scan.add(ScanGraphTests.seen(from: truth, of: points),
                              correcting: slip * truth)
        let landed = ScanGraphTests.place(update.alignment.pose)
        let expected = ScanGraphTests.place(truth)
        #expect(landed.distance(to: expected) < 0.2,
                "the next frame landed \(landed.distance(to: expected)) m from where it was")
    }

    // MARK: - Housekeeping

    @Test func resettingAScanForgetsEverything() {
        var run = ScanGraphTests.sweep(frames: 60, laps: 0.5)
        #expect(!run.scan.isEmpty)
        run.scan.reset()
        #expect(run.scan.isEmpty)
        #expect(run.scan.keyframes.isEmpty)
        #expect(run.scan.loops.isEmpty)
        #expect(run.scan.count == 0)
    }

    @Test func anEmptyScanAnswersPlainly() {
        let scan = ScanGraph()
        #expect(scan.isEmpty)
        #expect(scan.count == 0)
        #expect(scan.keyframes.isEmpty)
        #expect(scan.correction == matrix_identity_float4x4)
    }
}
