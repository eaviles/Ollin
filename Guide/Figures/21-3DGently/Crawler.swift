// figure: frame=150
//
// Guide listing (Chapter 21): a machine on tracks turning without steering.
// It drives up to the markers, then holds the throttle with the stick hard
// over, and the two bands run opposite ways: the warm one forward, the cool
// one back. It spins between the markers rather than driving between them.
// The run is scripted and there is no random anywhere, so it replays.
import Ollin
import OllinPhysics

final class Crawler: Sketch {
    let world = World3D()
    var crawler: Vehicle3D!
    var markers: [Body3D] = []
    var bandPhase: [Double] = [0, 0]

    let hull = Vector3(1.75, 0.85, 5.2)
    let wheelRadius = 0.44, wheelWidth = 0.6, trackX = 1.3

    override func setup() {
        world.ground = 0

        // A ring of markers to turn against: with the machine spinning between
        // them rather than driving past them, they are what says it stayed put.
        for index in 0 ..< 8 {
            let angle = Double(index) / 8 * .tau
            let post = world.addBody(.box(width: 0.5, height: 1.4, depth: 0.5),
                                     at: Vector3(cos(angle) * 5.6, 0.71,
                                                 sin(angle) * 5.6),
                                     kind: .static)
            post.userData = index % 2 == 0 ? Color(hex: 0x8D92E0)
                                           : Color(hex: 0x76B39D)
            markers.append(post)
        }

        // Ten road wheels, five to a band. Which side of the hull a wheel sits
        // on is what puts it on a band; there is no list to keep in order.
        var wheels: [Wheel3D] = []
        for side in [trackX, -trackX] {
            for i in 0 ..< 5 {
                let wheel = Wheel3D.wheel(at: Vector3(side, -0.28, -1.8 + Double(i) * 0.9),
                                          radius: wheelRadius, width: wheelWidth)
                wheel.suspensionLength = 0.4
                wheel.suspensionTravel = 0.28
                wheel.suspensionFrequency = 2
                wheels.append(wheel)
            }
        }
        crawler = world.addVehicle(.box(width: hull.x, height: hull.y, depth: hull.z),
                                   at: Vector3(0, 1.2, -3), wheels: wheels,
                                   mass: 4200, engineTorque: 520, topSpeed: 9,
                                   tracked: true)
        crawler.maxTilt = .pi / 3
    }

    override func draw() {
        background(Color(hex: 0x0C1119))
        environment(.sky(turbidity: 2.4, sunElevation: 0.62).rotated(2.2))
        lightingPreset(.standard)
        castShadows()
        perspective(eye: Vector3(4.5, 16, -8), target: Vector3(0, 0.3, -0.6),
                    fieldOfView: .pi / 4.4)

        // Drive up to the middle, then hold the throttle with the stick hard
        // over. Steering is not an angle here: full lock runs the inside band
        // backwards, and the machine turns where it stands.
        crawler.throttle = 1
        if frameCount > 60 { crawler.steering = 1 }
        world.step(dt: 1.0 / 60)
        bandPhase[0] += crawler.trackSpeed(.left) / 60
        bandPhase[1] += crawler.trackSpeed(.right) / 60

        material(.dielectric(roughness: 0.95))
        fill(Color(hex: 0x9B927E))
        withState {
            translate(0, -0.06, 0)
            drawBox(width: 200, height: 0.12, depth: 200)
        }

        material(.dielectric(roughness: 0.5))
        for post in markers {
            fill(post.userData as? Color ?? .white)
            withBody(post) { drawBox(width: 0.5, height: 1.4, depth: 0.5) }
        }

        drawCrawler()
    }

    /// The hull, the road wheels, and a band of links around each five. Each
    /// band is colored by which way it is running, which is what makes a still
    /// picture of a turn readable: warm forward, cool back.
    func drawCrawler() {
        material(.dielectric(roughness: 0.35))
        fill(Color(hex: 0xE8A33D))
        withBody(crawler.body) {
            drawBox(width: hull.x, height: hull.y, depth: hull.z)
            fill(Color(hex: 0x2A3038))
            withState {
                translate(0, 0.6, -0.5)
                drawBox(width: 1.4, height: 0.55, depth: 1.9)
            }
        }

        material(.dielectric(roughness: 0.6))
        fill(Color(hex: 0x3A424C))
        for wheel in crawler.wheels {
            withWheel(wheel) {
                drawCylinder(radius: wheel.radius, height: wheel.width * 0.75)
            }
        }

        material(.dielectric(roughness: 0.75))
        for (index, side) in [Vehicle3D.TrackSide.left, .right].enumerated() {
            let running = crawler.trackSpeed(side)
            fill(running < 0 ? Color(hex: 0x3F6FA8) : Color(hex: 0xC4622A))
            drawBand(on: side, phase: bandPhase[index])
        }
    }

    /// A closed run of links around one band's road wheels: over their tops,
    /// round the rear, back along the ground, round the nose.
    func drawBand(on side: Vehicle3D.TrackSide, phase: Double) {
        let wheels = crawler.wheels(on: side)
        guard wheels.count >= 2 else { return }
        let up = crawler.up, forward = crawler.forward
        let radius = wheelRadius + 0.06

        var path: [Vector3] = []
        for wheel in wheels { path.append(wheel.center + up * radius) }
        path += arc(around: wheels[wheels.count - 1].center, from: up,
                    toward: forward * -1, radius: radius)
        for wheel in wheels.reversed() { path.append(wheel.center - up * radius) }
        path += arc(around: wheels[0].center, from: up * -1, toward: forward,
                    radius: radius)

        let pitch = 0.34
        var lengths: [Double] = [0]
        for i in 1 ... path.count {
            lengths.append(lengths[i - 1] + (path[i % path.count] - path[i - 1]).length)
        }
        let total = lengths[path.count]
        guard total > pitch else { return }
        var segment = 0
        for k in 0 ..< Int(total / pitch) {
            let along = (Double(k) * pitch + phase).truncatingRemainder(dividingBy: total)
            let at = along < 0 ? along + total : along
            while segment < path.count - 1, lengths[segment + 1] < at { segment += 1 }
            while segment > 0, lengths[segment] > at { segment -= 1 }
            let span = max(1e-6, lengths[segment + 1] - lengths[segment])
            let t = (at - lengths[segment]) / span
            let from = path[segment], to = path[(segment + 1) % path.count]
            withState {
                translate(from + (to - from) * t)
                let heading = (to - from).normalized
                rotate(atan2(heading.x, heading.z), axis: .unitY)
                rotate(-asin(max(-1, min(1, heading.y))), axis: .unitX)
                drawBox(width: wheelWidth, height: 0.1, depth: pitch * 0.82)
            }
        }
    }

    /// Points along a half turn from `from` through `toward`: the cap that
    /// wraps one end wheel.
    func arc(around center: Vector3, from: Vector3, toward: Vector3,
             radius: Double) -> [Vector3] {
        (1 ... 5).map { step in
            let angle = Double(step) * .pi / 6
            return center + (from * cos(angle) + toward * sin(angle)) * radius
        }
    }
}
