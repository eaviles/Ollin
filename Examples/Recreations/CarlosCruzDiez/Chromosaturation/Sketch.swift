//  Recreation after Carlos Cruz-Diez - the Chromosaturation (conceived 1965,
//  first shown at the Cinétique exhibition in Grenoble in 1968, and built
//  for the street at Place Henri Mondor, Paris, in 1969), read from the
//  Cruz-Diez Foundation's page on the series and from the Pérez Art Museum
//  Miami's account of its own (Paris, 1965/2007): three chambers, one red,
//  one green, and one blue, that a visitor walks through. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist, his
//  family, the Cruz-Diez Foundation, the Atelier Cruz-Diez, Articruz, or the
//  museums that hold the work.
//  https://cruz-diez.com/works/chromosaturation/
//  https://www.pamm.org/?p=37369
//
//  An original Ollin interpretation, written from the accounts of the work.
//  Nothing was ported: the rooms are built and lit here from the stated
//  idea, and the eye's adaptation is this sketch's own model of what the
//  accounts describe.

import Foundation
import Ollin

/// A *Chromosaturation* (Carlos Cruz-Diez, Paris). **Drag** to look around.
///
/// In 1965 he conceived a walk through three rooms, each flooded with one
/// color of light, red, green, or blue, with nothing in them but the light.
/// The retina is used to taking in a whole range of colors at once; a room
/// of one color overwhelms it, and as you walk from one room into the next
/// the eye, adapted to the color it just left, sees the new one more vividly
/// than it is. The foundation that keeps his work says the experience
/// "creates disturbances in the retina."
///
/// The rooms here are three chambers in a row, `chamberWidth` by
/// `chamberDepth` meters and `chamberHeight` high, white matte inside, each
/// lit by two panels of one color in its ceiling, with a doorway in each
/// partition and in both end walls. A visitor walks in at one end, through
/// the green, the red, and the blue, out the other end, and round the back
/// to come in again, at `pace` meters a second, and the camera is their
/// eyes. Where a room's light reaches through a doorway into the next, the
/// two colors meet on the floor and the walls.
///
/// The eye's adaptation is modeled and named. The light around the eye is
/// taken as the mix of the rooms' colors by where the eye stands, the night
/// outside, in linear light; each channel's gain heads for the inverse of
/// that channel's share, `adaptation` of the way from seeing the room as it
/// is to seeing it as white, and never past `maxGain`, which in a room this
/// pure is what holds it; it drifts there over `adaptationTime` seconds.
/// The gains multiply the finished frame, so a red room pales as you stand
/// in it, and the green one you step into next burns. `adaptedTo` is what
/// the eye brings in at the start of the walk.
///
/// `--export-svg` draws the plan: the three rooms in their colors, the
/// walls with their doorways, the lights, the walk, and where the visitor
/// is.
@main
final class Chromosaturation: Sketch {
    /// How fast the visitor walks, in meters a second; 0 stands still.
    @Param(0 ... 1.4, icon: "figure.walk") var pace = 0.7
    /// Where the walk begins, in meters along the loop from outside the
    /// near end.
    @Param(0 ... 40, icon: "figure.walk.departure") var start = 0.0
    /// One chamber, in meters.
    @Param(3 ... 6, icon: "arrow.left.and.right") var chamberWidth = 4.5
    @Param(3 ... 8, icon: "arrow.up.and.down") var chamberDepth = 6.0
    @Param(2.4 ... 4, icon: "arrow.up") var chamberHeight = 3.0
    /// How bright the light panels are.
    @Param(4 ... 60, icon: "sun.max") var brightness = 28.0
    /// How far the eye adapts toward seeing a room as white: 0 never, 1 all
    /// the way.
    @Param(0 ... 1, icon: "eye") var adaptation = 0.85
    /// How many seconds the eye takes to settle most of the way.
    @Param(1 ... 30, icon: "timer") var adaptationTime = 10.0
    /// The most a channel is ever lifted by.
    @Param(1 ... 12, icon: "arrow.up.to.line") var maxGain = 8.0
    /// What the eye is adapted to when the walk begins: nothing, or one of
    /// the rooms it has just left.
    @Param(icon: "eye.circle") var adaptedTo = Eye.fresh

    enum Eye: String, CaseIterable, ParamOption { case fresh, green, red, blue }

    override var canvasSize: CanvasSize { .square(1080) }
    /// One lap of the walk.
    override var loopDuration: Double? { pace > 0 ? path.length / pace : nil }

    nonisolated static let chambers = 3
    /// The light in each room, in walking order.
    nonisolated static let colors = [Color(red: 0.1, green: 1, blue: 0.14),
                         Color(red: 1, green: 0.08, blue: 0.06),
                         Color(red: 0.12, green: 0.2, blue: 1)]
    nonisolated static let night = Color(red: 0.22, green: 0.24, blue: 0.3)
    /// The doorways, in meters.
    nonisolated static let doorWidth = 1.4
    nonisolated static let doorHeight = 2.3
    nonisolated static let wallThickness = 0.12
    nonisolated static let eyeHeight = 1.62

    // MARK: - The walk

    /// The visitor's loop: in through the near end, through the three rooms
    /// weaving a little but passing every doorway at its middle, out the far
    /// end, and round the back.
    struct Path {
        var points: [Vector2] = []
        var distances: [Double] = []
        var length = 0.0

        init(width: Double, depth: Double) {
            let w = width * Double(Chromosaturation.chambers)
            let back = -depth / 2 - 2.6
            var pts: [Vector2] = []
            for k in 0 ... 64 {
                let x = -3.5 + (w + 7) * Double(k) / 64
                let inside = x > 0 && x < w
                let z = inside ? 1.3 * sin(Double.pi * x / width) : 0
                pts.append(Vector2(x, z))
            }
            // Round the far corner, come back along the rear, round the
            // near corner.
            for k in 1 ..< 12 {
                let a = Double.pi / 2 * Double(k) / 12
                pts.append(Vector2(w + 3.5 + sin(a) * 2, (back + 2) / 2 * (1 - cos(a))))
            }
            pts.append(Vector2(w + 3.5, back))
            pts.append(Vector2(-3.5, back))
            for k in 1 ..< 12 {
                let a = Double.pi / 2 * Double(k) / 12
                pts.append(Vector2(-3.5 - sin(a) * 2, back * cos(a)))
            }
            points = pts
            distances = [0]
            for k in 1 ..< pts.count {
                distances.append(distances[k - 1] + (pts[k] - pts[k - 1]).length)
            }
            // Back to the start.
            distances.append(distances[distances.count - 1] + (pts[0] - pts[pts.count - 1]).length)
            length = distances[distances.count - 1]
        }

        /// The point and the heading `s` meters along the loop.
        func at(_ s: Double) -> (Vector2, Vector2) {
            var d = s.truncatingRemainder(dividingBy: length)
            if d < 0 { d += length }
            var lo = 0, hi = distances.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if distances[mid] <= d { lo = mid } else { hi = mid }
            }
            let a = points[lo], b = points[hi % points.count]
            let span = distances[hi] - distances[lo]
            let f = span > 0 ? (d - distances[lo]) / span : 0
            return (a + (b - a) * f, (b - a).normalized)
        }
    }

    private var path = Path(width: 4.5, depth: 6)
    private var pathFor = Vector2(4.5, 6)
    private var lookYaw = 0.0
    private var lookPitch = 0.0

    /// The eye's gain on each channel, and when it was last settled.
    private var gain = Vector3(1, 1, 1)
    private var adaptedAt = -1.0

    private let plane = Mesh.plane(width: 1, depth: 1, segments: 1)
    private let ground = Mesh.plane(width: 80, depth: 80)

    // MARK: - The run

    override func draw() {
        if pathFor != Vector2(chamberWidth, chamberDepth) {
            path = Path(width: chamberWidth, depth: chamberDepth)
            pathFor = Vector2(chamberWidth, chamberDepth)
        }
        let along = start + time * pace
        let (walker, heading) = path.at(along)
        let eye = Vector3(walker.x, Chromosaturation.eyeHeight, walker.y)
        adapt(at: eye)

        if isVectorExporting {
            drawPlan(walker, heading)
            return
        }
        look(from: eye, along: heading, at: along)
        background(Color(hex: 0x05060A))
        castShadows()
        // No fill: the rooms hold nothing but their own light, and a little
        // moon on the outside is kept out of them by their walls.
        directionalLight(Color(hex: 0x8FA3C8), direction: Vector3(-0.35, -0.75, -0.4), intensity: 0.35)
        lightTheRooms()

        noStroke()
        material(.matte)
        fill(Color(hex: 0x2C2D31))
        withState {
            translate(Double(Chromosaturation.chambers) * chamberWidth / 2, -0.01, 0)
            drawMesh(ground)
        }
        fill(Color(hex: 0xF4F3EF))
        drawMesh(plane, instances: walls())

        postProcess(.channelMixer(ColorMatrix(red: [gain.x, 0, 0, 0, 0],
                                              green: [0, gain.y, 0, 0, 0],
                                              blue: [0, 0, gain.z, 0, 0])))
        if !isExporting {
            drawText("drag to look around", width / 2, height - 26, size: 14,
                     color: Color(white: 1, alpha: 0.4), align: .center, .bottom)
        }
    }

    /// The visitor's eyes: along the walk, drifting toward the room's far
    /// wall and back as they go, and wherever a drag turns them.
    private func look(from eye: Vector3, along heading: Vector2, at along: Double) {
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
        let bob = Vector3(0, 0.012 * sin(stride), 0)
        var dir = Vector3(heading.x, 0, heading.y)
        // Inside, the eyes drift from the doorway ahead to the room's far
        // wall and back.
        let w = Double(Chromosaturation.chambers) * chamberWidth
        if eye.x > 0 && eye.x < w && abs(eye.z) < chamberDepth / 2 {
            let room = min(Chromosaturation.chambers - 1, max(0, Int(eye.x / chamberWidth)))
            let across = Vector3((Double(room) + 0.5) * chamberWidth - eye.x, 0.1, (eye.z > 0 ? -1 : 1) * chamberDepth / 2 - eye.z)
            let glance = 0.35 + 0.25 * sin(2 * Double.pi * along / 6.3)
            dir = (dir * (1 - glance) + across.normalized * glance).normalized
        }
        let yaw = atan2(dir.x, dir.z) + lookYaw
        let pitch = asin(max(-1, min(1, dir.y))) + lookPitch
        dir = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
        camera(.perspective(eye: eye + bob, target: eye + bob + dir * 5, fieldOfView: .degrees(68), near: 0.05, far: 120))
    }

    // MARK: - The rooms

    /// Two light panels in each room's ceiling, in the room's color.
    private func lightTheRooms() {
        for c in 0 ..< Chromosaturation.chambers {
            let x = (Double(c) + 0.5) * chamberWidth
            for z in [-chamberDepth / 4, chamberDepth / 4] {
                rectangleLight(Chromosaturation.colors[c], at: Vector3(x, chamberHeight - 0.03, z),
                               direction: Vector3(0, -1, 0), width: 1.2, height: 0.3, up: Vector3(1, 0, 0), isTwoSided: true,
                               intensity: brightness, reach: 3 * chamberWidth, castsShadow: true)
            }
        }
    }

    /// One wall: a plane turned to face `facing`, its width laid along
    /// `across` and its height along `along`, centered at `center`.
    private func wall(at center: Vector3, facing: Vector3, across: Vector3, width: Double, height: Double) -> MeshInstance {
        let along = across.cross(facing)
        return MeshInstance(position: center,
                            rotation: Chromosaturation.rotation(across: across, facing: facing, along: along),
                            scale: Vector3(width, 1, height))
    }

    /// Every wall of the three rooms, facing in, and the outside of the
    /// building, facing out. A wall with a doorway is two jambs and a lintel.
    private func walls() -> [MeshInstance] {
        var out: [MeshInstance] = []
        let w = chamberWidth, d = chamberDepth, h = chamberHeight
        let t = Chromosaturation.wallThickness / 2
        let n = Chromosaturation.chambers
        let total = Double(n) * w
        let right = Vector3(1, 0, 0), up = Vector3(0, 1, 0), forward = Vector3(0, 0, 1)

        for c in 0 ..< n {
            let x0 = Double(c) * w, x1 = x0 + w, xm = x0 + w / 2
            // Floor and ceiling.
            out.append(wall(at: Vector3(xm, 0, 0), facing: up, across: right, width: w, height: d))
            out.append(wall(at: Vector3(xm, h, 0), facing: -up, across: right, width: w, height: d))
            // The long walls, inside.
            out.append(wall(at: Vector3(xm, h / 2, -d / 2 + t), facing: forward, across: right, width: w, height: h))
            out.append(wall(at: Vector3(xm, h / 2, d / 2 - t), facing: -forward, across: -right, width: w, height: h))
            // The wall with a doorway at each end of the room, facing in.
            out += doorway(x: x0 + t, facing: right)
            out += doorway(x: x1 - t, facing: -right)
        }
        // The outside: the two end walls with their doorways, the long
        // walls, and the roof.
        out += doorway(x: -t, facing: -right)
        out += doorway(x: total + t, facing: right)
        out.append(wall(at: Vector3(total / 2, h / 2, -d / 2 - t), facing: -forward, across: -right, width: total, height: h))
        out.append(wall(at: Vector3(total / 2, h / 2, d / 2 + t), facing: forward, across: right, width: total, height: h))
        out.append(wall(at: Vector3(total / 2, h + 2 * t, 0), facing: up, across: right, width: total + 4 * t, height: d + 4 * t))
        return out
    }

    /// A wall across the rooms at `x` with the doorway in its middle: two
    /// jambs the full height and a lintel over the door.
    private func doorway(x: Double, facing: Vector3) -> [MeshInstance] {
        let d = chamberDepth, h = chamberHeight
        let dw = Chromosaturation.doorWidth, dh = Chromosaturation.doorHeight
        // The wall's width runs along z; which way depends on which side
        // faces in, so the plane is never turned inside out.
        let across = Vector3(0, 0, facing.x > 0 ? -1 : 1)
        let jamb = (d - dw) / 2
        return [
            wall(at: Vector3(x, h / 2, -d / 2 + jamb / 2), facing: facing, across: across, width: jamb, height: h),
            wall(at: Vector3(x, h / 2, d / 2 - jamb / 2), facing: facing, across: across, width: jamb, height: h),
            wall(at: Vector3(x, (dh + h) / 2, 0), facing: facing, across: across, width: dw, height: h - dh),
        ]
    }

    // MARK: - The eye

    /// One room's light as the eye reads it, in linear light, which is what
    /// the walls reflect and what the gains multiply.
    nonisolated static func light(_ room: Int) -> Vector3 {
        let color = colors[room]
        return Vector3(Color.srgbToLinear(color.red), Color.srgbToLinear(color.green), Color.srgbToLinear(color.blue))
    }

    /// The light around the eye: the rooms' colors by how much of the eye's
    /// surroundings each fills, and the night where the rooms are not.
    func surroundings(at eye: Vector3) -> Vector3 {
        let w = chamberWidth
        var sum = Vector3(0, 0, 0)
        var covered = 0.0
        if abs(eye.z) < chamberDepth / 2 {
            for c in 0 ..< Chromosaturation.chambers {
                let m = max(0, 1 - abs(eye.x - (Double(c) + 0.5) * w) / w)
                sum = sum + Chromosaturation.light(c) * m
                covered += m
            }
        }
        covered = min(1, covered)
        let night = Chromosaturation.night
        return sum + Vector3(Color.srgbToLinear(night.red), Color.srgbToLinear(night.green), Color.srgbToLinear(night.blue)) * (1 - covered)
    }

    /// Where the eye's gains are heading: each channel's inverse share of
    /// the light, `adaptation` of the way, and never past `maxGain`.
    func targetGain(for light: Vector3) -> Vector3 {
        let peak = max(light.x, max(light.y, light.z), 1e-6)
        func one(_ v: Double) -> Double {
            let full = 1 / max(v / peak, 0.02)
            return min(maxGain, max(1, 1 + adaptation * (full - 1)))
        }
        return Vector3(one(light.x), one(light.y), one(light.z))
    }

    /// Drifts the gains toward their target over `adaptationTime`, settling
    /// most of the way in that time.
    private func adapt(at eye: Vector3) {
        if adaptedAt < 0 || time < adaptedAt {
            switch adaptedTo {
            case .fresh: gain = Vector3(1, 1, 1)
            case .green: gain = targetGain(for: Chromosaturation.light(0))
            case .red: gain = targetGain(for: Chromosaturation.light(1))
            case .blue: gain = targetGain(for: Chromosaturation.light(2))
            }
            adaptedAt = time
        }
        let dt = time - adaptedAt
        adaptedAt = time
        let target = targetGain(for: surroundings(at: eye))
        let k = 1 - exp(-3 * dt / adaptationTime)
        gain = gain + (target - gain) * k
    }

    // MARK: - The plan

    /// The rooms from above: each in its color, the walls with their
    /// doorways, the lights, the walk, and the visitor.
    private func drawPlan(_ walker: Vector2, _ heading: Vector2) {
        let w = chamberWidth, d = chamberDepth
        let total = Double(Chromosaturation.chambers) * w
        let s = min(900 / (total + 8), 700 / (d + 7))
        let origin = Vector2(width / 2 - (total / 2) * s, height / 2 + 0.6 * s)
        func p(_ x: Double, _ z: Double) -> Vector2 { origin + Vector2(x, -z) * s }

        background(Color(hex: 0x2C2D31))
        noStroke()
        for c in 0 ..< Chromosaturation.chambers {
            fill(Chromosaturation.colors[c].withAlpha(0.55))
            let a = p(Double(c) * w, -d / 2), b = p(Double(c + 1) * w, d / 2)
            drawRect(a.x, b.y, b.x - a.x, a.y - b.y)
        }
        // The lights.
        fill(Color(hex: 0xF4F3EF))
        for c in 0 ..< Chromosaturation.chambers {
            let x = (Double(c) + 0.5) * w
            for z in [-d / 4, d / 4] {
                let a = p(x - 0.6, z + 0.15), b = p(x + 0.6, z - 0.15)
                drawRect(a.x, a.y, b.x - a.x, b.y - a.y)
            }
        }
        // The walls, with gaps for the doorways.
        noFill()
        stroke(Color(hex: 0xF4F3EF))
        strokeWeight(3)
        strokeCap(.butt)
        drawLine(p(0, -d / 2), p(total, -d / 2))
        drawLine(p(0, d / 2), p(total, d / 2))
        let dw = Chromosaturation.doorWidth
        for c in 0 ... Chromosaturation.chambers {
            let x = Double(c) * w
            drawLine(p(x, -d / 2), p(x, -dw / 2))
            drawLine(p(x, dw / 2), p(x, d / 2))
        }
        // The walk, and the visitor on it.
        stroke(Color(white: 1, alpha: 0.5))
        strokeWeight(1.2)
        drawPolyline(path.points.map { p($0.x, $0.y) }, closed: true)
        noStroke()
        fill(Color(hex: 0xF4F3EF))
        let at = p(walker.x, walker.y)
        drawCircle(at.x, at.y, 0.22 * s)
        stroke(Color(hex: 0xF4F3EF))
        strokeWeight(2)
        drawLine(at, p(walker.x + heading.x * 0.7, walker.y + heading.y * 0.7))
    }

    /// The turn that lays a plane's width along `across`, its face along
    /// `facing`, and its depth along `along` (three perpendicular unit
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
}
