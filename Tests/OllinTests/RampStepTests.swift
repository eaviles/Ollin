import Foundation
import Testing
@testable import Ollin

/// A stepped ramp holds each color flat up to the next stop, with no blending,
/// keeps its bands when reversed, and the holographic spectrum is one.
@Suite struct RampStepTests {

    static let thirds: [Double] = [0, 1.0 / 3, 2.0 / 3]

    @Test func aSteppedRampHoldsEachColorFlat() {
        let stripes = Ramp.stepped([.red, .green, .blue])
        let positions: [Double] = stripes.stops.map(\.position)
        #expect(stripes.isStepped)
        #expect(positions == Self.thirds)
        #expect(stripes.color(at: 0) == Color.red)
        #expect(stripes.color(at: 0.3) == Color.red)
        #expect(stripes.color(at: 1.0 / 3) == Color.green, "a stop's own position is its color")
        #expect(stripes.color(at: 0.5) == Color.green)
        #expect(stripes.color(at: 0.9) == Color.blue)
        #expect(stripes.color(at: 1) == Color.blue)
        #expect(stripes.color(at: -4) == Color.red, "clamped at the start")
        #expect(stripes.color(at: 9) == Color.blue, "clamped at the end")
        // The smooth ramp of the same colors mixes between them.
        let smooth = Ramp([.red, .green, .blue])
        let mixed = smooth.color(at: 0.25)
        #expect(!smooth.isStepped)
        #expect(mixed != Color.red)
        #expect(mixed != Color.green)
    }

    @Test func placedStopsHoldFromTheirPositionToTheNext() {
        let placed = Ramp.stepped(stops: [(0.2, Color.red), (0.5, Color.green), (0.9, Color.blue)])
        #expect(placed.color(at: 0.1) == Color.red, "below the first stop the first color shows")
        #expect(placed.color(at: 0.49) == Color.red)
        #expect(placed.color(at: 0.5) == Color.green)
        #expect(placed.color(at: 0.95) == Color.blue)
        let typed = Ramp.stepped(stops: [Ramp.Stop(position: 0.5, color: .green), Ramp.Stop(position: 0.2, color: .red)])
        let positions: [Double] = typed.stops.map(\.position)
        let sorted: [Double] = [0.2, 0.5]
        #expect(typed.isStepped)
        #expect(positions == sorted, "sorted for you")
        #expect(typed.color(at: 0.3) == Color.red)
    }

    @Test func reversedKeepsTheBands() {
        let forward = Ramp.stepped([.red, .green, .blue])
        let stripes = forward.reversed
        #expect(stripes.isStepped)
        #expect(stripes.color(at: 0.1) == Color.blue)
        #expect(stripes.color(at: 0.5) == Color.green)
        #expect(stripes.color(at: 0.9) == Color.red)
        // Each band is as wide as it was: the boundaries sit where they sat,
        // mirrored (to the rounding of one minus a third).
        let positions: [Double] = stripes.stops.map(\.position)
        #expect(positions.count == 3)
        for (p, q) in zip(positions, Self.thirds) { #expect(abs(p - q) < 1e-12) }
        let placed = Ramp.stepped(stops: [(0.2, Color.red), (0.5, Color.green)]).reversed
        // red held 0.2..<0.5 and green 0.5...1, so reversed green holds 0..<0.5 and red 0.5..<0.8.
        #expect(placed.color(at: 0.25) == Color.green)
        #expect(placed.color(at: 0.6) == Color.red)
        let placedPositions: [Double] = placed.stops.map(\.position)
        let halves: [Double] = [0, 0.5]
        #expect(placedPositions == halves)
        // Twice reversed is the ramp again: the same colors in the same bands.
        let twice = forward.reversed.reversed
        #expect(twice.isStepped)
        #expect(twice.stops.map(\.color) == forward.stops.map(\.color))
        for (p, q) in zip(twice.stops.map(\.position), forward.stops.map(\.position)) { #expect(abs(p - q) < 1e-12) }
    }

    @Test func theHolographicSpectrumIsEightFlatBandsInGratingOrder() {
        let spectrum = Ramp.holographic
        #expect(spectrum.isStepped)
        #expect(spectrum.stops.count == 8)
        // Violet first, red near the end: hue falls as the bands run, the way a
        // grating lays the short wavelengths nearest the center.
        let hues: [Double] = (0 ..< 8).map { i in spectrum.color(at: (Double(i) + 0.5) / 8).hue }
        let violet = hues[0], green = hues[3], red = hues[6]
        #expect(violet > 0.7, "violet \(violet)")
        #expect(violet < 0.8, "violet \(violet)")
        #expect(green > 0.3, "green \(green)")
        #expect(green < 0.45, "green \(green)")
        #expect(red < 0.02 || red > 0.95, "red \(red)")
        // Flat within a band: the same color at both ends of it.
        let early = spectrum.color(at: 0.01), late = spectrum.color(at: 0.12), next = spectrum.color(at: 0.13)
        #expect(early == late)
        #expect(late != next)
    }
}
