import Foundation
import Testing
@testable import Ollin

/// A sketch run with `--help` says what it takes and stops: its name, the
/// usage line from the words it was run with, its parameters, and the flags,
/// and the command line reports the run handled, so no window opens.
@MainActor
@Suite struct CommandLineHelpTests {

    final class Dial: Sketch {
        @Param("Radius", 10 ... 200) var radius = 80.0
        @Param("Seed", 1 ... 9) var seed = 3
        override func draw() {}
    }

    @Test func theHelpNamesTheSketchItsParametersAndItsFlags() {
        let sketch = Dial()
        let text = CommandLineHelp.text(for: sketch, arguments: ["/tmp/build/Example-Dial", "--help"])
        #expect(text.hasPrefix("Dial, an Ollin sketch."))
        #expect(text.contains("usage: Example-Dial [flags]"))
        #expect(text.contains("2 parameters, as --param takes them"))
        #expect(text.contains("radius") && text.contains("10...200"))
        #expect(text.contains("--export FILE"))
        #expect(text.contains("write one frame as a PNG"))
        #expect(text.contains("--help"))
        #expect(text.hasSuffix("Each flag in full: ollin docs Export"))
    }

    /// A host run names the sketch file in its usage line, the words before
    /// the first flag.
    @Test func aHostsUsageLineKeepsTheSketchFile() {
        let sketch = Dial()
        let text = CommandLineHelp.text(for: sketch, arguments: ["/usr/local/bin/OllinLive", "Sketches/Dial.swift", "-h"])
        #expect(text.contains("usage: OllinLive Sketches/Dial.swift [flags]"))
    }

    /// A sketch whose `setup()` would start something (a camera, a model)
    /// starts nothing under `--help`, and its parameters read as declared.
    @Test func helpNeverRunsSetup() {
        final class Starter: Sketch {
            static var setups = 0
            @Param("Radius", 10 ... 200) var radius = 80.0
            override func setup() {
                Starter.setups += 1
                radius = 150
            }
            override func draw() {}
        }
        Starter.setups = 0
        let sketch = Starter()
        let text = CommandLineHelp.text(for: sketch, arguments: ["Example-Starter", "--help"])
        #expect(text.contains("80") && !text.contains("150"))
        #expect(OllinApp.handleCommandLine(["Example-Starter", "--help"]) { Starter() })
        #expect(Starter.setups == 0, "setup ran \(Starter.setups) times under --help")
    }

    /// `--help` and `-h` both count as handled, ahead of any export on the
    /// line, so the caller exits instead of opening a window or writing.
    @Test func helpIsHandledBeforeAnythingElse() {
        #expect(OllinApp.handleCommandLine(["Example-Dial", "--help"]) { Dial() })
        #expect(OllinApp.handleCommandLine(["Example-Dial", "-h"]) { Dial() })
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("ollin-help-\(UUID().uuidString).png").path
        #expect(OllinApp.handleCommandLine(["Example-Dial", "--export", path, "--help"]) { Dial() })
        #expect(!FileManager.default.fileExists(atPath: path), "the export ran under --help")
        #expect(!OllinApp.isRenderingHeadless)
    }
}
