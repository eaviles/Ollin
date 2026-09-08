import AVFoundation
import os

// MARK: - The samples in hand

/// One stretch of sound, handed to an effect you wrote to change in place.
///
/// The samples run `-1...1` and are yours to rewrite. `left` and `right` are
/// the two channels of a stereo sound; on a mono one they are the same
/// channel, so code written against both is right either way.
///
/// ```swift
/// synth.effects = [
///     .custom("half") { sound in
///         for i in 0..<sound.frameCount {
///             sound.left[i] *= 0.5
///             sound.right[i] *= 0.5
///         }
///     },
/// ]
/// ```
///
/// This lands on the audio thread, many hundreds of times a second, with the
/// speakers waiting on it. Keep it to arithmetic over the samples: nothing
/// allocated, nothing locked, nothing reached back into the sketch.
public struct AudioBlock {
    /// Samples per second. What a frequency or a delay in seconds is measured
    /// against.
    public let sampleRate: Double
    /// How many samples each channel holds this time. Not a constant: the last
    /// block before a deadline can be short.
    public let frameCount: Int
    /// How many channels there are, usually two.
    public let channelCount: Int
    /// Seconds since this effect started running, at the first sample. What a
    /// slow wobble reads instead of keeping its own count.
    public let time: Double

    private let list: UnsafeMutableAudioBufferListPointer

    init(list: UnsafeMutableAudioBufferListPointer, frameCount: Int,
         sampleRate: Double, time: Double) {
        self.list = list
        self.frameCount = frameCount
        self.channelCount = list.count
        self.sampleRate = sampleRate
        self.time = time
    }

    /// One channel's samples, to read and rewrite.
    public subscript(channel: Int) -> UnsafeMutableBufferPointer<Float> {
        precondition(channel >= 0 && channel < channelCount, "no channel \(channel)")
        guard let data = list[channel].mData else {
            return UnsafeMutableBufferPointer(start: nil, count: 0)
        }
        return UnsafeMutableBufferPointer(
            start: data.assumingMemoryBound(to: Float.self), count: frameCount
        )
    }

    /// The first channel.
    public var left: UnsafeMutableBufferPointer<Float> { self[0] }

    /// The second channel, or the first again when there is only one.
    public var right: UnsafeMutableBufferPointer<Float> { self[min(1, channelCount - 1)] }
}

// MARK: - An effect of your own

/// An effect you wrote yourself, as a link in the chain.
///
/// The four built-in kinds cover the classics; this is the seam for everything
/// they do not. The closure is handed each ``AudioBlock`` on its way to the
/// speakers and rewrites the samples in place. It sits anywhere in
/// ``Synth/effects``, before or after the built-ins, and reaches an export the
/// same way they do.
///
/// ```swift
/// synth.effects = [
///     .custom("fold") { sound in
///         for i in 0..<sound.frameCount {
///             sound.left[i] = sin(sound.left[i] * 3)
///             sound.right[i] = sin(sound.right[i] * 3)
///         }
///     },
///     .reverb(Reverb(.hall, mix: 0.3)),
/// ]
/// ```
///
/// An effect that has to remember something between blocks, a filter or an
/// echo of its own, takes that memory as `state:` and gets it back `inout`
/// every time. The closure itself must be `@Sendable` because the audio thread
/// calls it, which is why captured variables are not the way to remember
/// things here.
///
/// The effect is a value, but the work inside is not written down: putting the
/// same value in two places shares one memory, and a copy that went through
/// `Codable` comes back as a passthrough that still knows its name.
public struct CustomEffect: Sendable {
    /// What to call it, in an inspector or a note.
    public var name: String

    let runner: CustomEffectRunner

    /// An effect that needs nothing but the samples in front of it.
    public init(_ name: String = "effect",
                _ process: @escaping @Sendable (AudioBlock) -> Void) {
        self.name = name
        self.runner = CustomEffectRunner(process)
    }

    /// An effect that remembers something between blocks.
    ///
    /// `state` is whatever the effect needs to carry: a running value, an
    /// array standing in for a delay line. It comes back `inout` on every
    /// block, changed however the last block left it.
    ///
    /// ```swift
    /// // A one-pole lowpass: each sample pulled toward the last.
    /// .custom("soften", state: (last: Float(0), lastR: Float(0))) { sound, held in
    ///     for i in 0..<sound.frameCount {
    ///         held.last += (sound.left[i] - held.last) * 0.08
    ///         held.lastR += (sound.right[i] - held.lastR) * 0.08
    ///         sound.left[i] = held.last
    ///         sound.right[i] = held.lastR
    ///     }
    /// }
    /// ```
    public init<State: Sendable>(
        _ name: String = "effect", state: State,
        _ process: @escaping @Sendable (AudioBlock, inout State) -> Void
    ) {
        self.name = name
        var held = state
        self.runner = CustomEffectRunner { block in process(block, &held) }
    }
}

extension CustomEffect: Hashable {
    /// The work is a closure, which cannot be compared, so an effect equals
    /// itself and its copies: the ones sharing the same runner.
    public static func == (lhs: CustomEffect, rhs: CustomEffect) -> Bool {
        lhs.name == rhs.name && lhs.runner === rhs.runner
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(ObjectIdentifier(runner))
    }
}

extension CustomEffect: Codable {
    /// Only the name can be written down. A decoded effect passes sound
    /// through untouched, so a chain read back from disk still has its shape
    /// and its labels, just not the work.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.name = try container.decode(String.self)
        self.runner = CustomEffectRunner { _ in }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}

/// Holds the closure across the seam to the audio thread.
///
/// The lock is the handoff: the sketch swaps the work in from the main thread,
/// the render thread runs it. Running inside the lock rather than copying the
/// closure out keeps reference counting off the audio thread, and makes one
/// runner placed twice in a chain touch its state one block at a time.
final class CustomEffectRunner: @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<(AudioBlock) -> Void>

    init(_ process: @escaping (AudioBlock) -> Void) {
        lock = OSAllocatedUnfairLock(uncheckedState: process)
    }

    func run(_ block: AudioBlock) {
        lock.withLockUnchecked { process in process(block) }
    }
}

// MARK: - The unit that carries it

/// The engine node a custom effect rides in.
///
/// The chain is engine wiring, so an effect of our own has to be a real node:
/// an in-process audio unit registered once and instantiated like the built-in
/// kinds. One unit serves every custom effect the way one delay unit serves
/// every `Delay`: the closure is a setting, applied and replaced without
/// rewiring, which is what lets a sketch swap the work while the sound runs.
final class ClosureAudioUnit: AUAudioUnit {

    /// Which runner's work this unit is doing right now. A holder rather than
    /// a property so the render block can reach it without touching `self`.
    final class Slot: @unchecked Sendable {
        private let lock: OSAllocatedUnfairLock<CustomEffectRunner>
        init(_ runner: CustomEffectRunner) { lock = OSAllocatedUnfairLock(initialState: runner) }
        func set(_ runner: CustomEffectRunner) { lock.withLock { $0 = runner } }
        func run(_ block: AudioBlock) {
            // Reading the reference is the brief part; the work itself runs
            // outside so a long effect never holds a swap out.
            lock.withLock { $0 }.run(block)
        }
    }

    /// What the render block owns: filled in when resources are allocated,
    /// reached at render time through the holder rather than through `self`.
    private final class RenderState: @unchecked Sendable {
        var pullBuffer: AVAudioPCMBuffer?
        var sampleRate: Double = 44100
        var renderedFrames = 0
    }

    let slot = Slot(CustomEffectRunner { _ in })
    private let renderState = RenderState()

    /// The room a convolution reverb prepared for this unit, kept so a change
    /// of `mix` rides the standing engine rather than replacing it, and a
    /// tail still sounding is not cut. Main-thread state, like the settings
    /// on the built-in units.
    var room: ConvolutionReverb?

    /// Puts a reverb's room onto this unit: the standing engine when it is
    /// the same room at the same rate, a new one otherwise.
    func setRoom(_ reverb: Reverb, impulse: ImpulseResponse, sampleRate: Double) {
        if let room, room.serves(reverb, at: sampleRate) {
            room.mix = reverb.mix
            return
        }
        let made = ConvolutionReverb(reverb, impulse: impulse, sampleRate: sampleRate)
        room = made
        slot.set(CustomEffectRunner { block in made.process(block) })
    }
    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var inputBusArray: AUAudioUnitBusArray!
    private var outputBusArray: AUAudioUnitBusArray!

    override init(componentDescription: AudioComponentDescription,
                  options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)
        // A placeholder format; the engine sets the real one when it connects.
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }

    override var inputBusses: AUAudioUnitBusArray { inputBusArray }
    override var outputBusses: AUAudioUnitBusArray { outputBusArray }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        renderState.pullBuffer = AVAudioPCMBuffer(
            pcmFormat: inputBus.format, frameCapacity: maximumFramesToRender
        )
        renderState.sampleRate = inputBus.format.sampleRate
        renderState.renderedFrames = 0
    }

    override func deallocateRenderResources() {
        renderState.pullBuffer = nil
        super.deallocateRenderResources()
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        // Captured here, dereferenced at render time: the buffer does not
        // exist until resources are allocated, which can be after the engine
        // has already taken this block.
        let slot = self.slot
        let state = self.renderState
        return { _, timestamp, frameCount, _, outputData, _, pullInputBlock in
            guard let buffer = state.pullBuffer, let pull = pullInputBlock else {
                return kAudioUnitErr_NoConnection
            }
            guard frameCount <= buffer.frameCapacity else {
                return kAudioUnitErr_TooManyFramesToProcess
            }

            // Pull the upstream sound into our own buffer. The list is taken
            // once and that same pointer is sized and handed over: each access
            // to the property re-declares the sizes from the frame length,
            // which is zero here, and a pull into a zero-sized list is
            // refused.
            let abl = buffer.mutableAudioBufferList
            let list = UnsafeMutableAudioBufferListPointer(abl)
            let byteSize = frameCount * UInt32(MemoryLayout<Float>.size)
            for index in 0..<list.count { list[index].mDataByteSize = byteSize }

            var pullFlags = AudioUnitRenderActionFlags()
            let pulled = pull(&pullFlags, timestamp, frameCount, 0, abl)
            guard pulled == noErr else { return pulled }

            let block = AudioBlock(
                list: list, frameCount: Int(frameCount),
                sampleRate: state.sampleRate,
                time: Double(state.renderedFrames) / state.sampleRate
            )
            slot.run(block)
            state.renderedFrames += Int(frameCount)

            // Hand the result out: the host either lends us its buffers to
            // fill or asks us to point at our own.
            let out = UnsafeMutableAudioBufferListPointer(outputData)
            for index in 0..<min(list.count, out.count) {
                if out[index].mData == nil {
                    out[index].mData = list[index].mData
                } else if let source = list[index].mData, let target = out[index].mData {
                    target.copyMemory(from: source, byteCount: Int(byteSize))
                }
                out[index].mDataByteSize = byteSize
            }
            return noErr
        }
    }

    // MARK: Making one

    /// The identity this unit is registered under, once per process.
    private static let componentDescription: AudioComponentDescription = {
        func code(_ text: String) -> OSType {
            var value: OSType = 0
            for byte in text.utf8 { value = (value << 8) | OSType(byte) }
            return value
        }
        return AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: code("olfx"),
            componentManufacturer: code("Olin"),
            componentFlags: 0, componentFlagsMask: 0
        )
    }()

    private static let registered: Void = {
        AUAudioUnit.registerSubclass(
            ClosureAudioUnit.self, as: componentDescription,
            name: "Ollin: Effect", version: 1
        )
    }()

    /// A unit ready to be wired, like `AVAudioUnitDelay()` for the built-ins.
    ///
    /// Instantiating an in-process unit completes inline, but nothing promises
    /// that, so the wait has a way out: if the unit cannot be made, the chain
    /// gets a link that passes sound through untouched, and says so.
    /// Carries the unit back from the callback that made it.
    ///
    /// `AVAudioUnit` is only declared `Sendable` by the newer SDKs, and the
    /// state an `OSAllocatedUnfairLock` holds has to be, so on an older one the
    /// lock will not accept it and this file stops building. A lock of its own
    /// does the same work, and the box is what takes responsibility for it.
    private final class InstantiatedUnit: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: AVAudioUnit?
        var unit: AVAudioUnit? {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); defer { lock.unlock() }; stored = newValue }
        }
    }

    static func makeUnit() -> AVAudioUnit {
        _ = registered
        let made = InstantiatedUnit()
        let done = DispatchSemaphore(value: 0)
        // A unit is asked to load in this process, which is the only way it can
        // load on a phone or a tablet, and there the option is not offered.
        #if os(macOS)
        let options: AudioComponentInstantiationOptions = .loadInProcess
        #else
        let options: AudioComponentInstantiationOptions = []
        #endif
        AVAudioUnit.instantiate(with: componentDescription, options: options) { unit, _ in
            made.unit = unit
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
        if let unit = made.unit { return unit }
        audioNoteOnce("a custom effect could not be created; that link in the chain passes sound through.")
        let passthrough = AVAudioUnitDelay()
        passthrough.wetDryMix = 0
        return passthrough
    }
}
