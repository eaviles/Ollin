import Foundation
import GameController
import Ollin

/// Samples every attached controller once a frame and works out what changed.
///
/// One hub for the process, because the system's controller list is
/// process-wide. It is polled rather than driven by callbacks, which is worth
/// stating because it is a design choice and not an oversight:
///
/// - A frame is the unit a sketch thinks in. Polling once per frame and
///   differencing gives held state and presses from the same read, with no
///   queue to drain and no ordering to reason about.
/// - Nothing arrives on another thread, so there is no lock and no handoff
///   here at all, unlike the audio and network satellites.
/// - A press lasts a tenth of a second or so, which is several frames. Unlike
///   MIDI, where a machine can send faster than a frame, a hand cannot press
///   and release a button between two frames, so nothing needs an event queue
///   to avoid missing it.
/// - And a synthetic controller can be driven through exactly this path. The
///   system's change handlers do not fire for one, so a design built on
///   handlers could not be tested without hardware plugged in.
@MainActor
final class ControllerHub {

    static let shared = ControllerHub()

    /// Where the list of attached controllers comes from. Tests replace this
    /// with synthetic controllers, which is the only way to exercise the read
    /// path with nothing plugged in: a synthetic controller is a real
    /// `GCController` but never joins the system's own list.
    var source: () -> [GCController] = { GCController.controllers() }

    /// Whether motion sensors have been asked for. They cost battery, so they
    /// stay off until a sketch says otherwise.
    var motionEnabled = false {
        didSet {
            guard motionEnabled != oldValue else { return }
            for slot in slots { applyMotionSetting(to: slot?.controller) }
        }
    }

    /// How much of a stick's travel around center to treat as center. Sticks
    /// rest a little off-zero, and a worn one rests further off, so a small
    /// default keeps a sketch from drifting on its own.
    var deadzone: Double = 0.1

    private struct Slot {
        var controller: GCController
        /// What is down as of the latest sample.
        var down: ControllerButtonMask
        /// What was down at the sample before it. The difference between the
        /// two is this frame's presses and releases.
        var wasDown: ControllerButtonMask
    }

    private var slots: [Slot?] = []
    private var lastFrame: Int = .min
    private var events: [Int: (connected: Bool, disconnected: Bool)] = [:]
    private var notedHeadless = false

    private init() {}

    // MARK: - Reading

    /// The state of one player's controller, sampling first if this frame has
    /// not been sampled yet.
    func controller(player: Int, frame: Int) -> Controller {
        guard player >= 1 else { return .absent(player: player) }

        if OllinApp.isRenderingHeadless {
            noteHeadlessOnce()
            return .absent(
                player: player,
                reason: "a game controller is live input, so an export reads it as centered and unpressed.")
        }

        sampleIfNeeded(frame: frame)

        let index = player - 1
        guard index < slots.count, let slot = slots[index] else {
            let event = events[player]
            return .absent(player: player).withDisconnect(event?.disconnected ?? false)
        }
        return read(slot, player: player)
    }

    /// How many players currently have a controller.
    func connectedCount(frame: Int) -> Int {
        guard !OllinApp.isRenderingHeadless else { return 0 }
        sampleIfNeeded(frame: frame)
        return slots.reduce(0) { $0 + ($1 == nil ? 0 : 1) }
    }

    /// The highest player number ever assigned this run, so a caller can walk
    /// every slot including one that just emptied.
    func slotCount(frame: Int) -> Int {
        guard !OllinApp.isRenderingHeadless else { return 0 }
        sampleIfNeeded(frame: frame)
        return slots.count
    }

    // MARK: - Sampling

    /// Take a reading, unless this frame already has one. Every read goes
    /// through here, so a frame that asks about four controllers still polls
    /// the hardware once, and every answer within a frame agrees.
    func sampleIfNeeded(frame: Int) {
        guard frame != lastFrame else { return }
        lastFrame = frame
        sample()
    }

    private func sample() {
        let attached = source()
        events.removeAll(keepingCapacity: true)

        // Anything that left. Walk slots in order so the answer never depends
        // on a dictionary's iteration order.
        for index in slots.indices {
            guard let slot = slots[index] else { continue }
            if !attached.contains(where: { $0 === slot.controller }) {
                slots[index] = nil
                events[index + 1] = (connected: false, disconnected: true)
            }
        }

        // Anything that arrived takes the lowest free slot, so player 1 stays
        // player 1 when player 2 unplugs.
        for controller in attached where !slots.contains(where: { $0?.controller === controller }) {
            let index = freeSlot()
            slots[index] = Slot(controller: controller, down: .none, wasDown: .none)
            events[index + 1] = (connected: true, disconnected: false)
            if index < 4 { controller.playerIndex = GCControllerPlayerIndex(rawValue: index) ?? .indexUnset }
            applyMotionSetting(to: controller)
        }

        // Carry each slot's button state forward so the next read can tell a
        // press from a hold.
        for index in slots.indices {
            guard let slot = slots[index], let pad = slot.controller.extendedGamepad else { continue }
            slots[index]?.wasDown = slot.down
            slots[index]?.down = currentMask(of: pad)
        }
    }

    private func freeSlot() -> Int {
        if let index = slots.firstIndex(where: { $0 == nil }) { return index }
        slots.append(nil)
        return slots.count - 1
    }

    // MARK: - Turning a profile into a snapshot

    private func read(_ slot: Slot, player: Int) -> Controller {
        let controller = slot.controller
        let event = events[player]
        guard let pad = controller.extendedGamepad else {
            return .absent(player: player).withConnect(event?.connected ?? false)
        }

        // Both masks were written at sample time, so differencing them gives
        // this frame's presses and releases, however many times the sketch
        // asks within the frame.
        let now = slot.down
        let before = slot.wasDown
        let motion = motionEnabled ? controller.motion : nil
        let surface = touchpad(of: controller)

        return Controller(
            player: player,
            isConnected: true,
            didConnect: event?.connected ?? false,
            didDisconnect: false,
            name: controller.vendorName,
            leftStick: stick(pad.leftThumbstick),
            rightStick: stick(pad.rightThumbstick),
            dpad: direction(pad.dpad),
            leftTrigger: trigger(pad.leftTrigger),
            rightTrigger: trigger(pad.rightTrigger),
            hasMotion: motion != nil,
            rotationRate: motion.map {
                Vector3(Double($0.rotationRate.x), Double($0.rotationRate.y), Double($0.rotationRate.z))
            } ?? .zero,
            gravity: motion.map {
                Vector3(Double($0.gravity.x), Double($0.gravity.y), Double($0.gravity.z))
            } ?? .zero,
            acceleration: motion.map {
                Vector3(Double($0.userAcceleration.x), Double($0.userAcceleration.y),
                        Double($0.userAcceleration.z))
            } ?? .zero,
            hasTouchpad: surface != nil,
            touch: surface.map { direction($0.touchSurface) } ?? .zero,
            isTouching: surface.map { $0.touchState != .up } ?? false,
            batteryLevel: controller.battery.map { Double($0.batteryLevel) },
            isCharging: controller.battery?.batteryState == .charging,
            down: now,
            pressed: now.rising(from: before),
            released: now.falling(from: before),
            unavailableReason: nil)
    }

    private func currentMask(of pad: GCExtendedGamepad) -> ControllerButtonMask {
        var mask = ControllerButtonMask()
        for button in ControllerButton.allCases {
            mask[button] = button.input(on: pad)?.isPressed ?? false
        }
        return mask
    }

    // MARK: - Axes

    /// A stick, deadzoned and flipped into canvas terms.
    ///
    /// The deadzone is radial and rescaled rather than a flat cut: a stick
    /// just outside it reads near zero and grows smoothly to 1, where cutting
    /// each axis on its own would make the value jump the moment it escaped
    /// and would square off a circular stick's corners.
    private func stick(_ pad: GCControllerDirectionPad) -> Vector2 {
        let raw = Vector2(Double(pad.xAxis.value), -Double(pad.yAxis.value))
        let magnitude = raw.length
        guard magnitude > deadzone else { return .zero }
        guard deadzone < 1 else { return .zero }
        let scaled = (magnitude - deadzone) / (1 - deadzone)
        return raw * (min(scaled, 1) / magnitude)
    }

    /// A dpad or touch surface, flipped but not deadzoned: these are already
    /// discrete or absolute.
    private func direction(_ pad: GCControllerDirectionPad) -> Vector2 {
        Vector2(Double(pad.xAxis.value), -Double(pad.yAxis.value))
    }

    private func trigger(_ input: GCControllerButtonInput) -> Double {
        let value = Double(input.value)
        guard value > deadzone else { return 0 }
        guard deadzone < 1 else { return 0 }
        return min((value - deadzone) / (1 - deadzone), 1)
    }

    /// The touchpad, where the controller has one.
    ///
    /// Taken from the profile by name rather than off `GCDualShockGamepad`,
    /// which types its touchpad as a plain direction pad and so cannot say
    /// whether a finger is down: a surface reporting (0, 0) is a finger resting
    /// dead center and an untouched pad alike. The named element is the one
    /// that carries `touchState`, which is what tells the two apart.
    private func touchpad(of controller: GCController) -> GCControllerTouchpad? {
        controller.physicalInputProfile.touchpads[GCInputDualShockTouchpadOne]
    }

    // MARK: - Settings

    private func applyMotionSetting(to controller: GCController?) {
        guard let motion = controller?.motion else { return }
        if motion.sensorsRequireManualActivation { motion.sensorsActive = motionEnabled }
    }

    private func noteHeadlessOnce() {
        guard !notedHeadless else { return }
        notedHeadless = true
        FileHandle.standardError.write(Data(
            ("⚠️ OllinController: a game controller is live input, so this export reads it as "
             + "centered and unpressed.\n").utf8))
    }

    // MARK: - Test support

    /// Forget every slot, so a test starts from nothing attached.
    func reset() {
        slots.removeAll()
        events.removeAll()
        lastFrame = .min
        motionEnabled = false
        deadzone = 0.1
        source = { GCController.controllers() }
    }
}

extension Controller {
    func withConnect(_ value: Bool) -> Controller {
        Controller(
            player: player, isConnected: isConnected, didConnect: value,
            didDisconnect: didDisconnect, name: name, leftStick: leftStick,
            rightStick: rightStick, dpad: dpad, leftTrigger: leftTrigger,
            rightTrigger: rightTrigger, hasMotion: hasMotion, rotationRate: rotationRate,
            gravity: gravity, acceleration: acceleration, hasTouchpad: hasTouchpad,
            touch: touch, isTouching: isTouching, batteryLevel: batteryLevel,
            isCharging: isCharging, down: down, pressed: pressed, released: released,
            unavailableReason: unavailableReason)
    }

    func withDisconnect(_ value: Bool) -> Controller {
        Controller(
            player: player, isConnected: isConnected, didConnect: didConnect,
            didDisconnect: value, name: name, leftStick: leftStick,
            rightStick: rightStick, dpad: dpad, leftTrigger: leftTrigger,
            rightTrigger: rightTrigger, hasMotion: hasMotion, rotationRate: rotationRate,
            gravity: gravity, acceleration: acceleration, hasTouchpad: hasTouchpad,
            touch: touch, isTouching: isTouching, batteryLevel: batteryLevel,
            isCharging: isCharging, down: down, pressed: pressed, released: released,
            unavailableReason: unavailableReason)
    }
}
