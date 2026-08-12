import Foundation
import Ollin

/// A sketch that leaves as something you can look into.
///
/// The scene is built for depth rather than for a flat frame: a colonnade
/// running away from the camera, a slow subject turning at the middle of it,
/// and a wall far behind. Watch it on the screen and it is an ordinary 3D
/// sketch. Press S and it leaves as spatial video, which is the same motion
/// recorded from two eyes at once, and in a headset the colonnade has actual
/// distance in it.
///
/// The two knobs are the whole craft. `depth` scales how far apart the eyes
/// stand: at 1 they sit where Ollin puts them by default, far enough apart
/// that the wall at the back separates by one percent of the frame, which is
/// the figure a cinema grades to so that nothing ever asks a viewer's eyes to
/// point outward. Push it to 3 and the scene reads like a diorama seen by
/// someone thirty feet tall. `stage` moves the distance at which the two eyes
/// agree: whatever sits there lands on the screen, nearer things come out of
/// it, farther things sit behind it. Sliding it from the near pillars to the
/// back wall changes which part of the scene the viewer is looking *into*
/// rather than *out at*, and that is a composition decision, not a setting.
///
/// The near pillar is deliberately close. It is the one thing here that can be
/// made uncomfortable, and finding the point where it stops being pleasant is
/// the fastest way to learn what these two numbers do.
@main
final class SpatialVideo: Sketch {

    @Param(0.25 ... 3, icon: "eye") var depth = 1.0
    @Param(4 ... 26, icon: "scope") var stage = 12.0
    @Param(icon: "square.stack.3d.forward.dottedline") var colonnade = true

    /// What the export reads. Both numbers are in world units, and this scene
    /// is drawn in meters, so the file can say so with no conversion.
    override var stereoGeometry: StereoGeometry {
        StereoGeometry(interocular: derivedSpacing * depth, convergence: stage)
    }

    /// Ollin's own spacing for this shot, which `depth` then scales. Read back
    /// from the camera the same way the exporter reads it, so the knob is a
    /// multiple of the default rather than a number out of nowhere.
    private var derivedSpacing: Double {
        StereoGeometry(convergence: stage).resolved(for: shot).interocular
    }

    private var shot: Camera3D {
        .perspective(eye: Vector3(0, 1.6, 16), target: Vector3(0, 1.2, -6),
                     fieldOfView: .pi / 3, near: 0.2, far: 400)
    }

    private var saved: String?

    override func setup() {
        seed(7)
    }

    override func keyPressed() {
        if key == "s" || key == "S" { save() }
    }

    override func draw() {
        background(Color(hex: 0x090C13))
        camera(shot)
        environment(.sunset.lightingOnly())
        directionalLight(Color(hex: 0xFFF1D6), direction: Vector3(-0.4, -0.8, -0.5), intensity: 1.6)

        wall()
        if colonnade { pillars() }
        subject()
        floor()

        drawCaption("eyes \(String(format: "%.3f", stereoGeometry.interocular ?? 0)) m apart · "
                    + "screen at \(String(format: "%.1f", stage)) m", edge: .top)
        drawCaption(saved ?? "S writes two seconds of spatial video you can open on a headset")
    }

    /// The colonnade: the reason the scene has depth to record. Each pair of
    /// pillars is a fixed size at a growing distance, so the picture gives the
    /// eye a ladder of separations to read rather than one plane.
    private func pillars() {
        for i in 0 ..< 9 {
            let z = 9.0 - Double(i) * 4.5
            let shade = 0.55 - Double(i) * 0.04
            for side in [-1.0, 1.0] {
                withState {
                    translate(side * 3.1, 1.7, z)
                    fill(Color(white: shade))
                    material(.dielectric(roughness: 0.55))
                    drawMesh(.cylinder(radius: 0.34, height: 3.4, segments: 24))
                    translate(0, 1.85, 0)
                    drawMesh(.box(width: 1.0, height: 0.3, depth: 1.0))
                }
            }
        }
    }

    /// The subject, turning at the middle distance so there is something to
    /// watch that is neither the nearest thing nor the farthest.
    private func subject() {
        withState {
            translate(0, 1.5, -6)
            rotateY(time * 0.35)
            rotateX(sin(time * 0.23) * 0.35)
            fill(Color(hex: 0xE8B74F))
            material(.metal(roughness: 0.18))
            drawMesh(.torusKnot(p: 2, q: 3, radius: 1.1, tube: 0.3, segments: 220, sides: 22))
        }
    }

    /// The far wall, which is what the default eye spacing is measured against:
    /// it is the farthest thing in the shot, so it carries the most separation.
    private func wall() {
        withState {
            translate(0, 6, -46)
            fill(Color(hex: 0x1C2438))
            material(.dielectric(roughness: 0.85))
            drawMesh(.box(width: 70, height: 26, depth: 0.5))
        }
        for i in 0 ..< 60 {
            withState {
                translate(random(-30, 30), random(1, 12), -45.4)
                fill(Color(hue: random(0.05, 0.14), saturation: 0.5, brightness: random(0.5, 1)))
                material(.dielectric(roughness: 0.4))
                drawMesh(.box(width: random(0.3, 1.4), height: random(0.3, 1.0), depth: 0.2))
            }
        }
    }

    private func floor() {
        withState {
            translate(0, -0.1, -14)
            fill(Color(hex: 0x141A26))
            material(.dielectric(roughness: 0.7))
            drawMesh(.box(width: 60, height: 0.2, depth: 80))
        }
    }

    /// Write a short clip of this same sketch as spatial video.
    ///
    /// A fresh instance is exported rather than the one on screen, because a
    /// video is a run rather than a moment: it starts at its own frame zero and
    /// renders on a fixed clock, so the file is the same every time. The window
    /// stops for as long as that takes.
    private func save() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("piece.mov")
        let clip = SpatialVideo()
        clip.depth = depth
        clip.stage = stage
        clip.colonnade = colonnade
        OllinApp.exportSpatialVideo(clip, to: url.path, frames: 60, fps: 30)
        saved = "saved to \(url.path)"
    }
}
