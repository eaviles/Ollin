import Ollin

/// Depth of field on a real 3D scene, defocused by the scene's **own** depth buffer.
///
/// Where `Effects/Defocus` hands `.defocus` a depth map you draw by hand, here the
/// depth comes for free: draw a 3D scene into a render target, and because meshes
/// land in it the target captures depth, exposed as `scene.depth`, a gray layer
/// (0 near … 1 far) the renderer fills from the scene's depth buffer. Feed that to
/// `.defocus` as the aux and the scene racks focus like a real lens.
///
/// ```swift
/// let scene = renderTarget()
/// withTarget(scene) { camera(...); drawSphere(...) }      // 3D → depth captured
/// let dof = scene.combined(with: scene.depth, .defocus(focus: ...))
/// drawImage(dof.image, 0, 0)
/// ```
///
/// `scene.depth` maps over the camera's `near`/`far`, so set them to bracket the
/// scene (good practice for depth precision anyway). Here a row of orbs recedes
/// from `z = +10` to `z = −18`, and the camera's `near: 5, far: 34` straddle them so
/// the focal plane sweeps the whole row. Drag horizontally to rack focus by hand;
/// left idle, it sweeps on its own. The blur carries near/far bokeh separation, so a
/// defocused near orb spreads softly over the sharp ones behind it.
@main
final class SceneDefocus: Sketch {

    override func draw() {
        // Rack the focal plane: drag across the canvas, or let it sweep.
        let focus = mouseIsPressed ? min(max(mouseX / width, 0), 1)
                                   : 0.5 + 0.45 * sin(time * 0.3)

        // The 3D scene, drawn into a render target. Drawing meshes into it turns on
        // depth capture (3D needs a depth buffer to occlude correctly), so `scene.depth`
        // becomes available below. A pure-2D target would carry no depth and cost nothing.
        let scene = renderTarget()
        withTarget(scene) {
            background(Color(hex: 0x0A0B12))
            // near/far bracket the orb row so the normalized depth spans 0…1 across it.
            perspective(eye: Vector3(0, 2.2, 18), target: Vector3(0, 0, -3),
                        fieldOfView: .pi / 4, near: 5, far: 34)

            let count = 9
            for i in 0 ..< count {
                let t = Double(i) / Double(count - 1)        // 0 nearest … 1 farthest
                let z = 10 - t * 28                          // +10 (near) … −18 (far)
                let x = sin(t * .tau * 1.5 + time * 0.25) * 4.2   // weave so none fully hides another
                withState {
                    translate(x, 0, z)
                    rotateY(time * 0.4 + Double(i))
                    fill(Color(hue: t * 0.8, saturation: 0.62, brightness: 1.0))
                    specular(0.5)
                    shininess(64)
                    drawSphere(radius: 1.7)
                }
            }
        }

        // Defocus the scene by its own depth. The band focus ± range stays sharp;
        // beyond it the blur grows toward maxBlur. `quality` sets the bokeh tap budget.
        let dof = scene.combined(with: scene.depth,
                                 .defocus(focus: focus, range: 0.05, maxBlur: 34))
        drawImage(dof.image, 0, 0)

        drawCaption("3D depth of field — focus \(String(format: "%.2f", focus)) (drag to rack)")
    }
}
