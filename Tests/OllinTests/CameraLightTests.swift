@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// A light read in the camera's frame (`Light.relativeTo(.camera)`, `headlight()`).
///
/// The claims a sketch is being promised: a world light is untouched (the same value,
/// no arithmetic, so a frame with none of the other kind packs byte-identically); a
/// camera-relative light is turned and moved by the camera's own basis, the eye at its
/// origin; a headlight always travels along the view; a rig read `relativeTo(.camera)`
/// keeps every light and its ambient; and, in pixels, a sphere under a headlight shades
/// the same wherever the camera orbits to, while the same sphere under a world light
/// shades from a different side at each azimuth.
@Suite
@MainActor
struct CameraLightTests {

    private func close(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }
    private func close(_ a: Vector3, _ b: Vector3, _ eps: Double = 1e-9) -> Bool {
        close(a.x, b.x, eps) && close(a.y, b.y, eps) && close(a.z, b.z, eps)
    }

    // MARK: The resolve

    @Test func aWorldLightComesBackAsItself() {
        let light = Light.point(.white, at: Vector3(1, 2, 3))
        let camera = Camera3D.orbiting(radius: 7, azimuth: 1.2, elevation: 0.4)
        #expect(light.frame == .world)
        #expect(light.resolved(in: camera) == light)
    }

    @Test func aHeadlightTravelsAlongTheView() {
        let light = Light.headlight()
        #expect(light.frame == .camera)
        #expect(light.kind == .directional)
        #expect(light.castsShadow == false)
        for (azimuth, elevation) in [(0.0, 0.0), (1.0, 0.3), (2.5, -0.5), (4.0, 1.2)] {
            let camera = Camera3D.orbiting(target: Vector3(1, -2, 3), radius: 6,
                                           azimuth: azimuth, elevation: elevation)
            let world = light.resolved(in: camera)
            let view = (camera.target - camera.eye).normalized
            #expect(close(world.direction, view),
                    "at azimuth \(azimuth): \(world.direction) against the view \(view)")
            #expect(world.frame == .world)
        }
    }

    @Test func aCameraSpacePositionSitsBesideTheEye() {
        // Eye on +z looking at the origin: camera x is world x, camera y world y, and
        // camera z (back toward the eye) is world z.
        let front = Camera3D.perspective(eye: Vector3(0, 0, 10))
        let ahead = Light.point(.white, at: Vector3(0, 0, -5)).relativeTo(.camera).resolved(in: front)
        #expect(close(ahead.position, Vector3(0, 0, 5)))
        let beside = Light.point(.white, at: Vector3(2, 1, 0)).relativeTo(.camera).resolved(in: front)
        #expect(close(beside.position, Vector3(2, 1, 10)))
        // Eye on +x: the camera's right is now world −z, its back world +x.
        let side = Camera3D.perspective(eye: Vector3(10, 0, 0))
        let aheadSide = Light.point(.white, at: Vector3(0, 0, -5)).relativeTo(.camera).resolved(in: side)
        #expect(close(aheadSide.position, Vector3(5, 0, 0)))
        let right = Light.point(.white, at: Vector3(2, 0, 0)).relativeTo(.camera).resolved(in: side)
        #expect(close(right.position, Vector3(10, 0, -2)))
    }

    @Test func aPanelTurnsWithItsUpHint() {
        // A rect light facing down the view with its height along camera y: from the
        // side, the panel's normal is world −x and its up still world y.
        let side = Camera3D.perspective(eye: Vector3(10, 0, 0))
        let panel = Light.rectangle(.white, at: Vector3(0, 0, -2), direction: Vector3(0, 0, -1),
                                    width: 2, height: 1, up: .unitY)
            .relativeTo(.camera).resolved(in: side)
        #expect(close(panel.direction, Vector3(-1, 0, 0)))
        #expect(close(panel.up, .unitY))
        #expect(close(panel.position, Vector3(8, 0, 0)))
    }

    @Test func noCameraReadsAsWorld() {
        let light = Light.point(.white, at: Vector3(1, 2, 3)).relativeTo(.camera)
        let world = light.resolved(in: nil)
        #expect(world.frame == .world)
        #expect(close(world.position, Vector3(1, 2, 3)))
    }

    @Test func relativeToIsAFrameAlone() {
        let light = Light.spot(.red, at: Vector3(1, 2, 3), direction: Vector3(0, -1, 0),
                               coneAngle: 0.5, penumbra: 0.3, intensity: 2)
        let moved = light.relativeTo(.camera)
        var expected = light
        expected.frame = .camera
        #expect(moved == expected)
        #expect(moved.relativeTo(.world) == light)
    }

    @Test func aRigFollowsTheCameraWhole() {
        let rig = LightingPreset.threePoint.relativeTo(.camera)
        #expect(rig.ambient == LightingPreset.threePoint.ambient)
        #expect(rig.lights.count == LightingPreset.threePoint.lights.count)
        #expect(rig.lights.allSatisfy { $0.frame == .camera })
        // Nothing but the frame moved.
        for (a, b) in zip(rig.lights, LightingPreset.threePoint.lights) {
            #expect(a.relativeTo(.world) == b)
        }
    }

    // MARK: Through the drawer

    private func packedDirection(azimuth: Double, light: Light) -> Vector3 {
        let d = Drawer()
        d.beginFrame()
        d.camera(.orbiting(radius: 5, azimuth: azimuth, elevation: 0.2))
        d.addLight(light)
        let l = d.makeLighting().lights.0
        return Vector3(Double(l.direction.x), Double(l.direction.y), Double(l.direction.z))
    }

    @Test func thePackedHeadlightPointsBackAtTheEye() {
        // The packer stores the direction *to* the light: for a headlight, from the
        // target back toward the eye, wherever the eye is.
        for azimuth in [0.0, 1.7, 3.9] {
            let camera = Camera3D.orbiting(radius: 5, azimuth: azimuth, elevation: 0.2)
            let toEye = (camera.eye - camera.target).normalized
            #expect(close(packedDirection(azimuth: azimuth, light: .headlight()), toEye, 1e-5))
        }
        // A world light packs the same whatever the camera does.
        let sun = Light.directional(.white, direction: Vector3(0, -1, 0))
        #expect(close(packedDirection(azimuth: 0, light: sun), .unitY, 1e-6))
        #expect(close(packedDirection(azimuth: 2, light: sun), .unitY, 1e-6))
    }

    @Test func worldLightsPassThroughUntouched() {
        let d = Drawer()
        d.beginFrame()
        d.camera(.orbiting(radius: 5, azimuth: 1, elevation: 0.2))
        let a = Light.point(.white, at: Vector3(1, 2, 3))
        let b = Light.directional(.red, direction: Vector3(-1, -1, 0), softness: 0.2)
        d.addLight(a)
        d.addLight(b)
        #expect(d.resolvedLights == [a, b])
        #expect(d.activeLights == [a, b])
    }

    // MARK: In pixels

    private func frame(_ sketch: Sketch) throws -> (width: Int, height: Int, data: [UInt8]) {
        let image = try #require(OllinApp.image(of: sketch, frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (w, h, data)
    }

    /// Where the light lands on the sphere: the brightness-weighted mean column of the
    /// picture, in pixels from the center. A headlight lights the middle of the disk
    /// from any angle, so it stays at zero; a world light lights one side.
    private func litCentroid(azimuth: Double, light: Light) throws -> Double {
        let probe = HeadlightProbe()
        probe.azimuth = azimuth
        probe.light = light
        let f = try frame(probe)
        var weight = 0.0, moment = 0.0
        for y in 0 ..< f.height {
            for x in 0 ..< f.width {
                let i = (y * f.width + x) * 4
                let lum = Double(f.data[i]) + Double(f.data[i + 1]) + Double(f.data[i + 2])
                weight += lum
                moment += lum * Double(x)
            }
        }
        #expect(weight > 0, "the sphere rendered black")
        return moment / weight - Double(f.width) / 2
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aHeadlightKeepsItsShadingUnderAnOrbit() throws {
        let stillA = try litCentroid(azimuth: 0, light: .headlight())
        let stillB = try litCentroid(azimuth: 2.2, light: .headlight())
        #expect(abs(stillA) < 1.5 && abs(stillB) < 1.5,
                "the headlight's centroid sits at \(stillA) then \(stillB) px from the center")
        // The same sphere under a world light shades from a different side at each
        // azimuth, which is the difference the frame makes.
        let sun = Light.directional(.white, direction: Vector3(-1, 0, -1))
        let sunA = try litCentroid(azimuth: 0, light: sun)
        let sunB = try litCentroid(azimuth: 2.2, light: sun)
        #expect(abs(sunA - sunB) > 12,
                "the world light's centroid moved only from \(sunA) to \(sunB) px")
    }
}

/// One white sphere at the origin under one light, seen from an orbit.
private final class HeadlightProbe: Sketch {
    var azimuth = 0.0
    var light = Light.headlight()
    override var canvasSize: CanvasSize { .square(192) }
    override func draw() {
        background(.black)
        camera(.orbiting(radius: 5, azimuth: azimuth, elevation: 0))
        self.light(light)
        fill(.white)
        material(.matte)
        drawSphere(radius: 1, segments: 96, rings: 64)
    }
}
