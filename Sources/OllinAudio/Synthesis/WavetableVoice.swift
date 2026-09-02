import Foundation

/// One wavetable note's running state: where in the cycle it is, how fast it
/// moves, and which strength of the table it reads.
///
/// The table is held by the synth rather than copied here, exactly as a
/// sampled voice holds its instrument. Set before the note starts and only
/// read afterwards.
struct WavetableVoice {
    private var table: Wavetable?
    /// Position through the current cycle, `0..<1`.
    private var phase = 0.0
    /// The fraction of a cycle one sample covers.
    private var increment = 0.0
    /// Which level of band limiting the note reads, chosen once from its pitch.
    private var level = 0
    private var scan = WavetableScan()

    mutating func reset() {
        table = nil
        phase = 0
    }

    /// Sets up a note.
    mutating func start(table: Wavetable, scan: WavetableScan, frequency: Double,
                        sampleRate: Double) {
        self.table = table
        self.scan = scan
        phase = 0
        increment = frequency / max(1, sampleRate)
        // The strongest level whose top harmonic still fits under half the
        // sample rate: what keeps a bright frame from folding at high notes.
        level = Wavetable.level(forIncrement: increment)
    }

    /// One sample, with the scan's envelope at `travel` (`0...1`) moving the
    /// position by the scan's sweep.
    mutating func next(travel: Double) -> Double {
        guard let table else { return 0 }
        let position = scan.position + scan.sweep * travel
        let value = table.sample(position: position, phase: phase, level: level)
        phase = fract(phase + increment)
        return Double(value)
    }
}
