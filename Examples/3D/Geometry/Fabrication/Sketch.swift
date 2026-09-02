import Foundation
import Ollin

/// A generated shape written out as something a 3D printer can build.
///
/// The knot is an ordinary `Mesh`: a curve swept into a tube. What makes it
/// printable is not how it looks but whether it closes. A printer has to work
/// out what is inside the surface and what is outside, and it can only do that
/// if every edge has a triangle on both sides of it. On screen an open surface
/// looks exactly as convincing as a closed one, which is why `printCheck()`
/// exists: turn `sealed` off and the tube's ends open up, the shape looks the
/// same from most angles, and the report underneath turns red.
///
/// Press S to write the knot as `.3mf`, `.stl`, and `.obj`. The size parameter is
/// the real one: the mesh is scaled so its longest side spans that many
/// millimeters, which is what the file records.
@main
final class Fabrication: Sketch {

    @Param(2 ... 7, icon: "circle.hexagonpath") var windings = 3.0
    @Param(2 ... 7, icon: "circle.circle") var turns = 2.0
    @Param(0.05 ... 0.35, icon: "circle.and.line.horizontal") var thickness = 0.16
    @Param(20 ... 120, icon: "ruler") var millimeters = 60.0
    @Param(icon: "shippingbox") var sealed = true

    /// Where the last save went, shown once it has happened.
    private var saved: String?

    override func keyPressed() {
        if key == "s" || key == "S" { save() }
    }

    override func draw() {
        background(Color(hex: 0x0A0D12))
        environment(.courtyard.lightingOnly())
        lightingPreset(.studio)
        cameraShowcase(.autoOrbit(period: 24), radius: 3.4, elevation: 0.35)

        let knot = sculpture()

        fill(Color(hex: 0xD8C08A))
        material(.metal(roughness: 0.28))
        drawMesh(knot)

        report(on: knot)
    }

    /// The shape itself: a (p, q) torus knot path, swept into a tube.
    ///
    /// `closed: true` joins the last ring of the tube back to the first, so the
    /// surface has no ends at all. With it off the tube stops where the path
    /// stops and stays open at both ends, which is the whole difference between
    /// a solid and a shell.
    private func sculpture() -> Mesh {
        let p = Int(windings.rounded())
        let q = Int(turns.rounded())
        let steps = 260
        var path: [Vector3] = []
        for i in 0 ..< steps {
            let t = Double(i) / Double(steps) * .tau
            let around = Double(p) * t, through = Double(q) * t
            let r = 2 + cos(through)
            path.append(Vector3(r * cos(around), sin(through), r * sin(around)) * 0.34)
        }
        return Mesh.tube(along: path, radius: thickness, sides: 18, closed: sealed)
    }

    /// The same examination the writers run, drawn where it can be read while
    /// the parameters move.
    private func report(on knot: Mesh) {
        let sized = knot.normalized(scale: millimeters)
        let check = sized.printCheck()
        let size = check.size

        withState {
            noStroke()
            textFont(OutlineFont.systemMedium)
            textSize(15 * scale)
            textAlign(.left, .top)

            let x = 34 * scale
            var y = 34 * scale
            let step = 22 * scale

            fill(.white)
            drawText("\(check.triangleCount) triangles, \(check.vertexCount) vertices", x, y)
            y += step
            drawText(String(format: "%.0f x %.0f x %.0f mm", size.x, size.y, size.z), x, y)
            y += step

            if check.isPrintable {
                fill(Color(hex: 0x7BD88F))
                drawText("closed and ready to print", x, y)
            } else {
                fill(Color(hex: 0xE8735A))
                for problem in check.problems {
                    drawText(problem, x, y)
                    y += step
                }
            }
        }

        drawCaption(saved ?? "S saves the knot as .3mf, .stl, and .obj")
    }

    /// Write the shape at the size the parameter asks for. `normalized(scale:)` is
    /// what turns model units into millimeters: it centers the mesh, which is
    /// where a build platform wants it, and fits its longest side.
    private func save() {
        let sized = sculpture().normalized(scale: millimeters)
        let folder = FileManager.default.temporaryDirectory
        for format in MeshFileFormat.allCases {
            let url = folder.appendingPathComponent("knot.\(format.fileExtension)")
            sized.write(to: url)
        }
        saved = "saved to \(folder.path)"
        print("Ollin: knot.3mf, knot.stl, and knot.obj written to \(folder.path)")
    }
}
