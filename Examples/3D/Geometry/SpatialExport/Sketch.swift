import Foundation
import Ollin

/// A sketch that leaves as a model instead of a picture.
///
/// Everything drawn here is ordinary 3D: a ring of shapes, each with its own
/// color and finish, under a camera and a light. Press S and the frame on
/// screen is written as a `.usdz`, the format Apple's platforms read without
/// being asked, so the piece can be opened from the Finder, sent in a message,
/// or stood on a real table at the size it says it is.
///
/// The two things worth watching are what carries and what does not. A mesh is
/// a surface, so it travels whole, with its transform, its color, and as much
/// of its finish as the format has a slot for. The floating dust is a point
/// cloud, which is not a surface at all, so it stays behind and says so once.
/// Turn `dust` off and the model is the same; the frame is not.
///
/// The size knob is the real one. A model file records how big one scene unit
/// is, and nothing here is scaled: at 1 the ring is meters across and fills a
/// room, at 0.05 it sits on a desk.
@main
final class SpatialExport: Sketch {

    @Param(3 ... 9, icon: "circle.hexagongrid") var pieces = 6.0
    @Param(0.01 ... 0.4, icon: "ruler") var metersPerUnit = 0.05
    @Param(icon: "sparkles") var dust = true

    /// Where the last save went, shown once it has happened.
    private var saved: String?

    override func keyPressed() {
        if key == "s" || key == "S" { save() }
    }

    override func draw() {
        background(Color(hex: 0x0B0E14))
        environment(.courtyard.lightingOnly())
        cameraShowcase(.autoOrbit(period: 30), radius: 7, elevation: 0.3)

        ring()
        if dust { motes() }

        drawCaption(saved ?? "S writes the frame as a .usdz you can open, send, or stand on a table")
    }

    /// The ring: one shape per piece, each with a color and a finish, placed
    /// by the transform stack. Every one of these becomes a node in the model,
    /// carrying the transform that put it there rather than being flattened
    /// into the pile.
    private func ring() {
        let count = Int(pieces.rounded())
        let shapes: [Mesh] = [.icosphere(radius: 0.5, subdivisions: 3),
                              .roundedBox(size: 0.85, radius: 0.18),
                              .torus(radius: 0.45, tube: 0.16),
                              .octahedron(radius: 0.62),
                              .capsule(radius: 0.26, height: 0.5),
                              .cone(radius: 0.45, height: 0.9)]

        for i in 0 ..< count {
            let t = Double(i) / Double(count)
            withState {
                rotateY(t * .tau)
                translate(2.4, sin(t * .tau * 2) * 0.35, 0)
                rotateY(time * 0.4 + t * 3)

                fill(Color(hue: t, saturation: 0.55, brightness: 0.95))
                // A physically-based finish maps straight across, since the
                // format describes a surface the same way Ollin's does. They
                // alternate because a metal has no color of its own: it shows
                // whatever is around it, which in AR is the actual room.
                material(i.isMultiple(of: 2)
                         ? .metal(roughness: 0.12 + t * 0.3)
                         : .dielectric(roughness: 0.3 + t * 0.4))
                drawMesh(shapes[i % shapes.count])
            }
        }

        // The floor is a mesh too, so it travels: a model that arrives with
        // something to stand on reads as a piece rather than a pile of parts.
        fill(Color(hex: 0x2A3140))
        material(.dielectric(roughness: 0.7))
        withState {
            translate(0, -0.9, 0)
            drawMesh(.cylinder(radius: 3.4, height: 0.08, segments: 64))
        }
    }

    /// Dust hanging in the air: a point cloud, which has no surface, so the
    /// export leaves it behind and says which frame it came from.
    private func motes() {
        var points: [PointCloud.Point] = []
        for i in 0 ..< 400 {
            let a = Double(i) * 2.399
            let r = 1.2 + fract(Double(i) * 0.618) * 2.6
            points.append(.init(position: Vector3(cos(a) * r,
                                                  sin(Double(i) * 0.37) * 1.6,
                                                  sin(a) * r),
                                color: .white.withAlpha(0.5), size: 0.02))
        }
        drawPointCloud(PointCloud(points: points))
    }

    /// Write what is on screen right now as a spatial model.
    ///
    /// `spatialScene(of:)` re-runs the sketch headlessly to this frame and
    /// collects its 3D draw calls as an ordinary `Scene`, so what gets written
    /// is a scene like any loaded one: readable, editable, and drawable again
    /// with `drawScene`.
    private func save() {
        let scene = OllinApp.spatialScene(of: SpatialExport(), frame: frameCount)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("piece.usdz")
        guard scene.write(to: url, metersPerUnit: metersPerUnit) else { return }
        saved = "saved to \(url.path)"
        print("Ollin: piece.usdz written to \(url.path)")
    }
}
