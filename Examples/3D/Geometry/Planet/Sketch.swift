import Ollin

/// A world made out of noise, lit like any other solid, and seen through its own air.
///
/// Nothing here is loaded. On the first frame six compute kernels write the maps a
/// planet uses, into textures the sketch keeps: the elevation, and then, read off
/// it, the surface color, the relief, the finish that decides how the sun lies on
/// the sea, the lights of the cities, and the weather. They are made once. They are
/// made again only when a parameter that shapes them moves, which is what `world`
/// and `cloudCover` do. A seventh map is written every frame: the shadow the
/// weather throws on the ground, which moves as the world turns under the sun.
///
/// After that the frame is ordinary 3D. A sphere carries the maps, a second sphere
/// a hair above it carries the shadows, a third the clouds, and one directional
/// light stands in for the sun. The cities go into a layer of their own.
///
/// What is not ordinary is the last step. A shader of the sketch's own, `air.metal`,
/// reads those two layers and puts the atmosphere over them. It knows where the
/// camera and the sun are, so for every pixel it can follow the line of sight
/// through a shell of air and add up the sunlight scattered toward the camera
/// along it. That one sum is the blue veil over the day side, the bright limb, the
/// ring of air standing off the edge, and the dusk along the terminator, where the
/// light has come the long way through the air and arrives red. It also knows which
/// pixels the sun has set on, so it is what switches the cities on.
///
/// Inspired by the procedural-planet piece in the vgpu example gallery (Vercel
/// Labs, MIT, https://github.com/vercel-labs/vgpu), read for which pieces are worth
/// having rather than for code: it is WGSL over WebGPU, and nothing in it transfers
/// as source. The fields are written from the published techniques: fractal sums
/// of noise (https://thebookofshaders.com/13/) over the simplex noise in Ollin's
/// shader library, and the ridged multifractal of F. Kenton Musgrave's terrain
/// basis. The air follows Tomoyuki Nishita, Takao Sirai,
/// Katsumi Tadamura and Eihachiro Nakamae, "Display of the Earth Taking into
/// Account Atmospheric Scattering" (SIGGRAPH 1993), with the scattering figures
/// Eric Bruneton and Fabrice Neyret give in "Precomputed Atmospheric Scattering"
/// (2008), the ozone layer of Sébastien Hillaire's "A Scalable and Production
/// Ready Sky and Atmosphere Rendering Technique" (2020), and Sydney Chapman's
/// grazing-incidence function (1931) for the depth of air along a slanting path.
/// The roughness of the sea is the slope of wind-driven waves that Charles Cox and
/// Walter Munk measured from photographs of the sun's glitter (1954). All of it is
/// credited in ATTRIBUTION.md.

/// Map size. In the middle of the disc this lands about one texel to a pixel, so
/// a coast is as sharp as the screen can show it. A GPU-written texture has no mip
/// chain under it. What keeps the edge of the disc from shimmering is that the
/// squeeze there runs one way only, toward the edge, and the sampler averages
/// along that one direction.
private let mapWidth = 4096, mapHeight = 2048

/// The shadows are soft-edged and dark on dark, so they are carried at half that.
private let shadowWidth = 2048, shadowHeight = 1024

/// How high the weather stands above the ground, in planet radii. This is 3 parts
/// in 1000, and that number is measured. A shell that stands further off the body
/// shows a band of itself past the body's edge, and a triangle seen that nearly
/// edge-on reads its map across a whole triangle's worth of texels at once. With
/// no mip chain to fall back on, the band breaks into the mesh's own teeth.
/// Halving the map does not help and finer triangles only make finer teeth;
/// keeping the overhang near a pixel is what removes it.
private let cloudHeight = 0.003

/// How finely the spheres are cut. At 128 around, the outline stays within a
/// seventh of a pixel of a true circle, which is finer than the picture can show.
/// A mesh is sent to the GPU again on every frame it is drawn, five of them here,
/// so twice as fine costs four times as much for nothing anyone can see: measured,
/// 12 milliseconds a frame against 4.
private let segmentsAround = 128, ringsDown = 64

/// One of the bake kernels, from the `.metal` file beside this one.
private func kernel(_ entry: String) -> ComputeKernel? {
    (try? ComputeKernel(entry: entry, resource: "planet", in: .module))
}

@main
final class Planet_Example: Sketch {

    // MARK: Parameters

    /// Which world. Every map is a function of this number, so changing it bakes
    /// a different planet.
    @Param(0 ... 9, icon: "globe.europe.africa") var world = 3
    /// How much of the sky holds cloud. Re-bakes the weather map.
    @Param(0 ... 1, icon: "cloud") var cloudCover = 0.6
    /// How bright the cities burn on the night side.
    @Param(0 ... 3, icon: "lightbulb") var cityGlow = 1.2
    /// How much air. At 1 a ray going straight down passes as much of it as it
    /// would over the Earth; 0 is a world with none.
    @Param(0 ... 2, icon: "circle.dashed") var haze = 1.0
    /// Turns per minute, near enough. Negative turns the other way.
    @Param(-2 ... 2, icon: "arrow.clockwise") var spin = 0.35

    // MARK: The maps

    /// The elevation, in red. Every other map is read off this one, which is why
    /// the coast is in the same place in all of them.
    private let heightMap = ComputeTexture(width: mapWidth, height: mapHeight)
    private let surfaceMap = ComputeTexture(width: mapWidth, height: mapHeight)
    private let reliefMap = ComputeTexture(width: mapWidth, height: mapHeight, format: .rgba8Unorm)
    private let finishMap = ComputeTexture(width: mapWidth, height: mapHeight, format: .rgba8Unorm)
    private let lightMap = ComputeTexture(width: mapWidth, height: mapHeight)
    private let cloudMap = ComputeTexture(width: mapWidth, height: mapHeight)
    private let cloudReliefMap = ComputeTexture(width: mapWidth, height: mapHeight,
                                                format: .rgba8Unorm)
    private let shadowMap = ComputeTexture(width: shadowWidth, height: shadowHeight,
                                           format: .rgba8Unorm)

    private let bakeHeight = kernel("planet_height")
    private let bakeSurface = kernel("planet_surface")
    private let bakeRelief = kernel("planet_relief")
    private let bakeFinish = kernel("planet_finish")
    private let bakeLights = kernel("planet_lights")
    private let bakeClouds = kernel("planet_clouds")
    private let castShadow = kernel("planet_shadow")
    private let starField = Shader(resource: "stars", in: .module)

    /// What the maps were last baked for, so a frame that changes nothing bakes
    /// nothing. `-1` is "never", which is what makes the first frame do the work.
    private var bakedWorld = -1
    private var bakedCover = -1.0

    // MARK: The bodies

    private var globe = Mesh(positions: [], normals: [], indices: [])
    private var cities = Mesh(positions: [], normals: [], indices: [])
    private var shade = Mesh(positions: [], normals: [], indices: [])
    private var weather = Mesh(positions: [], normals: [], indices: [])
    private var overcast = Mesh(positions: [], normals: [], indices: [])

    override func setup() {
        toneMap(.aces)

        let ball = Mesh.sphere(radius: 1, segments: segmentsAround, rings: ringsDown)

        // The world itself: color, relief, and the finish that spreads the sun
        // wide over water and leaves the ground matte.
        globe = ball
            .textured(surfaceMap.image)
            .normalMapped(reliefMap.image, scale: 1)
            .surfaceMapped(metallicRoughness: finishMap.image)

        // The same ball, black, carrying only the lights. Black takes no light of
        // its own, so this draws as the cities and nothing else.
        cities = ball.textured(lightMap.image, baseColor: .black)
        cities.material?.emissiveTexture = lightMap.image
        cities.material?.emissiveColor = .white

        // Cloud, a hair above the ground, its cover stored in the texture's alpha
        // and its own relief read back off that cover, so a bank of it catches
        // the sun on one side the way a solid would.
        let shell = Mesh.sphere(radius: 1 + cloudHeight, segments: segmentsAround, rings: ringsDown)
        weather = shell
            .textured(cloudMap.image)
            .normalMapped(cloudReliefMap.image, scale: 1)

        // The same cloud in black, for the layer the cities are drawn in: a town
        // under an overcast does not show from above.
        overcast = shell.textured(cloudMap.image, baseColor: .black)

        // And the shadow of the cloud, on a shell halfway between it and the
        // ground: black, as opaque as the cloud between that place and the sun.
        shade = Mesh.sphere(radius: 1 + cloudHeight / 2, segments: segmentsAround, rings: ringsDown)
            .textured(shadowMap.image, baseColor: .black)
    }

    override func draw() {
        guard let bakeHeight, let bakeSurface, let bakeRelief, let bakeFinish,
              let bakeLights, let bakeClouds, let castShadow else {
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
            relief.append(Float(0.017))            // how tall the land stands, in radii
            relief.append(Float(0))                // this map is the elevation
            compute(bakeRelief, reading: heightMap, writing: reliefMap, params: relief)
            compute(bakeFinish, reading: heightMap, writing: finishMap, params: seed)
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
            cloudRelief.append(Float(0.0045))      // how tall a full cloud stands
            cloudRelief.append(Float(1))           // this map is the weather
            compute(bakeRelief, reading: cloudMap, writing: cloudReliefMap,
                    params: cloudRelief)
            bakedCover = cloudCover
        }

        // The world leans on its axis, toward the sun: summer in the north. It
        // turns about that axis, and the weather turns a little faster than the
        // ground under it.
        let lean = Rotation3D.aboutZ(.degrees(-23.4))
        let turn = time * spin * 0.10
        let drift = turn * 0.18

        // The sun comes from the side and a little toward the camera, which is
        // what puts a terminator across the disc rather than lighting everything
        // the camera can see.
        let toSun = Vector3(0.86, 0.36, 0.36)
        let sunlight = 2.0

        // The shadow map is the ground's own, so it wants the sun as the ground
        // sees it: the lean undone, then the turn.
        let sunOverGround = toSun.rotated(by: lean.inverse).rotated(by: .aboutY(-turn))
        var cast = ComputeParams()
        cast.append(Float(sunOverGround.x))
        cast.append(Float(sunOverGround.y))
        cast.append(Float(sunOverGround.z))
        cast.append(Float(drift))                  // how far the weather has run ahead
        cast.append(Float(cloudHeight))
        cast.append(Float(0.50))                   // how dark a full shadow is
        compute(castShadow, reading: cloudMap, writing: shadowMap, params: cast)

        background(.black)

        let lens = Double.focalLength(35)
        let view = Camera3D.perspective(eye: Vector3(0, 0.26, 3.55), target: .zero,
                                        fieldOfView: lens)

        // The lit world. The stars go INSIDE this layer, over an opaque black, so
        // the layer holds a whole picture rather than a cut-out of one, and the
        // air is worked out over all of it.
        let scene = makeRenderTarget()
        withTarget(scene) {
            background(.black)
            drawImage(generate(starField).image, 0, 0)

            camera(view)
            light(.directional(.white, direction: -toSun, intensity: sunlight,
                               castsShadow: false))
            fill(.white)
            rotate(lean)

            // The maps decide the finish per pixel, so the factors stay at 1.
            material(.physicallyBased(metallic: 1, roughness: 1))
            withState { rotateY(turn); drawMesh(globe) }
            withState { rotateY(turn); drawMesh(shade) }

            material(.dielectric(roughness: 0.95))
            withState { rotateY(turn + drift); drawMesh(weather) }
        }

        // The cities, alone, with the weather over them in black. Same camera,
        // same turn, so they land on the world.
        let lights = makeRenderTarget()
        withTarget(lights) {
            camera(view)
            fill(.white)
            material(Material())
            rotate(lean)
            withState { rotateY(turn); drawMesh(cities) }
            withState { rotateY(turn + drift); drawMesh(overcast) }
        }

        // The air, over both. The shader wants the camera as three directions:
        // straight ahead, and how far right and up the edge of the picture is.
        let frame = view.basis
        let spread = tan(lens / 2)
        func air(citiesOnly: Bool) -> Shader {
            let right = frame.right * spread, up = frame.up * spread, ahead = -frame.back
            return Shader(resource: "air", in: .module, params: [
                Float(view.eye.x), Float(view.eye.y), Float(view.eye.z),
                Float(right.x), Float(right.y), Float(right.z),
                Float(up.x), Float(up.y), Float(up.z),
                Float(ahead.x), Float(ahead.y), Float(ahead.z),
                Float(toSun.x), Float(toSun.y), Float(toSun.z),
                Float(haze), Float(sunlight), Float(cityGlow),
                citiesOnly ? 1 : 0,
            ])
        }
        let planet = scene.combined(with: lights, .shader(air(citiesOnly: false)))
        // The same shader asked for the cities and nothing else, which is the
        // picture their glow is taken from.
        let night = scene.combined(with: lights, .shader(air(citiesOnly: true)))

        drawImage(planet.image, 0, 0)
        withState {
            blendMode(.add)
            // The glare a lens adds around anything brighter than white, which
            // here is sunlit cloud and the sun on the sea, and the glow around a
            // city.
            drawImage(planet.filtered(.bloom(threshold: 1.0, amount: 0.22,
                                             radius: 36)).image, 0, 0)
            drawImage(night.filtered(.bloom(threshold: 0.10, amount: 0.55,
                                            radius: 9)).image, 0, 0)
        }

        drawCaption("A planet baked on the GPU and seen through its own air")
    }
}
