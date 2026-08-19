// figure: frame=345
//
// Guide listing (Chapter 18): the driveable vehicle. A car accelerates down a
// straight, then turns hard with the hand brake on, and is caught with the back
// stepped out and the front wheels crossed up. The drive is scripted rather
// than typed, and there is no random anywhere, so the whole run replays.
import Ollin
import OllinPhysics

final class Joyride: Sketch {
    let world = World3D()
    var car: Vehicle3D!
    var crates: [Body3D] = []

    let palette: [Color] = [
        Color(hex: 0xE4572E), Color(hex: 0xF2A93B), Color(hex: 0x76B39D),
        Color(hex: 0x8D92E0),
    ]

    override func setup() {
        world.ground = 0

        // A line of markers round the outside of the corner, close enough to
        // clip one if the back comes round too far.
        for index in 0 ..< 7 {
            let angle = 0.34 + Double(index) / 6 * 0.62
            let crate = world.addBody(
                .box(width: 0.6, height: 0.6, depth: 0.6),
                at: Vector3(-17 + cos(angle) * 20, 0.31, 17.3 + sin(angle) * 20),
                density: 0.05, friction: 0.5)
            crate.userData = palette[index % palette.count]
            crates.append(crate)
        }

        // Front wheels steer, back wheels are driven and carry the hand brake:
        // the whole reason the back can be made to step out.
        let wheels = [
            Wheel3D.wheel(at: Vector3(0.8, -0.12, 1.3), radius: 0.38,
                          width: 0.3, steers: true),
            Wheel3D.wheel(at: Vector3(-0.8, -0.12, 1.3), radius: 0.38,
                          width: 0.3, steers: true),
            Wheel3D.wheel(at: Vector3(0.8, -0.12, -1.3), radius: 0.38,
                          width: 0.3, driven: true, handBrake: true),
            Wheel3D.wheel(at: Vector3(-0.8, -0.12, -1.3), radius: 0.38,
                          width: 0.3, driven: true, handBrake: true),
        ]
        for wheel in wheels {
            wheel.suspensionLength = 0.36
            wheel.suspensionTravel = 0.26
            wheel.suspensionFrequency = 1.6
        }
        car = world.addVehicle(.box(width: 1.7, height: 0.7, depth: 3.8),
                               at: Vector3(0, 0.9, -6), wheels: wheels,
                               mass: 1300, engineTorque: 520, topSpeed: 26)
        car.maxTilt = .pi / 3
    }

    override func draw() {
        background(Color(hex: 0x0C1119))
        environment(.sky(turbidity: 2.6, sunElevation: 0.8))
        lightingPreset(.standard)
        castShadows()
        perspective(eye: Vector3(10, 7.6, 18.6), target: Vector3(-1.8, 0.7, 26.2),
                    fieldOfView: .pi / 4.4)

        // The scripted drive: gas down the straight, then turn in hard with the
        // hand brake and let the back go.
        car.throttle = 1
        if frameCount > 285 {
            car.steering = 1
            car.handBrake = 1
        }
        world.step(dt: 1.0 / 60)

        // The floor: `world.ground` is a slab the world keeps out of `bodies`,
        // so the sketch draws its own.
        material(.dielectric(roughness: 0.95))
        fill(Color(hex: 0x6E7A6A))
        withState {
            translate(0, -0.06, 0)
            drawBox(width: 220, height: 0.12, depth: 220)
        }

        material(.dielectric(roughness: 0.5))
        for crate in crates {
            fill(crate.userData as? Color ?? .white)
            withBody(crate) { drawBox(width: 0.6, height: 0.6, depth: 0.6) }
        }

        drawCar()
    }

    /// A body, a cabin, and four wheels drawn wherever the suspension and the
    /// steering actually put them.
    func drawCar() {
        material(.dielectric(roughness: 0.3))
        fill(Color(hex: 0xE4572E))
        withBody(car.body) {
            drawBox(width: 1.7, height: 0.7, depth: 3.8)
            fill(Color(hex: 0x1D2430))
            withState {
                translate(0, 0.52, -0.2)
                drawBox(width: 1.42, height: 0.56, depth: 1.8)
            }
        }

        material(.dielectric(roughness: 0.7))
        for wheel in car.wheels {
            // A tire that is sliding rather than rolling lights up, which is
            // the one thing a driver wants to see.
            fill(Color.mix(Color(hex: 0x232B36), Color(hex: 0xF2A93B),
                           t: min(1, wheel.slip)))
            withWheel(wheel) {
                drawCylinder(radius: wheel.radius, height: wheel.width)
                fill(Color(hex: 0xB9AE9C))
                drawCylinder(radius: wheel.radius * 0.45, height: wheel.width * 1.06)
            }
        }
    }
}
