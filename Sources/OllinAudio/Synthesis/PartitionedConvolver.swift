import Accelerate
import Foundation

/// A stream convolved with a long response, block by block, with no latency.
///
/// The response is cut into partitions one block long. The first is applied
/// directly, sample by sample, so the answer to a sample begins on that
/// sample. The rest are applied in the frequency domain: each block's
/// spectrum is kept in a line, every partition's spectrum is multiplied
/// against the block it lines up with, and the products are summed before one
/// inverse transform. That sum is what makes a ten-second room cost about
/// what a short one does. The later partitions can afford to come out one
/// block late, because they begin one block into the response anyway: the
/// delay the buffering costs is exactly the delay their taps carry, so the
/// two paths add up to the whole convolution on time.
///
/// One of these per channel. Any number of samples may be handed in at once;
/// the block size inside is fixed, and the buffering hides it.
final class PartitionedConvolver {
    /// Samples per partition. At 256 the direct head is still cheap and a
    /// long room is still few enough spectra to sum on every block.
    static let partition = 256
    /// The most samples one `process` call takes; a longer stretch is handed
    /// over in slices of this.
    static let slice = 4096

    private let partition: Int
    private let fftLength: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    /// What the inverse transform of a product of two forward transforms is
    /// off by: each forward is twice the mathematical transform and the
    /// inverse is the length times it.
    private let scale: Float

    // The head, applied directly.
    private let head: UnsafeMutablePointer<Float>
    private let signal: UnsafeMutablePointer<Float>

    // The tail, as spectra.
    private let partitionCount: Int
    private let spectraReal: UnsafeMutablePointer<Float>
    private let spectraImag: UnsafeMutablePointer<Float>
    private let lineReal: UnsafeMutablePointer<Float>
    private let lineImag: UnsafeMutablePointer<Float>
    private var lineHead = 0
    private let pending: UnsafeMutablePointer<Float>
    private var pendingCount = 0
    private let previous: UnsafeMutablePointer<Float>
    private let frame: UnsafeMutablePointer<Float>
    private let frameReal: UnsafeMutablePointer<Float>
    private let frameImag: UnsafeMutablePointer<Float>
    private var sumReal: UnsafeMutablePointer<Float>
    private var sumImag: UnsafeMutablePointer<Float>
    private var altReal: UnsafeMutablePointer<Float>
    private var altImag: UnsafeMutablePointer<Float>
    private let output: UnsafeMutablePointer<Float>
    private let outputCapacity: Int
    private var outputRead = 0
    private var outputCount = 0

    /// How many taps the response has, after the head and tail were cut.
    let tapCount: Int

    init(response: [Float]) {
        let taps = response.isEmpty ? [0] : response
        tapCount = taps.count
        partition = PartitionedConvolver.partition
        fftLength = partition * 2
        log2n = vDSP_Length(log2(Double(fftLength)).rounded())
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        scale = 1 / Float(4 * fftLength)

        // The head is always one partition; a shorter response is padded.
        head = .allocate(capacity: partition)
        head.initialize(repeating: 0, count: partition)
        for index in 0..<min(partition, taps.count) { head[index] = taps[index] }
        let signalLength = partition - 1 + PartitionedConvolver.slice
        signal = .allocate(capacity: signalLength)
        signal.initialize(repeating: 0, count: signalLength)

        let tail = taps.count > partition ? Array(taps[partition...]) : []
        partitionCount = (tail.count + partition - 1) / partition
        let bins = max(1, partitionCount) * partition
        spectraReal = .allocate(capacity: bins)
        spectraImag = .allocate(capacity: bins)
        lineReal = .allocate(capacity: bins)
        lineImag = .allocate(capacity: bins)
        spectraReal.initialize(repeating: 0, count: bins)
        spectraImag.initialize(repeating: 0, count: bins)
        lineReal.initialize(repeating: 0, count: bins)
        lineImag.initialize(repeating: 0, count: bins)
        pending = .allocate(capacity: partition)
        pending.initialize(repeating: 0, count: partition)
        previous = .allocate(capacity: partition)
        previous.initialize(repeating: 0, count: partition)
        frame = .allocate(capacity: fftLength)
        frame.initialize(repeating: 0, count: fftLength)
        frameReal = .allocate(capacity: partition)
        frameImag = .allocate(capacity: partition)
        frameReal.initialize(repeating: 0, count: partition)
        frameImag.initialize(repeating: 0, count: partition)
        sumReal = .allocate(capacity: partition)
        sumImag = .allocate(capacity: partition)
        altReal = .allocate(capacity: partition)
        altImag = .allocate(capacity: partition)
        sumReal.initialize(repeating: 0, count: partition)
        sumImag.initialize(repeating: 0, count: partition)
        altReal.initialize(repeating: 0, count: partition)
        altImag.initialize(repeating: 0, count: partition)

        // The tail's output runs one partition late, so the ring starts with
        // one partition of silence in it; see the type's note on why that is
        // the right amount.
        outputCapacity = PartitionedConvolver.slice + partition * 2
        output = .allocate(capacity: outputCapacity)
        output.initialize(repeating: 0, count: outputCapacity)
        outputCount = partition

        // Each partition is transformed once, zero-padded to the frame, which
        // is what lets a block's spectrum meet it without wrapping.
        for index in 0..<partitionCount {
            frame.update(repeating: 0, count: fftLength)
            let start = index * partition
            let count = min(partition, tail.count - start)
            for offset in 0..<count { frame[offset] = tail[start + offset] }
            transformFrame(intoReal: spectraReal + index * partition,
                           imag: spectraImag + index * partition)
        }
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
        head.deallocate()
        signal.deallocate()
        spectraReal.deallocate()
        spectraImag.deallocate()
        lineReal.deallocate()
        lineImag.deallocate()
        pending.deallocate()
        previous.deallocate()
        frame.deallocate()
        frameReal.deallocate()
        frameImag.deallocate()
        sumReal.deallocate()
        sumImag.deallocate()
        altReal.deallocate()
        altImag.deallocate()
        output.deallocate()
    }

    /// Convolves `count` samples of `input`, writing the result to `wet`.
    /// `count` is at most `slice`.
    func process(input: UnsafePointer<Float>, wet: UnsafeMutablePointer<Float>, count: Int) {
        precondition(count <= PartitionedConvolver.slice)
        guard count > 0 else { return }
        let overlap = partition - 1

        // The head: the last partition of input is kept ahead of the new
        // samples, and the response runs backward over it, which is how a
        // correlation routine convolves.
        (signal + overlap).update(from: input, count: count)
        vDSP_conv(signal, 1, head + overlap, -1, wet, 1,
                  vDSP_Length(count), vDSP_Length(partition))
        signal.update(from: signal + count, count: overlap)

        guard partitionCount > 0 else { return }

        // The tail: the input gathers into whole partitions, each of which
        // pushes one partition of output onto the ring.
        var consumed = 0
        while consumed < count {
            let take = min(partition - pendingCount, count - consumed)
            (pending + pendingCount).update(from: input + consumed, count: take)
            pendingCount += take
            consumed += take
            if pendingCount == partition { processPartition() }
        }

        // And the ring hands back exactly the samples this call asked for.
        var remaining = count
        var written = 0
        while remaining > 0 {
            let run = min(remaining, outputCapacity - outputRead)
            vDSP_vadd(wet + written, 1, output + outputRead, 1, wet + written, 1, vDSP_Length(run))
            outputRead = (outputRead + run) % outputCapacity
            outputCount -= run
            written += run
            remaining -= run
        }
    }

    /// One whole partition of input: transformed, kept on the line, and the
    /// line summed against the response.
    private func processPartition() {
        // Overlap-save: the frame is the previous partition followed by this
        // one, so the second half of the inverse is free of wraparound.
        frame.update(from: previous, count: partition)
        (frame + partition).update(from: pending, count: partition)
        lineHead = (lineHead + 1) % partitionCount
        transformFrame(intoReal: lineReal + lineHead * partition,
                       imag: lineImag + lineHead * partition)
        previous.update(from: pending, count: partition)
        pendingCount = 0

        // The two real bins the packing keeps in slot zero (the constant and
        // the top of the band) multiply as plain numbers; the rest are
        // complex products, accumulated into alternating buffers.
        var constant: Float = 0
        var nyquist: Float = 0
        sumReal.update(repeating: 0, count: partition)
        sumImag.update(repeating: 0, count: partition)
        for index in 0..<partitionCount {
            let slot = (lineHead - index + partitionCount) % partitionCount
            let lineR = lineReal + slot * partition, lineI = lineImag + slot * partition
            let respR = spectraReal + index * partition, respI = spectraImag + index * partition
            constant += lineR[0] * respR[0]
            nyquist += lineI[0] * respI[0]
            var block = DSPSplitComplex(realp: lineR + 1, imagp: lineI + 1)
            var response = DSPSplitComplex(realp: respR + 1, imagp: respI + 1)
            var sum = DSPSplitComplex(realp: sumReal + 1, imagp: sumImag + 1)
            var alt = DSPSplitComplex(realp: altReal + 1, imagp: altImag + 1)
            vDSP_zvma(&block, 1, &response, 1, &sum, 1, &alt, 1, vDSP_Length(partition - 1))
            swap(&sumReal, &altReal)
            swap(&sumImag, &altImag)
        }
        sumReal[0] = constant
        sumImag[0] = nyquist

        var split = DSPSplitComplex(realp: sumReal, imagp: sumImag)
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_INVERSE))
        frame.withMemoryRebound(to: DSPComplex.self, capacity: partition) { interleaved in
            vDSP_ztoc(&split, 1, interleaved, 2, vDSP_Length(partition))
        }

        // The second half of the frame is the partition's output, scaled and
        // pushed onto the ring in one or two runs.
        var scale = self.scale
        var remaining = partition
        var source = partition
        var write = (outputRead + outputCount) % outputCapacity
        while remaining > 0 {
            let run = min(remaining, outputCapacity - write)
            vDSP_vsmul(frame + source, 1, &scale, output + write, 1, vDSP_Length(run))
            write = (write + run) % outputCapacity
            source += run
            remaining -= run
        }
        outputCount += partition
    }

    /// The forward transform of `frame`, packed as vDSP packs a real signal.
    private func transformFrame(intoReal real: UnsafeMutablePointer<Float>,
                                imag: UnsafeMutablePointer<Float>) {
        var split = DSPSplitComplex(realp: real, imagp: imag)
        frame.withMemoryRebound(to: DSPComplex.self, capacity: partition) { interleaved in
            vDSP_ctoz(interleaved, 2, &split, 1, vDSP_Length(partition))
        }
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
    }
}
