import Foundation
import simd
@testable import Ollin
import Testing

/// Authored scene animation: parsing glTF animations into `SceneAnimation`,
/// the three sampler modes against hand-computed values (linear, stepped,
/// cubic-spline Hermite), quaternion interpolation along the shortest arc, the
/// clamp-outside-the-keyframe-range rule, the normalized-integer rotation
/// decode, and `apply(_:at:)` semantics: absolute posing, authored components
/// kept where un-animated, matrix-authored nodes untouched, hand-set positions
/// surviving a rotation-only track.
@Suite
@MainActor
struct SceneAnimationTests {

    // MARK: Fixtures

    /// The animation buffer, laid out in order: three 2-key time tracks, a
    /// 2-key rotation (identity to 90 deg about y), a 2-key cubic-spline
    /// translation (in-tangent, value, out-tangent per keyframe), a 2-key
    /// translation starting at t=1, a stepped rotation, and the same 90-degree
    /// rotation quantized as normalized signed shorts.
    private static var animBufferB64: String {
        var buffer = Data()
        func put(_ floats: [Float]) {
            for f in floats { withUnsafeBytes(of: f) { buffer.append(contentsOf: $0) } }
        }
        let halfTurn: Float = 0.7071068
        put([0, 2])                                            // times02 @ 0
        put([0, 1])                                            // times01 @ 8
        put([1, 2])                                            // times12 @ 16
        put([0, 0, 0, 1, 0, halfTurn, 0, halfTurn])            // rotLin @ 24
        put([0, 0, 0, 0, 0, 0, 1, 0, 0,                        // cubic @ 56: a0 v0 b0
             0, 0, 0, 4, 0, 0, 0, 0, 0])                       //             a1 v1 b1
        put([5, 0, 0, 7, 0, 0])                                // late @ 128
        put([0, 0, 0, 1, 0, halfTurn, 0, halfTurn])            // rotStep @ 152
        for v: Int16 in [0, 0, 0, 32767, 0, 23170, 0, 23170] { // quant @ 184
            withUnsafeBytes(of: v) { buffer.append(contentsOf: $0) }
        }
        return buffer.base64EncodedString()
    }

    /// Six meshless nodes, one animation "moves" exercising every mode (plus a
    /// channel targeting the matrix-authored node, which must stay untouched),
    /// and a second animation holding only a morph-weights channel, which
    /// parses to nothing and is dropped.
    private var animatedJSON: String {
        """
        { "asset": {"version": "2.0"},
          "scene": 0,
          "scenes": [{"name": "Rig", "nodes": [0, 1, 2, 3, 4, 5]}],
          "nodes": [
            {"name": "spinner", "translation": [1, 0, 0]},
            {"name": "slider"},
            {"name": "stepper"},
            {"name": "boxed", "matrix": [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]},
            {"name": "late"},
            {"name": "quant"}
          ],
          "animations": [
            {"name": "moves",
             "channels": [
               {"sampler": 0, "target": {"node": 0, "path": "rotation"}},
               {"sampler": 1, "target": {"node": 1, "path": "translation"}},
               {"sampler": 2, "target": {"node": 2, "path": "rotation"}},
               {"sampler": 3, "target": {"node": 4, "path": "translation"}},
               {"sampler": 4, "target": {"node": 3, "path": "rotation"}},
               {"sampler": 5, "target": {"node": 5, "path": "rotation"}}
             ],
             "samplers": [
               {"input": 0, "output": 3, "interpolation": "LINEAR"},
               {"input": 0, "output": 4, "interpolation": "CUBICSPLINE"},
               {"input": 1, "output": 6, "interpolation": "STEP"},
               {"input": 2, "output": 5, "interpolation": "LINEAR"},
               {"input": 0, "output": 3, "interpolation": "LINEAR"},
               {"input": 0, "output": 7, "interpolation": "LINEAR"}
             ]},
            {"name": "ghost",
             "channels": [{"sampler": 0, "target": {"node": 0, "path": "weights"}}],
             "samplers": [{"input": 1, "output": 1, "interpolation": "LINEAR"}]}
          ],
          "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [2]},
            {"bufferView": 1, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]},
            {"bufferView": 2, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [1], "max": [2]},
            {"bufferView": 3, "componentType": 5126, "count": 2, "type": "VEC4"},
            {"bufferView": 4, "componentType": 5126, "count": 6, "type": "VEC3"},
            {"bufferView": 5, "componentType": 5126, "count": 2, "type": "VEC3"},
            {"bufferView": 6, "componentType": 5126, "count": 2, "type": "VEC4"},
            {"bufferView": 7, "componentType": 5122, "normalized": true, "count": 2, "type": "VEC4"}
          ],
          "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": 8},
            {"buffer": 0, "byteOffset": 8, "byteLength": 8},
            {"buffer": 0, "byteOffset": 16, "byteLength": 8},
            {"buffer": 0, "byteOffset": 24, "byteLength": 32},
            {"buffer": 0, "byteOffset": 56, "byteLength": 72},
            {"buffer": 0, "byteOffset": 128, "byteLength": 24},
            {"buffer": 0, "byteOffset": 152, "byteLength": 32},
            {"buffer": 0, "byteOffset": 184, "byteLength": 16}],
          "buffers": [{"uri": "data:application/octet-stream;base64,\(Self.animBufferB64)",
                       "byteLength": 200}]
        }
        """
    }

    /// Write a glTF string to a temp file and load it as a `Scene`, cleaning up.
    private func loadScene(_ json: String) throws -> Ollin.Scene? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-\(ProcessInfo.processInfo.globallyUniqueString).gltf")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return Scene(contentsOf: url)
    }

    /// The local x axis of a node's transform, for checking applied rotations.
    private func xAxis(_ node: SceneNode?) -> SIMD3<Float> {
        let c = node?.localTransform.columns.0 ?? SIMD4<Float>()
        return SIMD3(c.x, c.y, c.z)
    }

    // MARK: Parsing

    @Test func animationsParseGroupedAndNamed() throws {
        let scene = try #require(try loadScene(animatedJSON))
        // "ghost" holds only a morph-weights channel, so it parses to nothing.
        #expect(scene.animations.count == 1)
        let anim = try #require(scene.animation("moves"))
        #expect(anim.duration == 2)
        // Six channels over six distinct nodes group into six tracks, sorted by
        // node index (deterministic output order).
        #expect(anim.tracks.count == 6)
        #expect(anim.tracks.map(\.nodeIndex) == [0, 1, 2, 3, 4, 5])
        #expect(scene.animation("missing") == nil)
        #expect(Scene(nodes: [SceneNode(name: "hand")]).animations.isEmpty)
    }

    // MARK: Sampler math (hand-computed pins)

    @Test func linearRotationSlerpsHalfway() throws {
        var scene = try #require(try loadScene(animatedJSON))
        let anim = try #require(scene.animation("moves"))
        // Identity to 90 deg about y over [0, 2]: at t=1 the pose is 45 deg, so
        // the local +x axis lands at (cos 45, 0, -sin 45).
        scene.apply(anim, at: 1)
        let x = xAxis(scene.node("spinner"))
        #expect(simd_length(x - SIMD3(0.7071068, 0, -0.7071068)) < 1e-5)
        // The un-animated translation keeps its authored value.
        #expect(scene.node("spinner")?.position == Vector3(1, 0, 0))
    }

    @Test func cubicSplineMatchesHandComputedHermite() throws {
        var scene = try #require(try loadScene(animatedJSON))
        let anim = try #require(scene.animation("moves"))
        // Keys at t 0 and 2: v0=(0,0,0) out-tangent (1,0,0), v1=(4,0,0)
        // in-tangent 0. At t=1 (segment factor 0.5, duration 2):
        // x = 0.5*0 + 2*(0.125)*1 + 0.5*4 + 0 = 2.25.
        scene.apply(anim, at: 1)
        let p = try #require(scene.node("slider")?.position)
        #expect(abs(p.x - 2.25) < 1e-5)
        #expect(abs(p.y) < 1e-6 && abs(p.z) < 1e-6)
        // At the keyframes the value elements come back exactly.
        scene.apply(anim, at: 0)
        #expect(scene.node("slider")?.position.x == 0)
        scene.apply(anim, at: 2)
        #expect(scene.node("slider")?.position.x == 4)
    }

    @Test func stepHoldsUntilTheNextKey() throws {
        var scene = try #require(try loadScene(animatedJSON))
        let anim = try #require(scene.animation("moves"))
        // Keys at t 0 (identity) and 1 (90 deg): just before 1 it still holds
        // the first key; at 1 it lands the second exactly.
        scene.apply(anim, at: 0.999)
        #expect(simd_length(xAxis(scene.node("stepper")) - SIMD3(1, 0, 0)) < 1e-6)
        scene.apply(anim, at: 1)
        #expect(simd_length(xAxis(scene.node("stepper")) - SIMD3(0, 0, -1)) < 1e-5)
    }

    @Test func outsideTheKeyframeRangeClampsToTheNearestKey() throws {
        var scene = try #require(try loadScene(animatedJSON))
        let anim = try #require(scene.animation("moves"))
        // The "late" track starts at t=1 (5,0,0) and ends at t=2 (7,0,0):
        // before its first key it holds the first value, after the last the
        // last, and in between it lerps.
        scene.apply(anim, at: 0)
        #expect(scene.node("late")?.position == Vector3(5, 0, 0))
        scene.apply(anim, at: 1.5)
        #expect(abs((scene.node("late")?.position.x ?? 0) - 6) < 1e-5)
        scene.apply(anim, at: 10)
        #expect(scene.node("late")?.position == Vector3(7, 0, 0))
    }

    @Test func normalizedShortRotationDecodes() throws {
        var scene = try #require(try loadScene(animatedJSON))
        let anim = try #require(scene.animation("moves"))
        // The quantized track stores the same 90-degree end key as normalized
        // signed shorts (23170/32767 per component), decoded by the spec's
        // int-to-float rule and normalized on sampling.
        scene.apply(anim, at: 2)
        #expect(simd_length(xAxis(scene.node("quant")) - SIMD3(0, 0, -1)) < 1e-4)
    }

    @Test func slerpTakesTheShortestArcForNegatedQuaternions() {
        // q and -q are the same rotation: interpolation toward either endpoint
        // must land on the same halfway pose (up to quaternion sign).
        let q0 = SIMD4<Float>(0, 0, 0, 1)
        let q1 = SIMD4<Float>(0, 0.7071068, 0, 0.7071068)
        let a = SceneAnimation.Sampler.slerp(q0, q1, 0.5)
        let b = SceneAnimation.Sampler.slerp(q0, -q1, 0.5)
        #expect(abs(abs(simd_dot(simd_normalize(a), simd_normalize(b))) - 1) < 1e-5)
        // And the halfway pose is the 22.5-degree half-angle quaternion.
        #expect(abs(abs(simd_dot(simd_normalize(a),
                                 SIMD4<Float>(0, 0.3826834, 0, 0.9238795))) - 1) < 1e-5)
    }

    @Test func aSingleKeyframeHoldsItsValueEverywhere() {
        let s = SceneAnimation.Sampler(times: [3], values: [SIMD4<Float>(9, 0, 0, 0)],
                                       mode: .linear)
        #expect(s.sample(at: 0).x == 9)
        #expect(s.sample(at: 3).x == 9)
        #expect(s.sample(at: 10).x == 9)
    }

    // MARK: Apply semantics

    @Test func applyIsAbsoluteNotAdditive() throws {
        var once = try #require(try loadScene(animatedJSON))
        var wandered = try #require(try loadScene(animatedJSON))
        let anim = try #require(once.animation("moves"))
        once.apply(anim, at: 0.75)
        // A different sampling history must land on the identical pose.
        wandered.apply(anim, at: 1.8)
        wandered.apply(anim, at: 0.2)
        wandered.apply(anim, at: 0.75)
        #expect(once.node("spinner")?.localTransform == wandered.node("spinner")?.localTransform)
        #expect(once.node("slider")?.localTransform == wandered.node("slider")?.localTransform)
    }

    @Test func matrixAuthoredNodesStayUntouched() throws {
        var scene = try #require(try loadScene(animatedJSON))
        let anim = try #require(scene.animation("moves"))
        let before = try #require(scene.node("boxed")?.localTransform)
        // A channel targets "boxed", but a matrix-authored node has no TRS
        // components to recompose (the spec forbids animating one): untouched.
        scene.apply(anim, at: 1.5)
        #expect(scene.node("boxed")?.localTransform == before)
    }

    @Test func handSetPositionSurvivesARotationOnlyTrack() throws {
        var scene = try #require(try loadScene(animatedJSON))
        let anim = try #require(scene.animation("moves"))
        // Nudge the stepped node by hand, then animate: its track only rotates,
        // so the hand-set translation must ride through the rebuild.
        scene["stepper"]?.position = Vector3(0, 3, 0)
        scene.apply(anim, at: 1)
        #expect(scene.node("stepper")?.position == Vector3(0, 3, 0))
        #expect(simd_length(xAxis(scene.node("stepper")) - SIMD3(0, 0, -1)) < 1e-5)
    }
}
