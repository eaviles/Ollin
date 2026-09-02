#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `Remote`</sup>

---

## Remote

The sketch's `@Param` parameters, served to a phone. An installation is tuned from in front of it, not from behind the Mac that runs it. Register one extension and the sketch starts a small server on the local network. Any browser on the same Wi-Fi opens a touch surface with the same parameters the [inspector](../Helpers/Parameters.md) shows, live in both directions. It lives in a separate library so the drawing core stays free of Network.framework. Add `import OllinRemote` alongside `import Ollin` to reach it.

```swift
import Ollin
import OllinRemote

final class Wall: Sketch {
    @Param(0.1...4) var speed = 1.4
    @Param var accent = Color.purple

    override func setup() {
        extend(RemoteInspector())
    }

    override func draw() {
        background(.black)
        // speed and accent are live from the phone, the inspector, or both
    }
}
```

On launch the sketch prints one line, `Remote surface: http://your-mac.local:9330`. Open that address on the phone and the surface appears.

### Contents

- [Serving the surface](#serving-the-surface) - one extension, one port
- [What the phone shows](#what-the-phone-shows) - every control family, grouped like the inspector
- [How values land](#how-values-land) - the frame boundary, same as the inspector
- [The network story](#the-network-story) - who can reach it, and when it stops
- [Trying it](#trying-it) - the RemoteSurface example

<a name="serving-the-surface"></a>

### Serving the surface

```swift
extend(RemoteInspector())            // serves on port 9330
extend(RemoteInspector(port: 8080)) // or a port of your choosing
extend(RemoteInspector(port: 0))    // or any free port the system picks
```

`RemoteInspector` rides the [extension seam](../Core/Sketch.md#extensions), so registering it is the whole setup. It discovers the sketch's `@Param` properties the same way the host inspectors do. Two properties report where it landed:

```swift
remote.url        // "http://your-mac.local:9330", nil until the listener is up
remote.boundPort  // the port actually bound, useful with port 0
```

Keep the reference if the sketch wants to draw the address on the canvas. The example below does exactly that, so the piece tells visitors how to reach it.

<a name="what-the-phone-shows"></a>

### What the phone shows

The page renders one touch control per parameter, grouped the way `group:` arranges the inspector:

- a `Double` becomes a full-width slider; the whole row is the touch surface
- an `Int` becomes a stepper with large touch targets
- a `Bool` becomes a switch
- a `ParamOption` enum becomes a menu, or a segmented control when declared `style: .segmented`
- a `Color` becomes a swatch that opens the phone's color picker
- a `Vector2` declared `style: .pad` becomes a draggable XY pad; the fields form shows two numeric fields
- `Vector3`, `Rectangle`, `Insets`, and `ClosedRange` become labeled numeric fields
- a `String` becomes a text field
- a `Palette` or `Ramp` becomes a chip per color, each opening the phone's color picker, with a ramp's band drawn above them

The phone recolors a strip; it does not move a ramp's stops or change how many colors there are. Those stay on the Mac, where the handles are. The band the page draws fades straight between the stops, so it is close to what the sketch shows without being the sketch's own blend.

A header shows the sketch's name and the connection state. A monitor strip carries the frame rate, the clock, and the frame count, refreshed a few times a second. Rows ruled by `Param.show(when:)` appear and disappear as their rule flips.

Edits travel both ways. A slider moved on the phone lands in the sketch. A parameter changed in the Mac inspector, or a value the sketch changes itself, travels back to every open page.

<a name="how-values-land"></a>

### How values land

A value from the phone is queued and applied on the main thread at the next frame boundary, before `draw()`. That is the same place the host inspector's own edits land. A remote edit can never tear a frame or race the draw loop. Values ride the same persisted payloads the hosts use, so a control accepts and clamps exactly what the inspector would.

<a name="the-network-story"></a>

### The network story

The server listens on every interface of the Mac. Anyone on the same network who has the address can open the page and move the parameters while it is up. That makes it a studio and venue tool. It is fine on your own Wi-Fi or a private show network, and not something to leave running on hostile networks. There is no account and no pairing code; possession of the address is the whole key.

The server stops when the sketch goes away, including across a live reload, which builds a fresh sketch and a fresh extension. Call `stop()` to end it earlier by hand.

<a name="trying-it"></a>

### Trying it

The **RemoteSurface** example (`Examples/Integration/RemoteSurface`) draws a tunable aurora and serves every control family. Sliders, a toggle, a menu, a color, an XY pad, and a stepper sit in three groups. The canvas shows the address to open. Run it, open the address on a phone on the same Wi-Fi, and drag.

```sh
swift run --package-path Examples Example-Integration-RemoteSurface
```

---

See the **RemoteSurface** example for the full loop, and [`@Param`](../Helpers/Parameters.md) for everything a parameter can declare.
