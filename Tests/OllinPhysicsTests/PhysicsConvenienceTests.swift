import CoreGraphics
import Foundation
import Testing
@testable import Ollin
@testable import OllinPhysics

/// Laws for the physics drawing-and-mouse conveniences: `drawBody` as the
/// byte-identical form of the hand-written collider switch, `drawCollider`
/// rendering every case (the hand switch's `default: break` let exotic bodies
/// vanish), and the `dragBodies` press-drag-release lifecycle as one call.
@Suite
@MainActor
struct PhysicsConvenienceTests {

    private func bytes(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var out = [UInt8](repeating: 0, count: w * h * 4)
        out.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return out
    }

    // MARK: drawBody equals the hand-written switch

    private final class BodyScene: Sketch {
        var oneCall = true
        var world: World3D!
        override var canvasSize: CanvasSize { .square(256) }
        override func setup() {
            noLoop()
            world = World3D()
            world.addBody(.box(width: 1, height: 1, depth: 1),
                          at: Vector3(-2, 0.5, 0), kind: .static)
            world.addBody(.sphere(radius: 0.5), at: Vector3(0, 0.5, 0), kind: .static)
            world.addBody(.capsule(height: 0.8, radius: 0.3),
                          at: Vector3(2, 0.7, 0), kind: .static)
            world.addBody(.cylinder(height: 1, radius: 0.4),
                          at: Vector3(0, 0.5, -2), kind: .static)
        }
        override func draw() {
            background(Color(hex: 0x141821))
            perspective(eye: Vector3(5, 4, 8), target: Vector3(0, 0.5, 0))
            lights()
            fill(.coral)
            for body in world.bodies {
                if oneCall {
                    drawBody(body)
                } else {
                    withBody(body) {
                        switch body.collider {
                        case .box(let w, let h, let d):
                            drawBox(width: w, height: h, depth: d)
                        case .sphere(let r):
                            drawSphere(radius: r)
                        case .capsule(let h, let r):
                            drawCapsule(radius: r, height: h)
                        case .cylinder(let h, let r):
                            drawCylinder(radius: r, height: h)
                        default:
                            break
                        }
                    }
                }
            }
        }
    }

    @Test func drawBodyEqualsTheHandWrittenSwitch() throws {
        let one = BodyScene()
        let switched = BodyScene(); switched.oneCall = false
        #expect(bytes(of: try #require(OllinApp.image(of: one)))
             == bytes(of: try #require(OllinApp.image(of: switched))))
    }

    // MARK: every collider case draws

    private final class OneCollider: Sketch {
        var collider: Collider3D = .sphere(radius: 0.5)
        var draws = true
        override var canvasSize: CanvasSize { .square(128) }
        override func setup() { noLoop() }
        override func draw() {
            background(.black)
            perspective(eye: Vector3(2.5, 2, 4), target: .zero)
            lights()
            fill(.white)
            if draws { drawCollider(collider) }
        }
    }

    @Test func everyColliderCaseDrawsInk() throws {
        let exotic: [(String, Collider3D)] = [
            ("taperedCylinder", .taperedCylinder(height: 1, topRadius: 0.2, bottomRadius: 0.6)),
            ("taperedCapsule", .taperedCapsule(height: 0.8, topRadius: 0.2, bottomRadius: 0.4)),
            ("cone", .cone(height: 1, radius: 0.5)),
            ("hull", .hull([Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5),
                            Vector3(0, 0.6, 0), Vector3(-0.4, 0.4, 0.4)])),
            ("mesh", .mesh(.sphere(radius: 0.5))),
            ("heightfield", .heightfield(Heightfield(columns: 8, rows: 8) { u, v in u * v },
                                         width: 2, depth: 2, height: 0.6)),
            ("compound", .compound([.part(.sphere(radius: 0.3), at: Vector3(0, 0.5, 0)),
                                    .part(.box(width: 0.5, height: 0.5, depth: 0.5))])),
        ]
        for (name, collider) in exotic {
            let with = OneCollider(); with.collider = collider
            let without = OneCollider(); without.collider = collider; without.draws = false
            let inked = bytes(of: try #require(OllinApp.image(of: with)))
            let empty = bytes(of: try #require(OllinApp.image(of: without)))
            #expect(inked != empty, "\(name) must leave some ink on the frame")
        }
    }

    // MARK: dragBodies

    @Test func dragBodiesGrabsDragsAndReleases() throws {
        let sketch = Sketch()
        sketch.width = 400
        sketch.height = 400
        sketch.perspective(eye: Vector3(0, 0, 6), target: .zero)
        let world = World3D()
        world.addBody(.box(width: 1, height: 1, depth: 1), at: .zero, kind: .dynamic)

        let over = try #require(sketch.project(.zero))
        sketch.mouseX = over.x
        sketch.mouseY = over.y
        sketch.mouseIsPressed = true
        sketch.dragBodies(in: world)
        let joint = try #require(world.pointerGrab, "a press over the body takes hold")
        let firstTarget = joint.target

        sketch.mouseX = over.x + 60
        sketch.dragBodies(in: world)
        #expect(world.pointerGrab === joint, "the same joint rides the whole drag")
        #expect(joint.target.distance(to: firstTarget) > 1e-6, "the target follows the cursor")

        sketch.mouseIsPressed = false
        sketch.dragBodies(in: world)
        #expect(world.pointerGrab == nil, "release lets go")
        #expect(world.pointerGrabAttempted == false)
    }

    @Test func aMissedPressDoesNotGrabMidHold() throws {
        let sketch = Sketch()
        sketch.width = 400
        sketch.height = 400
        sketch.perspective(eye: Vector3(0, 0, 6), target: .zero)
        let world = World3D()
        world.addBody(.box(width: 1, height: 1, depth: 1), at: .zero, kind: .dynamic)

        // Press on empty sky: nothing grabbed, and the miss is remembered.
        sketch.mouseX = 5
        sketch.mouseY = 5
        sketch.mouseIsPressed = true
        sketch.dragBodies(in: world)
        #expect(world.pointerGrab == nil)
        #expect(world.pointerGrabAttempted)

        // Sweeping over the body while still holding does not pick it up.
        let over = try #require(sketch.project(.zero))
        sketch.mouseX = over.x
        sketch.mouseY = over.y
        sketch.dragBodies(in: world)
        #expect(world.pointerGrab == nil, "a hold that started on nothing stays empty")

        // A fresh press over the body does.
        sketch.mouseIsPressed = false
        sketch.dragBodies(in: world)
        sketch.mouseIsPressed = true
        sketch.dragBodies(in: world)
        #expect(world.pointerGrab != nil)
        sketch.mouseIsPressed = false
        sketch.dragBodies(in: world)
    }
}
