#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `OSCQuery`</sup>

---

## OSCQuery

OSCQuery is how a control app finds out what a sketch takes without anyone typing an address. The sketch publishes its `@Param` parameters as a tree, and an app that speaks the protocol (TouchOSC, Chataigne, ossia score, VDMX, Vezér) reads the tree, builds a control for each parameter with the right range, and sends values back over plain [OSC](./OSC.md). One extension does all of it. The support lives in `OllinOSC`, so add `import OllinOSC` beside `import Ollin` to reach it.

```swift
import Ollin
import OllinOSC

final class Wall: Sketch {
    @Param(20...400, group: "Shape") var radius = 120.0
    @Param(group: "Shape") var spin = true
    @Param var tint = Color.orange

    override func setup() {
        extend(OSCQueryServer())
    }

    override func draw() {
        background(.black)
        // radius, spin, and tint are live from any app that found the sketch
    }
}
```

When the sketch launches it prints one line, `OSCQuery: http://your-mac.local:9000 (OSC on port 9000)`. An app on the same network lists the sketch by name; a browser at that address shows the tree.

### Contents

- [Serving the namespace](#serving-the-namespace) - one extension, one port number, two protocols
- [What a client sees](#what-a-client-sees) - the node each parameter kind becomes
- [Writing a value](#writing-a-value) - the OSC message each kind takes
- [Reading the tree yourself](#reading-the-tree-yourself) - a browser, `curl`, or the sketch's own copy
- [Trying it](#trying-it) - the OSCQuery example, TouchOSC, and Chataigne

<a name="serving-the-namespace"></a>

### Serving the namespace

```swift
OSCQueryServer(port: Int = 9000, name: String? = nil)
OSCQueryServer(receiver: OSCReceiver, port: Int? = nil, name: String? = nil)
var receiver: OSCReceiver
var name: String?
var boundPort: Int?
var url: String?
var advertises: Bool
var isRunning: Bool
var unavailableReason: String?
func namespace() -> OSCQueryNode
func start()
func stop()
```

`isRunning` is true while the listener is up. When it is not, `unavailableReason` says why in a sentence worth drawing: a port another program holds, a bind the system refused, the OSC port that would not open. It follows the listener's own state, so it says so the moment the system does, and it clears when the listener comes up. `start()` serves again after `stop()`, or tries the port again after a start that failed; `setup` calls it for you the first time.

Register an `OSCQueryServer` with `extend(...)` in `setup()`. It discovers the sketch's parameters and opens two ports at one number. The namespace answers over HTTP on TCP, and the values arrive over OSC on UDP, at the same number. Both are advertised on the local network under the sketch's type name, or the `name` you give it. The service types are `_oscjson._tcp` and `_osc._udp`, so an app that browses for either finds the sketch. Pass `port: 0` to let the system pick, and read the numbers back from `boundPort` and `receiver.boundPort`.

The second initializer serves the namespace beside a receiver the sketch already reads. Its own `messages()` and `number(_:)` keep working for any address outside the tree, and the parameters take theirs. The namespace then listens on the receiver's port number unless you name another.

Values land on the main thread between frames, through the same control the inspector's own drag uses. A parameter's [smoothing](../Helpers/Parameters.md#smoothing) and clamping apply exactly as they do there. The tree the server hands out is rebuilt every quarter second, so a client that asks again sees what the sketch changed on its own.

Anyone on the network who has the address can move the parameters while the server is up. Treat it as a studio and venue tool. `advertises = false` keeps the ports open and the name to yourself, and `stop()` closes both; a reload that builds a fresh sketch releases them on its own.

<a name="what-a-client-sees"></a>

### What a client sees

A parameter becomes a node at `/name`, or at `/Group/name` when it declares a group. The group's container is named after it. The characters an OSC address cannot carry, a space and the reserved `#`, `*`, `?`, `[`, `]`, `{`, and `}`, become one underscore each, so a group called `Look & Feel` serves under `/Look_Feel`. The container's `DESCRIPTION` still says the real name. Every leaf carries the protocol's core attributes. `FULL_PATH` is its address, `TYPE` the OSC type tags of what it takes, `ACCESS` is 3 for readable and writable, `VALUE` the current value, `RANGE` its bounds, and `DESCRIPTION` the parameter's label. What each kind becomes:

| Parameter | `TYPE` | `VALUE` | `RANGE` |
|---|---|---|---|
| `Double` (and `Tempo`) | `f` | the number | `MIN` and `MAX` from the declared range |
| `Int` | `i` | the number | `MIN` and `MAX` |
| `Bool` | `T` | `true` or `false` | none |
| an enum or a `ParamChoices` catalog | `s` | the selected option's label | `VALS`, the option labels in order |
| `Color` | `r` | `#RRGGBBAA` | none |
| `Vector2` | `ff` | x, y | one `MIN`/`MAX` pair each |
| `Vector3` | `fff` | x, y, z | one pair each |
| `Rectangle` | `ffff` | x, y, width, height | one pair each |
| `Insets` | `ffff` | top, right, bottom, left | the edge range, four times |
| `ClosedRange<Double>` | `ff` | lower, upper | the outer range, twice |
| `String` | `s` | the text | none |
| `Palette` or `Ramp` | a container | one `r` child per color: `/inks/0`, `/inks/1`, and so on | none |

A strip of colors is served as a container of color methods rather than one node. A client that knows nothing about palettes still gets a color well per stop. Writing a child replaces that one color and leaves the stop where it sits. A hidden parameter, one whose [show rule](../Helpers/Parameters.md#show-rules) currently fails, stays in the tree and keeps taking values, as it keeps following an OSC binding.

`?HOST_INFO` answers with the server's `NAME`, the `EXTENSIONS` it speaks (`ACCESS`, `VALUE`, `RANGE`, and `DESCRIPTION`; the WebSocket `LISTEN` stream is not offered, so a client polls for changes), and `OSC_PORT` with `OSC_TRANSPORT` set to `UDP`. In code that answer is an `OSCQueryHostInfo`, with `name`, `extensions`, `oscPort`, and `oscTransport`.

<a name="writing-a-value"></a>

### Writing a value

A client sets a parameter by sending an OSC message to the address the tree names, on the OSC port, with arguments of the node's type. Values travel in the parameter's own units, the range the tree advertised. So `/Shape/radius 240.0` sets the radius to 240, and 1000 is clamped to the top of the range. The server reads generously. A number arrives as any numeric tag, an `i` for an `f` or the other way round. A menu takes its option's label as a string or its index as a number. A toggle takes `T`, `F`, or a number, where nonzero is on. A color takes the `r` type or a hex string, `#RRGGBB` or `#RRGGBBAA`. A message with too few arguments, or one whose kind does not fit, is ignored. The OSC 1.1 `r` type is new in `OSCArgument` for this, as `.color(Color)`, four bytes on the wire.

```text
  /Shape/radius   240.0            a Double
  /Shape/count    12               an Int
  /Shape/style    "Rings"          a menu, by label (or 1, by index)
  /Motion/spin    F                a Bool
  /Motion/pivot   0.25 0.75        a Vector2
  /Color/tint     r:#3399FFFF      a Color, or "#3399FF"
  /Color/inks/1   r:#FFFFFFFF      one color of a palette
```

<a name="reading-the-tree-yourself"></a>

### Reading the tree yourself

The whole tree is the JSON at the root address, and any node answers alone at its path. Add `?VALUE`, `?TYPE`, `?RANGE`, `?ACCESS`, `?DESCRIPTION`, or `?CONTENTS` to read one attribute. A node without that attribute answers 204. An attribute the server does not speak answers 400, and a path that leads nowhere answers 404.

```sh
curl http://localhost:9000/                        # the whole tree
curl http://localhost:9000/Shape/radius            # one node
curl 'http://localhost:9000/Shape/radius?VALUE'    # {"VALUE":[180]}
curl 'http://localhost:9000/?HOST_INFO'            # who serves, and the OSC port
```

Inside the sketch, `namespace()` returns the same tree as an `OSCQueryNode`, the value the server hands out. A node has its `fullPath`, `type`, `access`, `description`, `value` (an array of `OSCQueryValue`, one per type tag), `range` (an array of `OSCQueryRange` with `min`, `max`, or `values`), and `contents` when it is a container, which `isContainer` answers. `node(at:)` walks to a path and `methods` lists every leaf in address order. `OSCQueryNode` is `Codable` under the protocol's own attribute names, so it also decodes what another OSCQuery server publishes.

<a name="trying-it"></a>

### Trying it

The **OSCQuery** example (`Examples/Integration/OSCQuery`) serves a ring of marks with parameters in three groups. It draws the namespace as served down its left column, so the picture and the listing are the same thing seen twice. Run it, open the address it prints in a browser, and change a value with any OSC sender:

```sh
swift run --package-path Examples Example-Integration-OSCQuery
curl 'http://localhost:9000/Shape/radius?VALUE'
```

With TouchOSC on a phone on the same Wi-Fi, open the connection settings and choose OSCQuery. The sketch appears in the browse list. Pick it and TouchOSC builds a page of controls from the tree. Chataigne and ossia score find it the same way, as an OSCQuery server on the network. Any app that speaks only plain OSC still works: point it at the OSC port and send to the addresses the tree names.

---

See the **OSCQuery** example for a sketch that publishes its parameters and draws the tree, and the [OSC](./OSC.md) page for the messages underneath.
