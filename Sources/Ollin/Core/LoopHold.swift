import Foundation

/// A reason the live frame loop stands still.
///
/// A window's loop is its frame timer asking for a frame on every refresh.
/// Several owners can each want it stopped (the sketch, the timeline's
/// transport, a replay, a schedule, the system, the host), and each lets go
/// on its own time. So the reasons are a set: the loop runs when nothing in
/// the set still stands, and every reason is let go by the owner that took
/// it, never by another one starting the timer again.
///
/// Work that needs a frame while the loop stands still does not start the
/// timer either. It is written down as a frame owed (``LoopPass``), and each
/// kind of owed frame says which reasons it goes through. One function reads
/// both sets and decides (`SketchRunner.applyPause()`), so a reason or a kind
/// of work added here cannot be forgotten at a site.
struct LoopHold: OptionSet, Hashable, Sendable {
    let rawValue: UInt8

    /// The sketch stopped its own loop with `noLoop()`.
    static let still = LoopHold(rawValue: 1 << 0)
    /// The timeline's transport holds the clock.
    static let clock = LoopHold(rawValue: 1 << 1)
    /// A replay is paused, by its transport or at the end of its take.
    static let replay = LoopHold(rawValue: 1 << 2)
    /// The schedule took the piece off screen for the night.
    static let hidden = LoopHold(rawValue: 1 << 3)
    /// The Mac is going to sleep.
    static let asleep = LoopHold(rawValue: 1 << 4)
    /// The host stopped the frames: a screen saver between two runs.
    static let stopped = LoopHold(rawValue: 1 << 5)
    /// The canvas is being put away.
    static let closed = LoopHold(rawValue: 1 << 6)

    /// Every reason there is.
    static let all: LoopHold = [.still, .clock, .replay, .hidden, .asleep, .stopped, .closed]

    /// The reasons under which no frame is drawn even when one is asked for
    /// directly. A tick can already be queued when one of these lands, and a
    /// frame drawn in it would move a clock the transport placed, walk a
    /// paused replay off its frame, spend a night's worth of nothing, or
    /// reach a GPU that is powering down. The sketch's own stillness and a
    /// host's stop are not here: either leaves the frame to whoever asks for
    /// it by hand.
    static let refusingFrames: LoopHold = [.clock, .replay, .hidden, .asleep, .closed]

    /// The reasons left standing once the frames owed have gone through the
    /// ones they go through.
    func standing(owing owed: LoopPass) -> LoopHold {
        subtracting(owed.passesThrough)
    }

    /// Whether the frame timer is stopped: some reason stands that no owed
    /// frame goes through.
    func holdsLoop(owing owed: LoopPass) -> Bool {
        !standing(owing: owed).isEmpty
    }

    /// Whether a frame asked for right now is refused.
    func refusesFrame(owing owed: LoopPass) -> Bool {
        !standing(owing: owed).isDisjoint(with: .refusingFrames)
    }
}

/// Work that is owed a frame while the loop may be standing still.
///
/// Each kind goes through some reasons and no others (``passesThrough``). A
/// frame that was asked for goes through the sketch's own stillness and the
/// timeline's hold, drawn at the held time. Nothing goes through a night off,
/// the Mac's sleep, a host's stop, or a canvas put away: work owed under one
/// of those is late, and has its frame when the reason lets go.
struct LoopPass: OptionSet, Hashable, Sendable {
    let rawValue: UInt8

    /// `setup()` has not run for this run yet: a launch, a fresh reload, a
    /// restart.
    static let setup = LoopPass(rawValue: 1 << 0)
    /// A swap put a fresh instance in, and it has not heard so yet.
    static let reload = LoopPass(rawValue: 1 << 1)
    /// `setup()` is to run again in place, because an asset changed.
    static let setupRerun = LoopPass(rawValue: 1 << 2)
    /// A camera view was asked for from the host's menu.
    static let cameraSnap = LoopPass(rawValue: 1 << 3)
    /// A still sketch was woken for camera work or a carried swap, and its
    /// picture has not come to rest.
    static let settling = LoopPass(rawValue: 1 << 4)
    /// One frame was asked for: `redraw()`, a shader saved, a frame the work
    /// above did not get drawn.
    static let oneFrame = LoopPass(rawValue: 1 << 5)
    /// The timeline's transport placed or stepped the clock.
    static let clockPass = LoopPass(rawValue: 1 << 6)
    /// A replay's transport jumped.
    static let scrub = LoopPass(rawValue: 1 << 7)

    /// Every kind there is.
    static let all: LoopPass = [.setup, .reload, .setupRerun, .cameraSnap, .settling,
                                .oneFrame, .clockPass, .scrub]

    /// The kinds that are one deliberate frame, each drawn at the held time
    /// under the timeline's hold.
    static let askedFor: LoopPass = [.setup, .reload, .setupRerun, .cameraSnap, .oneFrame, .clockPass]

    /// The reasons these owed frames go through.
    var passesThrough: LoopHold {
        var through: LoopHold = []
        if !isDisjoint(with: .askedFor) { through.formUnion([.still, .clock]) }
        // Settling is motion, and under the timeline's hold time stands
        // still, so it waits for the clock rather than going through it.
        if contains(.settling) { through.insert(.still) }
        // A jump lands on its frame whatever the transport's own pause says.
        if contains(.scrub) { through.formUnion([.still, .replay]) }
        return through
    }
}
