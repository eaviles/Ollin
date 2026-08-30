import Foundation
import Ollin
internal import CJolt

/// Water filling a `World3D` below a level: bodies dropped into it float, bob,
/// tip upright, and drift, and bodies heavier than it sink through. Like
/// `World3D.ground` it is one property on the world rather than something each
/// body opts into, so setting it starts everything already in the world
/// floating.
///
/// ```swift
/// world.water = Water(level: 0)
/// ```
///
/// What floats and what sinks comes from the bodies' own `density`, the same
/// number `addBody` already takes, measured against the water's: a crate at
/// `density: 0.4` rides with 40% of itself under, and a stone at `2` goes
/// straight to the bottom. The waterline lands where the displaced volume says
/// it should, so a half-full barrel floats half-submerged without tuning.
///
/// Add `waves` and the surface rolls, carrying whatever is riding it:
///
/// ```swift
/// world.water = Water(level: 0, waves: Water.Waves(amplitude: 0.25,
///                                                  wavelength: 8))
/// ```
public struct Water: Equatable, Sendable {

    /// The height of the still surface, in world units. Everything below it is
    /// water, out to the horizon: this is an ocean, not a pool with walls.
    /// Animate it for a tide (bodies asleep at the old level wake and follow).
    public var level: Double

    /// How heavy the water is, relative to the default body material exactly
    /// the way a collider's `density` is. `1`, the default, is water: a body
    /// created at the default `density: 1` is then neutrally buoyant, lighter
    /// ones float, heavier ones sink.
    public var density: Double

    /// How strongly the water resists a body being dragged through it. This is
    /// what makes something dropped in settle instead of bobbing for ages;
    /// around `0.5` reads like water, `0` like a body falling through air.
    public var linearDrag: Double

    /// How strongly the water resists a body turning in it. Raise it to stop a
    /// long floating shape from rocking for too long after it lands.
    public var angularDrag: Double

    /// A current, in world units per second, that everything afloat is carried
    /// along by. `.zero` (the default) is still water.
    public var flow: Vector3

    /// The swell, if any. `nil` (the default) is a flat calm.
    public var waves: Waves?

    /// A rolling swell on the surface: a small train of crossed sine waves,
    /// which is what both floats the bodies and gives `World3D.waterMesh` its
    /// shape, so what you see and what the bodies ride are the same surface.
    public struct Waves: Equatable, Sendable {

        /// How far a crest rises above the still `level`, in world units.
        public var amplitude: Double

        /// The distance from one crest to the next, in world units.
        public var wavelength: Double

        /// How fast the swell travels, in world units per second.
        public var speed: Double

        /// Which way it travels, in radians about the y axis: `0` runs along
        /// +x.
        public var heading: Double

        public init(amplitude: Double = 0.2, wavelength: Double = 6,
                    speed: Double = 1.5, heading: Double = 0) {
            self.amplitude = amplitude
            self.wavelength = max(1e-6, wavelength)
            self.speed = speed
            self.heading = heading
        }

        /// The three crossed components, as (weight, wavelength scale, heading
        /// offset). One sine reads as corrugated metal; three at odd angles and
        /// odd sizes read as water. The weights are normalized at use, so
        /// `amplitude` stays the true height of a crest.
        static let components: [(weight: Double, scale: Double, turn: Double)] = [
            (1.00, 1.00, 0.00),
            (0.50, 0.55, 0.70),
            (0.28, 0.31, -1.10),
        ]

        static let totalWeight = components.reduce(0) { $0 + $1.weight }
    }

    public init(level: Double = 0, density: Double = 1,
                linearDrag: Double = 0.5, angularDrag: Double = 0.1,
                flow: Vector3 = .zero, waves: Waves? = nil) {
        self.level = level
        self.density = density
        self.linearDrag = linearDrag
        self.angularDrag = angularDrag
        self.flow = flow
        self.waves = waves
    }

    // MARK: The surface

    /// The surface height above `point`'s x and z, at `phase` seconds into the
    /// swell. Still water is just `level` everywhere.
    public func height(at point: Vector3, phase: Double) -> Double {
        guard let waves, waves.amplitude != 0 else { return level }
        var sum = 0.0
        for component in Waves.components {
            let (k, direction, drift) = wave(component, waves, phase)
            sum += component.weight * sin(k * (direction.x * point.x
                                               + direction.y * point.z) - drift)
        }
        return level + waves.amplitude * sum / Waves.totalWeight
    }

    /// The plane the buoyancyScale is measured against under `point`: the surface
    /// point directly above or below it, and the way the surface faces there.
    /// A wavy surface is handed to the solver one body at a time as the plane
    /// tangent to it, which is exact for still water and a good approximation
    /// for anything smaller than the waves it rides.
    func surface(at point: Vector3, phase: Double) -> (point: Vector3,
                                                       normal: Vector3) {
        guard let waves, waves.amplitude != 0 else {
            return (Vector3(point.x, level, point.z), Vector3(0, 1, 0))
        }
        var height = 0.0
        var slopeX = 0.0
        var slopeZ = 0.0
        for component in Waves.components {
            let (k, direction, drift) = wave(component, waves, phase)
            let travel = k * (direction.x * point.x + direction.y * point.z) - drift
            height += component.weight * sin(travel)
            let gradient = component.weight * k * cos(travel)
            slopeX += gradient * direction.x
            slopeZ += gradient * direction.y
        }
        let scale = waves.amplitude / Waves.totalWeight
        // The gradient is exact rather than sampled either side, so the normal
        // is right even where two components cross steeply.
        let normal = Vector3(-slopeX * scale, 1, -slopeZ * scale).normalized
        return (Vector3(point.x, level + height * scale, point.z), normal)
    }

    /// One component's wave number, direction in the xz plane, and how far it
    /// has traveled by `phase`.
    private func wave(_ component: (weight: Double, scale: Double, turn: Double),
                      _ waves: Waves,
                      _ phase: Double) -> (k: Double, direction: Vector2,
                                           drift: Double) {
        let k = 2 * .pi / (waves.wavelength * component.scale)
        let heading = waves.heading + component.turn
        return (k, Vector2(cos(heading), sin(heading)), k * waves.speed * phase)
    }
}

// MARK: - The world's water

extension World3D {

    /// The surface height above `point`, or `nil` when the world has no water.
    /// Reads the same surface the bodies are floating on, including the swell
    /// at this moment, so a sketch can sit something exactly on the waterline.
    public func waterHeight(at point: Vector3) -> Double? {
        water?.height(at: point, phase: waterPhase)
    }

    /// A patch of the water's surface as a `Mesh`, centered on `around`, so the
    /// water can be drawn with whatever material the sketch likes:
    ///
    /// ```swift
    /// if let surface = world.waterMesh(extent: 40) {
    ///     material(.glass(roughness: 0.1))
    ///     fill(Color(hex: "1b5e8c"))
    ///     drawMesh(surface)
    /// }
    /// ```
    ///
    /// The grid is rebuilt from the live surface each time it is called, which
    /// is what keeps the drawn swell and the ridden swell identical; keep
    /// `resolution` modest (the cost is `resolution²` vertices per frame).
    /// Returns `nil` when the world has no water.
    public func waterMesh(extent: Double = 50, resolution: Int = 64,
                          around center: Vector3 = .zero) -> Mesh? {
        guard let water else { return nil }
        let steps = max(1, min(512, resolution))
        let side = steps + 1
        let span = max(1e-6, extent)
        var positions: [Vector3] = []
        var normals: [Vector3] = []
        var uvs: [Vector2] = []
        positions.reserveCapacity(side * side)
        normals.reserveCapacity(side * side)
        uvs.reserveCapacity(side * side)

        for row in 0..<side {
            let v = Double(row) / Double(steps)
            let z = center.z - span + 2 * span * v
            for column in 0..<side {
                let u = Double(column) / Double(steps)
                let x = center.x - span + 2 * span * u
                let surface = water.surface(at: Vector3(x, 0, z), phase: waterPhase)
                positions.append(surface.point)
                normals.append(surface.normal)
                uvs.append(Vector2(u, v))
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(steps * steps * 6)
        for row in 0..<steps {
            for column in 0..<steps {
                let a = UInt32(row * side + column)
                let b = a + 1
                let c = UInt32((row + 1) * side + column)
                let d = c + 1
                // Wound counter-clockwise seen from above, so the surface faces
                // the sky.
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        return Mesh(positions: positions, normals: normals, indices: indices,
                    uvs: uvs)
    }

    /// Pushes every floating body up for one step, against the surface as it
    /// stands right now. Runs before the solver's own step, which is where the
    /// library's samples apply it: the impulse is the caller's job rather than
    /// the solver's, so this is the loop that makes a world with water float
    /// things without any body opting in.
    func applyBuoyancy(dt: Double) {
        guard let water else { return }
        waterPhase += dt

        // A sleeping body has stopped being pushed on, which is exactly right
        // while the water is unchanged: it has settled at its waterline and
        // stays there. The two ways that stops being right are different, so
        // they wake different bodies. Retuning the water moves the waterline
        // itself, so everything afloat in it has to be let go of, however deep
        // it is sleeping; a swell only moves the surface, so it wakes what it
        // washes over and leaves the bottom alone.
        let wake: CJoltBuoyancyWake = waterMoved ? CJOLT_BUOYANCY_WAKE_ALWAYS
            : (water.waves != nil ? CJOLT_BUOYANCY_WAKE_AT_SURFACE
                                  : CJOLT_BUOYANCY_WAKE_NEVER)
        waterMoved = false

        // Water fills the world below its surface out to the same reach as the
        // ground slab; the box climbs to the crests so a body riding one is
        // still found.
        let reach = Float(500.0 / unitsPerMeter)
        let top = Float((water.level + (water.waves?.amplitude ?? 0)) / unitsPerMeter)
        let boxMin: (Float, Float, Float) = (-reach, top - 2 * reach, -reach)
        let boxMax: (Float, Float, Float) = (reach, top, reach)

        // Every registered body is an upper bound on the dynamic ones the query
        // can return (ragdoll limbs and a character's stand-in are in here too,
        // and only the first of those can float).
        let capacity = max(1, bodyByID.count)
        if waterBodies.count < capacity {
            waterBodies = Array(repeating: 0, count: capacity)
            waterCenters = Array(repeating: 0, count: 3 * capacity)
        }

        let found = withFloats3(boxMin) { minimum in
            withFloats3(boxMax) { maximum in
                waterBodies.withUnsafeMutableBufferPointer { ids in
                    waterCenters.withUnsafeMutableBufferPointer { centers in
                        cjolt_world_bodies_in_box(handle, minimum, maximum,
                                                  ids.baseAddress, centers.baseAddress,
                                                  Int32(capacity))
                    }
                }
            }
        }

        let fluidDensity = Float(max(0, water.density) * 1000)
        let linearDrag = Float(max(0, water.linearDrag))
        let angularDrag = Float(max(0, water.angularDrag))
        let flow = meters(from: water.flow)

        for index in 0..<Int(found) {
            let id = waterBodies[index]
            let scale = bodyByID[id]?.buoyancyScale ?? 1
            guard scale > 0 else { continue }
            let center = units(from: waterCenters[3 * index],
                               waterCenters[3 * index + 1],
                               waterCenters[3 * index + 2])
            let plane = water.surface(at: center, phase: waterPhase)
            // The normal is a direction, so it crosses into the solver's meters
            // unchanged; the point is a place, so it converts.
            let point = meters(from: plane.point)
            let normal = (Float(plane.normal.x), Float(plane.normal.y),
                          Float(plane.normal.z))
            withFloats3(point) { surfacePoint in
                withFloats3(normal) { surfaceNormal in
                    withFloats3(flow) { current in
                        _ = cjolt_body_apply_buoyancy(handle, id, surfacePoint,
                                                      surfaceNormal, fluidDensity,
                                                      Float(scale), linearDrag,
                                                      angularDrag, current,
                                                      Float(dt), wake)
                    }
                }
            }
        }

        // Soft bodies are not in that sweep: the solver's own buoyancyScale works
        // through one mass and one inertia, which a bag of particles has
        // neither of, so each is floated particle by particle instead. They are
        // few and each is one call, so the list is walked rather than queried.
        let scale = unitsPerMeter
        for soft in softBodies where soft.density > 0 {
            // Where a rigid body is handed one tangent plane through its own
            // center, every particle is handed the surface directly above it.
            // A sheet is wide enough that one plane would have its far edges
            // riding a wave that is not under them, which curls a raft into a
            // bowl; this is the same surface function, asked more often.
            let particles = soft.particlePositions
            if soft.surfaceHeights.count != particles.count {
                soft.surfaceHeights = [Float](repeating: 0, count: particles.count)
            }
            for (index, particle) in particles.enumerated() {
                let height = water.height(at: particle, phase: waterPhase)
                soft.surfaceHeights[index] = Float((particle.y - height) / scale)
            }
            // The lift is the ratio of the two densities, the same
            // dimensionless number the rigid path forms from a body's mass and
            // the volume it displaces. A surface with no inside cannot be
            // measured that way, which is why it is formed here instead.
            let buoyancyScale = Float(max(0, water.density) / soft.density)
            soft.surfaceHeights.withUnsafeBufferPointer { heights in
                withFloats3(flow) { current in
                    _ = cjolt_soft_body_apply_buoyancy(
                        handle, soft.handle, heights.baseAddress,
                        Int32(heights.count), buoyancyScale, fluidDensity, linearDrag,
                        Float(soft.dragArea), Float(soft.particleSpacing),
                        current, Float(dt), wake)
                }
            }
        }
    }
}
