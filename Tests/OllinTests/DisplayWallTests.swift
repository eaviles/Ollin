import Foundation
import Testing
@testable import Ollin

/// Probes for one machine driving several displays.
///
/// Which display carries what is decided by where the displays are, so it is
/// arithmetic over rectangles and can be checked with none of them plugged in.
/// That is the half worth pinning: a wall is usually met for the first time in
/// the room it is going up in, with a ladder out and an hour to spare.
@Suite
@MainActor
struct DisplayWallTests {

    /// Two matching displays side by side, the left one primary.
    private static func pair() -> [WallScreen] {
        [WallScreen(frame: Rectangle(x: 0, y: 0, width: 1920, height: 1080),
                    key: "left", isPrimary: true),
         WallScreen(frame: Rectangle(x: 1920, y: 0, width: 1920, height: 1080), key: "right")]
    }

    private static let canvas = Vector2(2000, 1000)

    // MARK: Spreading one canvas across the displays

    @Test func twoDisplaysSideBySideCarryHalfEach() {
        let parts = WallPlan.parts(.spanning, base: .direct, canvas: Self.canvas,
                                   screens: Self.pair())
        #expect(parts.count == 2)
        #expect(parts[0].projection.shows == Rectangle(x: 0, y: 0, width: 0.5, height: 1))
        #expect(parts[1].projection.shows == Rectangle(x: 0.5, y: 0, width: 0.5, height: 1))
        #expect(parts[0].key == "left" && parts[1].key == "right")
    }

    @Test func oneDisplayAboveAnotherCarriesABandEach() {
        let screens = [WallScreen(frame: Rectangle(x: 0, y: 0, width: 1920, height: 1080),
                                  key: "top", isPrimary: true),
                       WallScreen(frame: Rectangle(x: 0, y: 1080, width: 1920, height: 1080),
                                  key: "bottom")]
        let parts = WallPlan.parts(.spanning, base: .direct, canvas: Self.canvas, screens: screens)
        #expect(parts[0].projection.shows == Rectangle(x: 0, y: 0, width: 1, height: 0.5))
        #expect(parts[1].projection.shows == Rectangle(x: 0, y: 0.5, width: 1, height: 0.5))
    }

    /// A display that is half the size of the one beside it carries half as much
    /// of the canvas, because the canvas is spread over the desk rather than
    /// shared out between the displays.
    @Test func aSmallerDisplayCarriesLess() {
        let screens = [WallScreen(frame: Rectangle(x: 0, y: 0, width: 2000, height: 1000),
                                  key: "big", isPrimary: true),
                       WallScreen(frame: Rectangle(x: 2000, y: 0, width: 1000, height: 1000),
                                  key: "small")]
        let parts = WallPlan.parts(.spanning, base: .direct, canvas: Self.canvas, screens: screens)
        #expect(abs(parts[0].projection.shows.width - 2.0 / 3) < 1e-12)
        #expect(abs(parts[1].projection.shows.width - 1.0 / 3) < 1e-12)
        #expect(abs(parts[1].projection.shows.x - 2.0 / 3) < 1e-12)
    }

    /// The gap between two monitors carries part of the canvas that nobody sees.
    /// That is what the arrangement looks like from in front of it, and the
    /// alternative would be a picture with a piece cut out of the middle.
    @Test func theGapBetweenTwoMonitorsCarriesCanvasNobodySees() {
        let screens = [WallScreen(frame: Rectangle(x: 0, y: 0, width: 1000, height: 1000),
                                  key: "left", isPrimary: true),
                       WallScreen(frame: Rectangle(x: 1500, y: 0, width: 1000, height: 1000),
                                  key: "right")]
        let parts = WallPlan.parts(.spanning, base: .direct, canvas: Self.canvas, screens: screens)
        let carried = parts.map(\.projection.shows.width).reduce(0, +)
        #expect(abs(carried - 0.8) < 1e-12, "the gap should carry the fifth nobody sees")
        #expect(abs(parts[1].projection.shows.x - 0.6) < 1e-12)
    }

    /// A machine that carries part of a longer wall divides that part between
    /// its own displays, not the whole canvas. Two machines with two projectors
    /// each is four beams, and each of them has to know its own quarter.
    @Test func aWallInsideAWallDividesWhatThisMachineCarries() {
        let base = Installation.Projection(shows: Rectangle(x: 0, y: 0, width: 0.5, height: 1),
                                           blend: Insets(right: 0.1))
        let parts = WallPlan.parts(.spanning, base: base, canvas: Self.canvas, screens: Self.pair())
        #expect(parts[0].projection.shows == Rectangle(x: 0, y: 0, width: 0.25, height: 1))
        #expect(parts[1].projection.shows == Rectangle(x: 0.25, y: 0, width: 0.25, height: 1))
        // The fades and the gamma are the machine's, so they come along.
        #expect(parts[0].projection.blend == base.blend)
    }

    @Test func mirroringPutsTheWholeCanvasOnEveryDisplay() {
        let parts = WallPlan.parts(.mirroring, base: .direct, canvas: Self.canvas,
                                   screens: Self.pair())
        #expect(parts.count == 2)
        #expect(parts.allSatisfy { $0.projection.shows == Installation.Projection.wholeCanvas })
    }

    @Test func oneDisplayIsTheRunItAlwaysWas() {
        let parts = WallPlan.parts(.one, base: .direct, canvas: Self.canvas, screens: Self.pair())
        #expect(parts.count == 1)
        #expect(parts[0].key == "left")
        #expect(parts[0].projection == .direct)
    }

    // MARK: Declaring the parts by hand

    /// The declarations are matched up left to right, whatever order the system
    /// hands the displays over in.
    @Test func declaredPartsAreMatchedLeftToRight() {
        let left = Installation.Projection(shows: Rectangle(x: 0, y: 0, width: 0.6, height: 1),
                                           blend: Insets(right: 0.2))
        let right = Installation.Projection(shows: Rectangle(x: 0.4, y: 0, width: 0.6, height: 1),
                                            blend: Insets(left: 0.2))
        let backwards = Array(Self.pair().reversed())
        let parts = WallPlan.parts(.parts([left, right]), base: .direct,
                                   canvas: Self.canvas, screens: backwards)
        #expect(parts[0].key == "left" && parts[0].projection == left)
        #expect(parts[1].key == "right" && parts[1].projection == right)
    }

    @Test func aDisplayPastTheDeclarationsStaysDark() {
        let only = Installation.Projection(shows: Rectangle(x: 0, y: 0, width: 0.5, height: 1))
        let parts = WallPlan.parts(.parts([only]), base: .direct,
                                   canvas: Self.canvas, screens: Self.pair())
        #expect(parts.count == 1, "the display with nothing declared for it should carry nothing")
        #expect(parts[0].key == "left")
    }

    @Test func aDeclarationPastTheDisplaysIsIgnored() {
        let one = Installation.Projection(shows: Rectangle(x: 0, y: 0, width: 0.5, height: 1))
        let two = Installation.Projection(shows: Rectangle(x: 0.5, y: 0, width: 0.5, height: 1))
        let parts = WallPlan.parts(.parts([one, two, two]), base: .direct,
                                   canvas: Self.canvas, screens: Self.pair())
        #expect(parts.count == 2)
    }

    /// Exactly one part is the one the piece's own window carries, and the
    /// window is moved to it. Without that, a run whose own display had no
    /// declaration would be drawing frames with nowhere to put them.
    @Test func exactlyOnePartIsTheOneTheWindowIsOn() {
        let onlyTheRight = Installation.Projection(shows: Rectangle(x: 0.5, y: 0,
                                                                    width: 0.5, height: 1))
        let screens = [WallScreen(frame: Rectangle(x: 0, y: 0, width: 1920, height: 1080),
                                  key: "left"),
                       WallScreen(frame: Rectangle(x: 1920, y: 0, width: 1920, height: 1080),
                                  key: "right", isPrimary: true)]
        let spread = WallPlan.parts(.spanning, base: .direct, canvas: Self.canvas, screens: screens)
        #expect(spread.filter(\.isPrimary).count == 1)
        #expect(spread.first(where: \.isPrimary)?.key == "right")

        // The primary display got no declaration, so the piece's own window
        // moves to the one part there is rather than being left with none.
        let declared = WallPlan.parts(.parts([onlyTheRight]), base: .direct,
                                      canvas: Self.canvas, screens: screens)
        #expect(declared.filter(\.isPrimary).count == 1)
        #expect(declared[0].key == "left")
    }

    // MARK: Rehearsing a wall that is not built yet

    /// A rehearsal lays the parts out side by side on one desk, so a wall can be
    /// looked at before it exists. They are laid out apart rather than
    /// overlapped: two beams sharing a band add their light, and two windows
    /// sharing one would only hide each other.
    @Test func aRehearsalLaysThePartsOutOnOneDesk() {
        let desk = [WallScreen(frame: Rectangle(x: 0, y: 0, width: 1600, height: 1000),
                               visible: Rectangle(x: 0, y: 40, width: 1600, height: 960),
                               key: "desk", isPrimary: true)]
        let parts = WallPlan.parts(.spanning, base: .direct, canvas: Vector2(1000, 1000),
                                   screens: desk, rehearsing: 3)
        #expect(parts.count == 3)
        #expect(parts.filter(\.isPrimary).count == 1)
        // Three equal strips of the canvas.
        for (index, part) in parts.enumerated() {
            #expect(abs(part.projection.shows.width - 1.0 / 3) < 1e-12)
            #expect(abs(part.projection.shows.x - Double(index) / 3) < 1e-12)
        }
        // Laid out in a row, in order, without touching, inside the desk.
        for (a, b) in zip(parts, parts.dropFirst()) {
            #expect(a.frame.x + a.frame.width < b.frame.x)
        }
        for part in parts {
            #expect(part.frame.x >= 0 && part.frame.x + part.frame.width <= 1600)
            #expect(part.frame.y >= 40 && part.frame.y + part.frame.height <= 1000)
        }
    }

    /// Nothing dragged in a rehearsal is kept. The windows stand for displays
    /// that are not here, so writing desk numbers into the room's file would put
    /// them on whatever is shown there next.
    @Test func aRehearsedDisplayIsFiledUnderNothing() {
        let desk = [WallScreen(frame: Rectangle(x: 0, y: 0, width: 1600, height: 1000),
                               key: "desk", isPrimary: true)]
        let parts = WallPlan.parts(.mirroring, base: .direct, canvas: Self.canvas,
                                   screens: desk, rehearsing: 2)
        #expect(parts.count == 2)
        #expect(parts.allSatisfy { $0.key == nil })
    }

    /// A rehearsed part is laid out at the proportions of the piece of canvas it
    /// carries, so a strip of a wide canvas reads as a strip.
    @Test func aRehearsedTileHasTheProportionsOfWhatItCarries() {
        let desk = [WallScreen(frame: Rectangle(x: 0, y: 0, width: 1600, height: 1000),
                               key: "desk", isPrimary: true)]
        let parts = WallPlan.parts(.spanning, base: .direct, canvas: Vector2(2000, 1000),
                                   screens: desk, rehearsing: 2)
        // Half of a canvas twice as wide as it is tall is square.
        for part in parts { #expect(abs(part.frame.width / part.frame.height - 1) < 1e-9) }
    }

    // MARK: What the command line says

    @Test func theFlagsSayWhichDisplays() {
        #expect(WallFlags.displays(["ollin", "--displays", "spanning"]) == .spanning)
        #expect(WallFlags.displays(["ollin", "--displays", "mirroring"]) == .mirroring)
        #expect(WallFlags.displays(["ollin", "--displays", "one"]) == .one)
        #expect(WallFlags.displays(["ollin", "--displays"]) == nil)
        #expect(WallFlags.displays(["ollin"]) == nil)

        #expect(WallFlags.rehearsal(["ollin", "--rehearse"]) == 2)
        #expect(WallFlags.rehearsal(["ollin", "--rehearse", "4"]) == 4)
        #expect(WallFlags.rehearsal(["ollin", "--rehearse", "--installation"]) == 2)
        #expect(WallFlags.rehearsal(["ollin"]) == nil)
    }

    /// Rehearsing is a look at a wall from a desk, so the desk keeps its pointer
    /// and its other windows, and a piece that declared one display is spread
    /// across the parts, since asking for a rehearsal is asking to see a wall.
    @Test func rehearsingPutsAPieceOnADeskRatherThanAWall() {
        let sketch = Sketch()
        let resolved = Installation.resolved(for: sketch, arguments: ["ollin", "--rehearse", "3"])
        #expect(resolved.runsUnattended)
        #expect(!resolved.fillsScreen)
        #expect(!resolved.hidesPointer)
        #expect(resolved.displays == .spanning)
    }

    @Test func theFlagCanPutAnyPieceOnEveryDisplay() {
        let sketch = Sketch()
        let resolved = Installation.resolved(
            for: sketch, arguments: ["ollin", "--installation", "--displays", "mirroring"])
        #expect(resolved.displays == .mirroring)
        // And taking the installation off takes the wall with it.
        let off = Installation.resolved(
            for: sketch, arguments: ["ollin", "--no-installation", "--displays", "mirroring"])
        #expect(off.displays == .one)
    }
}
