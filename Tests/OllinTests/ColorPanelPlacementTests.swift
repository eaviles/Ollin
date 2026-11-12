#if os(macOS)
import CoreGraphics
import Testing
@testable import Ollin

/// Where the Colors panel is moved when a color row opens it over the
/// inspector: beside the window where the screen has room, beside the column
/// where it has not, and nowhere at all when it was already clear.
@Suite
struct ColorPanelPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
    let gap = ColorPanelPlacement.gap

    /// A window with the inspector's column on its right edge.
    func columnOnRight(of window: CGRect, width: CGFloat = 300) -> CGRect {
        CGRect(x: window.maxX - width, y: window.minY, width: width, height: window.height)
    }

    func place(_ panel: CGRect, column: CGRect, window: CGRect) -> CGRect? {
        ColorPanelPlacement.origin(panel: panel, column: column, window: window, screen: screen)
            .map { CGRect(origin: $0, size: panel.size) }
    }

    @Test func aPanelClearOfTheColumnStaysWhereItIs() {
        let window = CGRect(x: 100, y: 100, width: 1000, height: 700)
        let panel = CGRect(x: 150, y: 300, width: 228, height: 320)      // over the canvas, by choice
        #expect(place(panel, column: columnOnRight(of: window), window: window) == nil)
    }

    @Test func itGoesOutsideTheWindowOnTheColumnsSide() throws {
        let window = CGRect(x: 100, y: 100, width: 1000, height: 700)
        let column = columnOnRight(of: window)
        let panel = CGRect(x: 900, y: 300, width: 228, height: 320)
        let placed = try #require(place(panel, column: column, window: window))
        #expect(placed.minX == window.maxX + gap)
        #expect(placed.minY == panel.minY, "the panel keeps its height on the screen")
        #expect(!placed.intersects(window) && screen.contains(placed))
    }

    @Test func withNoRoomThereItGoesOutsideOnTheFarSide() throws {
        let window = CGRect(x: 400, y: 100, width: 1100, height: 700)   // 12 points from the right edge
        let column = columnOnRight(of: window)
        let panel = CGRect(x: 1250, y: 300, width: 228, height: 320)
        let placed = try #require(place(panel, column: column, window: window))
        #expect(placed.maxX == window.minX - gap)
        #expect(!placed.intersects(window) && screen.contains(placed))
    }

    @Test func aWindowThatFillsTheScreenPutsItBesideTheColumn() throws {
        let window = screen
        let column = columnOnRight(of: window)
        let panel = CGRect(x: 1250, y: 300, width: 228, height: 320)
        let placed = try #require(place(panel, column: column, window: window))
        #expect(placed.maxX == column.minX - gap)
        #expect(!placed.intersects(column) && screen.contains(placed))
    }

    @Test func aColumnOnTheLeftMirrorsIt() throws {
        let window = CGRect(x: 300, y: 100, width: 1000, height: 700)
        let column = CGRect(x: window.minX, y: window.minY, width: 300, height: window.height)
        let panel = CGRect(x: 350, y: 300, width: 228, height: 320)
        let placed = try #require(place(panel, column: column, window: window))
        #expect(placed.maxX == window.minX - gap)

        let filling = screen
        let leftColumn = CGRect(x: 0, y: 0, width: 300, height: filling.height)
        let inside = try #require(place(CGRect(x: 40, y: 300, width: 228, height: 320),
                                        column: leftColumn, window: filling))
        #expect(inside.minX == leftColumn.maxX + gap)
    }

    @Test func aPanelOfItsOwnWindowGoesBesideThatWindow() throws {
        // The detached panel: the column is the whole window.
        let window = CGRect(x: 600, y: 200, width: 320, height: 600)
        let panel = CGRect(x: 650, y: 300, width: 228, height: 320)
        let placed = try #require(place(panel, column: window, window: window))
        #expect(placed.minX == window.maxX + gap)
        #expect(!placed.intersects(window))
    }

    @Test func aPanelHangingOffTheScreenIsBroughtBackOn() throws {
        let window = CGRect(x: 100, y: 100, width: 1000, height: 700)
        let column = columnOnRight(of: window)
        let low = try #require(place(CGRect(x: 900, y: -200, width: 228, height: 320), column: column, window: window))
        #expect(low.minY == screen.minY)
        let high = try #require(place(CGRect(x: 900, y: 700, width: 228, height: 320), column: column, window: window))
        #expect(high.maxY == screen.maxY)
    }

    @Test func aScreenWithRoomForNothingStillKeepsItOnScreen() throws {
        let narrow = CGRect(x: 0, y: 0, width: 500, height: 400)
        let window = narrow
        let column = CGRect(x: 200, y: 0, width: 300, height: 400)
        let panel = CGRect(x: 250, y: 50, width: 228, height: 320)
        let origin = try #require(ColorPanelPlacement.origin(panel: panel, column: column, window: window, screen: narrow))
        #expect(narrow.contains(CGRect(origin: origin, size: panel.size)))
    }

    /// The same windows on every run.
    struct Steps: RandomNumberGenerator {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    /// Wherever the panel starts over the column, with a window anywhere on
    /// the screen: the place chosen is on the screen, and clear of the column
    /// whenever the screen has a strip wide enough beside it.
    @Test func whereverItStartsItEndsOnScreenAndClear() {
        var generator = Steps()
        for _ in 0 ..< 400 {
            let width = CGFloat.random(in: 500 ... 1512, using: &generator)
            let height = CGFloat.random(in: 400 ... 944, using: &generator)
            let window = CGRect(x: CGFloat.random(in: 0 ... (1512 - width), using: &generator),
                                y: CGFloat.random(in: 0 ... (944 - height), using: &generator),
                                width: width, height: height)
            let column = columnOnRight(of: window, width: CGFloat.random(in: 240 ... 360, using: &generator))
            let panel = CGRect(x: column.minX + CGFloat.random(in: -200 ... 300, using: &generator),
                               y: CGFloat.random(in: 0 ... 600, using: &generator), width: 228, height: 320)
            guard let placed = place(panel, column: column, window: window) else {
                #expect(!panel.intersects(column))
                continue
            }
            #expect(screen.contains(placed), "placed \(placed) for window \(window)")
            let roomBeside = column.minX - gap - panel.width >= screen.minX
                || window.maxX + gap + panel.width <= screen.maxX
            if roomBeside { #expect(!placed.intersects(column), "placed \(placed) over column \(column)") }
        }
    }
}
#endif
