# Game controllers

`import OllinController` to read a game controller in `draw()`: two sticks, two
triggers, the buttons, and, on hardware that has them, motion and a touchpad.

```swift
import Ollin
import OllinController

@main
final class Sketch1: Sketch {
    var ship = Vector2(540, 540)

    override func draw() {
        background(.white)
        ship += controller.leftStick * 6
        if controller.wasPressed(.a) { fire(from: ship) }
        drawCircle(center: ship, radius: 30)
    }
}
```

A controller is a satellite rather than part of the core, the way the mouse and
keyboard are. Those arrive as events through the sketch's view and need the
AppKit and UIKit plumbing behind it; a controller is handed to the process by a
system service and touches no view at all, so it needs none of that, and the
drawing core stays free of one more framework.

## Reading it

`controller` is player one, taken fresh each frame. It is a snapshot rather than
a live object, the way `mouseX` is a number rather than something that keeps
changing under you, so read it inside `draw()`.

<img src="../../Guide/Images/28-SoundAndControl/ReadingAPad.jpg" alt="A schematic game controller with the left stick held up and to the right, the right trigger half pulled, and the bottom face button lit, beside a list of five reads and the value each returns for that pose" width="820">

| Read | What it is |
| --- | --- |
| `leftStick`, `rightStick` | `Vector2`, centered at zero, reaching 1 |
| `dpad` | `Vector2`, each axis −1, 0 or 1 |
| `leftTrigger`, `rightTrigger` | `Double` from 0 to 1 |
| `isDown(_:)` | whether a button is held right now |
| `wasPressed(_:)`, `wasReleased(_:)` | whether it changed this frame |
| `anyButtonIsDown`, `anyButtonWasPressed` | for a "press anything to start" |
| `isConnected`, `didConnect`, `didDisconnect` | whether one is there, and whether that just changed |
| `name` | what the controller calls itself |
| `batteryLevel`, `isCharging` | charge from 0 to 1, or `nil` where the pad does not say |

Three questions, three shapes of answer, picked per question rather than made
uniform. A stick is a **level**, so it is a number you read. A button press is an
**event**, so it fires on exactly one frame however long the button is held. A
controller arriving or leaving is a **third thing**, so it is both: `isConnected`
is the state and `didConnect` is the moment.

There is no queue to drain, unlike MIDI. A press lasts something like a tenth of
a second, which is several frames, so a hand cannot press and release a button
between two of them; a machine sending MIDI can, which is why that tier has a
drain and this one does not.

## Nothing plugged in

A controller that is not there still answers: sticks read centered, triggers
read 0, no button is down, and `isConnected` is `false`. A sketch runs either
way and does nothing in particular, rather than needing a check at every call
site. Ask `isConnected` when it matters, which is usually to tell someone to
plug one in.

An empty slot names no `unavailableReason`, because no controller attached is
not a fault. Something genuinely wrong does name one: see [exports](#exports).

## Which way is up

The sticks read in canvas terms. Pushing up gives a **negative** y, because
Ollin's y grows downward from the top left, so this moves up the screen with no
sign to remember:

```swift
position += controller.leftStick * speed
```

The system's own convention is the other way round. It is flipped once, on the
way in, so it never has to be flipped in a sketch. The same goes for the dpad
and the touchpad.

## Buttons

Buttons are named by **where they sit**, not by what is printed on them. A
PlayStation pad prints cross, circle, square and triangle where an Xbox pad
prints A, B, X and Y, and the system reports them by position, so `.a` is always
the bottom face button and a sketch written for one controller works on the
other.

In the diamond, `.y` (triangle) is the top face button, `.x` (square) the
left, `.b` (circle) the right, and `.a` (cross) the bottom.

The rest: `.leftShoulder`, `.rightShoulder`, `.leftTrigger`, `.rightTrigger`,
`.leftStick` and `.rightStick` (clicking a stick in), `.up`, `.down`, `.left`,
`.right` on the dpad, `.menu`, `.options`, `.home`, and `.touchpad`.

Not every controller has every button. One a controller lacks simply never reads
as down.

## The deadzone

A stick rarely rests at exactly zero, and a worn one rests further off, so a
sketch that adds the stick to a position every frame drifts on its own with no
deadzone at all. The default is `0.1`:

```swift
controllerDeadzone(0.15)   // more, for a well-used controller
controllerDeadzone(0)      // none, reading the hardware untouched
```

The cut is radial and rescaled rather than flat: a stick just past the edge
reads near zero and grows smoothly to a full 1 pushed all the way. Cutting each
axis on its own would make the value jump the moment it escaped, and would bend
a diagonal hold toward the diagonal.

## Motion

Some controllers report how they are being moved. PlayStation and Switch
controllers do; **Xbox controllers have no motion sensors at all** and never
will, whatever this is set to.

The sensors cost battery, so they stay off until a sketch asks:

```swift
override func setup() { controllerMotion(true) }

override func draw() {
    guard controller.hasMotion else { return drawStatus("this controller has no motion sensors") }
    rotate(controller.gravity.x * 0.5)
    drawRect(center: center, width: 400, height: 40)
}
```

| Read | What it is |
| --- | --- |
| `hasMotion` | whether this pad reports motion, and has been asked to |
| `rotationRate` | how fast it is turning, radians per second about each axis |
| `gravity` | which way is down as the controller sees it, so how it is being held |
| `acceleration` | how hard it is being moved, gravity taken out, in g |

`hasMotion` is false both when the hardware has no sensors and when nothing has
asked for them, so check it rather than assuming.

Attitude, the controller's absolute orientation, is not surfaced yet: there is
no public quaternion type to hand it back in. `gravity` covers the common case
of "which way is this being held".

## The touchpad

PlayStation controllers have one. `hasTouchpad` says so, `touch` is where the
finger is with each axis from −1 to 1, and `isTouching` says whether a finger is
on it at all. Check `isTouching` before reading `touch`, which holds its last
position otherwise.

```swift
if controller.hasTouchpad && controller.isTouching {
    drawCircle(center: center + controller.touch * 200, radius: 20)
}
```

`.touchpad` is the button, for pads where the surface also clicks.

## Several controllers

```swift
for player in 1...4 {
    let pad = controller(player)
    guard pad.isConnected else { continue }
    draw(paddle: player, at: pad.leftStick)
}
```

`connectedControllers` is every attached pad, player one first, and
`controllerCount` is how many.

A controller keeps its number for as long as it stays connected, and a new one
takes the lowest free number. So unplugging player two does not turn player
three into player two, and the next controller to arrive becomes the new player
two. On the first four, the number is also written to the controller itself,
which is what lights the player indicator on hardware that has one.

## Running behind another window

Off by default, which is the system's own default: a controller feeds whichever
app is frontmost, so a sketch behind another window reads centered and
unpressed.

```swift
controllersRunInBackground(true)
```

Worth turning on for an installation, or for a set where the sketch is projected
while a different window is being typed into.

## Pairing

A controller already paired with this Mac connects on its own. One that has
never been paired is a System Settings job, or:

```swift
discoverControllers()   // puts the system into pairing mode
```

## Permission

None. A controller needs no consent prompt and no entitlement, and a plain
`swift run` binary reads one with nothing configured. This was probed rather
than assumed: unlike the screen, which needs recording permission, nothing here
is gated.

## Exports

A controller is live input, so `--export` and the rest read it as centered and
unpressed rather than baking in whatever a hand happened to be doing when the
render started. It says so, once, on stderr, and `unavailableReason` carries the
same sentence for a sketch that wants to draw it:

```swift
if let reason = controller.unavailableReason { drawStatus(reason, style: .info) }
```

## What is not here

- **Rumble and haptics.** Controller vibration is an *output*, and belongs with
  the rest of the haptics work rather than bolted to the input side.
- **Adaptive triggers.** The DualSense's resistive triggers are an output too,
  for the same reason.
- **The light bar.** Same.
- **Apple Pencil.** Tilt, azimuth and force arrive with the iOS leg, where a
  Pencil exists; its force will join the `pressure` a sketch already reads
  rather than becoming a second thing.
- **Racing wheels and spatial accessories.** The system describes these, and
  nothing here reads them yet.

## See also

- [Input](../Helpers/Input.md) for the mouse, the keyboard, and trackpad pressure
- [MIDI](MIDI.md) for knobs and faders, which is the other shape of hardware control
- [Parameters](../Helpers/Parameters.md) for `@Param` parameters, which MIDI and OSC can drive
- The `Integration/ControllerInput` example
