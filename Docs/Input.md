#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Input`</sup>

---

## Input

Pointer and keyboard input live on the sketch as plain properties and overridable methods.

### Contents

- [mouseX / mouseY](#mouse)
- [mousePressed](#mousePressed)
- [key / keyCode / keyIsPressed](#key)
- [keyPressed / keyReleased](#keyPressed)
- [isKeyDown](#isKeyDown)

<a name="mouse"></a>

### mouseX / mouseY

```swift
mouseX: Double
mouseY: Double
```

The cursor position in sketch coordinates (points, top-left origin, y-down). They're seeded from the cursor's actual position when the window opens, so a mouse-driven sketch is alive on the first frame instead of waiting for the first move, then update as the pointer moves over the canvas.

```swift
override func draw() {
    background(.white)
    fill(.black)
    drawCircle(mouseX, mouseY, 24)   // a dot follows the cursor
}
```

<a name="mousePressed"></a>

### mousePressed

```swift
mousePressed()
```

Override to respond to a click; `mouseX`/`mouseY` hold the press location. Handy for regenerating an otherwise-static sketch on demand.

```swift
override func mousePressed() {
    randomSeed(frameCount)   // re-roll the randomness on each click
}
```

<a name="key"></a>

### key / keyCode / keyIsPressed

```swift
key: Character?
keyCode: KeyCode?
keyIsPressed: Bool
```

The most recent key event, split in two. A key that produces a character — a letter, a digit, punctuation, the space bar — arrives as `key` (`"a"`, `"5"`, `" "`). A key with no useful character — an arrow, the function row — arrives as `keyCode` (`.leftArrow`, `.return`, `.escape`, `.function(1)`, …) instead, so you match a named value rather than a magic number. Exactly one of the two is set for a given event; the other is `nil`. Both are set on press *and* release, so the hooks below can read which key fired.

`keyIsPressed` is `true` whenever any key is held.

```swift
override func draw() {
    background(.white)
    if key == "r" { background(.red) }        // a character key
    if keyCode == .leftArrow { /* … */ }      // a named key
}
```

The named keys are `upArrow` / `downArrow` / `leftArrow` / `rightArrow`, `return` (main Return) and `enter` (keypad), `tab`, `escape`, `delete` (Backspace) and `forwardDelete`, `home` / `end` / `pageUp` / `pageDown`, and `function(_:)` (`F1` is `.function(1)`).

<a name="keyPressed"></a>

### keyPressed / keyReleased

```swift
keyPressed()
keyReleased()
```

Override to respond to keys. Each fires once per physical press or release — auto-repeat doesn't re-fire `keyPressed()` — and `key`/`keyCode` hold the key that fired. For continuous response while a key is *held* (steering, movement), poll `isKeyDown(_:)` in `draw()` instead; the hooks are for discrete actions.

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

Whether a specific key is currently held — the polling counterpart to the one-shot `keyPressed()` hook, for movement that should continue as long as a key is down. Call it from `draw()`.

```swift
override func draw() {
    if isKeyDown(.leftArrow)  || isKeyDown("a") { x -= speed }
    if isKeyDown(.rightArrow) || isKeyDown("d") { x += speed }
}
```

The character form is case-sensitive: `isKeyDown("w")` and `isKeyDown("W")` differ by whether Shift was down at the press.
