import Ollin
import Foundation

/// Play a USD file's authored transform animation on the sketch clock.
///
/// A USD scene's xformOp timeSamples load as a `SceneAnimation` (read by
/// Ollin's own parser; no platform importer carries them), one animation for
/// the layer's whole timeline, its tracks bound to nodes by name.
/// `apply(_:at:)` samples it at a time of your choosing, so speed, looping,
/// and scrubbing stay in the sketch's hands: here the 8-second lap loops by
/// wrapping `time` over its `duration`. The bundled kinetic mobile
/// (regenerate it with `Scripts/make-usd-animated-scene.swift`) exercises
/// every authored form the animation bake handles: a spinning beam carrying a
/// counter-spinning child, a bobbing sphere on translation keys, a gem
/// tumbling on quaternion keys, a pendulum ring swinging about its hanging
/// point through the pivot idiom, and a counterweight breathing on scale keys.
///
/// Point this at any animated USD file by setting `OLLIN_SCENE` to its path;
/// a file with no animation just draws in its authored pose.
@main
final class USDAnimatedScene: Sketch {
    override var loopDuration: Double? { 8 }   // the mobile's authored lap
    private var mobile: Scene!

    override func setup() {
        if let path = ProcessInfo.processInfo.environment["OLLIN_SCENE"],
           let s = loadScene(path) {
            mobile = s
        } else {
            mobile = Scene(resource: "stage", extension: "usda", in: Bundle.module)
        }
    }

    override func draw() {
        background(Color(hex: 0x11141A))

        camera(mobile.camera ?? .orbiting(target: Vector3(0, 1.6, 0), radius: 7, elevation: 0.2))
        ambientLight(Color(white: 0.2))
        for l in mobile.lights { light(l) }
        castShadows()

        // Sample the authored animation on the sketch clock, wrapped over its
        // duration so it loops; a one-shot would just play `at: time` and hold.
        if let lap = mobile.animations.first, lap.duration > 0 {
            mobile.apply(lap, at: time.truncatingRemainder(dividingBy: lap.duration))
        }

        fill(.white)   // white fill shows each node's authored material color untouched
        drawScene(mobile)

        drawCaption("\(mobile.name ?? "stage.usda") · USD timeSamples · \(String(format: "%.1f", time.truncatingRemainder(dividingBy: 8))) s")
    }
}
