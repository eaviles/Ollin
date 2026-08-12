import Foundation
import Metal
import Testing
import Ollin
@testable import OllinDMX

/// The LED map: where the sample points land (strips walk by length, matrices
/// read cell centers, serpentine reverses alternate rows), how LEDs pack onto
/// universes (whole LEDs, spanning up), and how colors become channels (the
/// RGBW split and the master brightness ride the shipped fixture path). All
/// pure CPU except the one end-to-end pin, which is Metal-gated.
private let hasMetal = MTLCreateSystemDefaultDevice() != nil

@Suite
@MainActor
struct LEDMapTests {

    private func makeMap() -> LEDMap { LEDMap(sender: DMXSender(sACN: "127.0.0.1")) }

    // MARK: Sample-point geometry

    @Test func aStraightStripIncludesBothEndpointsEvenly() {
        let map = makeMap()
        let strip = map.addStrip(from: Vector2(0, 0), to: Vector2(100, 0), leds: 5)
        let xs = strip.positions.map(\.x)
        #expect(xs == [0, 25, 50, 75, 100])
        #expect(strip.positions.allSatisfy { $0.y == 0 })
    }

    @Test func aPolylineStripWalksByLengthNotByPointIndex() {
        // An L of 100 + 50: four LEDs land every 50 walked units, so the
        // third sits exactly on the corner and the last on the far end.
        let map = makeMap()
        let strip = map.addStrip(along: [Vector2(0, 0), Vector2(100, 0), Vector2(100, 50)], leds: 4)
        #expect(strip.positions[0] == Vector2(0, 0))
        #expect(strip.positions[1] == Vector2(50, 0))
        #expect(strip.positions[2] == Vector2(100, 0))
        #expect(strip.positions[3] == Vector2(100, 50))
    }

    @Test func aClosedStripSpacesAroundTheLoopWithoutDoublingTheSeam() {
        // A 40-unit square ring with 8 LEDs: one every 5 walked units, the
        // first on the start corner and none repeated (i/N, not i/(N-1)).
        let map = makeMap()
        let ring = map.addStrip(along: [Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)],
                                leds: 8, closed: true)
        #expect(ring.positions.count == 8)
        #expect(ring.positions[0] == Vector2(0, 0))
        #expect(ring.positions[1] == Vector2(5, 0))
        #expect(ring.positions[4] == Vector2(10, 10))
        #expect(Set(ring.positions.map { "\($0.x),\($0.y)" }).count == 8)
    }

    @Test func aMatrixReadsCellCentersInRowMajorOrder() {
        let map = makeMap()
        let panel = map.addMatrix(in: Rectangle(x: 0, y: 0, width: 30, height: 20),
                                  columns: 3, rows: 2)
        #expect(panel.positions == [
            Vector2(5, 5), Vector2(15, 5), Vector2(25, 5),
            Vector2(5, 15), Vector2(15, 15), Vector2(25, 15),
        ])
    }

    @Test func serpentineReversesEveryOtherRow() {
        let map = makeMap()
        let panel = map.addMatrix(in: Rectangle(x: 0, y: 0, width: 30, height: 20),
                                  columns: 3, rows: 2, serpentine: true)
        #expect(Array(panel.positions[3...]) == [Vector2(25, 15), Vector2(15, 15), Vector2(5, 15)])
    }

    // MARK: The wire plan

    @Test func wholeLEDsNeverStraddleAUniverseBoundary() {
        // 200 RGB LEDs from universe 1 channel 1: 170 fit (510 channels),
        // the 171st opens universe 2 at channel 1. Channels 511/512 stay dark
        // rather than holding two thirds of an LED.
        let slots = LEDMap.slots(count: 200, channelsPerLED: 3, universe: 1, address: 1)
        #expect(slots[169] == LEDMap.ChannelSlot(universe: 1, address: 508))
        #expect(slots[170] == LEDMap.ChannelSlot(universe: 2, address: 1))
        #expect(slots[199] == LEDMap.ChannelSlot(universe: 2, address: 88))
    }

    @Test func anOffsetStartPacksFromItsAddress() {
        // Starting at channel 508, one RGB LED still fits; starting at 511,
        // the first LED already can't, so it moves whole to the next universe.
        let fits = LEDMap.slots(count: 2, channelsPerLED: 3, universe: 5, address: 508)
        #expect(fits[0] == LEDMap.ChannelSlot(universe: 5, address: 508))
        #expect(fits[1] == LEDMap.ChannelSlot(universe: 6, address: 1))
        let spills = LEDMap.slots(count: 1, channelsPerLED: 3, universe: 5, address: 511)
        #expect(spills[0] == LEDMap.ChannelSlot(universe: 6, address: 1))
    }

    @Test func theMapListsEveryUniverseItTouches() {
        let map = makeMap()
        let strip = map.addStrip(from: Vector2(0, 0), to: Vector2(100, 0), leds: 200, universe: 3)
        map.addMatrix(in: Rectangle(x: 0, y: 0, width: 10, height: 10),
                      columns: 2, rows: 2, universe: 9)
        #expect(strip.universes == [3, 4])
        #expect(map.universes == [3, 4, 9])
    }

    // MARK: Colors onto channels

    @Test func packingWritesTheSampledBytes() {
        let map = makeMap()
        map.addStrip(from: Vector2(0, 0), to: Vector2(10, 0), leds: 2)
        let frame = map.packedUniverses(colors: [
            Color(red: 1, green: 0, blue: 0),
            Color(red: 0, green: 128.0 / 255, blue: 1),
        ])
        let universe = frame[1]!
        #expect(universe[1] == 255 && universe[2] == 0 && universe[3] == 0)
        #expect(universe[4] == 0 && universe[5] == 128 && universe[6] == 255)
    }

    @Test func anRGBWLayoutSplitsOutTheSharedWhite() {
        let map = makeMap()
        map.addPoints([Vector2(0, 0)], layout: [.red, .green, .blue, .white])
        let frame = map.packedUniverses(colors: [Color(red: 0.5, green: 0.5, blue: 1)])
        let universe = frame[1]!
        #expect(universe[1] == 0 && universe[2] == 0)     // the shared 0.5 moved to white
        #expect(universe[3] == 128 && universe[4] == 128)
    }

    @Test func brightnessScalesEveryLED() {
        let map = makeMap()
        map.addPoints([Vector2(0, 0)])
        map.brightness = 0.5
        let frame = map.packedUniverses(colors: [Color(red: 1, green: 1, blue: 1)])
        let universe = frame[1]!
        #expect(universe[1] == 128 && universe[2] == 128 && universe[3] == 128)
    }

    @Test func aSpanningRunLandsOnBothUniverses() {
        let map = makeMap()
        map.addStrip(from: Vector2(0, 0), to: Vector2(100, 0), leds: 171)
        let colors = [Color](repeating: Color(red: 1, green: 1, blue: 1), count: 171)
        let frame = map.packedUniverses(colors: colors)
        #expect(frame[1]?[508] == 255 && frame[1]?[510] == 255)
        #expect(frame[1]?[511] == 0 && frame[1]?[512] == 0)   // the straddle stays dark
        #expect(frame[2]?[1] == 255 && frame[2]?[3] == 255)
        #expect(frame[2]?[4] == 0)
    }

    // MARK: Defaults

    @Test func theDefaultRadiusIsHalfTheSpacingKeptToItsBand() {
        let map = makeMap()
        let sparse = map.addStrip(from: Vector2(0, 0), to: Vector2(1000, 0), leds: 2)
        #expect(sparse.sampleRadius == 32)                 // half of 1000, capped
        let even = map.addStrip(from: Vector2(0, 0), to: Vector2(100, 0), leds: 11)
        #expect(even.sampleRadius == 5)                    // half of 10
        let dense = map.addStrip(from: Vector2(0, 0), to: Vector2(100, 0), leds: 101)
        #expect(dense.sampleRadius == 1)                   // half of 1, floored
    }

    // MARK: End to end (Metal-gated)

    @Test(.enabled(if: hasMetal))
    func aRenderedFrameLandsOnTheWirePlan() throws {
        // A solid green texture through the real frame hook: the sampled
        // colors and the packed universe both read it back.
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: 8, height: 8, mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: desc))
        var bytes = [UInt8](repeating: 0, count: 8 * 8 * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i + 1] = 255          // G in BGRA
            bytes[i + 3] = 255
        }
        texture.replace(region: MTLRegionMake2D(0, 0, 8, 8), mipmapLevel: 0,
                        withBytes: bytes, bytesPerRow: 8 * 4)

        let map = makeMap()
        map.addPoints([Vector2(4, 4)], sampleRadius: 0)
        map.frameRendered(Sketch(), texture: texture)
        #expect(map.colors.count == 1)
        #expect(map.colors[0].green == 1 && map.colors[0].red == 0)
    }
}
