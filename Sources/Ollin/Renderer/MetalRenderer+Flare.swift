import Foundation
import Metal
import simd
import COllinShaders   // OllinLensFlareUniforms, shared with the shaders

// MARK: - Lens flare

extension MetalRenderer {

    /// Whether this frame flares. A flare needs a camera to be a defect of, and a
    /// light to be a defect about.
    func lensFlareActive(_ drawer: Drawer) -> Bool {
        drawer.lensFlareSetting != nil && drawer.camera3D != nil && !drawer.lights.isEmpty
    }

    /// The paraxial description of a lens, worked out once and kept. None of it
    /// moves when the light does, so a sketch holding one lens pays for the ghost
    /// enumeration on the first frame only.
    func flareOptics(for lens: Lens) -> LensOptics {
        if let cached = flareOpticsCache, cached.lens == lens { return cached.optics }
        var optics = lens.optics()
        if optics.ghosts.count > Int(OLLIN_MAX_FLARE_GHOSTS) {
            // A complicated lens makes more ghost paths than the frame can carry,
            // so keep the ones that will read: the two coating reflectances over
            // how widely the ghost spreads its light. The angle here is fixed
            // rather than the light's own, so which ghosts survive does not change
            // as the light crosses the frame, which would pop them in and out.
            let scored = optics.ghosts.map { ghost -> (LensGhost, Double) in
                let reflect = lens.ghostReflectance(ghost, angle: 0.15)
                let spread = max(ghost.toSensor.a * ghost.toSensor.a, 1e-9)
                return (ghost, (reflect.x + reflect.y + reflect.z) / spread)
            }
            optics.ghosts = scored.sorted { $0.1 > $1.1 }
                .prefix(Int(OLLIN_MAX_FLARE_GHOSTS)).map(\.0)
        }
        flareOpticsCache = (lens, optics)
        return optics
    }

    /// What the lens's brightest ghost is worth, in linear light, at `strength` 1.
    ///
    /// One number sets the whole flare's level, and everything under it stays as
    /// the optics worked it out: how the ghosts compare to each other in size,
    /// place, and color, and how each source compares to the others in the same
    /// frame. Nothing is bent to make the picture read.
    ///
    /// A scale is needed at all because the physical number is unusably small.
    /// Two coated interfaces pass on a few parts in ten thousand, and a real
    /// flare shows only because the sun is many thousands of times brighter than
    /// anything it lights. A sketch's lights carry no such range, and a light's
    /// `intensity` is set to light the scene rather than to say how bright the
    /// source is, so reading it literally would make one sketch's flare invisible
    /// and the next one's blinding.
    ///
    /// The value is above 1 on purpose. A lens usually has one ghost that lands
    /// near focus, which puts all its light in a small dot, and a dot like that
    /// is meant to blow out: it is the brightest thing in the frame. The ghosts
    /// spread wider come out far below it, which is what a real flare does.
    static let lensFlareGain = 3.0

    /// How soft the iris edge is, as a fraction of the iris radius. A real
    /// opening does not cut light off exactly at its rim: the edge diffracts, and
    /// a hard cut reads as a sticker.
    static let flareIrisSoftness = 0.12
    /// The same feather on the front opening, which is a wider and harder stop.
    static let flarePupilSoftness = 0.05

    /// What one arm of the star is worth where the baked pattern reads 1, at
    /// `strength` and `star` both 1.
    ///
    /// The pattern's mean is 1 and its core runs thousands of times above that,
    /// so this level blows the core out (which is what a source does) and leaves
    /// the arms in a range the picture can hold.
    static let lensFlareStarGain = 0.4

    /// The star pattern for a blade count, baked once and kept.
    func flareStar(blades: Int) -> MTLTexture? {
        if let cached = flareStarCache, cached.blades == blades { return cached.texture }
        let pattern = ApertureStar.bake(blades: blades)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: pattern.size, height: pattern.size,
            mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        // The bake is worked out in full floats and the texture holds halves, so
        // the core's ceiling is what keeps the brightest texels representable.
        let half = pattern.pixels.map { Float16($0) }
        half.withUnsafeBytes { bytes in
            texture.replace(region: MTLRegionMake2D(0, 0, pattern.size, pattern.size),
                            mipmapLevel: 0, withBytes: bytes.baseAddress!,
                            bytesPerRow: pattern.size * 8)
        }
        flareStarCache = (blades, texture)
        return texture
    }

    /// One source, worked out into the terms the flare uses.
    private struct FlareSource {
        /// The angle the source arrives at the front of the lens, in radians.
        var angle: SIMD2<Double>
        /// Where it sits on the frame, y-normalized.
        var frame: SIMD2<Double>
        /// The depth the visibility test compares the scene against.
        var depth: Double
        /// The source's own linear color, already carrying its intensity.
        var color: SIMD3<Double>
        /// How bright it is, which decides who gets carried when there are too many.
        var weight: Double
    }

    /// Add the lens flare to the resolved linear frame, returning the texture the
    /// rest of the chain should read, or the input untouched when the frame does
    /// not flare (no flare set, no camera, no light, an orthographic camera, or a
    /// lens that makes no ghosts), so a sketch without it is unchanged.
    ///
    /// This sits after the temporal resolve and the motion blur and before the
    /// frame filters, which puts it in linear light and ahead of the tone map. A
    /// flare is light arriving at the sensor, not paint on the finished picture,
    /// so a bloom placed after it glows the ghosts the way it glows everything
    /// else bright.
    func applyLensFlare(_ drawer: Drawer, resolved: MTLTexture, depth: MTLTexture?,
                        into cb: MTLCommandBuffer, width: Int, height: Int,
                        pooled: Bool) -> MTLTexture {
        guard let flare = drawer.lensFlareSetting, let camera = drawer.camera3D,
              let depth, !drawer.lights.isEmpty, width > 0, height > 0 else { return resolved }
        let aspect = Double(width) / Double(height)
        let projection = camera.projectionMatrix(aspect: aspect)
        // A flare needs a vantage point. An orthographic camera has no angle off
        // the axis to give a source, so it never makes one.
        guard projection.columns.3.w == 0,
              projection.columns.1.y > 0, projection.columns.0.x > 0 else { return resolved }
        let tanHalfFieldOfView = 1 / Double(projection.columns.1.y)
        let lensAspect = Double(projection.columns.1.y / projection.columns.0.x)
        let optics = flareOptics(for: flare.lens)
        guard !optics.ghosts.isEmpty, optics.directScale != 0,
              optics.pupilRadius > 0, optics.irisRadius > 0 else { return resolved }

        let viewProjection = projection * camera.viewMatrix
        let eye = camera.eye.simd3
        var sources: [FlareSource] = []
        for light in drawer.lights {
            let clip: SIMD4<Float>
            var pulledBack: SIMD3<Float>?
            switch light.kind {
            case .directional:
                // The sun sits at the end of the direction it comes from, which is
                // as far away as the projection reaches.
                clip = viewProjection * SIMD4<Float>((light.direction * -1).normalized.simd3, 0)
            default:
                let position = light.position.simd3
                clip = viewProjection * SIMD4<Float>(position, 1)
                // The depth the visibility test compares against sits a little in
                // front of the light, so a fixture drawn around its own bulb does
                // not put out the flare it is there to make.
                pulledBack = eye + (position - eye) * 0.98
            }
            guard clip.w > 1e-6 else { continue }   // behind the camera
            let frame = SIMD2<Double>(Double(clip.x / clip.w) * lensAspect, Double(clip.y / clip.w))
            guard simd_length(frame) <= 1 + flare.reach else { continue }
            // A source beyond the far plane projects past 1, where nothing in the
            // depth buffer could ever be farther, so hold it at the back of the
            // scene: an empty pixel then reads as seeing it.
            var testDepth = min(Double(clip.z / clip.w), 1)
            if let pulledBack {
                let near = viewProjection * SIMD4<Float>(pulledBack, 1)
                if near.w > 1e-6 { testDepth = min(Double(near.z / near.w), 1) }
            }
            let intensity = light.intensity
            let color = SIMD3<Double>(Color.srgbToLinear(light.color.red) * intensity,
                                      Color.srgbToLinear(light.color.green) * intensity,
                                      Color.srgbToLinear(light.color.blue) * intensity)
            let weight = 0.2126 * color.x + 0.7152 * color.y + 0.0722 * color.z
            guard weight > 1e-4 else { continue }
            sources.append(FlareSource(angle: frame * tanHalfFieldOfView, frame: frame,
                                       depth: testDepth, color: color, weight: weight))
        }
        if sources.count > Int(OLLIN_MAX_FLARE_LIGHTS) {
            sources = Array(sources.sorted { $0.weight > $1.weight }
                .prefix(Int(OLLIN_MAX_FLARE_LIGHTS)))
        }
        guard !sources.isEmpty else { return resolved }
        // The brightest source in the frame is the anchor the rest measure against.
        let brightest = sources.map(\.weight).max() ?? 1

        guard let visibility = acquireFilterTexture(width: Int(OLLIN_MAX_FLARE_LIGHTS),
                                                    height: 1, pooled: pooled),
              let output = acquireFilterTexture(width: width, height: height, pooled: pooled),
              let state = try? pipeline(.effect("ollin_flare_composite")) else { return resolved }

        // How much of each source the camera can see, one light per pixel of a
        // four-pixel strip, so the composite pays one texture read per light
        // instead of a ring of depth taps per pixel.
        var visionParams = [SIMD4<Float>](repeating: .zero, count: 1 + Int(OLLIN_MAX_FLARE_LIGHTS))
        visionParams[0] = SIMD4(Float(flare.sourceSize), Float(lensAspect),
                                Float(sources.count), 2e-5)
        for (index, source) in sources.enumerated() {
            visionParams[1 + index] = SIMD4(Float(source.frame.x / lensAspect * 0.5 + 0.5),
                                            Float(0.5 - source.frame.y * 0.5),
                                            Float(source.depth), 1)
        }
        encodeEffectFragment("ollin_flare_visibility", inputs: [depth], output: visibility,
                             params: visionParams, into: cb)

        var uniforms = OllinLensFlareUniforms()
        uniforms.lightCount = Int32(sources.count)
        uniforms.ghostCount = Int32(optics.ghosts.count)
        uniforms.optics = SIMD4<Float>(Float(optics.pupilRadius), Float(optics.irisRadius),
                                       Float(optics.directScale * tanHalfFieldOfView),
                                       Float(lensAspect))
        // The star's drawn size is measured at the iris wide open and grows as the
        // iris closes, since light bending around a smaller opening spreads
        // further. The size itself is chosen rather than physical: a real star's
        // arms are visible only because the source is thousands of times brighter
        // than the scene, and that reach is far outside what a bake of this size
        // can hold. What stays physical is its shape and how it answers the iris.
        let blades = max(0, camera.apertureBlades)
        // Held at eight times, since a lens stopped past that is a pinhole and its
        // star would otherwise reach across the whole picture.
        let openness = optics.irisRadius > 0 ? optics.openIrisRadius / optics.irisRadius : 1
        let starExtent = flare.star > 0 ? flare.starSize * min(openness, 8) : 0
        uniforms.iris = SIMD4<Float>(Float(blades), Float(starExtent),
                                     Float(MetalRenderer.flareIrisSoftness),
                                     Float(MetalRenderer.flarePupilSoftness))
        withUnsafeMutablePointer(to: &uniforms.starTints) { tuple in
            tuple.withMemoryRebound(to: simd_float4.self,
                                   capacity: Int(OLLIN_MAX_FLARE_LIGHTS)) { buffer in
                for (index, source) in sources.enumerated() {
                    let level = flare.strength * flare.star * MetalRenderer.lensFlareStarGain
                    let color = (source.color / brightest) * level
                    buffer[index] = SIMD4(Float(color.x), Float(color.y), Float(color.z), 0)
                }
            }
        }
        withUnsafeMutablePointer(to: &uniforms.ghosts) { tuple in
            tuple.withMemoryRebound(to: simd_float4.self,
                                   capacity: Int(OLLIN_MAX_FLARE_GHOSTS)) { buffer in
                for (index, ghost) in optics.ghosts.enumerated() {
                    buffer[index] = SIMD4(Float(ghost.toSensor.a), Float(ghost.toSensor.b),
                                          Float(ghost.toIris.a), Float(ghost.toIris.b))
                }
            }
        }
        withUnsafeMutablePointer(to: &uniforms.lights) { tuple in
            tuple.withMemoryRebound(to: simd_float4.self,
                                   capacity: Int(OLLIN_MAX_FLARE_LIGHTS)) { buffer in
                for (index, source) in sources.enumerated() {
                    buffer[index] = SIMD4(Float(source.angle.x), Float(source.angle.y),
                                          Float(source.frame.x), Float(source.frame.y))
                }
            }
        }
        let slots = Int(OLLIN_MAX_FLARE_LIGHTS) * Int(OLLIN_MAX_FLARE_GHOSTS)
        withUnsafeMutablePointer(to: &uniforms.tints) { tuple in
            tuple.withMemoryRebound(to: simd_float4.self, capacity: slots) { buffer in
                for (lightIndex, source) in sources.enumerated() {
                    let angle = simd_length(source.angle)
                    var raw: [SIMD3<Double>] = []
                    raw.reserveCapacity(optics.ghosts.count)
                    var peak = 0.0
                    for ghost in optics.ghosts {
                        let reflect = flare.lens.ghostReflectance(ghost, angle: angle)
                        // A ghost spreads the light it carries over the square of
                        // its magnification, which is why the small ones are the
                        // bright ones.
                        let spread = max(ghost.toSensor.a * ghost.toSensor.a, 1e-6)
                        let value = reflect / spread
                        raw.append(value)
                        peak = max(peak, 0.2126 * value.x + 0.7152 * value.y + 0.0722 * value.z)
                    }
                    guard peak > 0 else { continue }
                    let scale = flare.strength * MetalRenderer.lensFlareGain
                    for (ghostIndex, value) in raw.enumerated() {
                        // Measured against the brightest ghost this source makes,
                        // and tinted by both the coating and the source's color.
                        let color = value * (scale / peak) * (source.color / brightest)
                        buffer[lightIndex * Int(OLLIN_MAX_FLARE_GHOSTS) + ghostIndex] =
                            SIMD4(Float(color.x), Float(color.y), Float(color.z), 0)
                    }
                }
            }
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = countedEncoder(cb, pass, caller: "lens flare") else { return resolved }
        encoder.setRenderPipelineState(state)
        encoder.setFragmentTexture(resolved, index: 0)
        encoder.setFragmentTexture(visibility, index: 1)
        encoder.setFragmentTexture(starExtent > 0 ? flareStar(blades: blades) : visibility, index: 2)
        encoder.setFragmentSamplerState(imageSampler, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<OllinLensFlareUniforms>.stride,
                                 index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return output
    }

}
