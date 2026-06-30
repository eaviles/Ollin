import Testing
import Foundation

extension Trait where Self == ConditionTrait {

    /// The gate every GPU micro-benchmark shares: enabled only when `OLLIN_BENCH`
    /// is set in the environment, so the normal test suite skips the long sweeps.
    /// Run them via `Scripts/benchmark.sh <name>`.
    static var benchmark: Self {
        .enabled(if: ProcessInfo.processInfo.environment["OLLIN_BENCH"] != nil,
                 "set OLLIN_BENCH=1 (Scripts/benchmark.sh) to run the GPU micro-benchmarks")
    }
}
