import Foundation
import Ollin
import OllinRuntime

/// `swift run OllinRun --selftest`: the headless gate for the host that puts a
/// loose file on a wall. It needs no window, and it covers the two things this
/// host adds over the live host's own self-test.
///
/// The first is that the declaration survives the compile. A sketch on a wall
/// is configured by what it declares, and that declaration is written in a file
/// that is compiled into a dylib and loaded back: if any of it were lost on the
/// way, the piece would open in an ordinary window and nobody would know why.
///
/// The second is quieter and worse. The checkpoint a run writes is filed under
/// the sketch's own name, and each compile of a loose file is given a fresh
/// module name so repeated loads cannot collide. If that token reached the
/// name, every launch would look for a file the last launch never wrote, and a
/// piece that resumes at a desk would silently start over every morning on a
/// wall. So two compiles of one file must produce one name, and it must be the
/// name written in the file.
enum RunSelfTest {

    @MainActor
    static func run() -> Never {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("OllinRun-selftest")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // A sketch that declares nothing runs at a desk, whatever host started
        // it. This host must not put every loose file on a wall.
        print("OllinRun selftest: a plain sketch stays a plain sketch …")
        let plain = load(source: """
        import Ollin
        final class PlainSelfTestSketch: Sketch {
            override func draw() { background(.white) }
        }
        """, named: "Plain.swift", in: dir)
        guard !plain.installation.runsUnattended else {
            fail("a sketch that declares no installation came back running unattended")
        }

        // Everything the piece declares has to arrive intact: it is the whole
        // configuration of the run.
        print("OllinRun selftest: a declared installation survives the compile …")
        let wallSource = """
        import Ollin
        final class WallSelfTestSketch: Sketch {
            override var installation: Installation {
                Installation(hidesPointer: false,
                             checkpoint: .every(seconds: 30),
                             restarts: .onFailure(stalledAfter: 12))
            }
            override func draw() {
                background(.black)
                fill(.white)
                drawCircle(width / 2, height / 2, 120)
            }
        }
        """
        let wall = load(source: wallSource, named: "Wall.swift", in: dir)
        let declared = wall.installation
        guard declared.runsUnattended, declared.fillsScreen, !declared.hidesPointer else {
            fail("the window part of the declaration was lost: \(declared)")
        }
        guard declared.checkpoint == .every(seconds: 30) else {
            fail("the checkpoint cadence was lost: \(declared.checkpoint)")
        }
        guard declared.restarts == .onFailure(stalledAfter: 12) else {
            fail("the watch was lost: \(declared.restarts)")
        }

        // The name the checkpoint is filed under, twice, from two compiles of
        // the same file.
        print("OllinRun selftest: the sketch keeps one name across two compiles …")
        let again = load(source: wallSource, named: "Wall.swift", in: dir)
        let firstName = String(describing: type(of: wall))
        let secondName = String(describing: type(of: again))
        guard firstName == secondName else {
            fail("two compiles of one file gave two names (\(firstName), \(secondName)), "
                 + "so a piece would never find yesterday's checkpoint")
        }
        guard firstName == "WallSelfTestSketch" else {
            fail("the sketch's name came back as '\(firstName)' rather than the one in the file")
        }
        // Printed rather than asserted, and it is what makes the check above
        // worth having: the two modules really are different, and the name the
        // checkpoint uses is the one that drops them.
        print("  (the two modules: \(String(reflecting: type(of: wall))), "
              + "\(String(reflecting: type(of: again))))")

        // The loaded sketch draws through this binary's own Metal path, which
        // is what a window would ask of it a moment later.
        print("OllinRun selftest: the loaded sketch renders a frame …")
        guard OllinApp.image(of: wall) != nil else {
            fail("the loaded sketch rendered nothing")
        }

        print("OllinRun selftest: PASS: the declaration survived the compile, the sketch "
              + "kept the name '\(firstName)' across two of them, and it rendered.")
        exit(0)
    }

    /// Write `source` to a file and compile and load it, the way the host does.
    @MainActor
    private static func load(source: String, named name: String, in dir: String) -> Sketch {
        let path = (dir as NSString).appendingPathComponent(name)
        do {
            try source.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            fail("could not write \(name): \(error)")
        }
        switch SketchLoader(sketchPath: path).load() {
        case .success(let sketch): return sketch
        case .failure(let error): fail("\(name) did not load: \(error)")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("OllinRun selftest: FAIL: \(message)\n".utf8))
        exit(1)
    }
}
