import Ollin
import Foundation

/// Play a USD file's skeletal animation and blend shapes on the sketch clock.
///
/// A USD scene's UsdSkel tier loads through Ollin's own parser (no platform
/// importer carries it): each Skeleton prim's joints become ordinary scene
/// nodes you can pose by name, skinned meshes bend through the shipped
/// deforming tier, and blend-shape weights ride the same animation the
/// transform tracks do, so `apply(_:at:)` plays the whole rig with no new
/// API. The bundled pond (regenerate it with
/// `Scripts/make-usd-skinned-scene.swift`) exercises the envelope: a sea
/// serpent swaying on a five-joint skinned chain (two blended influences per
/// point, a geometry bind transform) and a lotus breathing on two blend
/// shapes, one dense with normal offsets and one sparse, driven by an
/// animation bound with no skeleton at all.
///
/// Point this at any rigged USD file by setting `OLLIN_SCENE` to its path;
/// a file with no deformation just draws in its authored pose.
@main
final class USDSkinnedScene: Sketch {
    override var loopDuration: Double? { 8 }   // the pond's authored lap
    private var pond: Scene!

    override func setup() {
        if let path = ProcessInfo.processInfo.environment["OLLIN_SCENE"],
           let s = loadScene(path) {
            pond = s
        } else {
            pond = Scene(resource: "stage", withExtension: "usda", in: Bundle.module)
        }
    }

    override func draw() {
        background(Color(hex: 0x0D1218))

        cameraControl(from: pond.camera ?? .orbiting(target: Vector3(0, 0.8, 0),
                                                     radius: 6, elevation: 0.25))
        ambientLight(Color(white: 0.2))
        for l in pond.lights { light(l) }
        castShadows()

        // Sample the authored animation on the sketch clock, wrapped over its
        // duration so it loops: joint tracks pose the serpent's chain, the
        // weights track breathes the lotus.
        if let lap = pond.animations.first, lap.duration > 0 {
            pond.apply(lap, at: time.truncatingRemainder(dividingBy: lap.duration))
        }

        fill(.white)   // white fill shows each node's authored material color untouched
        drawScene(pond)

        drawCaption("\(pond.name ?? "stage.usda") · UsdSkel skins + blend shapes · \(String(format: "%.1f", time.truncatingRemainder(dividingBy: 8))) s")
    }
}
