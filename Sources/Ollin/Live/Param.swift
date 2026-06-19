import Foundation
import os

/// How a `@Param` eases into a new value instead of snapping to it. Pass one to a
/// parameter to soften *every* source that drives the knob — a MIDI fader, an OSC
/// address, or a drag of the inspector slider all glide rather than jump.
///
/// ```swift
/// @Param(20...400, smoothing: .eased(0.3)) var radius = 120   // 0.3s glide
/// @Param(0...1, smoothing: .smoothed) var mix = 0.5           // adaptive 1€ filter
/// @Param(0...127) var snappy = 64                             // immediate (default)
/// ```
///
/// `.eased` glides to the target over a fixed time along an `Easing` curve —
/// crisp and predictable. `.smoothed` runs the value through a `OneEuroFilter`,
/// which stays steady while the knob is still and opens up as it moves — the
/// better feel for a hand on live hardware.
public enum ParamSmoothing: Sendable {
    /// Glide to each new value over `duration` seconds, shaped by `curve`.
    case eased(duration: Double, curve: Easing)
    /// Denoise the value with a 1€ filter (Casiez, Roussel & Vogel): `minCutoff`
    /// sets the resting smoothness, `beta` how quickly it opens up as the value
    /// moves.
    case smoothed(minCutoff: Double, beta: Double)

    /// `.eased(0.3)` — a glide of `duration` seconds with a gentle ease-out.
    public static func eased(_ duration: Double, curve: Easing = .easeOut) -> ParamSmoothing {
        .eased(duration: duration, curve: curve)
    }

    /// The 1€ filter at its gentle defaults — a good start for a live knob.
    public static var smoothed: ParamSmoothing { .smoothed(minCutoff: 1, beta: 0.007) }
}

/// A tunable parameter the live host surfaces as a slider. Declare it on a
/// sketch and read it like a normal property; the live host discovers it, shows
/// a slider, and persists its value across reloads.
///
/// ```swift
/// final class Pulse: Sketch {
///     @Param(0...200) var radius = 120.0          // label "Radius", from the name
///     @Param("Speed", 0.1...4) var rate = 1.0     // explicit label
///     override func draw() {
///         drawCircle(width / 2, height / 2, radius + sin(time * rate) * 40)
///     }
/// }
/// ```
///
/// The value is always clamped to its range. Pass a label to override the one
/// derived from the property name.
///
/// The value is safe to read and write from any thread: the live inspector
/// drives it from the main thread, and an external control source (a hardware
/// fader, a networked message) may drive the same knob from its own thread, so
/// the storage is guarded by a lock and the type is `Sendable`.
@propertyWrapper
public final class Param: @unchecked Sendable, FrameAdvancing {
    /// The value plus its glide state, kept together behind one lock.
    private struct Storage: Sendable {
        var current: Double                  // the (possibly gliding) value reads return
        var target: Double                   // what `current` is easing toward
        var easeStart: Double                // `current` when the target was last set (`.eased`)
        var easeElapsed: Double              // seconds into the current `.eased` glide
        var filter: OneEuroFilter<Double>?   // `.smoothed` state, nil otherwise
    }
    private let storage: OSAllocatedUnfairLock<Storage>

    /// The allowed range; the value is clamped to it.
    public let range: ClosedRange<Double>
    /// An explicit display label, or `nil` to derive one from the property name.
    public let label: String?
    /// How the value eases into changes, or `nil` for an immediate snap.
    public let smoothing: ParamSmoothing?

    /// The current value (the gliding one when smoothed); assigning sets a new
    /// target the value eases toward (or snaps to, with no smoothing).
    public var wrappedValue: Double {
        get { storage.withLock { clamp($0.current) } }
        set { retarget(newValue) }
    }

    /// The parameter itself, via `$radius` — handy for passing it around.
    public var projectedValue: Param { self }

    public init(wrappedValue: Double, _ range: ClosedRange<Double>, smoothing: ParamSmoothing? = nil) {
        self.range = range
        self.label = nil
        self.smoothing = smoothing
        self.storage = OSAllocatedUnfairLock(initialState: Param.makeStorage(wrappedValue, range, smoothing))
    }

    public init(wrappedValue: Double, _ label: String, _ range: ClosedRange<Double>, smoothing: ParamSmoothing? = nil) {
        self.range = range
        self.label = label
        self.smoothing = smoothing
        self.storage = OSAllocatedUnfairLock(initialState: Param.makeStorage(wrappedValue, range, smoothing))
    }

    /// Jump straight to `value` with no glide (both the value and the target), and
    /// reseat any filter so it continues from there. Used for direct restores —
    /// the live host re-applying a tuned value across a reload — where animating
    /// in from the default would be wrong.
    public func set(_ value: Double) {
        let v = clamp(value)
        storage.withLock { state in
            state.current = v
            state.target = v
            state.easeStart = v
            state.easeElapsed = .greatestFiniteMagnitude   // at rest
            state.filter?.reset(to: v)
        }
    }

    /// Set a new target. With no smoothing the value snaps; otherwise it begins
    /// gliding from wherever it is now. Assigning the value it's already heading
    /// for is a no-op, so it's safe to drive every frame (a knob repeating its
    /// last position won't restart the glide).
    private func retarget(_ value: Double) {
        let v = clamp(value)
        storage.withLock { state in
            guard v != state.target else { return }
            state.target = v
            if smoothing == nil {
                state.current = v
            } else {
                state.easeStart = state.current
                state.easeElapsed = 0
            }
        }
    }

    /// Step the glide one frame. A no-op for un-smoothed params. Called by the
    /// sketch each frame, the same pass that advances `@Eased` / `@Smoothed`.
    func advance(by dt: Double) {
        guard let smoothing else { return }
        storage.withLock { state in
            switch smoothing {
            case .eased(let duration, let curve):
                guard duration > 0, state.easeElapsed < duration else {
                    state.current = state.target
                    return
                }
                state.easeElapsed += dt
                let t = Swift.min(state.easeElapsed / duration, 1)
                state.current = state.easeStart + (state.target - state.easeStart) * curve(t)
            case .smoothed:
                if var filter = state.filter {
                    state.current = filter.filter(state.target, dt: dt)
                    state.filter = filter
                }
            }
        }
    }

    private func clamp(_ value: Double) -> Double {
        Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
    }

    private static func makeStorage(_ wrappedValue: Double, _ range: ClosedRange<Double>,
                                    _ smoothing: ParamSmoothing?) -> Storage {
        let v = Swift.min(Swift.max(wrappedValue, range.lowerBound), range.upperBound)
        var filter: OneEuroFilter<Double>?
        if case .smoothed(let minCutoff, let beta) = smoothing {
            var f = OneEuroFilter<Double>(minCutoff: minCutoff, beta: beta)
            f.reset(to: v)
            filter = f
        }
        return Storage(current: v, target: v, easeStart: v,
                       easeElapsed: .greatestFiniteMagnitude, filter: filter)
    }
}

/// A discovered `@Param` on a sketch: its persistence key (the property name),
/// the parameter itself (read/write the value, read the range), and a display
/// label. The live host builds one slider per handle.
public struct ParamHandle: Identifiable {
    /// The property name — a stable key for persisting the value across reloads.
    public let name: String
    public let param: Param
    public var id: String { name }
    public var label: String { param.label ?? ParamHandle.humanize(name) }

    /// "radius" -> "Radius", "noiseScale" -> "Noise Scale".
    static func humanize(_ name: String) -> String {
        var words: [String] = []
        var current = ""
        for character in name {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

public extension Sketch {
    /// The `@Param` parameters declared on this sketch, discovered via reflection
    /// (walking the class hierarchy). The live host uses this to build sliders;
    /// most sketches never call it directly.
    func parameters() -> [ParamHandle] {
        var handles: [ParamHandle] = []
        var mirror: Mirror? = Mirror(reflecting: self)
        while let current = mirror {
            for child in current.children {
                guard let param = child.value as? Param, let storageName = child.label else { continue }
                // Property-wrapper storage is named `_radius`; strip the underscore.
                let name = storageName.hasPrefix("_") ? String(storageName.dropFirst()) : storageName
                handles.append(ParamHandle(name: name, param: param))
            }
            mirror = current.superclassMirror
        }
        return handles
    }
}
