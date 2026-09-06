#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `LiveData`</sup>

---

## Live data

[`loadTable`](./Data.md) and [`loadJSON`](./Data.md) read a document once and keep it. A `DataFeed` reads one address over and over, so a sketch can draw something that is true right now. That could be the tide, a day of earthquakes, or a number a machine down the hall is publishing. When the machine wants to send rather than answer, use a [`PushFeed`](#PushFeed) instead. It holds a connection open, so each message arrives the moment it is sent.

The request runs on a background queue, so `draw()` never waits for the network. The bytes are read into a `JSON` or a `Table` on that queue too, so no frame pays for the parse.

Nothing throws. Before the first answer arrives, and whenever the network is down, `json` reads as null and `table`, `text`, and `bytes` are `nil`. `problem` says why. A feed with nothing to draw is in one state, not two.

### Contents

- [DataFeed](#DataFeed)
- [Reading the answer](#reading)
- [Telling news from a quiet poll](#updates)
- [How it is going](#health)
- [What the bytes are read as](#content)
- [How often it asks](#polling)
- [PushFeed: a feed that is pushed](#PushFeed)
- [Messages, one by one](#messages)
- [Staying connected](#reconnect)
- [In an export](#export)
- [Sending a key or a contact](#headers)
- [Sandboxed apps](#sandbox)

<a name="DataFeed"></a>

### DataFeed

```swift
DataFeed(_ address: String, every interval: Double = 300,
         as content: Content = .auto, headers: [String: String] = [:])
DataFeed(_ url: URL, every interval: Double = 300,
         as content: Content = .auto, headers: [String: String] = [:])
```

Make one in `setup()`, `start()` it, then read the latest answer in `draw()`.

```swift
final class Tide: Sketch {
    private let tide = DataFeed("https://example.org/tide.json", every: 600)

    override func setup() {
        tide.start()
    }

    override func draw() {
        background(.white)
        let height = tide.json["height"].number ?? 0
        drawCircle(center: center, radius: 40 + height * 20)
    }
}
```

`every:` is in seconds and never goes below one. Text that is not a valid address leaves the feed empty, and `problem` says so, the same as a server that never answers.

| Call | What it does |
|---|---|
| `start()` | Asks now, then every `interval` seconds. A feed that is already running ignores the call. You can call it from anywhere, not only from `setup()` on the main thread. |
| `stop()` | Stops asking. What arrived stays readable. A feed stops itself when it goes away. |
| `refresh()` | Asks now instead of waiting for the next turn, so bind it to a key press or an incoming message. It does nothing while a request is already in flight. |

<a name="reading"></a>

### Reading the answer

| Read | Type | Before the first answer |
|---|---|---|
| `json` | `JSON` | null |
| `table` | `Table?` | `nil` |
| `text` | `String?` | `nil` |
| `bytes` | `Data?` | `nil` |

`json` and `table` are the same types that [`loadJSON` and `loadTable`](./Data.md) hand back. A sketch that started from a bundled file can read a feed with the code it already has. `text` is filled whenever the bytes are UTF-8, whatever else was parsed.

<a name="updates"></a>

### Telling news from a quiet poll

`updates` counts the answers that differed from the one before. A poll that brings back what the feed already had does not count, so a sketch can use the count to start an entrance:

```swift
if tide.updateCount != seen {
    seen = tide.updateCount
    startTheTransition()
}
```

`timeSinceUpdate` is seconds since the answer last changed, or `nil` before the first one.

<a name="health"></a>

### How it is going

| Read | Type | Meaning |
|---|---|---|
| `isRunning` | `Bool` | Whether the feed is asking. |
| `isWaiting` | `Bool` | Whether a request is in flight right now. |
| `failures` | `Int` | How many requests have failed in a row. It goes back to zero on the next answer. |
| `problem` | `String?` | Why the last request failed, in a sentence a sketch can draw. It is `nil` once an answer arrives. |

A failure never clears what the feed already holds. A sketch can keep drawing the last good answer with the notice over it, instead of going blank:

```swift
if let problem = tide.problem { drawStatus(problem, style: .warning) }
```

<a name="content"></a>

### What the bytes are read as

`as:` decides. The default, `.auto`, takes the server's word for it, and falls back to the bytes.

| `Content` | What happens |
|---|---|
| `.auto` | A content type naming JSON is read as JSON. One naming CSV or tab-separated values is read as a table. When the server says nothing, a document opening with `{` or `[` is read as JSON, and anything else is tried as a table. |
| `.json` | Read as JSON, whatever the server calls it. |
| `.table` | Read as CSV or TSV, whatever the server calls it. |
| `.text` | Keep the text and the bytes, and parse nothing. |

Name the content type yourself when a server labels its documents carelessly, which many servers do.

<a name="polling"></a>

### How often it asks

Polling is slow on purpose, because a sketch on a wall runs for weeks.

- `every:` never goes below one second.
- The next request is scheduled only once the last one has finished, so a slow server can never make requests stack up.
- The feed asks conditionally. It sends back the `ETag` or `Last-Modified` the server gave it, so a server that supports those can reply with a header and no body. That reply is not an update.
- A run of failures backs off. The wait doubles each time, up to eight times the interval, and the next answer puts it back to the plain interval.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/09-Pictures/NumbersThatKeepArriving-dark.jpg">
  <img src="../../Guide/Images/09-Pictures/NumbersThatKeepArriving.jpg" alt="A diagram on cream paper. A row of request marks along a time line, labeled 200, 304, 304, then three red crosses labeled 500 with widening gaps between them marked wait, twice, four times, then 200 and 304. Below, a green staircase labeled updates steps from 1 to 2 only at the second 200, and under that a red band labeled problem covers the failing stretch" width="680">
</picture>

Keep a feed small. The parse happens off the frame, but a document of many megabytes is still slow to fetch and read. Put a big document in a file and read it once in `setup()`.

<a name="PushFeed"></a>

### PushFeed: a feed that is pushed

```swift
PushFeed(_ address: String, headers: [String: String] = [:],
         greeting: String? = nil, retryEvery: Double = 3)
PushFeed(_ url: URL, headers: [String: String] = [:],
         greeting: String? = nil, retryEvery: Double = 3)
```

A `DataFeed` asks on a schedule, which suits a value that changes slowly. A machine that wants to speak the moment something happens needs a connection held open instead, and that is what a `PushFeed` gives it. The address decides how the connection is made. `ws://` and `wss://` open a web socket. Anything else is read as a stream of server-sent events, which is the plain-HTTP way a server pushes.

```swift
final class Edits: Sketch {
    private let edits = PushFeed("https://stream.wikimedia.org/v2/stream/recentchange")

    override func setup() {
        edits.start()
    }

    override func draw() {
        background(.black)
        for message in edits.messages() {
            splash(message.json["title"].text ?? "")
        }
    }
}
```

The reads you learned on a `DataFeed` still work here. `json`, `text`, and `bytes` hold the latest message, `problem` says why when something is wrong, and nothing throws. `event` adds the label, on a stream that names its events.

| Call | What it does |
|---|---|
| `start()` | Connects, then keeps the connection alive from then on. A feed that is already running ignores the call. |
| `stop()` | Hangs up. What arrived stays readable. |
| `reconnect()` | Hangs up and dials again now, so bind it to a key press for when a piece looks stale. |
| `send(_:)` | Sends a message to the server, on a feed that is a web socket. A stream of server-sent events has no way to receive one. |

<a name="messages"></a>

### Messages, one by one

More than one message can arrive between two frames, and the latest-message reads only show the last of them. `messages()` misses nothing. It hands back every message since the last call, oldest first, and each one is a `Message` carrying `bytes`, `text`, `json`, and `event`.

```swift
for message in edits.messages() {
    ripples.append(Ripple(title: message.json["title"].text ?? ""))
}
```

A feed that nobody drains keeps the newest few hundred messages and drops the oldest, so an undrained buffer never grows without bound.

`updates` counts every message, and on a `PushFeed` a repeat still counts. A poll can bring back what a feed already had, but a push is sent because the server had something to say. `timeSinceUpdate` is seconds since the last message, or `nil` before the first one.

<a name="reconnect"></a>

### Staying connected

A piece on a wall outlives any socket, so a `PushFeed` has to reconnect. The feed does all of it on its own, and a sketch only ever reads `isConnected` and `problem` to say what is happening.

- A dropped connection redials after `retryEvery:` seconds, which never goes below one. A run of failures doubles the wait each time, up to eight times that. Anything that arrives puts the wait back to `retryEvery:` seconds.
- A stream of server-sent events that names its own retry time is obeyed. One that labels its messages with ids is resumed with the last id seen, so a short drop loses nothing the server still holds.
- A web socket is pinged every few seconds, so a connection that died without a word is noticed and redialed instead of being trusted. A quiet stream of events is given a minute before the same treatment.
- `greeting:` is sent each time the connection opens, not once. A service that wants a subscribe message wants it again after every redial. That is why the greeting is part of the feed, rather than a `send(_:)` made in `setup()`.
- A server that ends the stream on purpose (a `204`) is honored. The feed stops instead of redialing.

| Read | Type | Meaning |
|---|---|---|
| `isConnected` | `Bool` | Whether the connection is open right now. |
| `failures` | `Int` | How many connections have failed or dropped in a row. It goes back to zero once something arrives. |
| `problem` | `String?` | Why the connection is down, in a sentence a sketch can draw. It is `nil` while the connection is up. |

<a name="export"></a>

### In an export

In a headless export the feed reads once, while `start()` runs, and holds that answer for every frame. `timeSinceUpdate` reads zero throughout. An export that fetched per frame would render differently every run, and the export tier is built so that it does not. The read blocks whichever thread called `start()`, which is the thread running `setup()` in the ordinary case.

<a name="headers"></a>

### Sending a key or a contact

`headers:` are sent with every request. That is where an API key goes, or the contact address that some public services ask for:

```swift
let birds = DataFeed("https://example.org/api/birds", every: 900,
                     headers: ["X-Api-Key": key])
```

Keep a real key out of the sketch file. Read it from the environment or a file you do not commit.

<a name="sandbox"></a>

### Sandboxed apps

A sketch you run from the terminal reaches the network freely. A sketch wrapped as a sandboxed app needs the outgoing-connections entitlement (`com.apple.security.network.client`) in its entitlements file. Without that entitlement every request fails, and `problem` says the connection was refused.

### See also

- [`Data`](./Data.md) - `loadTable` and `loadJSON`, which read a document once and hand back the same types a feed does
- [`Parameters`](./Parameters.md) - `@Param` parameters, for values you tune rather than fetch
- [`OSC`](../Integration/OSC.md) - values pushed at the sketch over the network, where a feed pulls them
- [`Installation`](../Output/Installation.md) - what else changes for a sketch that runs for weeks
