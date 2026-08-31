import Ollin
import Foundation

/// Play a scene file's authored animation: keyframe tracks posing named nodes.
/// Press **F** to swap the bundled glTF orrery for its USD twin, a kinetic
/// mobile, loaded through the very same `loadScene` call.
///
/// A loaded `Scene` carries the animations its file was authored with, each a
/// set of keyframe tracks over the nodes; a USD layer's xformOp timeSamples
/// load the same way, as one `SceneAnimation` for the layer's whole timeline,
/// each track bound to the exact prim that authored its samples. `apply(_:at:)`
/// samples one at a time of your choosing, driven by the sketch's own clock, so
/// playback speed, looping, and scrubbing all stay in the sketch's hands: here
/// the 8-second lap loops by wrapping `time` over its `duration`.
///
/// The bundled orrery (regenerate it with `Scripts/make-animated-scene.swift`)
/// exercises all three interpolation modes its format defines: the planet and
/// moon arms swing on spherically-blended rotation keys, the marker orb bobs on
/// an eased cubic spline, and the base pointer ticks through stepped positions.
/// The bundled mobile (regenerate it with
/// `Scripts/make-usd-animated-scene.swift`) exercises every authored form the
/// USD animation bake handles: a spinning beam carrying a counter-spinning
/// child, a bobbing sphere on translation keys, a gem tumbling on quaternion
/// keys, a pendulum ring swinging about its hanging point through the pivot
/// idiom, and a counterweight breathing on scale keys.
///
/// Point this at any animated scene by setting `OLLIN_SCENE` to its path; a
/// file with no animation just draws in its authored pose.
@main
final class AnimatedScene: Sketch {
    override var loopDuration: Double? { 8 }   // both files author an 8-second lap
    private var scene: Scene!
    /// True while the USD mobile hangs on stage; **F** flips the bundled files.
    private var showingUSD = false
    /// A scene of the user's own, from `OLLIN_SCENE`; the toggle stays out of its way.
    private var overridden = false

    override func setup() {
        if let path = ProcessInfo.processInfo.environment["OLLIN_SCENE"],
           let s = loadScene(path) {
            scene = s
            overridden = true
        } else {
            loadStage()
        }
    }

    /// Both formats come through the same call: only the file name changes.
    private func loadStage() {
        scene = showingUSD
            ? Scene(resource: "stage", withExtension: "usda", in: Bundle.module)
            : Scene(resource: "scene", withExtension: "gltf", in: Bundle.module)
    }

    override func keyPressed() {
        guard !overridden, key == "f" || key == "F" else { return }
        showingUSD.toggle()
        loadStage()
    }

    override func draw() {
        background(Color(hex: 0x0E1117))

        cameraControl(from: scene.camera ?? .orbiting(target: Vector3(0, 1, 0),
                                                      radius: 6, elevation: 0.3))
        ambientLight(Color(white: 0.2))
        for l in scene.lights { light(l) }
        castShadows()

        // Sample the authored animation on the sketch clock, wrapped over its
        // duration so it loops; a one-shot would just play `at: time` and hold.
        if let lap = scene.animations.first, lap.duration > 0 {
            scene.apply(lap, at: time.truncatingRemainder(dividingBy: lap.duration))
        }

        fill(.white)   // white fill shows each node's authored material color untouched
        drawScene(scene)

        let names = scene.animations.map { $0.name }.joined(separator: ", ")
        let clock = String(format: "%.1f", time.truncatingRemainder(dividingBy: 8))
        drawCaption("\(scene.name ?? "scene") · animation \"\(names)\" · \(clock) s"
                    + (overridden ? "" : " · F for the \(showingUSD ? "glTF" : "USD") twin"))
    }
}
