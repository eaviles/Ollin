import Foundation
import Metal
import Ollin

/// Sends regions of the canvas to addressable LEDs: lay strips and matrices
/// over the picture, and every frame the pixels under them leave the screen as
/// DMX universes. Register it as a sketch extension and draw normally; the map
/// samples the *rendered* frame on the GPU (a few hundred points, not a
/// full-frame readback) and puts the bytes on the wire through a `DMXSender`.
///
/// ```swift
/// let dmx = DMXSender()                       // sACN multicast
/// let leds = LEDMap(sender: dmx)
///
/// override func setup() {
///     leds.addStrip(from: Vector2(100, 540), to: Vector2(980, 540), leds: 144)
///     leds.addMatrix(in: Rectangle(x: 390, y: 150, width: 300, height: 300),
///                    columns: 16, rows: 16, universe: 2)
///     extend(leds)
/// }
/// ```
///
/// Each LED reads a small patch of canvas around its point (averaged in linear
/// light, sized by default to the patch the LED stands for), and the byte sent
/// is the display byte: what you see at that pixel is what the lamp is told.
/// Universes pack whole LEDs (an LED's channels never straddle a universe
/// boundary, the convention pixel controllers expect) and a run that outgrows
/// one universe continues on the next number up.
///
/// The map drives lights, so it's live-only: a headless export renders no
/// frames to a window and sends nothing, the same way frame-sharing sits out
/// an export.
@MainActor
public final class LEDMap: SketchExtension {

    /// One mapped run of LEDs: where its sample points sit on the canvas and
    /// where its channels start on the wire. Returned by the `add…` calls;
    /// mostly useful for drawing the map back over the sketch (`positions`)
    /// and for reading which universes it occupies.
    public struct Fixture {
        /// The sample point of each LED, in canvas pixels, wire order.
        public let positions: [Vector2]
        /// The first universe this run writes.
        public let universe: Int
        /// The first channel (1…512) in that universe.
        public let address: Int
        /// The channels of one LED, in order (`[.red, .green, .blue]` for the
        /// common pixel; `.rgbw`-style layouts get the shared-part white split).
        public let layout: [DMXFixture.Role]
        /// The box radius, in canvas pixels, each LED averages around its point.
        public let sampleRadius: Double

        /// Where each LED landed on the wire, in LED order.
        let slots: [ChannelSlot]
        /// This run's indices into the map-wide `positions`/`colors` arrays.
        let range: Range<Int>

        /// How many LEDs the run holds.
        public var ledCount: Int { positions.count }
        /// Every universe number the run touches, ascending.
        public var universes: [Int] { Array(Set(slots.map(\.universe))).sorted() }

        /// Where LED `index` (0-based, wire order) landed: its universe and
        /// its first channel there. The lookup a monitor or a drawn preview
        /// uses to read one LED back off the wire; `nil` past the run.
        public func address(ofLED index: Int) -> (universe: Int, channel: Int)? {
            guard slots.indices.contains(index) else { return nil }
            return (slots[index].universe, slots[index].address)
        }
    }

    /// A single LED's landing place: a universe and its first channel there.
    struct ChannelSlot: Equatable {
        var universe: Int
        var address: Int
    }

    /// The sender the universes go out through. Its pacer handles the wire
    /// cadence, so the map sends every frame without flooding anything.
    public let sender: DMXSender

    /// A master level, 0…1, multiplied into every LED (through the fixture
    /// dimmer path, so a layout carrying a `.dimmer` channel gets it there
    /// instead). LED walls are bright; 1 sends the canvas as-is.
    public var brightness: Double = 1

    /// The mapped runs, in the order they were added.
    public private(set) var fixtures: [Fixture] = []

    /// Every sample point in the map, wire order across all fixtures.
    public var positions: [Vector2] { sampler.points.map(\.position) }

    /// The most recently sampled color of each LED (matching `positions`),
    /// empty until the first live frame. Handy for drawing the map's state
    /// back onto the canvas.
    public private(set) var colors: [Color] = []

    /// Every universe number the map writes, ascending.
    public var universes: [Int] {
        Array(Set(fixtures.flatMap { $0.slots.map(\.universe) })).sorted()
    }

    private let sampler = CanvasSampler()

    public init(sender: DMXSender) {
        self.sender = sender
    }

    // MARK: Building the map

    /// Maps a strip of `leds` LEDs evenly along a polyline (by walked length,
    /// so corners don't bunch them). `closed` joins the last point back to the
    /// first and spaces the LEDs around the loop: an LED ring. Channels start
    /// at `address` in `universe` and continue on the next universe up when
    /// the run outgrows one. `sampleRadius` defaults to half the LED spacing:
    /// each LED reads about the stretch of canvas it stands for.
    @discardableResult
    public func addStrip(along points: [Vector2], leds: Int, closed: Bool = false,
                         universe: Int = 1, address: Int = 1,
                         layout: [DMXFixture.Role] = [.red, .green, .blue],
                         sampleRadius: Double? = nil) -> Fixture {
        let count = max(1, leds)
        let contour = Contour(points, closed: closed)
        let positions = (0..<count).map { index -> Vector2 in
            if count == 1 { return contour.point(at: 0.5) }
            let t = closed ? Double(index) / Double(count)
                           : Double(index) / Double(count - 1)
            return contour.point(at: t)
        }
        let segments = max(1, closed ? count : count - 1)
        let spacing = contour.length / Double(segments)
        let radius = sampleRadius ?? defaultRadius(for: spacing / 2)
        return add(positions: positions, universe: universe, address: address,
                   layout: layout, sampleRadius: radius)
    }

    /// Maps a straight strip: `leds` LEDs from `from` to `to`, endpoints included.
    @discardableResult
    public func addStrip(from: Vector2, to: Vector2, leds: Int,
                         universe: Int = 1, address: Int = 1,
                         layout: [DMXFixture.Role] = [.red, .green, .blue],
                         sampleRadius: Double? = nil) -> Fixture {
        addStrip(along: [from, to], leds: leds, universe: universe,
                 address: address, layout: layout, sampleRadius: sampleRadius)
    }

    /// Maps a matrix of `columns × rows` LEDs over a rectangle, one LED per
    /// cell, sampling each cell's center. Wire order is straight rows, top row
    /// first, left to right; `serpentine: true` reverses every other row for a
    /// panel wired in a zigzag and addressed directly. (Pixel controllers are
    /// usually configured with the panel's wiring and expect straight rows on
    /// the wire, which is why straight is the default.) `sampleRadius`
    /// defaults to half the smaller cell side: each LED reads its own cell.
    @discardableResult
    public func addMatrix(in rect: Rectangle, columns: Int, rows: Int,
                          serpentine: Bool = false,
                          universe: Int = 1, address: Int = 1,
                          layout: [DMXFixture.Role] = [.red, .green, .blue],
                          sampleRadius: Double? = nil) -> Fixture {
        let columns = max(1, columns), rows = max(1, rows)
        let cellWidth = rect.width / Double(columns)
        let cellHeight = rect.height / Double(rows)
        var positions: [Vector2] = []
        positions.reserveCapacity(columns * rows)
        for row in 0..<rows {
            let reversed = serpentine && !row.isMultiple(of: 2)
            let cols = reversed ? Array((0..<columns).reversed()) : Array(0..<columns)
            for column in cols {
                positions.append(Vector2(rect.x + (Double(column) + 0.5) * cellWidth,
                                         rect.y + (Double(row) + 0.5) * cellHeight))
            }
        }
        let radius = sampleRadius ?? defaultRadius(for: min(cellWidth, cellHeight) / 2)
        return add(positions: positions, universe: universe, address: address,
                   layout: layout, sampleRadius: radius)
    }

    /// Maps loose LEDs at arbitrary canvas points, in the order given: lamps
    /// scattered over a set, each reading the pixel it hangs over.
    @discardableResult
    public func addPoints(_ points: [Vector2],
                          universe: Int = 1, address: Int = 1,
                          layout: [DMXFixture.Role] = [.red, .green, .blue],
                          sampleRadius: Double = 2) -> Fixture {
        add(positions: points, universe: universe, address: address,
            layout: layout, sampleRadius: sampleRadius)
    }

    /// Clears the whole map (fixtures, sample points, held colors).
    public func removeAll() {
        fixtures.removeAll()
        sampler.points = []
        colors = []
    }

    // MARK: The wire plan

    /// Where each of `count` LEDs lands, packing whole LEDs: a run starts at
    /// (`universe`, `address`) and an LED whose channels would cross channel
    /// 512 moves whole to channel 1 of the next universe up.
    static func slots(count: Int, channelsPerLED: Int,
                      universe: Int, address: Int) -> [ChannelSlot] {
        let width = min(max(channelsPerLED, 1), DMXUniverse.channelCount)
        var universe = universe
        var channel = min(max(address, 1), DMXUniverse.channelCount)
        var result: [ChannelSlot] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            if channel + width - 1 > DMXUniverse.channelCount {
                universe += 1
                channel = 1
            }
            result.append(ChannelSlot(universe: universe, address: channel))
            channel += width
        }
        return result
    }

    /// The frame's universes, filled from one color per LED (map order).
    /// Colors land through the fixture path, so an RGBW layout splits out its
    /// white and `brightness` scales the light either way.
    func packedUniverses(colors: [Color]) -> [Int: DMXUniverse] {
        var universes: [Int: DMXUniverse] = [:]
        for fixture in fixtures {
            for (offset, slot) in fixture.slots.enumerated() {
                let index = fixture.range.lowerBound + offset
                guard index < colors.count else { break }
                universes[slot.universe, default: DMXUniverse()].set(
                    DMXFixture(at: slot.address, fixture.layout),
                    color: colors[index], dimmer: brightness)
            }
        }
        return universes
    }

    private func add(positions: [Vector2], universe: Int, address: Int,
                     layout: [DMXFixture.Role], sampleRadius: Double) -> Fixture {
        let start = sampler.points.count
        let slots = Self.slots(count: positions.count, channelsPerLED: layout.count,
                               universe: universe, address: address)
        let fixture = Fixture(positions: positions, universe: universe,
                              address: min(max(address, 1), DMXUniverse.channelCount),
                              layout: layout, sampleRadius: sampleRadius,
                              slots: slots, range: start..<(start + positions.count))
        fixtures.append(fixture)
        sampler.points.append(contentsOf: positions.map {
            CanvasSampler.Point(position: $0, radius: sampleRadius)
        })
        return fixture
    }

    /// Half-spacing radii, kept to a sane band: never below 1 (a touch of
    /// averaging steadies a strip over fine detail) and never above 32 (a
    /// sparse run shouldn't blur half the canvas into each lamp).
    private func defaultRadius(for halfSpacing: Double) -> Double {
        min(max(halfSpacing, 1), 32)
    }

    // MARK: SketchExtension

    /// The map wants the rendered frame (as a GPU texture) whenever it has
    /// LEDs to feed; read each frame, so an emptied map stops paying for it.
    public var wantsRenderedTexture: Bool { !fixtures.isEmpty }

    /// Sample the frame at every mapped point and send the universes. Runs
    /// after each rendered frame; the sender's pacer turns the per-frame calls
    /// into the wire's own cadence.
    public func frameRendered(_ sketch: Sketch, texture: MTLTexture) {
        guard let samples = sampler.sample(texture) else { return }
        colors = samples.map {
            Color(red: Double($0.x) / 255, green: Double($0.y) / 255, blue: Double($0.z) / 255)
        }
        let frame = packedUniverses(colors: colors)
        for universe in frame.keys.sorted() {
            sender.send(frame[universe]!, universe: universe)
        }
    }
}
