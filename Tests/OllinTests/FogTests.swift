import Foundation
import Testing
@testable import Ollin

/// The `Fog` value: a fog measured against the camera rather than in world
/// units, so a preset reads alike at any scene scale. These pin the math the
/// value means, that the drawer turns it into exactly the world-unit call it
/// stands for at the framing in force, and the menu roster.
@Suite
@MainActor
struct FogTests {

    @Test func theVeilMeansATransmittanceAtTheTarget() {
        let mist = Fog(veil: 0.5)
        for distance in [1.0, 12.0, 400.0] {
            let d = mist.density(at: distance)
            #expect(abs(exp(-d * distance) - 0.5) < 1e-9, "at \(distance)")
        }
        #expect(Fog(veil: 0.25).density(at: 10) < Fog(veil: 0.5).density(at: 10))
        #expect(Fog(veil: 0.5, pooling: 2).heightFalloff(at: 10) == 0.2)
        #expect(Fog(veil: 0).density(at: 10) == 0)
        // Clamped short of 1: an air that hides the target hides everything.
        #expect(Fog(veil: 5).veil < 1 && Fog(veil: 5).density(at: 1).isFinite)
        #expect(Fog(veil: -1).veil == 0 && Fog(pooling: -3).pooling == 0)
    }

    @Test func presetsAreOrderedByVeilAndTintedKeepsTheAir() {
        #expect(Fog.haze.veil < Fog.mist.veil && Fog.mist.veil < Fog.thick.veil)
        #expect(Fog.groundMist.pooling > 0 && Fog.mist.pooling == 0)
        let red = Fog.groundMist.tinted(.red)
        #expect(red.color == .red && red.veil == Fog.groundMist.veil && red.pooling == Fog.groundMist.pooling)
    }

    @Test func theMenuRosterRoundTrips() {
        let names = Fog.paramChoices.map(\.name)
        #expect(names == ["haze", "mist", "thick", "groundMist", "night"])
        let param = Param(wrappedValue: Fog.night)
        #expect(param.stored == .option("night"))
        param.restore(.option("thick"))
        #expect(param.wrappedValue == .thick)
    }

    /// A colonnade fogged as a value and as the bare call it means at the
    /// camera's distance draw the same pixels.
    private final class Court: Sketch {
        var air: Fog?
        var bare: (density: Double, heightFalloff: Double)?
        static let distance = 9.0
        override var canvasSize: CanvasSize { .square(160) }
        override func draw() {
            background(Color(hex: 0xB4BDC9))
            camera(Camera3D(eye: Vector3(0, 2, Court.distance), target: Vector3(0, 1, 0)))
            directionalLight(.white, direction: Vector3(0.5, 0.85, 0.3), intensity: 0.9)
            if let air { fog(air) }
            if let bare { fog(Color(hex: 0xB4BDC9), density: bare.density, heightFalloff: bare.heightFalloff) }
            fill(Color(white: 0.3))
            drawGround(size: 30, thickness: 1)
            for z in stride(from: -12.0, through: 0, by: 3) {
                withState {
                    translate(0, 1.5, z)
                    fill(Color(white: 0.5))
                    drawCylinder(radius: 0.4, height: 3)
                }
            }
        }
    }

    private func bytes(_ sketch: Sketch) throws -> [UInt8] {
        let image = try #require(OllinApp.image(of: sketch))
        let data = try #require(image.dataProvider?.data as Data?)
        return Array(data)
    }

    @Test func aFogValueDrawsAsTheBareCallItMeansAtTheFraming() throws {
        let valued = Court()
        valued.air = Fog.groundMist
        let bare = Court()
        let distance = (Vector3(0, 2, Court.distance) - Vector3(0, 1, 0)).length
        bare.bare = (Fog.groundMist.density(at: distance), Fog.groundMist.heightFalloff(at: distance))
        let a = try bytes(valued), b = try bytes(bare)
        #expect(a == b)
        // And it is fog: the far end differs from a clear frame.
        let clear = Court()
        #expect(try bytes(clear) != a)
    }
}
