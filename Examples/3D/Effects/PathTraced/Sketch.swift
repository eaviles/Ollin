import Ollin

/// The path-traced export: tune the scene live, then render it offline.
///
/// The window shows this set through the ordinary raster pipeline, at full frame
/// rate, with every dial live. The *same sketch* exported with `--path-traced`
/// renders by tracing light paths instead: the panel's shadows soften with
/// distance, the floor picks up color bled from the spheres, every polished
/// surface mirrors the scene at any depth, the amber sphere turns to real solid
/// glass (light bends through it, its shadow glows amber instead of going black),
/// the glowing bar lights the set by its own surface, the hammered panel's
/// normal and roughness maps ride every traced hit (its relief ripples the
/// reflections), and the camera's aperture turns into a real thin-lens depth of
/// field (the raster view stays sharp; the lens is the traced camera's). That is
/// the whole workflow: the live window is the viewfinder, the flag is the film back.
///
///     swift run Example-3D-Effects-PathTraced                          # tune live
///     swift run Example-3D-Effects-PathTraced --export out.png --path-traced 512
///
/// The trace needs an Apple-silicon (ray-tracing) GPU; elsewhere the export falls
/// back to the raster pipeline with a note. Samples: 64 sketches the light in
/// seconds, 512 is clean, more is smoother still. `--pt-depth` caps the mirror
/// recursion (8 is plenty).
@main
final class PathTraced: Sketch {

    @Param(0...0.4, icon: "camera.aperture") var aperture = 0.12
    @Param(3...14, icon: "scope") var focusOn = 7.4

    /// A hammered-metal relief, built in code: a staggered grid of rounded dents
    /// baked into a normal map, with a matching metallic-roughness map that
    /// keeps the dent floors polished and roughens the flats between them.
    private static let hammered: (normal: Image, mr: Image) = {
        let size = 256
        let cells = 7.0
        func dent(_ u: Double, _ v: Double) -> Double {
            let row = (v * cells).rounded(.down)
            let ox = row.truncatingRemainder(dividingBy: 2) * 0.5
            var cu = (u * cells + ox).truncatingRemainder(dividingBy: 1) - 0.5
            let cv = (v * cells).truncatingRemainder(dividingBy: 1) - 0.5
            cu = abs(cu) > 0.5 ? cu - (cu > 0 ? 1 : -1) : cu
            let d = min((cu * cu + cv * cv).squareRoot() / 0.46, 1.0)
            let fall = 1 - d * d
            return fall * fall
        }
        var nBytes = [UInt8](); nBytes.reserveCapacity(size * size * 4)
        var mrBytes = [UInt8](); mrBytes.reserveCapacity(size * size * 4)
        let step = 1.0 / Double(size)
        for y in 0..<size {
            for x in 0..<size {
                let u = (Double(x) + 0.5) * step, v = (Double(y) + 0.5) * step
                let strength = 1.6
                let gu = (dent(u + step, v) - dent(u - step, v)) / (2 * step) * strength * step * cells
                let gv = (dent(u, v + step) - dent(u, v - step)) / (2 * step) * strength * step * cells
                let inv = 1 / (1 + gu * gu + gv * gv).squareRoot()
                nBytes.append(UInt8(((-gu * inv) * 0.5 + 0.5) * 255))
                nBytes.append(UInt8(((gv * inv) * 0.5 + 0.5) * 255))
                nBytes.append(UInt8((inv * 0.5 + 0.5) * 255))
                nBytes.append(255)
                // Dent floors polish toward 0.1 roughness; the flats brush out to 0.5.
                let rough = 0.5 - 0.4 * dent(u, v)
                mrBytes.append(0)
                mrBytes.append(UInt8(rough * 255))
                mrBytes.append(255)
                mrBytes.append(255)
            }
        }
        return (Image(width: size, height: size, premultipliedRGBA: nBytes)!,
                Image(width: size, height: size, premultipliedRGBA: mrBytes)!)
    }()

    override func draw() {
        background(Color(hex: 0x0B0C10))

        // The studio environment lights the set and fills mirror misses.
        environment(.studio.intensity(0.9))

        // A warm softbox from the left: the traced export samples its real surface,
        // so its shadows sharpen at contact and melt with distance.
        rectLight(Color(hue: 0.08, saturation: 0.35, brightness: 1.0),
                  at: Vector3(-3.4, 2.6, 1.4),
                  direction: Vector3(0.66, -0.6, -0.46),
                  width: 2.6, height: 1.8, intensity: 6)

        // The camera: a low viewpoint with a real aperture. `aperture` and
        // `focusDistance` are read by the path-traced export only; the live view
        // stays pinhole-sharp while you frame.
        var cam = Camera3D(eye: Vector3(sin(time * 0.1) * 1.4, 1.5, 8.6),
                           target: Vector3(0, 0.55, 0),
                           projection: .perspective(fieldOfView: .pi / 4.2))
        cam.aperture = aperture
        cam.focusDistance = focusOn
        camera(cam)

        // A glossy dark floor: the traced render shows true reflections of the row
        // and the color the spheres bleed onto it.
        withState {
            translate(0, -0.5, 0)
            fill(Color(white: 0.35))
            material(.metal(roughness: 0.12))
            drawBox(width: 24, height: 1, depth: 18)
        }

        // The row: chrome, colored gloss, solid amber glass, and matte side by
        // side, so one export shows the whole material range under one light. The
        // glass sphere is where the traced render pulls furthest ahead of the
        // window: the trace bends light through the body, tints it along the
        // interior path, and passes it on into the shadow. Each rests on the floor.
        let finishes: [(Color, Material)] = [
            (Color(white: 0.95), .metal(roughness: 0.04)),
            (Color(hue: 0.02, saturation: 0.75, brightness: 0.85), .dielectric(roughness: 0.08)),
            (Color(hue: 0.1, saturation: 0.4, brightness: 1.0),
             .glass(thickness: 1, attenuationColor: Color(hue: 0.09, saturation: 0.75, brightness: 0.9),
                    attenuationDistance: 0.9)),
            (Color(hue: 0.12, saturation: 0.6, brightness: 0.95), .dielectric(roughness: 0.5)),
            (Color(white: 0.85), Material())
        ]
        for (i, f) in finishes.enumerated() {
            withState {
                let x = -3.0 + Double(i) * 1.5
                translate(x, 0.75, Double(i % 2) * -1.3)
                fill(f.0)
                material(f.1)
                drawSphere(radius: 0.75)
            }
        }

        // A tall polished slab behind the row, catching the set in its face.
        withState {
            translate(3.4, 1.3, -2.8)
            rotateY(-0.35)
            fill(Color(white: 0.9))
            material(.metal(roughness: 0.05))
            drawBox(width: 1.4, height: 3.6, depth: 0.35)
        }

        // A hammered-copper relief panel on the left: its normal map dents the
        // shading and its metallic-roughness map polishes each dent's floor. The
        // traced export reads both maps at every hit, so the relief survives into
        // the floor's reflection and the light the panel bounces on the set.
        withState {
            translate(-4.2, 1.6, -2.2)
            rotateY(0.5)
            rotateX(.pi / 2)
            fill(Color(hue: 0.07, saturation: 0.55, brightness: 0.9))
            material(.physicallyBased(metallic: 1, roughness: 1))
            drawMesh(Mesh.plane(width: 2.8, depth: 2.8)
                .normalMapped(Self.hammered.normal)
                .surfaceMapped(metallicRoughness: Self.hammered.mr))
        }

        // A cool glowing bar floating at the right edge: an emissive mesh, so in
        // the traced render its own surface is a light. The trace samples it the
        // way it samples the softbox, so the glow reaches the floor and the
        // sphere row as smooth, soft-shadowed light rather than speckle.
        withState {
            translate(4.0, 0.5, 0.6)
            rotateZ(0.5 * .pi)
            var bar = Mesh.box(width: 0.24, height: 2.4, depth: 0.24)
            bar.material = MeshMaterial(emissiveFactor: Color(red: 1.4, green: 2.3, blue: 2.6))
            drawMesh(bar)
        }
    }
}
