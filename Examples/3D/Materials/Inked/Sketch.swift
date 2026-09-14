import Ollin

/// Ink on the edges, and a light that rides the camera.
///
/// A still life in the toon material with an ink line around every shape
/// (`outline(width:color:)`), the cartoon look. The line is drawn as an
/// inverted hull, the mesh once more pushed out along its normals with the
/// faces toward the eye culled, so only the rim past the silhouette shows; it
/// holds its width in pixels at any distance, like a pen, and a nearer shape
/// hides a farther one's line.
///
/// The `rig` parameter is the other half. A world-space rig turns the cel bands
/// with the world as the camera orbits, the way a sun would; the same rig read
/// `relativeTo(.camera)` keeps its key, fill, and rim placed around the eye, so
/// the bands stay put on each shape as the view goes round; and a `headlight()`
/// alone is the flat, even look of a flash. Drag to orbit, scroll to dolly.
@main
final class Inked: Sketch {

    enum Rig: CaseIterable, ParamOption {
        case worldSun, cameraRig, headlight
    }

    @Param(0 ... 8, group: "Ink") var lineWidth = 3.0
    @Param(group: "Ink") var ink = Color(white: 0.08)
    @Param(1 ... 8, group: "Ink") var bands = 3
    @Param(group: "Light") var rig: Rig = .cameraRig

    override func draw() {
        background(Color(hex: 0xF2EBDD))
        cameraShowcase(.autoOrbit(period: .tau / 0.18), target: Vector3(0, -0.2, 0), radius: 9,
                       elevation: 0.3, fieldOfView: .pi / 4)

        switch rig {
        case .worldSun:
            lightingPreset(.threePoint)
        case .cameraRig:
            lightingPreset(.threePoint.relativeTo(.camera))
        case .headlight:
            ambientLight(Color(white: 0.2))
            headlight(intensity: 0.9)
        }

        var toon = Material.toon
        toon.toonBands = Double(bands)
        material(toon)
        outline(width: lineWidth, color: ink)

        withState {
            translate(-2.4, -0.3, 0.3)
            fill(Color(hex: 0xE8553F))
            drawSphere(radius: 1.05, segments: 64, rings: 40)
        }
        withState {
            translate(0.1, 0, -0.4)
            rotateY(time * 0.25); rotateX(0.4)
            fill(Color(hex: 0x3F9BD9))
            drawBox(size: 1.5)
        }
        withState {
            translate(2.5, -0.4, 0.5)
            rotateX(1.05); rotateY(time * 0.35)
            fill(Color(hex: 0xC85BB5))
            drawTorus(radius: 0.75, tube: 0.32, segments: 64, sides: 32)
        }
        withState {
            translate(0.2, 1.7, 0.2)
            rotateY(time * 0.2); rotateZ(0.5)
            fill(Color(hex: 0xF0B429))
            drawTorusKnot(radius: 0.55, tube: 0.16)
        }
        withState {
            // The floor takes a matte finish and no line: a toon floor would
            // band, and the rig's highlight would land on it between the shapes.
            translate(0, -1.75, 0)
            material(.matte)
            noOutline()
            fill(Color(hex: 0xD9D0BC))
            drawPlane(width: 16, depth: 16)
        }
    }
}
