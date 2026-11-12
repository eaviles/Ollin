import Testing
@testable import Ollin

/// A long menu folded into submenus: what the first level reads, that every
/// option is still reachable exactly once, and what an option is called
/// inside its submenu. The easing curves are the roster that needed it:
/// thirty-two names in one list, twelve rows folded.
@Suite
struct ParamMenuGroupTests {
    typealias Menu = ParamControl.Menu
    typealias Row = ParamControl.Menu.Row

    final class Subject: Sketch {
        @Param var curve: Easing = .easeInOutCubic
        @Param var finish: Material = .matte
        @Param var wood: Wood = .oak
    }

    /// A roster with one group, one name the roster does not hold, and one
    /// choice left on the first level.
    struct Wood: ParamChoices, Equatable {
        let grain: Int
        static let oak = Wood(grain: 1), redOak = Wood(grain: 2), whiteOak = Wood(grain: 3), pine = Wood(grain: 4)
        static var paramChoices: [(name: String, value: Wood)] {
            [("pine", .pine), ("oak", .oak), ("redOak", .redOak), ("whiteOak", .whiteOak)]
        }
        static var paramChoiceGroups: [(title: String, names: [String])] {
            [("Oak", ["oak", "redOak", "whiteOak", "bogOak"])]
        }
    }

    @MainActor private func menu(_ name: String) throws -> Menu {
        let handle = try #require(Subject().parameters().first { $0.name == name })
        guard case .menu(let menu) = handle.control else {
            Issue.record("\(name) is not a menu")
            throw CancellationError()
        }
        return menu
    }

    private func menu(_ options: [String], _ groups: [Menu.Group]) -> Menu {
        Menu(options: options, groups: groups, read: { 0 }, write: { _ in })
    }

    @Test @MainActor func theCurvesFoldIntoTwelveRows() throws {
        let menu = try menu("curve")
        #expect(menu.options.count == 32)
        let titles = menu.rows.map { row -> String in
            switch row {
            case .option(let index): return menu.options[index]
            case .group(let group): return group.title + " >"
            }
        }
        #expect(titles == ["Linear", "Sine >", "Quad >", "Cubic >", "Quart >", "Quint >", "Expo >", "Circ >",
                           "Back >", "Elastic >", "Bounce >", "Smoothstep"])
    }

    @Test @MainActor func everyCurveIsReachableOnce() throws {
        let menu = try menu("curve")
        var reached: [Int] = []
        for row in menu.rows {
            switch row {
            case .option(let index): reached.append(index)
            case .group(let group): reached.append(contentsOf: group.indices)
            }
        }
        #expect(reached.sorted() == Array(menu.options.indices))
    }

    @Test @MainActor func aFamilyReadsInOutAndBoth() throws {
        let menu = try menu("curve")
        let cubic = try #require(menu.groups.first { $0.title == "Cubic" })
        #expect(cubic.indices.map { menu.options[$0] } == ["Ease In Cubic", "Ease Out Cubic", "Ease In Out Cubic"])
        #expect(cubic.indices.map { Menu.shortLabel(menu.options[$0], under: cubic.title) }
                == ["Ease In", "Ease Out", "Ease In Out"])
    }

    @Test @MainActor func aPickInsideASubmenuStillWritesItsOwnName() throws {
        let sketch = Subject()
        let handle = try #require(sketch.parameters().first { $0.name == "curve" })
        guard case .menu(let menu) = handle.control else { return }
        let bounce = try #require(menu.groups.first { $0.title == "Bounce" })
        menu.write(bounce.indices[1])
        #expect(sketch.curve == .easeOutBounce)
        #expect(handle.param.stored == .option("easeOutBounce"))
        #expect(menu.read() == bounce.indices[1])
    }

    @Test @MainActor func aRosterThatDeclaresNoGroupsStaysFlat() throws {
        let menu = try menu("finish")
        #expect(menu.groups.isEmpty)
        #expect(menu.rows == menu.options.indices.map { Row.option($0) })
    }

    @Test @MainActor func aNameTheRosterDoesNotHoldIsIgnored() throws {
        let menu = try menu("wood")
        #expect(menu.options == ["Pine", "Oak", "Red Oak", "White Oak"])
        #expect(menu.rows == [.option(0), .group(Menu.Group(title: "Oak", indices: [1, 2, 3]))])
    }

    @Test func aSubmenuStandsWhereItsFirstOptionStood() {
        let menu = menu(["a", "b", "c", "d", "e"], [Menu.Group(title: "Late", indices: [4, 2]),
                                                    Menu.Group(title: "Early", indices: [1])])
        #expect(menu.rows == [.option(0), .group(Menu.Group(title: "Early", indices: [1])),
                              .group(Menu.Group(title: "Late", indices: [4, 2])), .option(3)])
    }

    @Test func anOptionTwoGroupsNameStaysWithTheFirst() {
        let menu = menu(["a", "b", "c"], [Menu.Group(title: "One", indices: [0, 1]),
                                          Menu.Group(title: "Two", indices: [1, 2])])
        #expect(menu.rows == [.group(Menu.Group(title: "One", indices: [0, 1])),
                              .group(Menu.Group(title: "Two", indices: [2]))])
    }

    @Test func aGroupLeftWithNothingIsNoRow() {
        let menu = menu(["a", "b"], [Menu.Group(title: "Gone", indices: [7, -1]),
                                     Menu.Group(title: "Twice", indices: [])])
        #expect(menu.rows == [.option(0), .option(1)])
    }

    @Test(arguments: [
        ("Ease In Out Cubic", "Cubic", "Ease In Out"),
        ("Brushed Metal", "Metal", "Brushed"),
        ("Metal Brushed", "Metal", "Brushed"),
        ("Soap Bubble", "Glass", "Soap Bubble"),      // the title is not part of it
        ("Cubic", "Cubic", "Cubic"),                  // nothing would be left
        ("ease in cubic", "Cubic", "ease in"),        // whatever the case
        ("Ease In Out Cubic", "Out Cubic", "Ease In"),
        ("Linear", "", "Linear"),
    ])
    func anOptionDropsItsGroupsWord(option: String, title: String, expected: String) {
        #expect(Menu.shortLabel(option, under: title) == expected)
    }
}
