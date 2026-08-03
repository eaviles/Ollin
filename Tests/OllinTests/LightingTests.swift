@testable import Ollin
import Testing
import simd
import COllinShaders

/// CPU checks on the 3D mesh lighting/material model, exercised through `Drawer`:
/// how lights pack into the GPU `OllinLighting` uniform (`makeLighting`), the
/// auto/custom/off modes, the directional/point/spot encodings, and the material
/// finish bound per mesh batch as a uniform. No Metal device, so these run in CI.
@Suite
struct LightingTests {

    private func close(_ a: Float, _ b: Float, _ eps: Float = 1e-5) -> Bool { abs(a - b) <= eps }

    private func freshDrawer() -> Drawer {
        let d = Drawer()
        d.beginFrame()
        d.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        return d
    }

    // MARK: Modes

    @Test func defaultIsAutoLit() {
        // No lights set → the default rig shades (enabled, with the rig's lights).
        let u = freshDrawer().makeLighting()
        #expect(u.enabled == 1)
        #expect(u.lightCount == Int32(Drawer.defaultLights.count))
        #expect(close(u.ambient.x, Float(Color.srgbToLinear(Drawer.defaultAmbient.red))))
    }

    @Test func noLightsIsUnlit() {
        let d = freshDrawer()
        d.noLights()
        #expect(d.makeLighting().enabled == 0)
    }

    @Test func customLightsReplaceTheDefault() {
        let d = freshDrawer()
        d.addLight(.point(.white, at: Vector3(1, 2, 3)))
        let u = d.makeLighting()
        #expect(u.enabled == 1)
        #expect(u.lightCount == 1)   // the default rig's 2 lights are gone
    }

    @Test func ambientAloneCountsAsCustom() {
        // An ambient with no directional is a flat, full-control fill (not the rig).
        let d = freshDrawer()
        d.ambientLight(Color(white: 0.5))
        let u = d.makeLighting()
        #expect(u.enabled == 1)
        #expect(u.lightCount == 0)
        #expect(close(u.ambient.x, Float(Color.srgbToLinear(0.5))))
    }

    @Test func beginFrameResetsToAuto() {
        let d = freshDrawer()
        d.noLights()
        d.beginFrame()
        d.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        #expect(d.makeLighting().enabled == 1)   // back to the auto-lit default
    }

    // MARK: Light encodings

    @Test func directionalStoresDirectionToTheLight() {
        let d = freshDrawer()
        // Light travels straight down; the GPU wants the direction *to* the light (up).
        d.addLight(.directional(.white, direction: Vector3(0, -1, 0)))
        let l = d.makeLighting().lights.0
        #expect(l.kind == 0)
        #expect(close(l.direction.x, 0) && close(l.direction.y, 1) && close(l.direction.z, 0))
    }

    @Test func pointStoresPosition() {
        let d = freshDrawer()
        d.addLight(.point(.white, at: Vector3(4, 5, 6)))
        let l = d.makeLighting().lights.0
        #expect(l.kind == 1)
        #expect(close(l.position.x, 4) && close(l.position.y, 5) && close(l.position.z, 6))
    }

    @Test func spotConeCosines() {
        let d = freshDrawer()
        // Full angle π/3 → half-angle π/6. Penumbra 0 → inner == outer (hard edge).
        d.addLight(.spot(.white, at: .zero, direction: Vector3(0, -1, 0),
                         angle: .pi / 3, penumbra: 0))
        let l = d.makeLighting().lights.0
        #expect(l.kind == 2)
        #expect(close(l.cosOuter, Float(cos(Double.pi / 6))))
        #expect(close(l.cosInner, l.cosOuter))
    }

    @Test func spotPenumbraNarrowsInnerCone() {
        let d = freshDrawer()
        // Penumbra 0.5 narrows the full-bright inner cone to half the half-angle.
        d.addLight(.spot(.white, at: .zero, direction: Vector3(0, -1, 0),
                         angle: .pi / 3, penumbra: 0.5))
        let l = d.makeLighting().lights.0
        #expect(close(l.cosInner, Float(cos(Double.pi / 6 * 0.5))))
        #expect(l.cosInner > l.cosOuter)   // inner cone is tighter than the outer
    }

    @Test func intensityScalesColor() {
        let d = freshDrawer()
        d.addLight(.directional(.white, direction: Vector3(0, -1, 0), intensity: 0.5))
        let l = d.makeLighting().lights.0
        #expect(close(l.color.x, Float(Color.srgbToLinear(1.0) * 0.5)))
    }

    // MARK: Area lights

    @Test func rectPacksAnOrthonormalFrame() {
        let d = freshDrawer()
        d.addLight(.rect(.white, at: Vector3(1, 2, 3), direction: Vector3(0, 0, 1),
                         width: 4, height: 2))
        let l = d.makeLighting().lights.0
        #expect(l.kind == 3)
        #expect(close(l.position.x, 1) && close(l.position.y, 2) && close(l.position.z, 3))
        #expect(close(l.direction.z, 1))
        #expect(close(l.axisA.w, 2) && close(l.axisB.w, 1))   // half-extents
        let t = SIMD3<Float>(l.axisA.x, l.axisA.y, l.axisA.z)
        let b = SIMD3<Float>(l.axisB.x, l.axisB.y, l.axisB.z)
        let n = SIMD3<Float>(l.direction.x, l.direction.y, l.direction.z)
        #expect(close(simd_length(t), 1) && close(simd_length(b), 1))
        #expect(close(simd_dot(t, n), 0) && close(simd_dot(b, n), 0))
        // Right-handed: tangent × bitangent is the facing normal (the shader's
        // corner winding depends on it).
        let cr = simd_cross(t, b)
        #expect(close(cr.x, n.x) && close(cr.y, n.y) && close(cr.z, n.z))
    }

    @Test func rectTwoSidedRidesDirectionW() {
        let d = freshDrawer()
        d.addLight(.rect(.white, at: .zero, direction: Vector3(0, 0, 1),
                         width: 1, height: 1, twoSided: true))
        d.addLight(.rect(.white, at: .zero, direction: Vector3(0, 0, 1),
                         width: 1, height: 1))
        let u = d.makeLighting()
        #expect(close(u.lights.0.direction.w, 1))
        #expect(close(u.lights.1.direction.w, 0))
    }

    @Test func rectDegenerateUpStillPacksAFrame() {
        // A panel facing straight down is parallel to the default up hint; the
        // packer falls back to a stable axis instead of a NaN frame.
        let d = freshDrawer()
        d.addLight(.rect(.white, at: .zero, direction: Vector3(0, -1, 0),
                         width: 2, height: 2))
        let l = d.makeLighting().lights.0
        let t = SIMD3<Float>(l.axisA.x, l.axisA.y, l.axisA.z)
        let b = SIMD3<Float>(l.axisB.x, l.axisB.y, l.axisB.z)
        #expect(t.x.isFinite && b.x.isFinite)
        #expect(close(simd_length(t), 1) && close(simd_length(b), 1))
        #expect(close(simd_dot(t, b), 0))
    }

    @Test func diskPacksRadiusInBothHalfExtents() {
        let d = freshDrawer()
        d.addLight(.disk(.white, at: .zero, direction: Vector3(0, 0, 1), radius: 1.5))
        let l = d.makeLighting().lights.0
        #expect(l.kind == 4)
        #expect(close(l.axisA.w, 1.5) && close(l.axisB.w, 1.5))
    }

    @Test func tubePacksCenterAxisHalfLengthRadius() {
        let d = freshDrawer()
        d.addLight(.tube(.white, from: Vector3(-2, 1, 0), to: Vector3(4, 1, 0), radius: 0.25))
        let l = d.makeLighting().lights.0
        #expect(l.kind == 5)
        #expect(close(l.position.x, 1) && close(l.position.y, 1) && close(l.position.z, 0))
        #expect(close(l.axisA.x, 1) && close(l.axisA.y, 0) && close(l.axisA.z, 0))
        #expect(close(l.axisA.w, 3))     // half-length
        #expect(close(l.axisB.w, 0.25))  // tube radius
    }

    @Test func areaLightsNeverCastShadows() {
        // The caster search covers the punctual kinds only (area casting is a
        // follow-up), so an area-only scene under castShadows() stays unshadowed.
        let d = freshDrawer()
        d.addLight(.rect(.white, at: Vector3(0, 3, 0), direction: Vector3(0, -1, 0),
                         width: 2, height: 2))
        d.castShadows()
        #expect(d.makeLighting().shadowLight == -1)
    }

    // MARK: Shadow casters

    @Test func directionalCasterUsesThe2DMap() {
        let d = freshDrawer()
        d.addLight(.directional(.white, direction: Vector3(-0.5, -1, -0.3)))
        d.castShadows()
        let u = d.makeLighting()
        #expect(u.shadowKind == 0)      // a 2D (orthographic) shadow map
        #expect(u.shadowLight == 0)
    }

    @Test func directionalIsPreferredOverPointAsTheCaster() {
        // With both present, the directional casts (the 2D map), not the point.
        let d = freshDrawer()
        d.addLight(.point(.white, at: Vector3(0, 3, 0)))
        d.addLight(.directional(.white, direction: Vector3(0, -1, 0)))
        d.castShadows()
        let u = d.makeLighting()
        #expect(u.shadowKind == 0)
        #expect(u.shadowLight == 1)     // the directional's index, not the point's
    }

    @Test func pointCasterPacksFarPlane() {
        // A point light with no directional/spot is the caster: an omnidirectional cube
        // map storing linear distance. It carries the far plane in `shadowDepthA` (the
        // normalizer for the stored distance). The camera (freshDrawer) is at distance 5
        // from the target; the light is 3 from the target, so far = 3 + 1.5·5 = 10.5.
        let d = freshDrawer()
        d.addLight(.point(.white, at: Vector3(0, 3, 0)))
        d.castShadows()
        let u = d.makeLighting()
        #expect(u.shadowKind == 1)      // a cube shadow map
        #expect(u.shadowLight == 0)
        #expect(close(u.shadowDepthA, 10.5))   // far plane = dist(3) + 1.5·r(5)
    }

    @Test func specularDefaultsToTheDiffuseColor() {
        let d = freshDrawer()
        d.addLight(.directional(Color(red: 0.8, green: 0.4, blue: 0.2), direction: Vector3(0, -1, 0)))
        let l = d.makeLighting().lights.0
        // No specular set → the highlight tint matches the diffuse color, so a
        // single-color light shades exactly as before.
        #expect(close(l.specular.x, l.color.x) && close(l.specular.y, l.color.y) && close(l.specular.z, l.color.z))
    }

    @Test func specularTintPacksSeparately() {
        let d = freshDrawer()
        d.addLight(.directional(.black, direction: Vector3(0, -1, 0), intensity: 0.5, specular: .white))
        let l = d.makeLighting().lights.0
        // Diffuse black, specular white × intensity — the two are independent.
        #expect(close(l.color.x, 0))
        #expect(close(l.specular.x, Float(Color.srgbToLinear(1.0) * 0.5)))
    }

    @Test func softnessPacksAndClamps() {
        let d = freshDrawer()
        d.addLight(.directional(.white, direction: Vector3(0, -1, 0), softness: 0.4))
        #expect(close(d.makeLighting().lights.0.softness, 0.4))
        let d2 = freshDrawer()
        d2.addLight(.directional(.white, direction: Vector3(0, -1, 0), softness: 5))   // clamps to 1
        #expect(close(d2.makeLighting().lights.0.softness, 1))
    }

    @Test func lightsCapAtMax() {
        let d = freshDrawer()
        for _ in 0..<(Int(OLLIN_MAX_LIGHTS) + 4) {
            d.addLight(.point(.white, at: .zero))
        }
        #expect(d.makeLighting().lightCount == Int32(OLLIN_MAX_LIGHTS))
    }

    @Test func cameraEyeIsPacked() {
        let d = Drawer()
        d.beginFrame()
        d.camera(Camera3D(eye: Vector3(1, 2, 3), target: .zero))
        let u = d.makeLighting()
        #expect(close(u.cameraPosition.x, 1) && close(u.cameraPosition.y, 2) && close(u.cameraPosition.z, 3))
    }

    // MARK: Material on the batch

    @Test func materialRidesTheBatchUniform() {
        let d = freshDrawer()
        d.specular(0.6)
        d.shininess(50)
        d.drawMesh(.box(size: 1))
        let finish = d.batches.last!.finish
        #expect(close(finish.specular, 0.6))   // bound per batch as a uniform
        #expect(close(finish.shininess, 50))
        // The Blinn-Phong material rides the batch uniform, not the vertices. The w slots
        // carry only the ray-traced-reflection finish: a non-PBR mesh bakes metalness 0
        // (normal.w) and roughness 1 (position.w), so a reflection treats it as diffuse.
        #expect(close(d.meshVertices.first!.position.w, 1))
        #expect(close(d.meshVertices.first!.normal.w, 0))
    }

    @Test func materialIsSavedByState() {
        let d = freshDrawer()
        d.specular(0.6); d.shininess(50)
        d.pushState()
        d.specular(0.1); d.shininess(8)
        d.popState()
        d.drawMesh(.box(size: 1))
        let finish = d.batches.last!.finish
        #expect(close(finish.specular, 0.6) && close(finish.shininess, 50))
    }

    @Test func materialChangeBreaksTheSolidBatch() {
        // A material(_:) change opens a fresh batch (the finish is one per-batch uniform),
        // but consecutive solids with the same finish merge into one.
        let d = freshDrawer()
        d.material(.clay); d.drawMesh(.box(size: 1)); d.drawMesh(.box(size: 1))
        d.material(.glossy); d.drawMesh(.box(size: 1))
        let meshBatches = d.batches.filter { $0.kind == .mesh3D }
        #expect(meshBatches.count == 2)
    }

    // MARK: Lighting presets

    @Test func standardPresetIsTheDefaultRig() {
        // The auto-lit default and `.standard` are one source of truth.
        #expect(LightingPreset.standard.ambient == Drawer.defaultAmbient)
        #expect(LightingPreset.standard.lights == Drawer.defaultLights)
    }

    @Test func builtInPresetsAreCurated() {
        // A small, hand-picked set — each non-empty, none a sprawling catalog.
        let presets: [LightingPreset] = [.standard, .threePoint, .goldenHour, .noir, .studio, .moonlight]
        for p in presets {
            #expect(!p.lights.isEmpty)
            #expect(p.lights.count <= 4)
        }
    }

    @Test func intensifiedScalesEveryLight() {
        let dimmed = LightingPreset.studio.intensified(by: 0.5)
        for (a, b) in zip(LightingPreset.studio.lights, dimmed.lights) {
            #expect(close(Float(b.intensity), Float(a.intensity * 0.5)))
        }
        // Ambient is the shadow floor, not the key brightness — left untouched.
        #expect(dimmed.ambient == LightingPreset.studio.ambient)
    }
}

/// Rendered probes for the area-light shading contract: a panel lights the side
/// it faces (and only that side unless two-sided), and brightness falls off with
/// distance (unlike the punctual kinds). Pixel probes, not snapshots: the claims
/// are directional, so a tolerance-banded pixel is the discriminating check.
@Suite
@MainActor
struct AreaLightRenderProbes {

    private func centerPixel(_ mode: AreaLightProbe.Mode) throws -> Int {
        let image = try #require(OllinApp.image(of: AreaLightProbe.make(mode), frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let i = (h / 2 * w + w / 2) * 4
        return Int(data[i])   // the quad is white-lit, so red suffices
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aPanelLightsWhatItFaces() throws {
        let lit = try centerPixel(.front)
        #expect(lit > 100, "expected a clearly lit surface, got \(lit)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aOneSidedPanelLeavesItsBackDark() throws {
        let dark = try centerPixel(.facingAway)
        #expect(dark < 12, "a panel facing away from the surface still lit it: \(dark)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aTwoSidedPanelLightsBothSides() throws {
        let lit = try centerPixel(.facingAwayTwoSided)
        #expect(lit > 100, "expected the two-sided back face to light, got \(lit)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func brightnessFallsOffWithDistance() throws {
        let near = try centerPixel(.front)
        let far = try centerPixel(.far)
        #expect(far < near - 30, "expected a distant panel dimmer: near \(near), far \(far)")
    }
}

/// The render probe: a white camera-facing quad lit by one rect panel, placed per
/// mode, at a small canvas for speed. The default material (specular 0) keeps the
/// reading a pure diffuse term.
private final class AreaLightProbe: Sketch {
    enum Mode { case front, facingAway, facingAwayTwoSided, far }
    var mode = Mode.front

    static func make(_ mode: Mode) -> AreaLightProbe {
        let probe = AreaLightProbe()
        probe.mode = mode
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        camera(.orbiting(radius: 3))
        switch mode {
        case .front:
            rectLight(.white, at: Vector3(0, 0, 2), direction: Vector3(0, 0, -1),
                      width: 2, height: 2, intensity: 2)
        case .facingAway:
            rectLight(.white, at: Vector3(0, 0, 2), direction: Vector3(0, 0, 1),
                      width: 2, height: 2, intensity: 2)
        case .facingAwayTwoSided:
            rectLight(.white, at: Vector3(0, 0, 2), direction: Vector3(0, 0, 1),
                      width: 2, height: 2, twoSided: true, intensity: 2)
        case .far:
            rectLight(.white, at: Vector3(0, 0, 6), direction: Vector3(0, 0, -1),
                      width: 2, height: 2, intensity: 2)
        }
        fill(.white)
        drawMesh(Mesh(positions: [Vector3(-1, -1, 0), Vector3(1, -1, 0),
                                  Vector3(1, 1, 0), Vector3(-1, 1, 0)],
                      normals: [.unitZ, .unitZ, .unitZ, .unitZ],
                      indices: [0, 1, 2, 0, 2, 3]))
    }
}

/// `lightingPreset(_:)` is the bare facade; checks here go through `Drawer` to pin
/// that a preset packs as a custom (sketch-controlled) rig.
@Suite
struct LightingPresetFacadeTests {

    private func close(_ a: Float, _ b: Float, _ eps: Float = 1e-5) -> Bool { abs(a - b) <= eps }

    @Test func presetSetsAmbientAndLights() {
        let d = Drawer()
        d.beginFrame()
        d.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        // Mirror what Sketch.lightingPreset(_:) does on the drawer.
        let preset = LightingPreset.threePoint
        d.ambientLight(preset.ambient)
        for light in preset.lights { d.addLight(light) }
        let u = d.makeLighting()
        #expect(u.enabled == 1)
        #expect(u.lightCount == Int32(preset.lights.count))
        #expect(close(u.ambient.x, Float(Color.srgbToLinear(preset.ambient.red))))
    }
}
