import Foundation

/// A resonant state-variable filter, solved by trapezoidal integration.
///
/// The plain way to write a digital filter samples the circuit's behaviour and
/// then folds the answer, which pulls the cutoff away from where it was asked
/// for as it climbs and makes resonance misbehave near the top. Integrating the
/// circuit equations instead keeps the cutoff where it was asked for across the
/// whole range and stays stable while the cutoff is swept, which is the whole
/// point here: a filter that only sounds right standing still is no use to a
/// note that opens as it is struck.
///
/// All four responses fall out of the same two state variables, so a mode
/// change costs nothing.
struct StateVariableFilter {
    /// The integrator states, carried between samples.
    private var ic1eq: Double = 0
    private var ic2eq: Double = 0

    /// Coefficients, recomputed whenever cutoff or resonance moves.
    private var g: Double = 0
    private var k: Double = 2
    private var a1: Double = 0
    private var a2: Double = 0
    private var a3: Double = 0

    /// Clears the states. Called when a voice takes a new note so the tail of
    /// the previous one cannot ring into it.
    mutating func reset() {
        ic1eq = 0
        ic2eq = 0
    }

    /// Sets the cutoff in Hz and the resonance `0...1`.
    ///
    /// Cheap enough to call every sample, which is what a filter envelope does.
    mutating func setCoefficients(cutoff: Double, resonance: Double, sampleRate: Double) {
        // Above this the warping runs away, and below it there is nothing to hear.
        let fc = min(max(cutoff, 10), sampleRate * 0.45)
        // Full resonance would leave the filter ringing on its own forever.
        let res = min(max(resonance, 0), 0.98)
        g = tan(.pi * fc / sampleRate)
        k = 2 - 2 * res
        a1 = 1 / (1 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
    }

    /// Runs one sample through, returning the requested response.
    @inline(__always)
    mutating func next(_ v0: Double, mode: Voice.Filter.Mode) -> Double {
        let v3 = v0 - ic2eq
        let v1 = a1 * ic1eq + a2 * v3
        let v2 = ic2eq + a2 * ic1eq + a3 * v3
        ic1eq = 2 * v1 - ic1eq
        ic2eq = 2 * v2 - ic2eq

        switch mode {
        case .lowpass:  return v2
        case .bandpass: return v1
        case .highpass: return v0 - k * v1 - v2
        case .notch:    return v0 - k * v1
        }
    }
}
