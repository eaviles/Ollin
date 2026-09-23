import Foundation

/// What a tracker throws, in one vocabulary for the whole module.
///
/// A tracker that runs a model of its own throws `unavailable` from a call
/// made while the model will not load or run here, the same sentence its
/// `unavailableReason` holds, since a call in hand can throw where a frame
/// drawn without one can only read. `failed` is a run that went through and
/// could not produce its result: a matte the system would not convert, an
/// encoder that answered nothing.
public enum VisionError: Error, CustomStringConvertible {
    /// The model isn't usable here: the file is missing, will not load, or
    /// cannot run on this machine. The text is the tracker's `unavailableReason`.
    case unavailable(String)
    /// A run could not produce its result; the text says which step.
    case failed(String)

    public var description: String {
        switch self {
        case .unavailable(let reason): return reason
        case .failed(let reason): return reason
        }
    }
}
