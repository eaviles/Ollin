import Foundation

/// The file formats a `Mesh` can be written as for fabrication.
///
/// All three carry triangles and nothing else: no uvs, no vertex colors, no
/// material. That is the point. What a printer builds is the surface, and
/// keeping the writers to geometry keeps what comes out of them honest.
public enum MeshFileFormat: Sendable, CaseIterable {

    /// Binary STL. A flat list of triangles with their normals, no shared
    /// vertices, no units. It is the format every slicer reads, and the largest
    /// of the three for the same mesh, since each triangle repeats its corners.
    case stl

    /// Wavefront OBJ. Text, shared vertices, no units. Reads everywhere, and
    /// stays editable by hand.
    case obj

    /// 3MF. A compressed package carrying real units and an explicitly manifold
    /// mesh, so the model arrives at the printer at the size you meant. The one
    /// to reach for when the mesh is going to be built.
    case threeMF

    /// The lowercase file extension this format is written with.
    public var fileExtension: String {
        switch self {
        case .stl: "stl"
        case .obj: "obj"
        case .threeMF: "3mf"
        }
    }

    /// The format a file extension names, or `nil` for one none of them use.
    /// Case-insensitive, and a leading dot is fine.
    public init?(fileExtension: String) {
        let ext = fileExtension.hasPrefix(".")
            ? String(fileExtension.dropFirst()).lowercased()
            : fileExtension.lowercased()
        switch ext {
        case "stl": self = .stl
        case "obj": self = .obj
        case "3mf": self = .threeMF
        default: return nil
        }
    }
}

/// The physical unit one model unit stands for when a mesh is written for
/// fabrication.
///
/// A `Mesh` carries bare numbers; a printer needs a size. The unit says how to
/// read those numbers, so a cube two units across is 2 mm or 2 cm depending on
/// what you declare. Only 3MF records it in the file. STL and OBJ have nowhere
/// to put it, and are read as millimeters by nearly everything, which is why
/// that is the default here.
///
/// Scaling is a separate step, and `normalized(scale:)` is the tool: it
/// recenters the mesh on the origin (where a build platform wants it) and fits
/// its longest side to the size you ask for.
///
/// ```swift
/// sculpture.normalized(scale: 60).write(to: "sculpture.3mf")   // 60 mm across
/// ```
public enum ModelUnit: String, Sendable, CaseIterable {
    case micron, millimeter, centimeter, inch, foot, meter

    /// How many millimeters one of these is, so a check can report a physical
    /// size whatever unit the mesh is declared in.
    public var millimeters: Double {
        switch self {
        case .micron: 0.001
        case .millimeter: 1
        case .centimeter: 10
        case .inch: 25.4
        case .foot: 304.8
        case .meter: 1000
        }
    }
}

/// Which axis points up in the written file.
///
/// Ollin's world is y-up, and fabrication is z-up: a build platform is the xy
/// plane and height is z. So the writers rotate the mesh a quarter turn about x
/// on the way out by default, and a model that stood upright in the sketch
/// stands upright on the platform. `.y` writes the coordinates untouched, for
/// when a mesh is headed back into a graphics tool rather than onto a printer.
public enum UpAxis: Sendable {
    /// Ollin's own orientation, written verbatim.
    case y
    /// The fabrication convention: the mesh is rotated so its y becomes z.
    case z
}

// MARK: - Writing

public extension Mesh {

    /// This mesh encoded in `format`, ready to write or hand on. Returns `nil`
    /// only for a mesh with no triangles left to write.
    ///
    /// The mesh is prepared the same way for every format: coincident vertices
    /// are merged into one connected surface, degenerate triangles are dropped,
    /// the winding is settled against the mesh's own normals, and the whole
    /// thing is turned z-up unless you ask otherwise. See `write(to:)` for what
    /// each of those is for.
    func data(as format: MeshFileFormat, unit: ModelUnit = .millimeter,
              upAxis: UpAxis = .z) -> Data? {
        guard let prepared = FabricationMesh(self, upAxis: upAxis) else { return nil }
        switch format {
        case .stl: return prepared.stlData()
        case .obj: return prepared.objData()
        case .threeMF: return prepared.threeMFData(unit: unit)
        }
    }

    /// Write this mesh to `url` for fabrication, in the format its extension
    /// names (`.stl`, `.obj`, `.3mf`) or the one you pass. Returns whether it
    /// was written; a failure prints what went wrong rather than trapping, like
    /// the loaders.
    ///
    /// Four things happen to the geometry on the way out, each of which a mesh
    /// coming from a sketch needs:
    ///
    /// - **Vertices are merged.** Ollin's generators are flat-shaded, so every
    ///   triangle carries its own three corners and neighbors share no vertex
    ///   at all. A slicer reading that sees a pile of loose triangles rather
    ///   than a solid, so the writers merge coincident corners first.
    /// - **Degenerate triangles are dropped.** A triangle with no area is a
    ///   crack to anything trying to work out what is inside.
    /// - **The winding is settled against the mesh's own normals.** A surface
    ///   can be shaded from one side and wound from the other, and the writers
    ///   believe the normals, since that is the side you saw when you made it.
    ///   A mesh with no normals falls back to its signed volume: a closed
    ///   surface enclosing a negative volume is inside out.
    /// - **The mesh is turned z-up**, so it stands on the build platform the way
    ///   it stood in the sketch. Pass `upAxis: .y` to leave it alone.
    ///
    /// Size is yours to set, and `normalized(scale:)` is how: it centers the
    /// mesh and fits its longest side, so `normalized(scale: 60)` written as
    /// millimeters prints 60 mm across.
    ///
    /// ```swift
    /// let sculpture = blobs.mesh(resolution: 96)
    /// sculpture.normalized(scale: 60).write(to: "sculpture.3mf")
    /// ```
    ///
    /// A mesh a printer will refuse (one with holes, or wound inconsistently)
    /// is still written, with a note saying so. `printCheck()` is the same
    /// examination if you would rather ask before writing.
    @discardableResult
    func write(to url: URL, as format: MeshFileFormat? = nil,
               unit: ModelUnit = .millimeter, upAxis: UpAxis = .z) -> Bool {
        guard let format = format ?? MeshFileFormat(fileExtension: url.pathExtension) else {
            print("Ollin: don't know what format to write '\(url.lastPathComponent)' as. Use .stl, .obj, or .3mf, or pass one explicitly.")
            return false
        }
        guard let data = data(as: format, unit: unit, upAxis: upAxis) else {
            print("Ollin: nothing to write to '\(url.lastPathComponent)': the mesh has no triangles.")
            return false
        }
        let check = printCheck(upAxis: upAxis)
        if !check.isPrintable {
            print("Ollin: writing '\(url.lastPathComponent)', which a printer may refuse: \(check.problems.joined(separator: "; ")).")
        }
        do {
            try data.write(to: url)
            return true
        } catch {
            print("Ollin: couldn't write '\(url.path)': \(error.localizedDescription)")
            return false
        }
    }

    /// Write this mesh to a file `path`. Sugar over `write(to:)`.
    @discardableResult
    func write(to path: String, as format: MeshFileFormat? = nil,
               unit: ModelUnit = .millimeter, upAxis: UpAxis = .z) -> Bool {
        write(to: URL(fileURLWithPath: path), as: format, unit: unit, upAxis: upAxis)
    }
}

public extension Sketch {

    /// Write `mesh` to a file for fabrication, in the format the extension names
    /// (`.stl`, `.obj`, `.3mf`). Sugar over `Mesh.write(to:)`, the writing
    /// counterpart of `loadMesh`.
    ///
    /// ```swift
    /// saveMesh(sculpture.normalized(scale: 60), to: "sculpture.3mf")
    /// ```
    @discardableResult
    func saveMesh(_ mesh: Mesh, to path: String, as format: MeshFileFormat? = nil,
                  unit: ModelUnit = .millimeter, upAxis: UpAxis = .z) -> Bool {
        mesh.write(to: path, as: format, unit: unit, upAxis: upAxis)
    }
}

// MARK: - The prepared mesh

/// A mesh put in the shape a fabrication file wants: welded into one connected
/// surface, degenerates gone, wound outward, and oriented for the platform.
///
/// All three writers share it, so an STL and a 3MF of the same mesh describe the
/// same solid rather than each format's own idea of it.
struct FabricationMesh {

    /// Distinct vertex positions, already in the written orientation.
    let positions: [Vector3]
    /// Triangle corners as indices into `positions`, three per triangle.
    let indices: [UInt32]

    var triangleCount: Int { indices.count / 3 }

    /// Prepare `mesh`, or fail if nothing survives (no triangles, or every one
    /// of them degenerate).
    init?(_ mesh: Mesh, upAxis: UpAxis) {
        guard !mesh.isEmpty else { return nil }
        let welded = mesh.welded()
        guard welded.indices.count >= 3 else { return nil }

        var positions = welded.positions
        var indices = welded.indices

        if FabricationMesh.isReversed(mesh: mesh, welded: welded) {
            // Flip every triangle together, so the surface stays consistently
            // wound however it was handed to us.
            for t in stride(from: 0, to: indices.count, by: 3) {
                indices.swapAt(t + 1, t + 2)
            }
        }

        if upAxis == .z {
            // A quarter turn about x: y becomes up, z becomes depth. It is a
            // rotation, so winding and normals ride along untouched.
            positions = positions.map { Vector3($0.x, -$0.z, $0.y) }
        }

        self.positions = positions
        self.indices = indices
    }

    /// Whether the mesh is wound against the way it is shaded, so the writers
    /// should flip it.
    ///
    /// A surface can be lit from one side and wound from the other (building a
    /// mesh by extruding a profile is the usual way to end up there), and the
    /// normals are the side that was seen, so they win. Agreement is summed over
    /// the whole surface weighted by triangle area, so a few noisy normals
    /// cannot outvote the body of the mesh, and every triangle flips together or
    /// none does.
    ///
    /// With no normals to ask, a closed surface enclosing a negative volume is
    /// inside out, which is the only other unambiguous reading. An open one with
    /// no normals is left exactly as authored.
    private static func isReversed(mesh: Mesh, welded: MeshWelding) -> Bool {
        let positions = welded.positions
        let indices = welded.indices

        if !mesh.normals.isEmpty && mesh.normals.count == mesh.positions.count {
            // Gather each welded position's authored normal from the original
            // vertices that merged onto it.
            var authored = [Vector3](repeating: .zero, count: positions.count)
            for (original, target) in welded.remap.enumerated()
            where original < mesh.normals.count && target < authored.count {
                authored[target] += mesh.normals[original]
            }
            var agreement = 0.0
            for t in stride(from: 0, to: indices.count, by: 3) {
                let a = positions[Int(indices[t])]
                let b = positions[Int(indices[t + 1])]
                let c = positions[Int(indices[t + 2])]
                let face = (b - a).cross(c - a)
                guard face.lengthSquared > 0 else { continue }
                let said = authored[Int(indices[t])] + authored[Int(indices[t + 1])]
                    + authored[Int(indices[t + 2])]
                guard said.lengthSquared > 0 else { continue }
                let area = face.length * 0.5
                agreement += area * face.normalized.dot(said.normalized)
            }
            return agreement < 0
        }

        return signedVolume(positions: positions, indices: indices) < 0
    }

    /// The signed volume the triangles enclose, by the divergence theorem over
    /// the origin. Positive when the surface is wound outward, and meaningless
    /// unless it is closed, which is why only a closed mesh is judged by it.
    static func signedVolume(positions: [Vector3], indices: [UInt32]) -> Double {
        var total = 0.0
        for t in stride(from: 0, to: indices.count, by: 3) {
            let a = positions[Int(indices[t])]
            let b = positions[Int(indices[t + 1])]
            let c = positions[Int(indices[t + 2])]
            total += a.dot(b.cross(c))
        }
        return total / 6
    }
}

// MARK: - Binary STL

extension FabricationMesh {

    /// Binary STL: an 80-byte header, the triangle count, then 50 bytes per
    /// triangle holding a normal, three corners, and two spare bytes.
    func stlData() -> Data {
        var data = Data()
        data.reserveCapacity(84 + triangleCount * 50)

        // The header must not begin with "solid": a reader that sees that word
        // at the start of a file takes it for the text form and finds garbage.
        var header = Array("Ollin mesh export".utf8)
        header.append(contentsOf: [UInt8](repeating: 0, count: 80 - header.count))
        data.append(contentsOf: header)
        data.append(littleEndian: UInt32(triangleCount))

        for t in stride(from: 0, to: indices.count, by: 3) {
            let a = positions[Int(indices[t])]
            let b = positions[Int(indices[t + 1])]
            let c = positions[Int(indices[t + 2])]
            let normal = (b - a).cross(c - a).normalized
            for v in [normal, a, b, c] {
                data.append(littleEndian: Float(v.x))
                data.append(littleEndian: Float(v.y))
                data.append(littleEndian: Float(v.z))
            }
            data.append(littleEndian: UInt16(0))   // attribute byte count
        }
        return data
    }
}

// MARK: - Wavefront OBJ

extension FabricationMesh {

    /// OBJ: vertices, then faces indexing them 1-based.
    ///
    /// Geometry only, no normals. Every consumer works them out from the
    /// triangles, and writing them would mean either giving a merged corner one
    /// averaged normal (rounding off the very edges the merge just joined) or
    /// unpicking the shared vertices that make the mesh a solid.
    func objData() -> Data {
        var text = "# Ollin mesh export\n"
        text.reserveCapacity(positions.count * 32 + triangleCount * 24)
        for p in positions {
            text += "v \(number(p.x)) \(number(p.y)) \(number(p.z))\n"
        }
        for t in stride(from: 0, to: indices.count, by: 3) {
            text += "f \(indices[t] + 1) \(indices[t + 1] + 1) \(indices[t + 2] + 1)\n"
        }
        return Data(text.utf8)
    }
}

// MARK: - 3MF

extension FabricationMesh {

    /// 3MF: a package holding the model as XML, plus the two files that say what
    /// the package is.
    ///
    /// The mesh has to be manifold and wound counter-clockwise seen from
    /// outside, which is what the welding and the winding pass upstream leave
    /// it as, and a triangle's three corners have to be distinct, which is what
    /// dropping degenerates leaves true.
    func threeMFData(unit: ModelUnit) -> Data {
        var model = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="\(unit.rawValue)" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
         <resources>
          <object id="1" type="model">
           <mesh>
            <vertices>

        """
        model.reserveCapacity(positions.count * 48 + triangleCount * 40)
        for p in positions {
            model += "     <vertex x=\"\(number(p.x))\" y=\"\(number(p.y))\" z=\"\(number(p.z))\"/>\n"
        }
        model += "    </vertices>\n    <triangles>\n"
        for t in stride(from: 0, to: indices.count, by: 3) {
            model += "     <triangle v1=\"\(indices[t])\" v2=\"\(indices[t + 1])\" v3=\"\(indices[t + 2])\"/>\n"
        }
        model += """
            </triangles>
           </mesh>
          </object>
         </resources>
         <build>
          <item objectid="1"/>
         </build>
        </model>

        """

        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
         <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
         <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
        </Types>

        """

        let rels = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
         <Relationship Id="rel0" Target="/3D/3dmodel.model" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
        </Relationships>

        """

        return ZipWriter.package([
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(rels.utf8)),
            ("3D/3dmodel.model", Data(model.utf8)),
        ])
    }
}

// MARK: - Number formatting

/// A coordinate written plainly: no exponent, no trailing zeros, and anything
/// under a ten-thousandth of a unit called zero (a hundred nanometers at
/// millimeter scale, well past anything that can be built).
private func number(_ value: Double) -> String {
    guard value.isFinite, abs(value) >= 1e-4 else { return "0" }
    var text = String(format: "%.6f", value)
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text.isEmpty ? "0" : text
}

// MARK: - Byte helpers

private extension Data {
    mutating func append(littleEndian value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
    mutating func append(littleEndian value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
    mutating func append(littleEndian value: Float) {
        Swift.withUnsafeBytes(of: value.bitPattern.littleEndian) { append(contentsOf: $0) }
    }
}
