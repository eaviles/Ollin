import Ollin
import Foundation

/// Play a scene file's *deforming* animation: skins that bend meshes and morph
/// targets that blend them. Press **F** to swap the bundled glTF tidepool for
/// its USD twin, a pond, loaded through the very same `loadScene` call.
///
/// Rigid node tracks move whole objects; the deforming tier moves the vertices
/// themselves. A skin poses a mesh through a joint hierarchy (each vertex
/// blending up to four joints by weight), and morph targets displace vertices
/// between authored shapes, mixed by the node's `weights`. Both play through
/// the same `apply(_:at:)` used for rigid tracks, and `drawScene` poses
/// automatically, so nothing new is needed to draw them.
///
/// The bundled tidepool (regenerate it with `Scripts/make-skinned-scene.swift`)
/// sways three kelp blades on four-joint skins, a wave traveling up each, while
/// the anemone pulses on two morph targets: a puff that swells it and a ripple
/// that scallops its rim. Its `weights` are also just a node property: set
/// `scene["anemone"]?.weights = [1, 0]` by hand to pose a blend shape.
///
/// The bundled pond (regenerate it with `Scripts/make-usd-skinned-scene.swift`)
/// is the same tier from the USD side, whose UsdSkel leg runs on the project's
/// own parser (no platform importer carries it): each Skeleton prim's joints
/// become ordinary scene nodes you can pose by name, skinned meshes bend
/// through the shipped deforming tier, and blend-shape weights ride the same
/// animation the transform tracks do, so `apply(_:at:)` plays the whole rig
/// with no new API. It exercises the envelope: a sea serpent swaying on a
/// five-joint skinned chain (two blended influences per point, a geometry bind
/// transform) and a lotus breathing on two blend shapes, one dense with normal
/// offsets and one sparse, driven by an animation bound with no skeleton at
/// all.
///
/// Point this at any skinned or morphing scene by setting `OLLIN_SCENE` to its
/// path; a file with neither draws exactly as `AnimatedScene` would.
@main
final class SkinnedScene: Sketch {
    override var loopDuration: Double? { showingUSD ? 8 : 6 }   // each file's own lap
    private var scene: Scene!
    /// True while the USD pond is on stage; **F** flips the bundled files.
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
        background(Color(hex: 0x081016))

        cameraControl(from: scene.camera ?? .orbiting(target: Vector3(0, 0.6, 0),
                                                      radius: 5, elevation: 0.3))
        ambientLight(Color(white: 0.2))
        for l in scene.lights { light(l) }
        castShadows()

        // Sample the authored animation on the sketch clock, wrapped over its
        // duration so it loops; the skins and morphs pose along with it.
        var clock = ""
        if let sway = scene.animations.first, sway.duration > 0 {
            let at = time.truncatingRemainder(dividingBy: sway.duration)
            scene.apply(sway, at: at)
            clock = String(format: " · %.1f s", at)
        }

        fill(.white)   // white fill shows each node's authored material color untouched
        drawScene(scene)

        let what = showingUSD
            ? "UsdSkel skins + blend shapes"
            : "animation \"" + scene.animations.map { $0.name }.joined(separator: ", ") + "\""
        drawCaption("\(scene.name ?? "scene") · \(what)\(clock)"
                    + (overridden ? "" : " · F for the \(showingUSD ? "glTF" : "USD") twin"))
    }
}
