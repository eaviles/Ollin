import Ollin

/// Scene inspection views: snap the camera to a known angle while building a scene.
///
/// The camera auto-orbits (and you can grab it with a drag), but the host's
/// **Camera menu** jumps it to a canonical view, the way a modeling tool's numpad
/// does: Reset (⌘0) returns to the opening framing, Front/Back/Left/Right/Top/
/// Bottom (⌘1–⌘6) look straight down each axis, and Isometric (⌘7) is the
/// three-quarter that shows all three axes at once. Each snap glides via the camera
/// rig, then hands back to the orbit.
///
/// The scene is three colored axis rods (X red, Y green, Z blue) around a neutral
/// block, so every view is unambiguous: Front looks down +Z (the blue rod points at
/// you), Right looks down +X (red), Top looks down from +Y (green).
@main
final class SceneViews: Sketch {

    override func draw() {
        background(Color(white: 0.11))
        cameraShowcase(.autoOrbit(period: 32), target: .zero, radius: 9,
                       elevation: 0.35, fieldOfView: .pi / 4)
        cameraAxis()        // the orientation widget: click an axis to snap the view
        groundGrid()        // a faint reference floor at y = 0

        lightingPreset(.threePoint)
        castShadows()

        // The floor that catches the shadows.
        withState {
            translate(0, -2.2, 0)
            fill(Color(white: 0.5)); specular(0.05)
            drawPlane(width: 16, depth: 16)
        }

        // A neutral block at the center, taller than wide so its own orientation
        // reads too.
        withState {
            fill(Color(white: 0.82)); specular(0.2)
            drawBox(width: 1.6, height: 2.2, depth: 1.1)
        }

        // The three positive axes as colored rods with a sphere cap, the universal
        // X-red / Y-green / Z-blue convention.
        axisRod(.x, .red)
        axisRod(.y, .green)
        axisRod(.z, .blue)

        // Top edge so it clears the orientation axis widget parked at bottom-center.
        drawCaption("Camera menu: Reset · Front · Back · Left · Right · Top · " +
                    "Bottom · Isometric    (or drag to orbit)", edge: .top)
    }

    private enum Axis { case x, y, z }

    /// Draw a rod of `length` from the origin along the positive `axis`, capped with
    /// a small sphere, in `color`.
    private func axisRod(_ axis: Axis, _ color: Color) {
        let length = 3.4
        let thick = 0.12
        let mid = length / 2
        withState {
            fill(color); specular(0.4)
            switch axis {
            case .x:
                withState { translate(mid, 0, 0); drawBox(width: length, height: thick, depth: thick) }
                withState { translate(length, 0, 0); drawSphere(radius: 0.26) }
            case .y:
                withState { translate(0, mid, 0); drawBox(width: thick, height: length, depth: thick) }
                withState { translate(0, length, 0); drawSphere(radius: 0.26) }
            case .z:
                withState { translate(0, 0, mid); drawBox(width: thick, height: thick, depth: length) }
                withState { translate(0, 0, length); drawSphere(radius: 0.26) }
            }
        }
    }
}
