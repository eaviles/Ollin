#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Input`</sup>

---

## Input

Pointer and keyboard input are plain properties and overridable methods on the sketch.

### Contents

- [mouseX / mouseY](#mouse)
- [mouse / previousMouse](#mousePoint)
- [mouseIsPressed](#mouseIsPressed)
- [mousePressed / mouseReleased](#mousePressed)
- [pressure / pressureIsAvailable](#pressure)
- [key / keyCode / keyIsPressed](#key)
- [keyPressed / keyReleased](#keyPressed)
- [isKeyDown](#isKeyDown)
- [moveAxis](#moveAxis)
- [Keyboard focus in the hosts](#keyboardFocus)

<a name="mouse"></a>

### mouseX / mouseY

```swift
mouseX: Double
mouseY: Double
```

The cursor position in sketch coordinates (points, top-left origin, y-down). When the window opens, both values start from the cursor's actual position. So a mouse-driven sketch responds on the first frame instead of reading (0, 0) until the first move. After that they follow the pointer as it moves over the canvas.

```swift
override func draw() {
    background(.white)
    fill(.black)
    drawCircle(mouseX, mouseY, 24)   // a dot follows the cursor
}
```

Two calls remap the mouse into their own coordinates. One is [`withViewBox`](../Drawing/Drawing.md#viewbox), which does it for the length of its block. The other is [`viewControl`](../Drawing/Drawing.md#viewcontrol), which does it for the rest of the frame. The remap keeps a piece written for the whole canvas working when the view is not the whole canvas. In both cases, `mouseX` and `mouseY` give the position in the content under the pointer, not the position on the screen. The pointer values are restored before the next frame.

<a name="mousePoint"></a>

### mouse / previousMouse

```swift
mouse: Vector2
previousMouse: Vector2
```

`mouse` is the same cursor position as one point. The geometry calls take a point directly, so you can pass it without unpacking it. `previousMouse` is where the cursor was when the previous frame drew.

```swift
drawLine(previousMouse, mouse)          // ink follows the pointer
let speed = (mouse - previousMouse).length
if circle.contains(mouse) { … }
```

`mouse - previousMouse` is this frame's drag, so you do not need to track the motion yourself. On the first frame `previousMouse` equals `mouse`, so the first delta is zero rather than a jump from the corner. `previousMouse` holds the canvas-space position the window reported. The coordinate remaps above apply to `mouse` for their frame, so they never change `previousMouse`.

<a name="mouseIsPressed"></a>

### mouseIsPressed

```swift
mouseIsPressed: Bool
```

Whether a mouse button is currently held over the canvas. It is the polling counterpart to the one-shot hooks below, and it works the same way as `keyIsPressed`. Poll it in `draw()` for anything that should continue while the button is down, such as dragging, painting, or steering. `mouseX`/`mouseY` keep updating through the drag.

```swift
override func draw() {
    if mouseIsPressed {
        drawCircle(mouseX, mouseY, 12)   // paint while the button is down
    }
}
```

<a name="mousePressed"></a>

### mousePressed / mouseReleased

```swift
mousePressed()
mouseReleased()
```

Override these to respond to a click. Each fires once per press or release, and `mouseX`/`mouseY` hold the event's location. Use `mousePressed()` to regenerate an otherwise static sketch on demand. Use `mouseReleased()` to act on a finished drag or stroke. The `DigitReader` example classifies its drawing in `mouseReleased()`.

```swift
override func mousePressed() {
    randomSeed(frameCount)   // re-roll the randomness on each click
}
```

<a name="pressure"></a>

### pressure / pressureIsAvailable

```swift
pressure: Double            // 0...1, 0 when nothing is held
pressureIsAvailable: Bool   // whether this device can measure it at all
```

How hard the pointer is pressed. On a pressure-sensing device (a Force Touch trackpad, a pen tablet) the value varies continuously through a press. On a device that cannot measure pressure the value is `1` while a button is down. A pressure-driven sketch still works there, but only at that single level.

`pressureIsAvailable` tells you which kind of device you have. The answer comes from the event, not from the machine, so it is `false` until the first press. Read it in `mousePressed()` rather than in `setup()`:

```swift
override func mousePressed() {
    brush = pressureIsAvailable ? .pressure(light: 0.1) : .speed(fast: 0.15)
}
```

Ollin asks the trackpad for the drawing gesture, which is a single stage over the full range. A press therefore reads as a smooth amount, and no force-click fires look-up in the middle of a stroke. See [Marks](../Drawing/Marks.md) for the brush that reads pressure.

<a name="key"></a>

### key / keyCode / keyIsPressed

```swift
key: Character?
keyCode: KeyCode?
keyIsPressed: Bool
```

The most recent key event, split into two properties. A key that produces a character arrives as `key`, so a letter, a digit, punctuation, or the space bar reads as `"a"`, `"5"`, or `" "`. A key with no useful character arrives as `keyCode` instead, so you match a named value rather than a magic number. That means an arrow or a function key reads as `.leftArrow`, `.return`, `.escape`, or `.function(1)`. Exactly one of the two is set for a given event, and the other is `nil`. Both are set on press *and* release, so the hooks below can read which key fired.

`keyIsPressed` is `true` whenever any key is held.

```swift
override func draw() {
    background(.white)
    if key == "r" { background(.red) }        // a character key
    if keyCode == .leftArrow { /* … */ }      // a named key
}
```

The named keys are `upArrow` / `downArrow` / `leftArrow` / `rightArrow`, `return`, `enter`, `tab`, `escape`, `delete`, `forwardDelete`, `home` / `end` / `pageUp` / `pageDown`, and `function(_:)`. `return` is the main Return key, and `enter` is the keypad one. `delete` is Backspace, and `F1` is `.function(1)`.

<a name="keyPressed"></a>

### keyPressed / keyReleased

```swift
keyPressed()
keyReleased()
```

Override these to respond to keys. Each fires once per physical press or release, and auto-repeat does not fire `keyPressed()` again. `key`/`keyCode` hold the key that fired. The hooks are for discrete actions, so for a continuous response while a key is *held* (steering, movement), poll `isKeyDown(_:)` in `draw()` instead.

```swift
override func keyPressed() {
    if key == " " { paused.toggle() }       // space toggles
    if keyCode == .escape { reset() }
}
```

<a name="isKeyDown"></a>

### isKeyDown

```swift
isKeyDown(_ character: Character) -> Bool
isKeyDown(_ code: KeyCode) -> Bool
```

Whether a specific key is currently held. It is the polling counterpart to the one-shot `keyPressed()` hook, for movement that should continue while a key is down. Call it from `draw()`.

```swift
override func draw() {
    if isKeyDown(.leftArrow)  || isKeyDown("a") { x -= speed }
    if isKeyDown(.rightArrow) || isKeyDown("d") { x += speed }
}
```

The character form is case-sensitive, so `isKeyDown("w")` and `isKeyDown("W")` differ by whether Shift was down at the press.

<a name="moveAxis"></a>

### moveAxis

```swift
moveAxis: Vector2
```

The held movement keys (WASD and the arrows) as one direction. Each axis is in `-1...1`, in canvas orientation, so up is `(0, -1)` and right is `(1, 0)`. Opposite keys held together cancel to zero.

```swift
position += moveAxis * speed * deltaTime
```

A 3D sketch reads the same value and maps y onto its own forward direction. The usual choice is for canvas up to mean "ahead", so `-moveAxis.y` is the throttle.

<a name="keyboardFocus"></a>

<a name="droppedFiles"></a>

### droppedFiles / filesDropped

```swift
droppedFiles() -> [String]
filesDropped()
```

Files dropped on the window from the Finder. `droppedFiles()` returns the paths dropped since the last call, oldest first, and reading them empties the list. `filesDropped()` is called once at each drop, after the paths have arrived and with `mouseX`/`mouseY` at the drop point, so a sketch can respond there or poll in `draw()`, whichever it prefers. Anything the Finder can hand over arrives: a picture for `loadImage`, a clip, a font, a table. A drop is live input outside a take, neither recorded nor replayed.

```swift
override func filesDropped() {
    for path in droppedFiles() {
        if let picture = loadImage(path) { pictures.append((picture, mouse)) }
    }
}
```

Every host takes the drop wherever the sketch is running: the live window, the gallery, and the performance stage with its code hidden. With the code showing, the editor over the stage takes the drop as text instead.

### Keyboard focus in the hosts

A window that *is* the sketch gives the sketch the keyboard as soon as it opens. That covers a standalone `swift run` and the live host, so everything above works with no click first. The examples gallery is different. Its example list keeps the keyboard, so the arrow keys navigate the examples. In the gallery, a sketch that reads keys shows a small **"Click the sketch to use the keyboard"** prompt over the canvas. Clicking the sketch gives it the keys, and clicking back in the example list returns them.

When you embed `SketchView` in your own SwiftUI app, the `keyboardFocus:` parameter sets the same policy. `.automatic` is the default, and it claims the keys when the view appears. `.onClick` leaves the keys to the rest of the window until the canvas is clicked. `showsKeyboardHint:` shows that same prompt for sketches that want keys:

```swift
SketchView(sketch, keyboardFocus: .onClick, showsKeyboardHint: true)
```
