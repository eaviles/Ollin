#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Input`</sup>

---

## Input

Pointer and keyboard input live on the sketch as plain properties and overridable methods.

### Contents

- [mouseX / mouseY](#mouse)
- [mouseIsPressed](#mouseIsPressed)
- [mousePressed / mouseReleased](#mousePressed)
- [pressure / pressureIsAvailable](#pressure)
- [key / keyCode / keyIsPressed](#key)
- [keyPressed / keyReleased](#keyPressed)
- [isKeyDown](#isKeyDown)
- [Keyboard focus in the hosts](#keyboardFocus)

<a name="mouse"></a>

### mouseX / mouseY

```swift
mouseX: Double
mouseY: Double
```

The cursor position in sketch coordinates (points, top-left origin, y-down). They are seeded from the cursor's actual position when the window opens. So a mouse-driven sketch is alive on the first frame, instead of reading (0, 0) until the first move. After that they track the pointer as it moves over the canvas.

```swift
override func draw() {
    background(.white)
    fill(.black)
    drawCircle(mouseX, mouseY, 24)   // a dot follows the cursor
}
```

Two calls put the mouse into coordinates of their own for a while: [`withViewBox`](../Drawing/Drawing.md#viewbox) for the length of its block, and [`viewControl`](../Drawing/Drawing.md#viewcontrol) for the rest of the frame. That is what keeps a piece written for the whole canvas working when it is not looking at the whole canvas. In both, `mouseX` and `mouseY` read the content the pointer is over rather than the glass it is on. The pointer itself is restored before the next frame.

<a name="mouseIsPressed"></a>

### mouseIsPressed

```swift
mouseIsPressed: Bool
```

Whether a mouse button is currently held over the canvas. It's the polling counterpart to the one-shot hooks below, mirroring `keyIsPressed`. Poll it in `draw()` for anything that should continue as long as the button is down, such as dragging, painting, or steering. `mouseX`/`mouseY` keep updating through the drag.

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

Override to respond to a click. Each fires once per press or release, and `mouseX`/`mouseY` hold the event's location. Use `mousePressed()` to regenerate an otherwise-static sketch on demand. `mouseReleased()` is the natural moment to act on a finished drag or stroke, and the `DigitReader` example classifies its drawing there.

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

How hard the pointer is being pressed. On a pressure-sensing device (a Force Touch trackpad, a pen tablet) it varies continuously through a press. On a device that cannot measure pressure it is simply `1` while a button is down. A pressure-driven sketch still works, at one level.

`pressureIsAvailable` says which you have. It is `false` until the first press tells us, because the answer comes from the event rather than the machine. So read it in `mousePressed()` rather than `setup()`:

```swift
override func mousePressed() {
    brush = pressureIsAvailable ? .pressure(light: 0.1) : .speed(fast: 0.15)
}
```

Ollin asks the trackpad for the drawing gesture, which is a single stage over the full range. A press reads as a smooth amount, and no force-click fires look-up mid-stroke. See [Marks](../Drawing/Marks.md) for the brush that reads it.

<a name="key"></a>

### key / keyCode / keyIsPressed

```swift
key: Character?
keyCode: KeyCode?
keyIsPressed: Bool
```

The most recent key event, split in two. A key that produces a character arrives as `key`. A letter, a digit, punctuation, or the space bar reads as `"a"`, `"5"`, or `" "`. A key with no useful character arrives as `keyCode` instead, so you match a named value rather than a magic number. An arrow or a function key reads as `.leftArrow`, `.return`, `.escape`, or `.function(1)`. Exactly one of the two is set for a given event, and the other is `nil`. Both are set on press *and* release, so the hooks below can read which key fired.

`keyIsPressed` is `true` whenever any key is held.

```swift
override func draw() {
    background(.white)
    if key == "r" { background(.red) }        // a character key
    if keyCode == .leftArrow { /* … */ }      // a named key
}
```

The named keys are `upArrow` / `downArrow` / `leftArrow` / `rightArrow`, `return`, `enter`, `tab`, `escape`, `delete`, `forwardDelete`, `home` / `end` / `pageUp` / `pageDown`, and `function(_:)`. `return` is the main Return key and `enter` is the keypad one, `delete` is Backspace, and `F1` is `.function(1)`.

<a name="keyPressed"></a>

### keyPressed / keyReleased

```swift
keyPressed()
keyReleased()
```

Override to respond to keys. Each fires once per physical press or release, since auto-repeat doesn't re-fire `keyPressed()`, and `key`/`keyCode` hold the key that fired. For continuous response while a key is *held* (steering, movement), poll `isKeyDown(_:)` in `draw()` instead, because the hooks are for discrete actions.

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

Whether a specific key is currently held. It's the polling counterpart to the one-shot `keyPressed()` hook, for movement that should continue as long as a key is down. Call it from `draw()`.

```swift
override func draw() {
    if isKeyDown(.leftArrow)  || isKeyDown("a") { x -= speed }
    if isKeyDown(.rightArrow) || isKeyDown("d") { x += speed }
}
```

The character form is case-sensitive, so `isKeyDown("w")` and `isKeyDown("W")` differ by whether Shift was down at the press.

<a name="keyboardFocus"></a>

### Keyboard focus in the hosts

A window that *is* the sketch hands the sketch the keyboard the moment it opens. That covers a standalone `swift run` and the live host, so all of the above works with no click first. The examples gallery is different, because its example list keeps the keyboard, so the arrow keys navigate examples. A sketch that reads keys shows a small **"Click the sketch to use the keyboard"** prompt over the canvas. Clicking the sketch gives it the keys, and clicking back in the list returns them.

When you embed `SketchView` in your own SwiftUI app, the same policy is the `keyboardFocus:` parameter. `.automatic` claims the keys on appear, and it is the default. `.onClick` leaves them to the rest of the window until the canvas is clicked. `showsKeyboardHint:` floats that same prompt for sketches that want keys:

```swift
SketchView(sketch, keyboardFocus: .onClick, showsKeyboardHint: true)
```
