import Foundation
import Metal
@testable import Ollin
import Testing

/// What `ollin doctor` says about this machine. The report is the framework's
/// own, so these read exactly what the command prints: that every answer is
/// shaped for a person, that anything called a problem carries the line that
/// fixes it, and that the two answers a running test process has already proven
/// come back as they should.
struct DoctorTests {

    /// One report, read three ways, since asking for it runs the compilers and
    /// compiles a shader.
    ///
    /// Every finding is said in full. A problem is only useful with the thing to
    /// do about it beside it: a note may carry one; an `ok` never needs one. And
    /// this process has already compiled the shader library to run its own
    /// snapshots, so both GPU answers are settled before the report is asked.
    @Test func everyFindingIsSaidInFull() throws {
        let findings = Doctor.report()
        #expect(!findings.isEmpty)
        for finding in findings {
            #expect(!finding.title.isEmpty)
            #expect(!finding.detail.isEmpty)
            #expect(finding.notes.allSatisfy { !$0.isEmpty })
        }

        for finding in findings where finding.level == .problem {
            #expect(finding.fix != nil, "\(finding.title) says something is wrong and not what to do")
        }

        try #require(MTLCreateSystemDefaultDevice() != nil)
        let device = try #require(findings.first { $0.title == "The Metal device" })
        #expect(device.level == .ok)
        #expect(!device.detail.isEmpty)
        // Ray tracing, mesh shaders, and temporal scaling are each said either way.
        #expect(device.notes.count == 3)
        let shaders = try #require(findings.first { $0.title == "The shader compiler" })
        #expect(shaders.level == .ok)
    }

    /// A checkout that is not the one the command on the path points at is a
    /// note rather than a silence, because running one clone's command against
    /// another clone's sources is the confusing case this exists to name.
    @Test func aCommandFromAnotherCheckoutIsSaidSo() throws {
        let elsewhere = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-doctor-\(UUID().uuidString)").path
        let findings = Doctor.report(repository: elsewhere)
        let command = try #require(findings.first { $0.title == "The ollin command" })
        #expect(command.level == .note)
        #expect(command.fix == "Scripts/ollin install")
    }

    /// The lines the command prints: the answer, then anything under it, then
    /// the fix last, so the thing to do is what is left on screen.
    @Test func theLinesReadAsTheCommandPrintsThem() {
        let findings = [Doctor.Finding(.problem, "The shader compiler", "it would not compile",
                                       notes: ["every sketch compiles the library when it starts"],
                                       fix: "xcodebuild -downloadComponent MetalToolchain")]
        let lines = Doctor.lines(findings)
        #expect(lines.count == 3)
        #expect(lines[0] == "  no  The shader compiler: it would not compile")
        #expect(lines[1].hasPrefix("        every sketch"))
        #expect(lines[2] == "        fix: xcodebuild -downloadComponent MetalToolchain")
        #expect(Doctor.hasProblem(findings))
        #expect(!Doctor.hasProblem([Doctor.Finding(.note, "a", "b")]))
    }

    /// The places zsh is asked about are real directories to look in, named
    /// absolutely, so a person can check the same ones by hand.
    @Test func theCompletionHomesAreAbsolute() {
        #expect(!Doctor.completionDirectories.isEmpty)
        #expect(Doctor.completionDirectories.allSatisfy { $0.hasPrefix("/") })
    }
}
