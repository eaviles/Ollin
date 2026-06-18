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
        // The vertex w slots no longer carry the material (only the wireframe line width).
        #expect(close(d.meshVertices.first!.position.w, 0))
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
