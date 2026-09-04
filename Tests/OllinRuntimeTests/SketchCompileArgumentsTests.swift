import Testing
@testable import OllinRuntime

/// The `swiftc` line a sketch compile starts from. The compiler's own default
/// is `-Onone`, and a sketch left there ran its CPU work several times slower
/// under the live window than under a release build, so the level is always
/// spelled out and optimized unless the host asks for the plain compile.
@Suite
struct SketchCompileArgumentsTests {
    private func arguments(_ optimization: SketchLoader.Optimization) -> [String] {
        SketchLoader.compileArguments(
            dylibPath: "/tmp/work/sketch.dylib", moduleName: "OllinRuntimeSketch_1",
            sources: ["/tmp/work/Sketch.swift", "/tmp/work/__OllinFactory.swift"],
            optimization: optimization)
    }

    @Test func aSketchCompilesOptimizedByDefault() {
        #expect(SketchLoader(sketchPath: "/tmp/Sketch.swift").optimization == .speed)
        let args = arguments(.speed)
        #expect(args.contains("-O"))
        #expect(!args.contains("-Onone"))
    }

    @Test func thePlainCompileSaysSo() {
        let args = arguments(.none)
        #expect(args.contains("-Onone"))
        #expect(!args.contains("-O"))
    }

    @Test func theLevelIsSpelledOutOnceAndTheLinkerFlagsSurvive() {
        for level in [SketchLoader.Optimization.speed, .none] {
            let args = arguments(level)
            #expect(args.filter { $0.hasPrefix("-O") }.count == 1)
            #expect(args.first == "swiftc")
            #expect(args.contains("-emit-library"))
            // Ollin symbols stay unresolved at link time so they bind to the
            // host at `dlopen`; one shared `Sketch` across the boundary.
            #expect(args.contains("dynamic_lookup"))
            #expect(!args.contains("-lOllin"))
            #expect(args.contains("/tmp/work/Sketch.swift"))
            #expect(args.contains("/tmp/work/__OllinFactory.swift"))
        }
    }
}
