import Foundation
import OllinRuntime

// MARK: - The compile pass

/// A block's answer: whether it failed, the first error it gave, and whether
/// the answer is worth keeping for the next run.
struct Answer: Sendable {
    var failed = false
    var message = ""
    var keep = true
}

/// One block as the compile pass needs it.
struct CompileJob: Sendable {
    /// The whole file handed to the compiler.
    var source: String
    /// The file's name, which a diagnostic then carries.
    var name: String
    /// The path the loader is made for, beside the page's preambles.
    var loaderPath: String
    var preambleLines: Range<Int>
    /// The answer kept from an earlier run, when there is one: "" for a block
    /// that compiled, else the error it gave.
    var known: String?
    /// The page and line, for a report.
    var place: String
}

/// How a compiler's log becomes the one line a person acts on.
typealias FirstError = @Sendable (_ log: String, _ preambleLines: Range<Int>) -> String

/// Compile every job that has no kept answer, across the cores.
///
/// With `direct`, a block is compiled by the compiler process alone, and the
/// jobs `compares` picks are compiled through the loader as well; a job whose
/// two answers differ is named in `disagreements`. Without it every block goes
/// through the loader, one loader per job, each writing its own work
/// directory so the runs do not collide.
func compileAll(_ jobs: [CompileJob], direct: DirectCompile?, compares: Set<Int>, firstError: @escaping FirstError,
                quiet: Bool) -> (answers: [Answer], disagreements: [String]) {
    let found = Shelf<Answer>()
    let disagreed = Shelf<String>()
    let tally = Tally()
    let total = jobs.count

    @Sendable func answer(_ result: Result<Void, SketchLoader.LoadError>, _ job: CompileJob) -> Answer {
        guard case .failure(let error) = result else { return Answer() }
        let log = "\(error)"
        let message = firstError(log, job.preambleLines)
        // Only a diagnostic is an answer worth keeping. A compiler that died
        // or could not start says nothing about the block, and remembering
        // that would repeat it on every later run.
        return Answer(failed: true, message: message, keep: log.contains(": error: ") && !message.isEmpty)
    }
    // Two compiles of one block name their throwaway modules apart, and that
    // name can appear in a message; everything else has to match to the letter.
    @Sendable func comparable(_ answer: Answer) -> String {
        (answer.failed ? "failed: " : "compiled") + answer.message.replacingOccurrences(
            of: #"OllinRuntimeCheck_[A-Fa-f0-9]+"#, with: "the probe", options: .regularExpression)
    }

    DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
        let job = jobs[index]
        // Each compile opens pipes to its process, and the handles are let go
        // only when a pool drains. The threads of this loop never return to
        // one until the loop ends, so without a pool of its own per block the
        // handles pile up, about two a compile through the loader: 3,731
        // open after 84 s, against 33 throughout with the pool (measured
        // 2026-11-11). A process here may hold 10,240 files; a run that
        // compiled every block twice passed that near its end, and from
        // there nothing can be written or started.
        autoreleasepool {
            if let known = job.known {
                found.put(Answer(failed: !known.isEmpty, message: known), at: index)
            } else {
                @Sendable func throughLoader() -> Answer {
                    answer(SketchLoader(sketchPath: job.loaderPath).typecheck(job.source, fileName: job.name), job)
                }
                if let direct {
                    let mine = answer(direct.typecheck(job.source, fileName: job.name), job)
                    found.put(mine, at: index)
                    if compares.contains(index) {
                        let theirs = throughLoader()
                        if comparable(mine) != comparable(theirs) {
                            disagreed.put("\(job.place): the compiler alone says \"\(comparable(mine))\", "
                                          + "the loader says \"\(comparable(theirs))\"", at: index)
                        }
                    }
                } else {
                    found.put(throughLoader(), at: index)
                }
            }
        }
        let done = tally.add()
        if !quiet && done % 25 == 0 {
            FileHandle.standardError.write(Data("  \(done)/\(total)\r".utf8))
        }
    }
    return (jobs.indices.map { found[$0] ?? Answer(failed: true, message: "no answer", keep: false) },
            disagreed.all.sorted())
}

/// A count kept from many threads.
final class Tally: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func add() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}
