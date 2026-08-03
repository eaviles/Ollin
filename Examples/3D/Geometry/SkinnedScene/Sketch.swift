import Ollin
import Foundation

/// Play a scene file's *deforming* animation: skins that bend meshes and morph
/// targets that blend them.
///
/// Rigid node tracks move whole objects; the deforming tier moves the vertices
/// themselves. A skin poses a mesh through a joint hierarchy (each vertex
/// blending up to four joints by weight), and morph targets displace vertices
/// between authored shapes, mixed by the node's `weights`. Both play through
/// the same `apply(_:at:)` used for rigid tracks, and `drawScene` poses
/// automatically, so nothing new is needed to draw them. The bundled tidepool
/// (regenerate it with `Scripts/make-skinned-scene.swift`) sways three kelp
/// blades on four-joint skins, a wave traveling up each, while the anemone
/// pulses on two morph targets: a puff that swells it and a ripple that
/// scallops its rim. Its `weights` are also just a node property: set
/// `scene["anemone"]?.weights = [1, 0]` by hand to pose a blend shape.
///
/// Point this at any skinned or morphing glTF by setting `OLLIN_SCENE` to its
/// path; a file with neither draws exactly as `AnimatedScene` would.
@main
final class SkinnedScene: Sketch {
    override var loopDuration: Double? { 6 }   // the "sway" animation's period
    private var tidepool: Scene!

    override func setup() {
        if let path = ProcessInfo.processInfo.environment["OLLIN_SCENE"],
           let s = loadScene(path) {
            tidepool = s
        } else {
            tidepool = Scene(resource: "scene", extension: "gltf", in: Bundle.module)
        }
    }

    override func draw() {
        background(Color(hex: 0x081016))

        camera(tidepool.camera ?? .orbiting(target: Vector3(0, 0.6, 0), radius: 5, elevation: 0.3))
        for l in tidepool.lights { light(l) }
        castShadows()

        // Sample the authored animation on the sketch clock, wrapped over its
        // duration so it loops; the skins and morphs pose along with it.
        if let sway = tidepool.animations.first {
            tidepool.apply(sway, at: time.truncatingRemainder(dividingBy: sway.duration))
        }

        fill(.white)   // white fill shows each node's authored material color untouched
        drawScene(tidepool)

        let names = tidepool.animations.map { $0.name }.joined(separator: ", ")
        drawCaption("\(tidepool.name ?? "scene") · animation \"\(names)\" · \(String(format: "%.1f", time.truncatingRemainder(dividingBy: 6))) s")
    }
}
