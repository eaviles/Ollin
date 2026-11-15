import Testing

/// The suites of this target that work the media engine and hold the main
/// actor while they do, run one test at a time.
///
/// They cannot share a moment. The phone-screen suite drives a sender that
/// closes when it is not asked for a frame for two seconds, which is the
/// product's own rule, and a recording test renders and encodes on the main
/// actor for longer than that without a pause. Interleaved, the first times
/// out for a reason that is neither suite's fault. A serialized parent is the
/// one way two suites take turns, so both live inside this one.
///
/// `Scripts/test.sh` runs it in the device phase, by this name.
@Suite(.serialized) struct PhoneMediaTests {}
