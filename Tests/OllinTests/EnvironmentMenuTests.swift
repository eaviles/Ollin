import Testing
@testable import Ollin

/// `Environment` on the inspector's menu (`ParamChoices`): the roster is the
/// built-in list in its browse order, a tuned choice persists under its name
/// and restores to the same value, and an environment built another way (a
/// procedural sky, a modified built-in) is off the menu and reads as the first
/// entry, the `ParamChoices` rule.
@Suite struct EnvironmentMenuTests {

    @Test func theMenuIsTheBuiltInRosterInBrowseOrder() {
        let names = Environment.paramChoices.map(\.name)
        #expect(names == Environment.allBuiltins.map(\.name))
        #expect(names.count == 20)
        #expect(names.first == "studio")
        for (choice, builtin) in zip(Environment.paramChoices, Environment.allBuiltins) {
            #expect(choice.value == builtin.environment)
        }
    }

    @Test func aChoicePersistsUnderItsNameAndRestores() {
        let param = Param(wrappedValue: Environment.sunset)
        #expect(param.stored == .option("sunset"))
        param.restore(.option("cityNight"))
        #expect(param.wrappedValue == .cityNight)
        #expect(param.control.isMenu, "a named-catalog type is a pop-up menu")
    }

    @Test func anEnvironmentBuiltAnotherWayIsOffTheMenu() {
        let sky = Environment.sky(sunElevation: 0.4)
        #expect(!Environment.paramChoices.contains { $0.value == sky })
        #expect(Environment.stored(sky) == .option("studio"),
                "a value that matches no choice persists as the first entry, the ParamChoices rule")
        let modified = Environment.city.lightingOnly()
        #expect(!Environment.paramChoices.contains { $0.value == modified },
                "a modifier makes a different value; keep the parameter on the plain built-in")
    }
}

private extension ParamControl {
    var isMenu: Bool {
        if case .menu = self { return true }
        return false
    }
}
