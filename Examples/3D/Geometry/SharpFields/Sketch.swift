import Ollin

/// A field with corners, meshed so the corners stay.
///
/// `isosurface` turns a field into a `Mesh` by marching cubes: it reads the
/// field at the corners of a grid of cubes and puts a vertex on every edge the
/// surface crosses. A vertex can only sit on a grid edge, so a corner of the
/// field that falls inside a cube comes out as a bevel across it, and a
/// machined block reads as a pebble at any resolution you can afford.
///
/// `method: .dualContouring` puts one vertex in each cube instead, where the
/// field's own normals at the crossings say the surface is. Three faces meet
/// at a corner, so the vertex lands on the corner; two meet along an edge, so
/// it lands on the edge. The block here is a distance field with a hole bored
/// through it and a sphere bitten out of one corner, and `sharp` switches the
/// method under it. Turn `wireframe` on to see the cells: the same grid gives
/// both meshes, and only where the vertices sit differs. Push `bite` up until
/// the sphere nears the bore and the steps of the grid show along the strip
/// between them, then past 0.86 and the two curved surfaces meet at a knife
/// edge: a cube can hold a sliver of one surface without any of its edges
/// crossing the other, which is the one kind of crease the method reads by
/// the cell, and the one `detail` is for.
///
/// The mesh is rebuilt only when a parameter moves, since it is the kind of
/// work that belongs in `setup()`, and `detail` is where the cost lives.
@main
final class SharpFields: Sketch {
    @Param(icon: "cube") var sharp = true
    @Param(10 ... 64, icon: "square.grid.3x3") var detail = 22.0
    @Param(0 ... 0.9, icon: "circle.dashed") var bore = 0.55
    @Param(0 ... 1.4, icon: "circle.lefthalf.filled") var bite = 0.65
    @Param(icon: "grid") var wireframe = false

    private var mesh = Mesh(positions: [], indices: [])
    private var built = ""

    /// The block, the bore, and the bite, as one distance field with inside
    /// positive: a unit block minus a cylinder along z minus a sphere at a corner.
    private func field(_ p: Vector3) -> Double {
        let q = Vector3(abs(p.x) - 1, abs(p.y) - 1, abs(p.z) - 1)
        let block = Vector3(max(q.x, 0), max(q.y, 0), max(q.z, 0)).length
            + min(max(q.x, max(q.y, q.z)), 0)
        let hole = (p.x * p.x + p.y * p.y).squareRoot() - bore
        let corner = (p - Vector3(1, 1, 1)).length - bite
        return -max(block, -hole, -corner)
    }

    override func draw() {
        background(Color(hex: 0x14171E))
        environment(.courtyard.rotated(time * 0.05).lightingOnly())
        lightingPreset(.studio)
        cameraShowcase(.autoOrbit(period: 24), radius: 5.2, elevation: 0.42)

        let key = "\(sharp) \(Int(detail)) \(bore) \(bite)"
        if key != built {
            let box = Box3(min: Vector3(-1.3, -1.3, -1.3), max: Vector3(1.3, 1.3, 1.3))
            mesh = isosurface(at: 0, in: box, resolution: Int(detail),
                              method: sharp ? .dualContouring : .marchingCubes,
                              field: field)
            built = key
        }

        fill(Color(hex: 0xD9C08A))
        material(.dielectric(roughness: 0.45))
        if wireframe {
            stroke(Color(hex: 0x8FA7C4))
            strokeWeight(1)
            self.wireframe()
        }
        drawMesh(mesh)
    }
}
