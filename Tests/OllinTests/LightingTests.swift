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

    @Test func rectCasterPacksASpotStyleMap() {
        // A rect panel with no punctual light casts: a spot-style perspective map
        // from the panel's center (shadowKind 0), the PCSS penumbra sized from the
        // panel's extent (shadowDepthA > 0 at the default softness) and the
        // perspective linearization term negative (the spot-path flag).
        let d = freshDrawer()
        d.addLight(.rect(.white, at: Vector3(0, 3, 0), direction: Vector3(0, -1, 0),
                         width: 2, height: 2))
        d.castShadows()
        let u = d.makeLighting()
        #expect(u.shadowKind == 0)
        #expect(u.shadowLight == 0)
        #expect(u.shadowDepthA > 0)
        #expect(u.shadowDepthB < 0)
    }

    @Test func casterPacksItsDepthLinearizeConstants() {
        // The transmittance thickness needs absolute world distance from a map
        // depth, so a punctual 2D caster packs both projection constants: the
        // directional box flags orthographic (z = 0), the spot perspective (z = 1),
        // both with the negative [2][2]/[3][2] Metal projections produce; with no
        // caster the field stays zero, the shader's skip sentinel.
        let dir = freshDrawer()
        dir.addLight(.directional(.white, direction: Vector3(0, -1, 0.3)))
        dir.castShadows()
        let a = dir.makeLighting().shadowLinearize
        #expect(a.x < 0 && a.y < 0 && a.z == 0)

        let spot = freshDrawer()
        spot.addLight(.spot(.white, at: Vector3(0, 4, 0), direction: Vector3(0, -1, 0)))
        spot.castShadows()
        let b = spot.makeLighting().shadowLinearize
        #expect(b.x < 0 && b.y < 0 && b.z == 1)
        // The x term matches what the PCSS ratio already carries for a spot.
        #expect(b.x == spot.makeLighting().shadowDepthB)

        let none = freshDrawer()
        none.addLight(.directional(.white, direction: Vector3(0, -1, 0.3)))
        let c = none.makeLighting().shadowLinearize
        #expect(c.x == 0 && c.y == 0 && c.z == 0)
    }

    @Test func panelExtentSizesThePenumbra() {
        // The PCSS penumbra radius comes from the panel's own extent, so doubling
        // the panel doubles the packed texel radius (same position, same frustum;
        // small panels, clear of the 40-texel kernel cap).
        func penumbra(_ side: Double) -> Float {
            let d = freshDrawer()
            d.addLight(.rect(.white, at: Vector3(0, 3, 0), direction: Vector3(0, -1, 0),
                             width: side, height: side))
            d.castShadows()
            return d.makeLighting().shadowDepthA
        }
        let small = penumbra(0.2)
        let big = penumbra(0.4)
        #expect(small > 0)
        #expect(close(big, small * 2, 1e-3))
    }

    @Test func softnessZeroKeepsTheAreaCasterHard() {
        // shadowSoftness(0) routes every caster to the hard legacy 3x3, the area
        // kind included (shadowDepthA == 0 is the shader's hard-path sentinel).
        let d = freshDrawer()
        d.addLight(.disk(.white, at: Vector3(0, 3, 0), direction: Vector3(0, -1, 0),
                         radius: 1))
        d.castShadows()
        d.shadowSoftness(0)
        #expect(d.makeLighting().shadowDepthA == 0)
    }

    @Test func punctualCastersStayPreferredOverArea() {
        // The caster search appends the area kinds after the punctual ones, so a
        // scene holding both casts from its point light, not the panel.
        let d = freshDrawer()
        d.addLight(.rect(.white, at: Vector3(0, 3, 0), direction: Vector3(0, -1, 0),
                         width: 2, height: 2))
        d.addLight(.point(.white, at: Vector3(0, 3, 0)))
        d.castShadows()
        let u = d.makeLighting()
        #expect(u.shadowKind == 1)
        #expect(u.shadowLight == 1)     // the point's index, not the rect's
    }

    @Test func aTubeNeverCasts() {
        // A tube emits radially (no facing axis to render a map from), so a
        // tube-only scene under castShadows() stays unshadowed.
        let d = freshDrawer()
        d.addLight(.tube(.white, from: Vector3(-1, 2, 0), to: Vector3(1, 2, 0)))
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

    // MARK: More than one caster

    /// The frame's caster list, read out of the packed uniform (a C fixed-size array
    /// imports as a homogeneous tuple).
    private func casters(_ u: OllinLighting) -> [OllinShadowCaster] {
        var u = u
        let n = min(Int(u.shadowCasterCount), Int(OLLIN_MAX_SHADOW_CASTERS))
        guard n > 0 else { return [] }
        return withUnsafePointer(to: &u.shadowCasters) { ptr in
            ptr.withMemoryRebound(to: OllinShadowCaster.self,
                                  capacity: Int(OLLIN_MAX_SHADOW_CASTERS)) { buf in
                (0..<n).map { buf[$0] }
            }
        }
    }

    @Test func aKeyLightAndASpotBothCast() {
        // The headline: two lights that each render a 2D map, so neither waits for
        // the other. The layer each one renders into is its slot index.
        let d = freshDrawer()
        d.addLight(.directional(.white, direction: Vector3(0, -1, 0)))
        d.addLight(.spot(.white, at: Vector3(2, 3, 0), direction: Vector3(0, -1, 0)))
        d.castShadows()
        let list = casters(d.makeLighting())
        #expect(list.count == 2)
        #expect(list[0].lightIndex == 0 && list[0].kind == 0)
        #expect(list[1].lightIndex == 1 && list[1].kind == 0)
    }

    @Test func aPointLightCastsFromAnySlot() {
        // A point light beside a directional key takes a slot of its own, and keeps its
        // own kind there: the renderer hands each point caster a cube of the cube-map
        // array, or traces every one of them against the frame's one structure.
        let d = freshDrawer()
        d.addLight(.directional(.white, direction: Vector3(0, -1, 0)))
        d.addLight(.point(.white, at: Vector3(0, 3, 0)))
        d.castShadows()
        let beside = casters(d.makeLighting())
        #expect(beside.count == 2)
        #expect(beside[0].lightIndex == 0 && beside[0].kind == 0)   // the key's 2D map
        #expect(beside[1].lightIndex == 1 && beside[1].kind == 1)   // the point light's cube

        let alone = freshDrawer()
        alone.addLight(.point(.white, at: Vector3(0, 3, 0)))
        alone.castShadows()
        #expect(casters(alone.makeLighting()).map(\.kind) == [1])
    }

    @Test func theSingleCasterFieldsMirrorSlotZero() {
        // Every system that predates the list still reads the single-caster fields, so
        // they must carry exactly what slot 0 carries.
        let d = freshDrawer()
        d.addLight(.spot(.white, at: Vector3(2, 3, 0), direction: Vector3(0, -1, 0)))
        d.addLight(.directional(.white, direction: Vector3(0, -1, 0)))
        d.castShadows()
        let u = d.makeLighting()
        let primary = casters(u)[0]
        #expect(u.shadowLight == primary.lightIndex)
        #expect(u.shadowKind == primary.kind)
        #expect(close(u.shadowStrength, primary.strength))
        #expect(close(u.shadowTexelWorld, primary.texelWorld))
        #expect(close(u.shadowDepthA, primary.depthA))
        #expect(close(u.shadowDepthB, primary.depthB))
        #expect(u.lightViewProjection == primary.lightViewProjection)
        #expect(u.shadowLinearize == primary.linearize)
    }

    @Test func aLightCanOptOutOfCasting() {
        // A fill light lights the scene and throws nothing.
        let d = freshDrawer()
        d.addLight(.directional(.white, direction: Vector3(0, -1, 0)))
        d.addLight(.spot(.white, at: Vector3(2, 3, 0),
                         direction: Vector3(0, -1, 0)).castingShadow(false))
        d.castShadows()
        let list = casters(d.makeLighting())
        #expect(list.count == 1)
        #expect(list[0].lightIndex == 0)
    }

    @Test func optingThePrimaryOutHandsTheJobOn() {
        let d = freshDrawer()
        d.addLight(.directional(.white, direction: Vector3(0, -1, 0)).castingShadow(false))
        d.addLight(.spot(.white, at: Vector3(2, 3, 0), direction: Vector3(0, -1, 0)))
        d.castShadows()
        let u = d.makeLighting()
        #expect(u.shadowLight == 1)     // the spot, not the opted-out directional
        #expect(casters(u).count == 1)
    }

    @Test func severalPointLightsEachTakeASlot() {
        // The spot is the primary here (a spot outranks a point), and both point lights
        // cast beside it, each from a slot of its own and each still a cube caster.
        let d = freshDrawer()
        d.addLight(.point(.white, at: Vector3(0, 3, 0)))
        d.addLight(.point(.white, at: Vector3(3, 3, 0)))
        d.addLight(.spot(.white, at: Vector3(2, 3, 0), direction: Vector3(0, -1, 0)))
        d.castShadows()
        let list = casters(d.makeLighting())
        #expect(list.count == 3)
        #expect(list[0].lightIndex == 2 && list[0].kind == 0)   // the spot, the primary
        #expect(list[1].lightIndex == 0 && list[1].kind == 1)
        #expect(list[2].lightIndex == 1 && list[2].kind == 1)
    }

    @Test func theCasterListCapsAtFour() {
        let d = freshDrawer()
        for k in 0..<6 {
            d.addLight(.spot(.white, at: Vector3(Double(k), 3, 0), direction: Vector3(0, -1, 0)))
        }
        d.castShadows()
        let u = d.makeLighting()
        #expect(u.shadowCasterCount == Int32(OLLIN_MAX_SHADOW_CASTERS))
        #expect(casters(u).map { Int($0.lightIndex) } == [0, 1, 2, 3])   // the ones set first
    }

    @Test func aTubeIsNeverInTheCasterList() {
        let d = freshDrawer()
        d.addLight(.directional(.white, direction: Vector3(0, -1, 0)))
        d.addLight(.tube(.white, from: Vector3(-1, 2, 0), to: Vector3(1, 2, 0)))
        d.castShadows()
        #expect(casters(d.makeLighting()).count == 1)
    }

    @Test func noShadowsMeansNoCasters() {
        let d = freshDrawer()
        d.addLight(.directional(.white, direction: Vector3(0, -1, 0)))
        d.addLight(.spot(.white, at: Vector3(2, 3, 0), direction: Vector3(0, -1, 0)))
        #expect(d.makeLighting().shadowCasterCount == 0)
    }

    @Test func eachCasterCarriesItsOwnProjection() {
        // Two casters must not share one map: their view-projections differ, which is
        // what puts each shadow where its own light throws it.
        let d = freshDrawer()
        d.addLight(.directional(.white, direction: Vector3(0, -1, 0)))
        d.addLight(.spot(.white, at: Vector3(2, 3, 0), direction: Vector3(-0.4, -1, 0)))
        d.castShadows()
        let list = casters(d.makeLighting())
        #expect(list[0].lightViewProjection != list[1].lightViewProjection)
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

    // MARK: Contact shadows

    @Test func contactShadowsPackTheRayLengthWithTheCaster() {
        // The default length derives from the eye-to-target distance (2.5%), so
        // the one-liner seats objects at any scene scale; an explicit length
        // passes through in world units.
        let d = freshDrawer()   // eye (0,0,5), target zero → r = 5
        d.addLight(.directional(.white, direction: Vector3(0, -1, 0.3)))
        d.castShadows()
        d.contactShadows()
        let u = d.makeLighting()
        #expect(close(u.contactShadow.x, 0.125))
        d.contactShadows(length: 3)
        #expect(close(d.makeLighting().contactShadow.x, 3))
    }

    @Test func contactShadowsAreInertWithoutACaster() {
        // The march refines the caster's shadow, so without `castShadows()` (or
        // with no light qualifying) the gate stays zero and the carriers'
        // sample branch is untaken.
        let d = freshDrawer()
        d.addLight(.directional(.white, direction: Vector3(0, -1, 0.3)))
        d.contactShadows()
        #expect(d.makeLighting().contactShadow.x == 0)
    }

    @Test func contactShadowsResetEachFrame() {
        let d = freshDrawer()
        d.addLight(.directional(.white, direction: Vector3(0, -1, 0.3)))
        d.castShadows()
        d.contactShadows()
        d.beginFrame()
        d.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        d.addLight(.directional(.white, direction: Vector3(0, -1, 0.3)))
        d.castShadows()
        #expect(d.makeLighting().contactShadow.x == 0)   // per-frame, like the lights
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

/// Behavioral probes for the area-light *cast shadow*: a floor under a hovering slab,
/// lit by one overhead rect panel, rendered with and without `castShadows()` so the
/// per-pixel difference isolates the shadow. They read the same on either device path
/// (the traced panel on an RT GPU, the spot-style PCSS map elsewhere), so they gate on
/// Metal only.
@Suite
@MainActor
struct AreaShadowRenderProbes {

    private func pixels(_ sketch: Sketch) throws -> [UInt8] {
        let image = try #require(OllinApp.image(of: sketch, frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// Red-channel difference per pixel (lit-minus-shadowed; the scene is grayscale).
    private func shadowDiff(panelSide: Double) throws -> [Int] {
        let lit = try pixels(AreaShadowProbe.make(panelSide: panelSide, casts: false))
        let shadowed = try pixels(AreaShadowProbe.make(panelSide: panelSide, casts: true))
        return stride(from: 0, to: lit.count, by: 4).map { Int(lit[$0]) - Int(shadowed[$0]) }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aPanelCasterDropsAShadow() throws {
        let diff = try shadowDiff(panelSide: 1.0)
        let darkened = diff.filter { $0 > 20 }.count
        #expect(darkened > 200, "expected a clear shadow patch, got \(darkened) darkened pixels")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aBiggerPanelSoftensTheShadow() throws {
        // The penumbra comes from the panel's real extent: growing the panel (its
        // radiance scaled down to keep the poured flux comparable) shrinks the
        // fully-dark core and widens the partial band. Both counts are normalized
        // to each render's own deepest shadow, so the two sizes compare fairly.
        func bands(_ side: Double) throws -> (umbra: Int, penumbra: Int) {
            let diff = try shadowDiff(panelSide: side)
            let maxDiff = diff.max() ?? 0
            guard maxDiff > 30 else { return (0, 0) }
            let umbra = diff.filter { $0 > Int(0.8 * Double(maxDiff)) }.count
            let penumbra = diff.filter {
                $0 > Int(0.15 * Double(maxDiff)) && $0 < Int(0.6 * Double(maxDiff))
            }.count
            return (umbra, penumbra)
        }
        let small = try bands(0.5)
        let big = try bands(2.5)
        #expect(big.umbra < small.umbra,
                "expected the umbra to shrink as the panel grows: small \(small), big \(big)")
        #expect(big.penumbra > small.penumbra,
                "expected the partial band to widen as the panel grows: small \(small), big \(big)")
    }
}

/// The shadow probe scene: a gray floor, a slab hovering over it, one overhead rect
/// panel. `casts` flips `castShadows()` with everything else identical, so a pixel
/// difference is the cast shadow alone. Radiance scales down with panel area so a
/// bigger panel pours a comparable total flux (the lit-floor level stays put).
private final class AreaShadowProbe: Sketch {
    var casts = true
    var panelSide = 1.0

    static func make(panelSide: Double, casts: Bool) -> AreaShadowProbe {
        let probe = AreaShadowProbe()
        probe.panelSide = panelSide
        probe.casts = casts
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        camera(.orbiting(radius: 8, elevation: 0.9))
        rectLight(.white, at: Vector3(0, 5, 0), direction: Vector3(0, -1, 0),
                  width: panelSide, height: panelSide,
                  intensity: 6 / (panelSide * panelSide))
        if casts { castShadows() }
        fill(Color(white: 0.85))
        drawPlane(width: 20, depth: 20)
        withState {
            translate(0, 1.5, 0)
            drawBox(width: 1.4, height: 0.15, depth: 1.4)
        }
    }
}

/// Behavioral probe for area light seen *in a ray-traced reflection*: the hit shade
/// evaluates the exact LTC diffuse, so a panel-lit wall must stay lit in a mirror.
/// Rendered with the panel on and off, everything else identical, so the mirrored
/// region's difference isolates the panel's reflected light; pins the deferred trace's
/// LTC resolve + amp-table bind (losing either goes dark only in the reflection).
/// RT-gated: without ray tracing there is no traced reflection to probe.
@Suite
@MainActor
struct AreaReflectionRenderProbes {

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aPanelLitWallStaysLitInAMirror() throws {
        func mirroredMean(panelOn: Bool) throws -> Double {
            let image = try #require(OllinApp.image(of: AreaReflectionProbe.make(panelOn: panelOn),
                                                    frame: 1))
            let w = image.width, h = image.height
            var data = [UInt8](repeating: 0, count: w * h * 4)
            let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            // The mirrored wall sits in the lower-middle band of the frame.
            var sum = 0, count = 0
            for y in (h * 55 / 100)..<(h * 72 / 100) {
                for x in (w * 36 / 100)..<(w * 70 / 100) {
                    sum += Int(data[(y * w + x) * 4]); count += 1
                }
            }
            return Double(sum) / Double(count)
        }
        let lit = try mirroredMean(panelOn: true)
        let dark = try mirroredMean(panelOn: false)
        #expect(lit - dark > 40,
                "expected the panel's light in the mirrored wall: on \(lit), off \(dark)")
    }
}

/// The reflection probe scene: a warm strip panel over a white diffuse wall, seen in
/// a near-mirror metal floor under a bundled environment with ray-traced reflections.
private final class AreaReflectionProbe: Sketch {
    var panelOn = true

    static func make(panelOn: Bool) -> AreaReflectionProbe {
        let probe = AreaReflectionProbe()
        probe.panelOn = panelOn
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 0.8, 0), radius: 9,
                         azimuth: 0.2, elevation: 0.35))
        environment(.night)
        rayTracedReflections()
        if panelOn {
            rectLight(Color(hue: 0.09, saturation: 0.3, brightness: 1.0),
                      at: Vector3(0, 2.2, -1.0), direction: Vector3(0, -0.35, -1),
                      width: 3.0, height: 0.8, intensity: 10)
        }
        withState {
            fill(Color(white: 0.9))
            material(.metal(roughness: 0.05))
            drawPlane(width: 16, depth: 12)
        }
        withState {
            translate(0, 1.6, -2.6)
            fill(.white)
            material(.dielectric(roughness: 0.85))
            drawBox(width: 5.0, height: 3.2, depth: 0.25)
        }
    }
}

/// Behavioral probe for the hit shade's roughness fade: a surface seen *in* a reflection
/// carries only one traced ray, which has no lobe width, so a rough hit fades that ray
/// back into the prefiltered environment. The measurable consequence is that past the
/// fade's ramp, geometry in the hit's own mirror direction stops mattering: blocking that
/// direction with a black wall must leave a rough surface's mirrored image alone while
/// visibly darkening a smooth one. Rendered as two counterfactual pairs (one knob, the
/// wall's roughness) because the whole-frame snapshot diff averages this away entirely.
/// RT-gated: without ray tracing there is no traced hit to fade.
@Suite
@MainActor
struct ReflectionRoughnessProbes {

    /// Mean red over the band of the mirror floor holding the wall's reflected image.
    private func mirroredWallMean(roughness: Double, blocked: Bool) throws -> Double {
        let scene = ReflectionRoughnessProbe.make(roughness: roughness, blocked: blocked)
        let image = try #require(OllinApp.image(of: scene, frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0, count = 0
        for y in (h * 56 / 100)..<(h * 70 / 100) {
            for x in (w * 38 / 100)..<(w * 68 / 100) {
                sum += Int(data[(y * w + x) * 4]); count += 1
            }
        }
        return Double(sum) / Double(count)
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aRoughSurfaceInAMirrorIgnoresWhatItFaces() throws {
        // Roughness 0.85 is past the fade's ramp, so the traced bounce is discarded
        // entirely and only the prefiltered environment remains: walling off the mirror
        // direction can have no effect. Without the fade the wall would mirror the black
        // wall sharply and this region would drop.
        let open = try mirroredWallMean(roughness: 0.85, blocked: false)
        let walled = try mirroredWallMean(roughness: 0.85, blocked: true)
        #expect(abs(open - walled) < 2,
                "expected a rough wall's mirrored image to ignore its own mirror direction: open \(open), walled \(walled)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aSmoothSurfaceInAMirrorStillShowsWhatItFaces() throws {
        // The counterfactual that gives the test above its teeth: below the ramp the
        // traced bounce survives at full weight, so the same black wall must show up.
        let open = try mirroredWallMean(roughness: 0.05, blocked: false)
        let walled = try mirroredWallMean(roughness: 0.05, blocked: true)
        #expect(open - walled > 6,
                "expected a smooth wall to mirror the black wall it faces: open \(open), walled \(walled)")
    }
}

/// The roughness-fade probe scene: a white wall over a near-mirror floor under a bundled
/// environment, its reflection the thing measured. `blocked` stands a black wall behind
/// the camera, out of frame, filling the white wall's mirror direction: it is invisible
/// to the eye and reachable only by a traced ray.
private final class ReflectionRoughnessProbe: Sketch {
    var roughness = 0.85
    var blocked = false

    static func make(roughness: Double, blocked: Bool) -> ReflectionRoughnessProbe {
        let probe = ReflectionRoughnessProbe()
        probe.roughness = roughness
        probe.blocked = blocked
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 0.8, 0), radius: 9,
                         azimuth: 0.2, elevation: 0.35))
        environment(.night)
        rayTracedReflections()
        directionalLight(.white, direction: Vector3(-0.3, -1, -0.4), intensity: 0.8)
        withState {
            fill(Color(white: 0.9))
            material(.metal(roughness: 0.05))
            drawPlane(width: 16, depth: 12)
        }
        withState {
            translate(0, 1.6, -2.6)
            fill(.white)
            // Metal, so the reflected lobe *is* the whole appearance: a dielectric
            // reflects about 4% head-on and buries the effect under its diffuse body.
            material(.metal(roughness: roughness))
            drawBox(width: 5.0, height: 3.2, depth: 0.25)
        }
        if blocked {
            withState {
                translate(0, 1.6, 11)
                fill(.black)
                material(.dielectric(roughness: 0.9))
                drawBox(width: 40, height: 30, depth: 0.5)
            }
        }
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

/// Behavioral probes for light shaping: an IES profile reshaping a point light's
/// throw and a cookie masking (and orienting, and rolling) a spot's projection,
/// each read off a rendered frame against its unshaped counterpart. Metal-gated;
/// the shaped paths are identical across RT and non-RT devices.
@Suite
@MainActor
struct LightShapingRenderProbes {

    private func pixels(_ sketch: Sketch) throws -> (data: [UInt8], w: Int, h: Int) {
        let image = try #require(OllinApp.image(of: sketch, frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (data, w, h)
    }

    private func red(_ p: (data: [UInt8], w: Int, h: Int), _ x: Int, _ y: Int) -> Int {
        Int(p.data[(y * p.w + x) * 4])
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aProfileReshapesTheThrow() throws {
        // Unshaped: the point light's peak lands at the quad's center.
        let plain = try pixels(LightShapingProbe.make(.plainPoint))
        let plainCenter = red(plain, plain.w / 2, plain.h / 2)
        #expect(plainCenter > 100, "expected a lit center without a profile, got \(plainCenter)")

        // The ring profile is dark on axis and bright in a 30-degree band, so the
        // center goes dark while a ring of the same row lights up.
        let ringed = try pixels(LightShapingProbe.make(.ringProfile))
        let ringedCenter = red(ringed, ringed.w / 2, ringed.h / 2)
        #expect(ringedCenter < 12, "the profile's dark axis still lit the center: \(ringedCenter)")
        let row = ringed.h / 2
        let rowMax = (0..<ringed.w).map { red(ringed, $0, row) }.max() ?? 0
        #expect(rowMax > 80, "expected the profile's bright ring in the row, got max \(rowMax)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aCookieMasksAndOrientsTheProjection() throws {
        // The cookie's left half is black, right half white; the projector
        // convention lands the image un-mirrored for the camera behind the light,
        // so the rendered right half is lit and the left dark.
        let p = try pixels(LightShapingProbe.make(.halfCookie))
        let left = red(p, p.w / 4, p.h / 2)
        let right = red(p, 3 * p.w / 4, p.h / 2)
        #expect(right > 80, "the cookie's white half should light, got \(right)")
        #expect(left < 12, "the cookie's black half should block, got \(left)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func rollSpinsTheProjection() throws {
        // A half-turn of roll swaps the cookie's halves.
        let p = try pixels(LightShapingProbe.make(.halfCookieRolled))
        let left = red(p, p.w / 4, p.h / 2)
        let right = red(p, 3 * p.w / 4, p.h / 2)
        #expect(left > 80, "after a half-turn roll the left half should light, got \(left)")
        #expect(right < 12, "after a half-turn roll the right half should block, got \(right)")
    }
}

/// The light-shaping render probe: the camera-facing white quad from the area
/// probes, lit by one shaped point or spot light. The ring IES fixture is
/// authored here (dark on axis, bright in a band around 30 degrees).
private final class LightShapingProbe: Sketch {
    enum Mode { case plainPoint, ringProfile, halfCookie, halfCookieRolled }
    var mode = Mode.plainPoint

    static let ringIES = """
    IESNA:LM-63-2002
    [TEST] Ollin probe fixture
    TILT=NONE
    1 1000 1 8 1 1 2 0.1 0.1 0.1
    1.0 1.0 100
    0 10 20 30 40 50 60 90
    0
    0 0 800 1000 800 200 0 0
    """

    static func make(_ mode: Mode) -> LightShapingProbe {
        let probe = LightShapingProbe()
        probe.mode = mode
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        camera(.orbiting(radius: 3))
        switch mode {
        case .plainPoint:
            pointLight(.white, at: Vector3(0, 0, 1.5), intensity: 1.2,
                       axis: Vector3(0, 0, -1))
        case .ringProfile:
            let profile = IESProfile(string: LightShapingProbe.ringIES)!
            pointLight(.white, at: Vector3(0, 0, 1.5), intensity: 1.2,
                       profile: profile, axis: Vector3(0, 0, -1))
        case .halfCookie, .halfCookieRolled:
            var gobo = Image(width: 8, height: 8, color: .black)
            for y in 0..<8 { for x in 4..<8 { gobo[x, y] = .white } }
            spotLight(.white, at: Vector3(0, 0, 2), direction: Vector3(0, 0, -1),
                      angle: 1.9, penumbra: 0.1, intensity: 1.2,
                      cookie: LightCookie(gobo),
                      roll: mode == .halfCookieRolled ? .pi : 0)
        }
        fill(.white)
        drawMesh(Mesh(positions: [Vector3(-1, -1, 0), Vector3(1, -1, 0),
                                  Vector3(1, 1, 0), Vector3(-1, 1, 0)],
                      normals: [.unitZ, .unitZ, .unitZ, .unitZ],
                      indices: [0, 1, 2, 0, 2, 3]))
    }
}

/// Behavioral probes for contact shadows (`contactShadows()`): the same scene
/// rendered with only the march flipped, so a pixel difference isolates the
/// screen-space term (the map's own shadow is on in both). The A/B idiom of
/// `AreaShadowRenderProbes`; `hasMetal` only, since the march runs on any GPU.
@Suite
@MainActor
struct ContactShadowRenderProbes {

    private func pixels(_ sketch: Sketch) throws -> [UInt8] {
        let image = try #require(OllinApp.image(of: sketch, frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// Red-channel lit-minus-marched difference (the scene is near-grayscale).
    private func contactDiff(caster: ContactShadowProbe.Caster) throws -> [Int] {
        let plain = try pixels(ContactShadowProbe.make(caster: caster, contact: false))
        let marched = try pixels(ContactShadowProbe.make(caster: caster, contact: true))
        return stride(from: 0, to: plain.count, by: 4).map { Int(plain[$0]) - Int(marched[$0]) }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theMarchSeatsARestingBox() throws {
        let diff = try contactDiff(caster: .directional)
        let darkened = diff.filter { $0 > 10 }.count
        #expect(darkened > 15, "expected a contact seam at the box's base, got \(darkened) darkened pixels")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aPointCasterSeatsToo() throws {
        // The positional branch: the march direction is per pixel, toward the
        // light's position.
        let diff = try contactDiff(caster: .point)
        let darkened = diff.filter { $0 > 10 }.count
        #expect(darkened > 15, "expected a contact seam under a point caster, got \(darkened)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aSpotCasterSeatsToo() throws {
        let diff = try contactDiff(caster: .spot)
        let darkened = diff.filter { $0 > 10 }.count
        #expect(darkened > 15, "expected a contact seam under a spot caster, got \(darkened)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func withoutACasterTheMarchIsInert() throws {
        // `contactShadows()` without `castShadows()`: the gate stays zero and the
        // frame is byte-identical to one that never asked.
        let off = ContactShadowProbe.make(caster: .directional, contact: false)
        off.casts = false
        let on = ContactShadowProbe.make(caster: .directional, contact: true)
        on.casts = false
        #expect(try pixels(off) == pixels(on))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anEmptyFloorHoldsNoFalseShadow() throws {
        // A lone floor with nothing resting on it: every ray marches into open
        // air, the mask stays all-lit (multiplying by exactly 1.0), and the frame
        // is byte-identical. A regression canary for marching acne on the ground
        // plane; the curved-surface acne treatment is pinned by the march's
        // camera-ward lift (see the shader comment), which a whole-frame probe
        // can't isolate.
        let off = ContactShadowProbe.make(caster: .directional, contact: false)
        off.floorOnly = true
        let on = ContactShadowProbe.make(caster: .directional, contact: true)
        on.floorOnly = true
        #expect(try pixels(off) == pixels(on))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func twoRendersAgreeByteForByte() throws {
        // The dither is a pure function of pixel position, so the whole term is
        // deterministic: two fresh renders agree exactly.
        let a = try pixels(ContactShadowProbe.make(caster: .directional, contact: true))
        let b = try pixels(ContactShadowProbe.make(caster: .directional, contact: true))
        #expect(a == b)
    }
}

/// The contact probe scene: a gray floor, a box resting flush on it, one caster.
/// `contact` flips `contactShadows()` with everything else identical (the map's
/// shadow stays on), so a pixel difference is the screen-space term alone.
private final class ContactShadowProbe: Sketch {
    enum Caster { case directional, point, spot }
    var caster: Caster = .directional
    var contact = true
    var casts = true
    var floorOnly = false

    static func make(caster: Caster, contact: Bool) -> ContactShadowProbe {
        let probe = ContactShadowProbe()
        probe.caster = caster
        probe.contact = contact
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 0.5, 0), radius: 8,
                         azimuth: 0.4, elevation: 0.3))
        ambientLight(Color(white: 0.2))
        switch caster {
        case .directional:
            directionalLight(.white, direction: Vector3(-0.7, -0.55, -0.3), intensity: 1.0)
        case .point:
            pointLight(.white, at: Vector3(4, 3, 2), intensity: 1.0)
        case .spot:
            spotLight(.white, at: Vector3(4, 4, 2),
                      direction: Vector3(-4, -4, -2).normalized,
                      angle: .pi / 2.5, intensity: 1.0)
        }
        if casts { castShadows() }
        shadowSoftness(0.8)
        if contact { contactShadows() }
        fill(Color(white: 0.85))
        drawPlane(width: 20, depth: 20)
        if !floorOnly {
            withState {
                fill(Color(white: 0.75))
                translate(-0.8, 0.7, 0)
                drawBox(size: 1.4)
            }
            withState {
                fill(Color(white: 0.75))
                translate(1.2, 0.62, 0.8)
                drawSphere(radius: 0.62)
            }
            withState {
                fill(Color(white: 0.75))
                translate(0.6, 0.5, -1.4)
                drawCylinder(radius: 0.5, height: 1.0)
            }
        }
    }
}

/// Behavioral probes for **more than one shadow caster in a frame**: a floor under a
/// hovering box, lit by two lights that throw their shadows to opposite sides. Each
/// light is switched on and off as a caster while everything else stays put, so the
/// per-pixel difference isolates one shadow at a time. The check that matters is the
/// second caster's shadow surviving into the both-cast render: with one caster per
/// frame that region reads fully lit.
@Suite
@MainActor
struct MultipleCasterRenderProbes {

    private func pixels(_ sketch: Sketch) throws -> [UInt8] {
        let image = try #require(OllinApp.image(of: sketch, frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// Red-channel darkening against the unshadowed render (the scene is grayscale).
    private func darkening(_ mode: TwoCasterProbe.Mode, fillIsSpot: Bool = false) throws -> [Int] {
        let lit = try pixels(TwoCasterProbe.make(.none, fillIsSpot: fillIsSpot))
        let shadowed = try pixels(TwoCasterProbe.make(mode, fillIsSpot: fillIsSpot))
        return stride(from: 0, to: lit.count, by: 4).map { Int(lit[$0]) - Int(shadowed[$0]) }
    }

    /// How much of the second caster's own shadow (the part the first caster does not
    /// darken) survives into the render where both cast.
    private func secondShadowSurvival(fillIsSpot: Bool) throws -> (region: Int, kept: Int) {
        let onlyKey = try darkening(.keyOnly, fillIsSpot: fillIsSpot)
        let onlyFill = try darkening(.fillOnly, fillIsSpot: fillIsSpot)
        let both = try darkening(.both, fillIsSpot: fillIsSpot)
        var region = 0, kept = 0
        for i in 0..<both.count where onlyFill[i] > 20 && onlyKey[i] < 5 {
            region += 1
            if both[i] > 20 { kept += 1 }
        }
        return (region, kept)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theSecondCasterThrowsItsOwnShadow() throws {
        // The fill light's own shadow: darkened when it alone casts, untouched by the
        // key light's shadow, so this region belongs to the second caster only.
        let (region, kept) = try secondShadowSurvival(fillIsSpot: false)
        #expect(region > 200, "expected a clear second shadow, got \(region) pixels")
        #expect(kept > region * 9 / 10,
                "the second caster's shadow must survive with both casting: kept \(kept) of \(region)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func bothShadowsLandTogether() throws {
        // The mirror of the check above: the key light's own region survives too, so
        // neither caster overwrites the other's map.
        let onlyKey = try darkening(.keyOnly)
        let onlyFill = try darkening(.fillOnly)
        let both = try darkening(.both)
        var region = 0, kept = 0
        for i in 0..<both.count where onlyKey[i] > 20 && onlyFill[i] < 5 {
            region += 1
            if both[i] > 20 { kept += 1 }
        }
        #expect(region > 200, "expected a clear first shadow, got \(region) pixels")
        #expect(kept > region * 9 / 10, "kept \(kept) of \(region)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aSpotCastsBesideADirectional() throws {
        // The pair a sketch actually reaches for: a key light plus a stage light. The
        // spot is the second caster, so its map is a layer of its own.
        let (region, kept) = try secondShadowSurvival(fillIsSpot: true)
        #expect(region > 200, "expected the spot's own shadow, got \(region) pixels")
        #expect(kept > region * 9 / 10, "kept \(kept) of \(region)")
    }
}

/// The two-caster probe scene: a gray floor, a box hovering over it, and two lights
/// aimed from opposite sides so their shadows fall apart from each other. `mode` picks
/// which of them casts, through the per-light `castsShadow` opt-out, so every render
/// shares one lighting rig and differs only in what throws.
private final class TwoCasterProbe: Sketch {
    enum Mode { case none, keyOnly, fillOnly, both }

    var mode: Mode = .both
    var fillIsSpot = false

    static func make(_ mode: Mode, fillIsSpot: Bool = false) -> TwoCasterProbe {
        let probe = TwoCasterProbe()
        probe.mode = mode
        probe.fillIsSpot = fillIsSpot
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        camera(.orbiting(radius: 9, elevation: 1.0))
        let keyCasts = mode == .keyOnly || mode == .both
        let fillCasts = mode == .fillOnly || mode == .both
        light(Light.directional(.white, direction: Vector3(1, -1.1, 0), intensity: 0.9)
                .castingShadow(keyCasts))
        if fillIsSpot {
            light(Light.spot(.white, at: Vector3(3.4, 4, 0), direction: Vector3(-0.7, -1, 0),
                             angle: 1.1, intensity: 2.2)
                    .castingShadow(fillCasts))
        } else {
            light(Light.directional(.white, direction: Vector3(-1, -1.1, 0), intensity: 0.9)
                    .castingShadow(fillCasts))
        }
        if mode != .none { castShadows() }
        fill(Color(white: 0.85))
        drawPlane(width: 24, depth: 24)
        withState {
            translate(0, 1.6, 0)
            drawBox(size: 1.4)
        }
    }
}
