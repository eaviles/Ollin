import CoreML
import Foundation

/// Loads Core ML models **one at a time, process-wide**. Load-bearing:
/// concurrent `MLModel` loads of the *same* compiled model directory race in
/// the framework's GPU program preparation, and some of the instances come
/// back subtly broken: they load without error and then return wrong
/// numbers. Measured with four concurrent loads of one compiled path
/// (`.cpuAndGPU`): three of the four instances produced corrupt masks,
/// nondeterministically; with the loads serialized and only the
/// *predictions* concurrent, all four were byte-identical and correct.
/// Loading the same model into several trackers is the ordinary case (two
/// trackers over one fetched model, a test suite running in parallel), so
/// every tracker's load goes through here, never through `MLModel.load`
/// directly.
///
/// Only the load is serialized; predictions stay fully concurrent.
actor ModelLoader {

    static let shared = ModelLoader()

    /// Whether a load is running; late arrivals park in `waiters` and are
    /// woken one at a time. An actor alone wouldn't do this: awaiting the
    /// framework's load suspends the actor, and reentrancy would let the
    /// next load start mid-way.
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func load(contentsOf url: URL,
              computeUnits: MLComputeUnits = .all) async throws -> sending MLModel {
        while busy {
            await withCheckedContinuation { waiters.append($0) }
        }
        busy = true
        defer {
            busy = false
            if !waiters.isEmpty { waiters.removeFirst().resume() }
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        return try await MLModel.load(contentsOf: url, configuration: configuration)
    }
}
