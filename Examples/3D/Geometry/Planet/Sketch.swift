import Ollin

/// A world made out of noise, then lit like any other solid.
///
/// Nothing here is loaded. On the first frame six compute kernels write the maps a
/// planet wears, into textures the sketch keeps: the elevation, and then, read off
/// it, the surface color, the relief, the finish that decides where the sun glints,
/// the lights of the cities, and the weather. They are made once. They are made
/// again only when a knob that shapes them moves, which is what `world` and
/// `cloudCover` do.
///
/// After that the frame is ordinary 3D. A sphere wears the maps, a second sphere a
/// hair above it carries the clouds, a third wider one carries the air, and one
/// directional light stands in for the sun.
///
/// What is not ordinary is that three of those go into layers of their own, and two
/// masks against the lit picture put them back. An emissive map would glow on the
/// day side too, where nobody would ever see a city, so the lights are kept only
/// where the lit planet is dark (`.mask(invert: true)`). A Fresnel rim is a view
/// angle and knows nothing about the sun, so the halo is kept only where the lit
/// planet is bright, read through a blurred copy of it so the daylight reaches a
/// little way past the edge. The terminator does the deciding both times, and it
/// costs two combines rather than a shader of our own.
///
/// Inspired by the procedural-planet piece in the vgpu example gallery (Vercel
/// Labs, MIT, https://github.com/vercel-labs/vgpu), read for which pieces are worth
/// having rather than for code: it is WGSL over WebGPU, and nothing in it transfers
/// as source. The fields here are written from the published techniques, the value
/// noise and fractal sums of https://thebookofshaders.com/13/ and the ridged
/// multifractal of F. Kenton Musgrave's terrain basis, both already in Ollin's
/// shader library and credited in ATTRIBUTION.md.

/// Map size. The visible half of the world is half of this, laid across about 700
/// pixels, so the surface arrives at roughly two texels a pixel. A GPU-written
/// texture has no mip chain under it, so going much wider buys detail the screen
/// cannot show and pays for it at every sample.
private let mapWidth = 2048, mapHeight = 1024

/// The weather is carried at half that. Cloud has no fine detail to lose.
private let cloudWidth = 1024, cloudHeight = 512

/// One of the bake kernels, from the `.metal` file beside this one.
private func kernel(_ entry: String) -> ComputeKernel? {
    ComputeKernel(entry: entry, resource: "planet", in: .module)
}

@main
final class Planet_Example: Sketch {

    // MARK: Knobs

    /// Which world. Every map is a function of this number, so changing it bakes
    /// a different planet.
    @Param(0 ... 9, icon: "globe.europe.africa") var world = 3
    /// How much of the sky holds cloud. Re-bakes the weather map.
    @Param(0 ... 1, icon: "cloud") var cloudCover = 0.66
    /// How bright the cities burn on the night side.
    @Param(0 ... 3, icon: "lightbulb") var cityGlow = 1.4
    /// How much air: the thin haze lying on the surface, and the halo standing off
    /// its edge, both of which are Fresnel rims.
    @Param(0 ... 2, icon: "circle.dashed") var haze = 1.0
    /// Turns per minute, near enough. Negative turns the other way.
    @Param(-2 ... 2, icon: "arrow.clockwise") var spin = 0.35

    // MARK: The maps

    /// The elevation, in red. Every other map is read off this one, which is why
    /// the coast is in the same place in all of them.
    private let heightMap = ComputeTexture(width: mapWidth, height: mapHeight)
    private let surfaceMap = ComputeTexture(width: mapWidth, height: mapHeight)
    private let reliefMap = ComputeTexture(width: mapWidth, height: mapHeight)
    private let finishMap = ComputeTexture(width: mapWidth, height: mapHeight)
    private let lightMap = ComputeTexture(width: mapWidth, height: mapHeight)
    private let cloudMap = ComputeTexture(width: cloudWidth, height: cloudHeight)
    private let cloudReliefMap = ComputeTexture(width: cloudWidth, height: cloudHeight)

    private let bakeHeight = kernel("planet_height")
    private let bakeSurface = kernel("planet_surface")
    private let bakeRelief = kernel("planet_relief")
    private let bakeFinish = kernel("planet_finish")
    private let bakeLights = kernel("planet_lights")
    private let bakeClouds = kernel("planet_clouds")
    private let starField = Shader(resource: "stars", in: .module)

    /// What the maps were last baked for, so a frame that changes nothing bakes
    /// nothing. `-1` is "never", which is what makes the first frame do the work.
    private var bakedWorld = -1
    private var bakedCover = -1.0

    // MARK: The bodies

    private var globe = Mesh(positions: [], normals: [], indices: [])
    private var cities = Mesh(positions: [], normals: [], indices: [])
    private var weather = Mesh(positions: [], normals: [], indices: [])
    private var air = Mesh(positions: [], normals: [], indices: [])

    override func setup() {
        toneMap(.aces)

        let ball = Mesh.sphere(radius: 1, segments: 256, rings: 128)

        // The world itself: color, relief, and the finish that makes water shine
        // and ground stay matte.
        globe = ball
            .textured(surfaceMap.image)
            .normalMapped(reliefMap.image, scale: 1)
            .surfaceMapped(metallicRoughness: finishMap.image)

        // The same ball, black, carrying only the lights. Black takes no light of
        // its own, so this draws as the cities and nothing else.
        cities = ball.textured(lightMap.image, baseColor: .black)
        cities.material?.emissiveTexture = lightMap.image
        cities.material?.emissiveColor = .white

        // Cloud, a hair above the ground, its cover riding the texture's alpha
        // and its own relief read back off that cover, so a bank of it catches
        // the sun on one side the way a solid would.
        //
        // The hair is 3 parts in 1000, and that number is measured. A shell that
        // stands further off the body shows a band of itself past the body's edge,
        // and a triangle seen that nearly edge-on reads its map across a whole
        // triangle's worth of texels at once. With no mip chain to fall back on,
        // the band breaks into the mesh's own teeth. Halving the map does not help
        // and finer triangles only make finer teeth; keeping the overhang under a
        // pixel is what removes it.
        weather = Mesh.sphere(radius: 1.003, segments: 256, rings: 128)
            .textured(cloudMap.image)
            .normalMapped(cloudReliefMap.image, scale: 1)

        // The air, on a shell of its own: black everywhere but the limb, where a
        // Fresnel rim lights up. It is drawn into its own layer and added at the
        // canvas, which is what puts a glow OUTSIDE the planet's own edge.
        air = Mesh.sphere(radius: 1.028, segments: 128, rings: 64)
        air.material = MeshMaterial(baseColor: .black)
    }

    override func draw() {
        guard let bakeHeight, let bakeSurface, let bakeRelief, let bakeFinish,
              let bakeLights, let bakeClouds else {
            background(.black)
            drawStatus("Planet needs its planet.metal file. Run the "
                       + "Example-3D-Geometry-Planet target.", style: .warning)
            return
        }

        // Bake, but only what is out of date. The height carries the seed, and
        // the four maps under it are read off the height.
        if bakedWorld != world {
            var seed = ComputeParams()
            seed.append(Float(world))
            compute(bakeHeight, writing: heightMap, params: seed)
            compute(bakeSurface, reading: heightMap, writing: surfaceMap, params: seed)

            var relief = ComputeParams()
            relief.append(Float(5.5))              // slope strength of the normal map
            relief.append(Float(0))                // read the elevation, in red
            compute(bakeRelief, reading: heightMap, writing: reliefMap, params: relief)
            compute(bakeFinish, reading: heightMap, writing: finishMap)
            compute(bakeLights, reading: heightMap, writing: lightMap, params: seed)

            bakedWorld = world
            bakedCover = -1                        // the weather carries the seed too
        }
        if bakedCover != cloudCover {
            var sky = ComputeParams()
            sky.append(Float(world))
            sky.append(Float(cloudCover))
            compute(bakeClouds, writing: cloudMap, params: sky)

            var cloudRelief = ComputeParams()
            cloudRelief.append(Float(3.0))
            cloudRelief.append(Float(1))           // read the cover, in alpha
            compute(bakeRelief, reading: cloudMap, writing: cloudReliefMap,
                    params: cloudRelief)
            bakedCover = cloudCover
        }

        background(.black)

        let turn = time * spin * 0.10
        let eye = Camera3D.perspective(eye: Vector3(0, 0.26, 3.55), target: .zero,
                                       fieldOfView: .pi / 4.6)

        // The sun comes from the side and a little behind, which is what puts a
        // terminator across the middle of the disc rather than lighting
        // everything the camera can see.
        //
        // The stars go INSIDE this layer, over an opaque black, so the layer holds
        // a whole picture rather than a cut-out of one: the mask below reads it,
        // and the glow is taken from it. Keeping a layer opaque is also the way to
        // stay clear of a sharp edge. An additive draw sums alpha as well as color,
        // so adding light inside a see-through layer can leave its alpha above 1,
        // and drawing that layer back then subtracts what is behind it. Light is
        // added at the canvas here, where the destination is already opaque.
        let scene = makeRenderTarget()
        withTarget(scene) {
            background(.black)
            drawImage(generate(starField).image, 0, 0)

            camera(eye)
            light(.directional(.white, direction: Vector3(-0.86, -0.36, -0.36),
                               intensity: 2.1, castsShadow: false))
            fill(.white)

            // The maps decide the finish per pixel, so the factors stay at 1. The
            // thin haze lying over the surface itself is a low rim, kept at a high
            // power so it stays near the edge; the halo outside the edge is the
            // shell below.
            var surface = Material.physicallyBased(metallic: 1, roughness: 1)
            surface.rim = 0.16 * haze
            surface.rimPower = 5.0
            surface.rimColor = Color(hex: 0x8FC0FF)
            material(surface)
            withState { rotateY(turn); drawMesh(globe) }

            material(.dielectric(roughness: 0.92))
            withState { rotateY(turn * 1.18); drawMesh(weather) }
        }

        // The cities, alone. Same camera, same turn, so they land on the world.
        let lights = makeRenderTarget()
        withTarget(lights) {
            camera(eye)
            fill(.white)
            material(Material())
            var lit = cities
            lit.material?.emissiveColor = Color(white: cityGlow)
            withState { rotateY(turn); drawMesh(lit) }
        }

        // The air, also alone: a shell a little wider than the world, black but
        // for its Fresnel rim. Black adds nothing, so adding this layer at the
        // canvas leaves a ring of light standing off the planet's own edge.
        let atmosphere = makeRenderTarget()
        withTarget(atmosphere) {
            camera(eye)
            fill(.white)
            var shell = Material()
            shell.rim = 0.42 * haze
            shell.rimPower = 4.0
            shell.rimColor = Color(hex: 0x6EA8FF)
            material(shell)
            drawMesh(air)
        }

        // Two masks, both against the lit picture, in opposite directions. The
        // cities are kept where it is dark. The halo is kept where it is bright,
        // read through a blurred copy so the daylight bleeds a little way past the
        // edge and the ring of air survives outside the disc while the night limb
        // stays dark. A rim is a view angle and knows nothing about the sun, so
        // this is what tells it where the sun is.
        let night = lights.combined(with: scene, .mask(channel: .luminance, invert: true))
        let daylight = scene.filtered(.gaussianBlur(radius: 30))
        let halo = atmosphere.combined(with: daylight, .mask(channel: .luminance))

        drawImage(scene.image, 0, 0)
        withState {
            blendMode(.add)
            drawImage(night.image, 0, 0)
            drawImage(halo.filtered(.gaussianBlur(radius: 4)).image, 0, 0)
            // The glow the eye expects around a lit limb, and around a city.
            drawImage(scene.filtered(.bloom(threshold: 0.80, amount: 0.5,
                                            radius: 46)).image, 0, 0)
            drawImage(night.filtered(.bloom(threshold: 0.12, amount: 0.7,
                                            radius: 14)).image, 0, 0)
        }

        drawCaption("A planet baked on the GPU: surface, relief, finish, lights, weather")
    }
}
