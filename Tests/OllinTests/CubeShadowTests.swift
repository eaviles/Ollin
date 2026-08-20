@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// The point caster's rasterized fallback: the six-face mid-point cube a GPU renders when
/// it cannot trace a visibility ray from a render stage.
///
/// It is the one 3D path the development machine never takes, which is how it stayed
/// broken while every snapshot passed: an Apple-silicon GPU traces its point casters, so
/// the cube is dead code here. `OLLIN_NO_RAY_TRACING=1` in the environment answers "this
/// device cannot trace" and brings it back, and these probes then run. They also run
/// unasked on a GPU that genuinely cannot trace.
///
/// Nothing here diffs a committed image. Each probe states a fact about where light and
/// shadow must land, so it reads the same on any GPU and says which fault it caught:
///
/// - a shadow lands on the far side of its caster from the light (the six views are
///   written for a bottom-left framebuffer origin, and Metal's is top-left, so rendering
///   them unchanged stores every face upside down and mirrors the shadow to the near side);
/// - a caster the camera does not frame still throws its shadow (the far plane used to be
///   fitted from the camera's framing radius, which says nothing about how far the light
///   reaches, so anything past it was clipped out of the cube and cast nothing);
/// - a floor the light grazes shades smoothly rather than shadowing itself in bands (the
///   bias has to cover the distance a surface crosses under one tap spread, measured at
///   the surface itself, and that grows without bound as the light nears its plane).
@Suite(.serialized)
@MainActor
struct CubeShadowTests {

    /// Whether this run exercises the rasterized cube: either the GPU cannot trace from a
    /// render stage, or the environment says to pretend it cannot.
    nonisolated static var runsTheCube: Bool {
        Snapshot.hasMetal && (!Snapshot.hasRaytracing
            || ProcessInfo.processInfo.environment["OLLIN_NO_RAY_TRACING"] == "1")
    }

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// Mean red over a fractional box of the frame (top-left origin).
    private func mean(_ image: CGImage, x: ClosedRange<Double>, y: ClosedRange<Double>) -> Double {
        let d = pixels(of: image)
        let w = image.width, h = image.height
        var sum = 0, count = 0
        for py in Int(Double(h) * y.lowerBound)..<Int(Double(h) * y.upperBound) {
            for px in Int(Double(w) * x.lowerBound)..<Int(Double(w) * x.upperBound) {
                sum += Int(d[(py * w + px) * 4]); count += 1
            }
        }
        return Double(sum) / Double(max(count, 1))
    }

    @Test(.enabled(if: CubeShadowTests.runsTheCube))
    func theShadowFallsAwayFromTheLight() throws {
        // A pillar stands to the right of a light hanging over the middle of a floor, and
        // the camera looks straight down. So its shadow belongs in the right half of the
        // frame and the left half must stay lit. A face stored upside down puts the whole
        // shadow in the left half instead, which is exactly as wrong as it can be.
        let image = try #require(OllinApp.image(of: CubeShadowScene.make(.pillar), frame: 1))
        let shadowed = mean(image, x: 0.62...0.95, y: 0.40...0.60)
        let opposite = mean(image, x: 0.05...0.38, y: 0.40...0.60)
        #expect(opposite - shadowed > 40,
                "the shadow belongs on the far side of the pillar from the light: that side \(shadowed), the other side \(opposite)")
    }

    @Test(.enabled(if: CubeShadowTests.runsTheCube))
    func aCasterTheCameraDoesNotFrameStillCastsIt() throws {
        // The camera holds a target one step in front of itself and stands off to the side
        // of the light, while a pillar sits further down the floor than the camera is from
        // the light. The old far plane was the light's distance to that target plus the
        // camera's own radius, so the pillar fell outside the cube entirely: it lit up and
        // threw nothing. Read the wedge of floor it shadows against the lit floor beside it.
        let image = try #require(OllinApp.image(of: CubeShadowScene.make(.distantPillar), frame: 1))
        let shadow = mean(image, x: 0.46...0.60, y: 0.500...0.545)
        let beside = mean(image, x: 0.10...0.30, y: 0.500...0.545)
        #expect(beside - shadow > 40,
                "the far pillar should throw its shadow: in it \(shadow), beside it \(beside)")
    }

    @Test(.enabled(if: CubeShadowTests.runsTheCube))
    func distantInstancedCopiesStillCastThem() throws {
        // The same distant pillar, drawn as an instanced copy over an instanced floor, so
        // the frame holds no plain mesh at all. A copy carries a matrix rather than
        // vertices the frame scans, so fitting the far plane to the scanned vertices alone
        // left this frame nothing to fit to: it kept the camera's own framing radius, and
        // the pillar stood well outside the cube and threw nothing.
        let image = try #require(OllinApp.image(of: CubeShadowScene.make(.distantCopies), frame: 1))
        let shadow = mean(image, x: 0.46...0.60, y: 0.500...0.545)
        let beside = mean(image, x: 0.10...0.30, y: 0.500...0.545)
        #expect(beside - shadow > 40,
                "the far copy should throw its shadow: in it \(shadow), beside it \(beside)")
    }

    @Test(.enabled(if: CubeShadowTests.runsTheCube))
    func aDistantFieldCopyStillCastsIt() throws {
        // The same again from a `MeshField`, whose copies live in the field's own retained
        // buffers. The field answers for them with its own bound, which is the only way a
        // frame drawn by one call can say how far its casters reach.
        let image = try #require(OllinApp.image(of: CubeShadowScene.make(.distantField), frame: 1))
        let shadow = mean(image, x: 0.46...0.60, y: 0.500...0.545)
        let beside = mean(image, x: 0.10...0.30, y: 0.500...0.545)
        #expect(beside - shadow > 40,
                "the far field copy should throw its shadow: in it \(shadow), beside it \(beside)")
    }

    @Test(.enabled(if: CubeShadowTests.runsTheCube))
    func aGrazedFloorClimbsSmoothly() throws {
        // A light barely above a long floor, read as a column of rows running away from it.
        // A point light does not fall off with distance here, so the floor is shaded by the
        // angle alone: it brightens toward the camera, and it brightens SMOOTHLY, each row
        // a little more than the last. A floor that shadows itself climbs in fits instead,
        // holding dark for a stretch and then jumping. So the probe reads how much the
        // climb bends from one step to the next, which says nothing about how bright the
        // floor is or how fast it brightens, only that neither changes abruptly.
        let image = try #require(OllinApp.image(of: CubeShadowScene.make(.grazedFloor), frame: 1))
        var rows: [Double] = []
        for step in 0..<26 {
            let y = 0.42 + Double(step) * 0.020
            rows.append(mean(image, x: 0.25...0.75, y: y...(y + 0.014)))
        }
        let steps = (1..<rows.count).map { rows[$0] - rows[$0 - 1] }
        var bend = 0.0
        var bendAt = 0
        for i in 1..<steps.count where abs(steps[i] - steps[i - 1]) > bend {
            bend = abs(steps[i] - steps[i - 1])
            bendAt = i
        }
        #expect(bend < 6,
                "the floor climbs in a fit at row \(bendAt) (bend \(bend)): \(steps.map { Int($0) })")
    }
}

/// The five scenes the cube probes read. Each puts a point light over a floor with no
/// directional or spot light, so the point light is the frame's caster.
private final class CubeShadowScene: Sketch {
    enum Kind { case pillar, distantPillar, distantCopies, distantField, grazedFloor }
    var kind: Kind = .pillar

    /// The distant-copy scenes' geometry: one box, placed twice. The floor is a copy
    /// as well, so the frame holds no plain mesh and the far-plane fit has only the
    /// copies to work from.
    private let box = Mesh.box(size: 1)
    private let field = MeshField()
    private static let floorCopy = MeshInstance(position: Vector3(0, -0.05, 0),
                                                scale: Vector3(90, 0.1, 90),
                                                color: Color(white: 0.85))
    private static let pillarCopy = MeshInstance(position: Vector3(0, 1.4, -8.0),
                                                 scale: Vector3(2.4, 2.8, 1.0),
                                                 color: Color(white: 0.6))

    static func make(_ kind: Kind) -> CubeShadowScene {
        let scene = CubeShadowScene()
        scene.kind = kind
        return scene
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.02))
        ambientLight(Color(white: 0.04))
        castShadows()
        switch kind {
        case .pillar:
            // Straight down on a pillar standing to the right of the light, so which way
            // its shadow points reads off the frame with no projection to undo.
            camera(Camera3D(eye: Vector3(0, 9, 0.001), target: .zero,
                            projection: .perspective(fieldOfView: .pi / 3)))
            pointLight(.white, at: Vector3(0, 3.2, 0), intensity: 2.2)
            withState { fill(Color(white: 0.85)); specular(0); drawPlane(width: 20, depth: 20) }
            withState {
                translate(2.2, 0.9, 0)
                fill(Color(white: 0.6)); specular(0)
                drawBox(width: 1.0, height: 1.8, depth: 1.0)
            }
        case .distantPillar:
            // The camera holds a target one step in front of itself, off to the side of the
            // light, and looks down the floor at a pillar further from the light than it is:
            // a caster the camera's own framing says nothing about.
            let eye = Vector3(12, 4, 10)
            let aim = Vector3(0, 1.0, -14)
            camera(Camera3D(eye: eye, target: eye + (aim - eye).normalized,
                            projection: .perspective(fieldOfView: .pi / 3)))
            pointLight(.white, at: Vector3(0, 6, 10), intensity: 1.6)
            withState { fill(Color(white: 0.85)); specular(0); drawPlane(width: 90, depth: 90) }
            withState {
                translate(0, 1.4, -8.0)
                fill(Color(white: 0.6)); specular(0)
                drawBox(width: 2.4, height: 2.8, depth: 1.0)
            }
        case .distantCopies, .distantField:
            // The distant-pillar camera and light exactly, over copies rather than meshes.
            let eye = Vector3(12, 4, 10)
            let aim = Vector3(0, 1.0, -14)
            camera(Camera3D(eye: eye, target: eye + (aim - eye).normalized,
                            projection: .perspective(fieldOfView: .pi / 3)))
            pointLight(.white, at: Vector3(0, 6, 10), intensity: 1.6)
            specular(0)
            let copies = [CubeShadowScene.floorCopy, CubeShadowScene.pillarCopy]
            if kind == .distantCopies {
                drawMesh(box, instances: copies)
            } else {
                if field.isEmpty { field.place(box, at: copies) }
                drawMeshField(field)
            }
        case .grazedFloor:
            // A light barely above a long floor: every part of it the camera sees is lit
            // at a hard grazing angle, the case a flat bias cannot hold.
            camera(Camera3D(eye: Vector3(0, 1.5, 4.0), target: Vector3(0, 0.6, -3.0),
                            projection: .perspective(fieldOfView: .pi / 3.2)))
            pointLight(.white, at: Vector3(0, 0.9, 3.0), intensity: 1.6)
            withState { fill(Color(white: 0.85)); specular(0); drawPlane(width: 120, depth: 120) }
        }
    }
}
