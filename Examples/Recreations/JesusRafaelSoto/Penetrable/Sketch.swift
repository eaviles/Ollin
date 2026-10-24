//  Recreation after Jesús Rafael Soto - the Penetrables (from 1969), read
//  from The Houston Penetrable (designed 2004, completed by the Atelier Soto
//  and first shown in 2014; lacquered aluminum structure, PVC tubes, and
//  water-based silkscreen ink, 848.4 x 1999 x 1211.6 cm, Museum of Fine Arts,
//  Houston), and the museum's account of it: 24,000 tubes, hand-painted and
//  tied, hung from the ceiling to the floor of Cullinan Hall, which at rest
//  compose a floating yellow orb on a transparent ground. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist, his
//  estate, or the museum.
//  https://emuseum.mfah.org/objects/107105
//  https://mfah.org/exhibitions/jesus-rafael-soto
//
//  An original Ollin interpretation, written from the record and the
//  accounts of the work. Nothing was ported: the tubes were painted and hung
//  by hand. The orb's size and height are this sketch's reading, since the
//  record does not give them.

import Foundation
import Ollin

/// A *Penetrable* (Jesús Rafael Soto, Paris). **Drag** to look around.
///
/// From the late 1960s he hung rooms of thin tubes or threads from a frame
/// overhead, close enough together to read as a solid from across the room,
/// and asked people to walk into them. "When you enter a penetrable," he
/// said, "you have the sensation of being in a light swirl, a total
/// plenitude of vibrations." The Houston one is the largest: 24,000 PVC
/// tubes 28 feet long over 2,600 square feet, each painted yellow where it
/// passes through an orb that hangs in the middle of the room, so that from
/// outside the yellow sections line up into one floating form, and from
/// inside it comes apart into strands around you.
///
/// The room is built at the record's measurements: 200 tubes across 19.99 m
/// and 120 deep across 12.12 m, which is one tube every ten centimeters, each
/// 8.48 m from the frame to just above the floor. Every tube is painted
/// along the stretch of its length that crosses the orb at rest, so when it
/// swings the paint goes with it. A visitor walks a long loop that comes in
/// through the front, crosses under the orb, leaves by the back, and comes
/// round again. Their body, `reach` centimeters around, pushes every tube it
/// meets aside at the hip, and each tube is a pendulum hung from the frame
/// that swings back slowly and settles, so a wake opens behind them and
/// closes. `air` moves the whole room a little.
///
/// `view` is where you are: **walk** is the visitor's own eyes, **gallery**
/// stands outside and watches them go through, from the front or turned
/// `around` the room. `pace` is how fast they walk and `haze` how much the
/// clear tubes show.
///
/// `--export-svg` draws every tube as a line through the camera (in the
/// gallery view), the clear lengths gray and the painted ones yellow, and
/// the visitor's body as a line with a ring at the hip, so the grid, the orb,
/// and the parting can be read back from the file.
@main
final class Penetrable: Sketch {
    enum View: String, CaseIterable, ParamOption { case walk, gallery }

    @Param(icon: "eye") var view = View.walk
    /// How fast the visitor walks, in meters a second.
    @Param(0.2 ... 1.4, icon: "figure.walk") var pace = 0.55
    /// How far the visitor's body pushes the tubes aside, in centimeters.
    @Param(15 ... 45, icon: "person") var reach = 26.0
    /// How far the room's air moves the tubes at the floor, in centimeters.
    @Param(0 ... 10, icon: "wind") var air = 2.0
    /// How much the clear tubes show.
    @Param(0.05 ... 0.8, icon: "drop") var haze = 0.16
    /// Where you stand in the gallery view, turned around the room from the
    /// front, in degrees.
    @Param(-180 ... 180, icon: "camera.rotate") var around = 0.0

    override var canvasSize: CanvasSize { .square(1080) }

    // The record's measurements, in meters.
    static let roomWidth = 19.99
    static let roomDepth = 12.116
    static let frameHeight = 8.484
    static let columns = 200
    static let rows = 120
    static let floorGap = 0.04
    static let tubeRadius = 0.005
    static var length: Double { frameHeight - floorGap }
    static var spacingX: Double { roomWidth / Double(columns) }
    static var spacingZ: Double { roomDepth / Double(rows) }

    /// The orb: its middle and its three half-widths (this sketch's reading).
    static let orbCenter = Vector3(0, 4.3, 0)
    static let orbRadii = Vector3(6.0, 2.9, 3.9)
    /// Where the body meets the tubes, and its height.
    static let hip = 1.0
    static let bodyHeight = 1.75

    /// Where tube `i` hangs from the frame.
    static func top(_ i: Int) -> Vector3 {
        let column = i % columns, row = i / columns
        return Vector3(-roomWidth / 2 + (Double(column) + 0.5) * spacingX, frameHeight,
                       -roomDepth / 2 + (Double(row) + 0.5) * spacingZ)
    }

    /// The painted stretch of each tube, as distances down from the frame,
    /// or nil for a tube that misses the orb.
    static let paint: [ClosedRange<Double>?] = (0 ..< columns * rows).map { i in
        let t = top(i)
        let dx = (t.x - orbCenter.x) / orbRadii.x, dz = (t.z - orbCenter.z) / orbRadii.z
        let inside = 1 - dx * dx - dz * dz
        guard inside > 0 else { return nil }
        let half = orbRadii.y * inside.squareRoot()
        return (frameHeight - orbCenter.y - half) ... (frameHeight - orbCenter.y + half)
    }

    /// The visitor's loop: in through the front, under the orb, out the
    /// back, round, and in again, walked by arc length.
    struct Path {
        var points: [Vector2] = []
        var distances: [Double] = []
        var length = 0.0

        init() {
            let count = 2048
            for k in 0 ... count {
                let a = 2 * Double.pi * Double(k) / Double(count)
                points.append(Vector2(2.8 * sin(a) + 1.0 * sin(2 * a), 13.5 * cos(a)))
            }
            distances = [0]
            for k in 1 ..< points.count {
                distances.append(distances[k - 1] + (points[k] - points[k - 1]).length)
            }
            length = distances[distances.count - 1]
        }

        /// The point and the heading `s` meters along the loop.
        func at(_ s: Double) -> (Vector2, Vector2) {
            let d = s.truncatingRemainder(dividingBy: length) + (s < 0 ? length : 0)
            var lo = 0, hi = distances.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if distances[mid] <= d { lo = mid } else { hi = mid }
            }
            let span = distances[hi] - distances[lo]
            let f = span > 0 ? (d - distances[lo]) / span : 0
            let p = points[lo] + (points[hi] - points[lo]) * f
            return (p, (points[hi] - points[lo]).normalized)
        }
    }

    static let path = Path()
    /// Where the walk begins, in meters along the loop: three meters in front
    /// of the room, so the visitor is inside within a few seconds.
    static let start = 5.68

    // Each tube's swing from the frame: how far its foot is off plumb, per
    // meter of tube, along x and z, and how fast that is changing.
    private var tiltX = [Double](repeating: 0, count: columns * rows)
    private var tiltZ = [Double](repeating: 0, count: columns * rows)
    private var spinX = [Double](repeating: 0, count: columns * rows)
    private var spinZ = [Double](repeating: 0, count: columns * rows)
    private var stepped = -1.0

    private var order: [Int] = Array(0 ..< columns * rows)
    private var sortedFrom = Vector3(1e9, 0, 0)
    private var lookYaw = 0.0
    private var lookPitch = 0.0

    /// One strip a meter square, flat in x and z, its face up y.
    private let strip = Mesh.plane(width: 1, depth: 1, segments: 1)
    private let body = Mesh.capsule(radius: 0.2, height: Penetrable.bodyHeight, segments: 16, rings: 8)
    private let floorMesh = Mesh.plane(width: 80, depth: 80)
    private let beam = Mesh.box(size: 1)

    private static let clear = Color(hex: 0xF7FAFB)
    private static let yellow = Color(hex: 0xF6CD05)
    private static let backdrop = Color(hex: 0xCBCFCF)

    // MARK: - The run

    override func draw() {
        let (walker, heading) = Penetrable.path.at(Penetrable.start + time * pace)
        settle(walker: walker)

        let eye: Vector3
        if view == .walk {
            eye = lookFromTheWalk(walker, heading)
        } else {
            let turn = Double.pi / 180 * around
            eye = Vector3(sin(turn) * 21.5, 1.6, cos(turn) * 21.5)
            camera(.perspective(eye: eye, target: Vector3(0, 3.9, 0), fieldOfView: .degrees(52), near: 0.05, far: 200))
        }

        background(Penetrable.backdrop)
        if isVectorExporting {
            drawAsLines(walker)
            return
        }
        // Daylight comes in low through the hall's glass onto the floor, the
        // frame, and the visitor.
        ambientLight(Color(white: 0.7))
        directionalLight(Color(white: 1), direction: Vector3(-0.45, -0.3, -0.85), intensity: 0.85)
        fog(Penetrable.backdrop, density: 0.005)
        temporalAntialiasing()

        noStroke()
        fill(Color(hex: 0xB4B1AA))
        drawMesh(floorMesh)
        drawFrame()
        if view == .gallery {
            fill(Color(hex: 0x2B2D33))
            withState {
                translate(walker.x, Penetrable.bodyHeight / 2, walker.y)
                drawMesh(body)
            }
        }
        drawTubes(from: eye)
    }

    /// The visitor's eyes: along the loop, turned toward the orb while they
    /// are outside the room, and wherever a drag turns them.
    private func lookFromTheWalk(_ walker: Vector2, _ heading: Vector2) -> Vector3 {
        if mouseIsPressed {
            let move = mouse - previousMouse
            lookYaw -= move.x * 0.004
            lookPitch = max(-0.9, min(0.9, lookPitch - move.y * 0.004))
        } else {
            let ease = exp(-deltaTime * 0.6)
            lookYaw *= ease
            lookPitch *= ease
        }
        let stride = 2 * Double.pi * time * pace / 0.72
        let eye = Vector3(walker.x, 1.62 + 0.012 * sin(stride), walker.y)
        let outside = max(abs(walker.x) - Penetrable.roomWidth / 2, abs(walker.y) - Penetrable.roomDepth / 2)
        let toward = min(max(outside / 4, 0), 1) * 0.45 + 0.3
        let forward = Vector3(heading.x, 0, heading.y)
        let toOrb = (Penetrable.orbCenter - eye).normalized
        var dir = (forward * (1 - toward) + toOrb * toward).normalized
        let yaw = atan2(dir.x, dir.z) + lookYaw
        let pitch = asin(max(-1, min(1, dir.y))) + 0.1 + lookPitch
        dir = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
        camera(.perspective(eye: eye, target: eye + dir * 5, fieldOfView: .degrees(64), near: 0.05, far: 200))
        return eye
    }

    // MARK: - The tubes

    /// Steps every tube's swing to this frame: the body pushes aside the ones
    /// it meets at the hip, the air leans the room a little, and each tube
    /// swings back toward plumb as a rod hung from one end, and settles.
    private func settle(walker: Vector2) {
        if stepped < 0 || time < stepped { reset() }
        var dt = time - stepped
        stepped = time
        let lever = Penetrable.frameHeight - Penetrable.hip
        // A rod swinging from one end, 8.44 m long: about 4.8 s a swing.
        let stiffness = 3 * 9.81 / (2 * Penetrable.length)
        let damping = 0.35
        let drift = air / 100 / Penetrable.length
        while dt > 1e-9 {
            let h = min(dt, 1.0 / 60)
            dt -= h
            for i in 0 ..< tiltX.count {
                var restX = 0.0, restZ = 0.0
                if drift > 0 {
                    let t = Penetrable.top(i)
                    restX = drift * signedNoise(t.x * 0.08 + stepped * 0.07, t.z * 0.08)
                    restZ = drift * signedNoise(t.x * 0.08 + 31, t.z * 0.08 + stepped * 0.06)
                }
                spinX[i] += (-stiffness * (tiltX[i] - restX) - damping * spinX[i]) * h
                spinZ[i] += (-stiffness * (tiltZ[i] - restZ) - damping * spinZ[i]) * h
                tiltX[i] += spinX[i] * h
                tiltZ[i] += spinZ[i] * h
            }
            push(walker: walker, lever: lever, step: h)
        }
    }

    /// Puts every tube the body overlaps at the hip back on the body's edge,
    /// and gives it the speed that took, up to the pace of the walk.
    private func push(walker: Vector2, lever: Double, step: Double) {
        let radius = reach / 100
        // A tube already swinging can come at the body from farther off than
        // the body reaches, so the search covers any swing a push can give.
        let span = radius + 1.0
        let c0 = max(0, Int(((walker.x - span) + Penetrable.roomWidth / 2) / Penetrable.spacingX))
        let c1 = min(Penetrable.columns - 1, Int(((walker.x + span) + Penetrable.roomWidth / 2) / Penetrable.spacingX) + 1)
        let r0 = max(0, Int(((walker.y - span) + Penetrable.roomDepth / 2) / Penetrable.spacingZ))
        let r1 = min(Penetrable.rows - 1, Int(((walker.y + span) + Penetrable.roomDepth / 2) / Penetrable.spacingZ) + 1)
        guard c0 <= c1, r0 <= r1 else { return }
        for row in r0 ... r1 {
            for column in c0 ... c1 {
                let i = row * Penetrable.columns + column
                let t = Penetrable.top(i)
                let at = Vector2(t.x + tiltX[i] * lever, t.z + tiltZ[i] * lever)
                let off = at - walker
                let gap = off.length
                guard gap < radius else { continue }
                let away = gap > 1e-9 ? off / gap : Vector2(1, 0)
                let edge = walker + away * radius
                let newX = (edge.x - t.x) / lever, newZ = (edge.y - t.z) / lever
                // A body pushes a tube no faster than it walks.
                var kickX = (newX - tiltX[i]) / step, kickZ = (newZ - tiltZ[i]) / step
                let kick = (kickX * kickX + kickZ * kickZ).squareRoot() * lever
                let most = pace * 1.2
                if kick > most {
                    kickX *= most / kick
                    kickZ *= most / kick
                }
                spinX[i] = kickX
                spinZ[i] = kickZ
                tiltX[i] = newX
                tiltZ[i] = newZ
            }
        }
    }

    private func reset() {
        for i in 0 ..< tiltX.count { tiltX[i] = 0; tiltZ[i] = 0; spinX[i] = 0; spinZ[i] = 0 }
        stepped = time
    }

    /// Where tube `i` is `s` meters down from the frame.
    private func point(_ i: Int, _ s: Double) -> Vector3 {
        let t = Penetrable.top(i)
        let d = Vector3(tiltX[i], -1, tiltZ[i]).normalized
        return t + d * s
    }

    private func drawTubes(from eye: Vector3) {
        // Nearest first, so a clear tube shows once over what is behind it
        // rather than piling up into a wall.
        if (eye - sortedFrom).length > 0.3 {
            let keys = (0 ..< order.count).map { i -> Double in
                let t = Penetrable.top(i)
                return (t.x - eye.x) * (t.x - eye.x) + (t.z - eye.z) * (t.z - eye.z)
            }
            order.sort { keys[$0] < keys[$1] }
            sortedFrom = eye
        }
        var painted: [MeshInstance] = []
        var bare: [MeshInstance] = []
        painted.reserveCapacity(12_000)
        bare.reserveCapacity(order.count + 12_000)
        let width = 2 * Penetrable.tubeRadius
        for i in order {
            let t = Penetrable.top(i)
            let down = Vector3(tiltX[i], -1, tiltZ[i]).normalized
            // A tube this thin reads the same from every side, so it is drawn
            // as a flat strip of its width turned toward the eye.
            let toEye = eye - t
            var facing = toEye - down * toEye.dot(down)
            facing = facing.length > 1e-9 ? facing.normalized : Vector3(0, 0, 1)
            let turn = Penetrable.rotation(across: facing.cross(down), facing: facing, along: down)
            // Each tube was painted by hand, so no two are quite one shade.
            let shade = 0.95 + 0.05 * Penetrable.jitter(i)
            func piece(_ a: Double, _ b: Double, _ tint: Color?) -> MeshInstance {
                MeshInstance(position: t + down * ((a + b) / 2), rotation: turn,
                             scale: Vector3(width, 1, b - a), color: tint)
            }
            if let band = Penetrable.paint[i] {
                painted.append(piece(band.lowerBound, band.upperBound, Color(white: shade)))
                bare.append(piece(0, band.lowerBound, nil))
                bare.append(piece(band.upperBound, Penetrable.length, nil))
            } else {
                bare.append(piece(0, Penetrable.length, nil))
            }
        }
        // A flat strip has no round side for a light to model, so the tubes
        // take their colors as painted.
        withoutLights {
            fill(Penetrable.yellow)
            drawMesh(strip, instances: painted)
            fill(Penetrable.clear.withAlpha(haze))
            drawMesh(strip, instances: bare)
        }
    }

    /// The turn that lays a strip's width along `across`, its face along
    /// `facing`, and its length along `along` (three perpendicular unit
    /// vectors, `across` x `facing` = `along`).
    static func rotation(across x: Vector3, facing y: Vector3, along z: Vector3) -> Rotation3D {
        let trace = x.x + y.y + z.z
        if trace > 0 {
            let s = (trace + 1).squareRoot() * 2
            return Rotation3D(x: (y.z - z.y) / s, y: (z.x - x.z) / s, z: (x.y - y.x) / s, w: s / 4)
        } else if x.x > y.y && x.x > z.z {
            let s = (1 + x.x - y.y - z.z).squareRoot() * 2
            return Rotation3D(x: s / 4, y: (y.x + x.y) / s, z: (z.x + x.z) / s, w: (y.z - z.y) / s)
        } else if y.y > z.z {
            let s = (1 + y.y - x.x - z.z).squareRoot() * 2
            return Rotation3D(x: (y.x + x.y) / s, y: s / 4, z: (z.y + y.z) / s, w: (z.x - x.z) / s)
        } else {
            let s = (1 + z.z - x.x - y.y).squareRoot() * 2
            return Rotation3D(x: (z.x + x.z) / s, y: (z.y + y.z) / s, z: s / 4, w: (x.y - y.x) / s)
        }
    }

    /// A number in -1...1 fixed for each tube.
    static func jitter(_ i: Int) -> Double {
        var h = UInt64(i &+ 1) &* 0x9E37_79B9_7F4A_7C15
        h ^= h >> 31
        h = h &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 29
        return Double(h & 0xFFFF) / 32767.5 - 1
    }

    /// The aluminum frame the tubes hang from: its two sides and a beam
    /// across every meter and a half.
    private func drawFrame() {
        fill(Color(hex: 0xE2E4E6))
        let w = Penetrable.roomWidth, d = Penetrable.roomDepth, y = Penetrable.frameHeight + 0.05
        var beams: [MeshInstance] = []
        for x in [-w / 2, w / 2] {
            beams.append(MeshInstance(position: Vector3(x, y, 0), scale: Vector3(0.05, 0.07, d + 0.05)))
        }
        for k in 0 ... 8 {
            let z = -d / 2 + d * Double(k) / 8
            beams.append(MeshInstance(position: Vector3(0, y, z), scale: Vector3(w + 0.05, 0.07, 0.05)))
        }
        drawMesh(beam, instances: beams)
    }

    // MARK: - The plot

    /// Every tube as lines through the camera, the clear lengths gray and the
    /// painted ones yellow, and the visitor as a line with a ring at the hip.
    private func drawAsLines(_ walker: Vector2) {
        strokeWeight(0.35)
        for i in 0 ..< tiltX.count {
            if let band = Penetrable.paint[i] {
                stroke(Color(hex: 0xA7AEB2))
                drawLine(point(i, 0), point(i, band.lowerBound))
                drawLine(point(i, band.upperBound), point(i, Penetrable.length))
                stroke(Penetrable.yellow)
                drawLine(point(i, band.lowerBound), point(i, band.upperBound))
            } else {
                stroke(Color(hex: 0xA7AEB2))
                drawLine(point(i, 0), point(i, Penetrable.length))
            }
        }
        stroke(Color(hex: 0x2B2D33))
        strokeWeight(1.2)
        drawLine(Vector3(walker.x, 0, walker.y), Vector3(walker.x, Penetrable.bodyHeight, walker.y))
        let ring = (0 ..< 48).map { k -> Vector3 in
            let a = 2 * Double.pi * Double(k) / 48
            return Vector3(walker.x + cos(a) * reach / 100, Penetrable.hip, walker.y + sin(a) * reach / 100)
        }
        drawPolyline(ring, closed: true)
    }
}
