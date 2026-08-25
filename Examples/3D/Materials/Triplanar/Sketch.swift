import Ollin

/// Triplanar projection: texture for meshes that have no uvs at all.
///
/// A marched metaball skin has no uv layout and no way to author one, so
/// `textured(_:)` has nothing to map through. `triplanarTextured(_:scale:)`
/// projects the picture flat along each of the three world axes instead and
/// blends the three reads by how squarely the surface faces each axis: every
/// part of any shape is covered, no unwrap, no seam line. A normal map rides
/// the same projection (no tangent basis needed), so the veins read as
/// engraved relief.
///
/// The projection is anchored to the *world*, and the blob makes that
/// visible: as it morphs, the surface flows *through* the standing pattern
/// like a form turning under falling light. The cairn shows the same anchor
/// from its good side: three separate boxes, drawn separately, continue one
/// another's pattern because they share the one projection. `tile` is the
/// size of one texture tile in world units; `relief` is the normal map's
/// strength. The maps are authored in setup from a vein function, no image
/// files.
@main
final class Triplanar: Sketch {

    @Param(0.4...3, icon: "squareshape.split.3x3") var tile = 1.1
    @Param(0...2, icon: "circle.grid.cross") var relief = 1.0

    var stone = Image(width: 1, height: 1, color: .white)
    var veins = Image(width: 1, height: 1, color: .white)
    var balls = Metaballs()

    /// The vein field: 0 in a vein's floor, 1 on open stone. Sine-warped
    /// bands raised to a sharp power, so the veins run thin, tile both ways,
    /// and every run is identical.
    func veinField(_ u: Double, _ v: Double) -> Double {
        let warp = 0.09 * sin(v * 2 * .tau) + 0.05 * sin(u * 3 * .tau + 1.7)
        let a = unipolar(sin((u * 3 + warp) * .tau))
        let b = unipolar(sin((v * 4 + 0.14 * sin(u * 2 * .tau) + 0.31) * .tau))
        return min(pow(a, 0.16), pow(b, 0.22))
    }

    func makeMaps() {
        let size = 256
        var color = [UInt8](repeating: 255, count: size * size * 4)
        var normal = [UInt8](repeating: 255, count: size * size * 4)
        let d = 1.0 / Double(size)
        for y in 0..<size {
            for x in 0..<size {
                let u = (Double(x) + 0.5) * d, v = (Double(y) + 0.5) * d
                let h = veinField(u, v)
                // Warm sand over darker seams.
                let t = 0.45 + 0.55 * h
                let i = (y * size + x) * 4
                color[i]     = UInt8(214 * t)
                color[i + 1] = UInt8(196 * t)
                color[i + 2] = UInt8(168 * t)
                // The veins engraved: slopes of the same field, green-up.
                let strength = 0.3
                let dx = (veinField(u + d, v) - veinField(u - d, v)) / (2 * d) * strength
                let dy = (veinField(u, v + d) - veinField(u, v - d)) / (2 * d) * strength
                let len = (dx * dx + dy * dy + 1).squareRoot()
                normal[i]     = UInt8((-dx / len * 0.5 + 0.5) * 255)
                normal[i + 1] = UInt8((dy / len * 0.5 + 0.5) * 255)
                normal[i + 2] = UInt8((1 / len * 0.5 + 0.5) * 255)
            }
        }
        stone = Image(width: size, height: size, premultipliedRGBA: color)!
        veins = Image(width: size, height: size, premultipliedRGBA: normal)!
    }

    override func setup() {
        makeMaps()
    }

    /// The morphing blob: three balls on slow circling paths.
    func blobMesh() -> Mesh {
        balls = Metaballs()
        let t = time * 0.35
        balls.add(at: Vector3(0.85 * sin(t), 0.4 * sin(t * 1.6), 0.3 * cos(t)), radius: 0.95)
        balls.add(at: Vector3(0.8 * cos(t * 0.8), 0.5 * cos(t * 1.2), 0.4 * sin(t * 0.9)),
                  radius: 0.75)
        balls.add(at: Vector3(0, 0.7 * sin(t * 0.7 + 2), 0.5 * cos(t * 1.4)), radius: 0.6)
        return balls.mesh(resolution: 52)
    }

    override func draw() {
        background(Color(hex: 0x10131A))
        cameraShowcase(.sway(amplitude: 0.16, period: 26), target: .zero, radius: 10.6,
                       elevation: 0.16, fieldOfView: .pi / 4)
        environment(.studio.intensity(0.9))
        directionalLight(Color(kelvin: 5200), direction: Vector3(-0.5, -0.6, -0.55),
                         intensity: 1.05)
        ambientLight(Color(white: 0.05))

        fill(.white)
        material(.dielectric(roughness: 0.65))

        // The hero: a no-uv marched skin wearing the stone.
        withState {
            translate(-2.1, 0.35, 0)
            drawMesh(blobMesh().triplanarTextured(stone, normal: veins, scale: tile,
                                                  normalScale: relief))
        }
        // The cairn: three separate boxes sharing one standing pattern.
        withState {
            translate(2.3, -0.4, 0)
            for (size, y) in [(Vector3(1.9, 0.8, 1.5), 0.0),
                              (Vector3(1.3, 0.7, 1.1), 0.75),
                              (Vector3(0.8, 0.6, 0.7), 1.4)] {
                withState {
                    translate(0, y, 0)
                    drawMesh(Mesh.box(width: size.x, height: size.y, depth: size.z)
                        .triplanarTextured(stone, normal: veins, scale: tile,
                                           normalScale: relief))
                }
            }
        }
        material(Material())
        drawLabels()
    }

    private func drawLabels() {
        withState {
            textFont(OutlineFont.system)
            textSize(26)
            textAlign(.center)
            noStroke()
            fill(Color(white: 0.55))
            for (name, x) in [("marched skin", -2.1), ("one pattern, three boxes", 2.3)] {
                if let p = project(Vector3(x, -1.7, 0)) {
                    drawText(name, at: p)
                }
            }
        }
    }
}
