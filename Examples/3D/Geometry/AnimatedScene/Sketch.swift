import Ollin
import Foundation

/// Play a scene file's authored animation: keyframe tracks posing named nodes.
///
/// A loaded `Scene` carries the animations its file was authored with, each a
/// set of keyframe tracks over the nodes. `apply(_:at:)` samples one at a time
/// of your choosing, driven by the sketch's own clock, so playback speed,
/// looping, and scrubbing all stay in the sketch's hands: here the 8-second
/// "spin" loops by wrapping `time` over its `duration`. The bundled orrery
/// (regenerate it with `Scripts/make-animated-scene.swift`) exercises all three
/// interpolation modes the format defines: the planet and moon arms swing on
/// spherically-blended rotation keys, the marker orb bobs on an eased cubic
/// spline, and the base pointer ticks through stepped positions.
///
/// Point this at any animated glTF by setting `OLLIN_SCENE` to its path; a file
/// with no animation just draws in its authored pose.
@main
final class AnimatedScene: Sketch {
    override var loopDuration: Double? { 8 }   // the "spin" animation's period
    private var orrery: Scene!

    override func setup() {
        if let path = ProcessInfo.processInfo.environment["OLLIN_SCENE"],
           let s = loadScene(path) {
            orrery = s
        } else {
            orrery = Scene(resource: "scene", extension: "gltf", in: Bundle.module)
        }
    }

    override func draw() {
        background(Color(hex: 0x0E1117))

        cameraControl(from: orrery.camera ?? .orbiting(target: Vector3(0, 1, 0),
                                                       radius: 6, elevation: 0.3))
        for l in orrery.lights { light(l) }
        castShadows()

        // Sample the authored animation on the sketch clock, wrapped over its
        // duration so it loops; a one-shot would just play `at: time` and hold.
        if let spin = orrery.animations.first {
            orrery.apply(spin, at: time.truncatingRemainder(dividingBy: spin.duration))
        }

        fill(.white)   // white fill shows each node's authored material color untouched
        drawScene(orrery)

        let names = orrery.animations.map { $0.name }.joined(separator: ", ")
        drawCaption("\(orrery.name ?? "scene") · animation \"\(names)\" · \(String(format: "%.1f", time.truncatingRemainder(dividingBy: 8))) s")
    }
}
