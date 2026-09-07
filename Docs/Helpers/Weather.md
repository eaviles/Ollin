#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Weather`</sup>

---

## The weather outside

A [`DataFeed`](./LiveData.md) reads any address. A `Weather` is a feed that already knows the address to ask and the shape of the answer, so a sketch reads the sky over a place the way it reads a slider: `cloudCover`, `windSpeed`, `condition`, and the rest, in plain units. Make one for a place, or for a place by name, `start()` it, and read it in `draw()`.

The sun is not fetched at all. `Place.sun(at:)` works out where it is from the place and the clock, so a sketch can put it in the sky, and know when it rises and sets, with no network.

Nothing throws. Before the first answer arrives, and whenever the network is down, every reading is `nil` and `problem` says why. A failure never takes the last good reading away.

### Contents

- [Weather](#Weather)
- [Reading the sky](#reading)
- [The whole reading at once](#Reading)
- [The sky in a word](#Condition)
- [Where the sun is](#sun)
- [How it is going](#health)
- [In an export](#export)
- [Where the data comes from](#source)
- [Where the Mac is](#location)

<a name="Weather"></a>

### Weather

```swift
Weather(at place: Place, every interval: Double = 900)
Weather(latitude: Double, longitude: Double, every interval: Double = 900)
Weather(in name: String, every interval: Double = 900)
```

```swift
final class Sky: Sketch {
    private let sky = Weather(in: "Oaxaca")

    override func setup() {
        sky.start()
    }

    override func draw() {
        background(sky.isDay == true ? .white : .black)
        let clouds = sky.cloudCover ?? 0
        drawCircle(center: center, radius: 100 + clouds * 200)
    }
}
```

A `Place` is a latitude and a longitude in degrees, north and east positive: `Place(latitude: 19.43, longitude: -99.13)` is Mexico City. A name ("Oaxaca", "Tromsø", "Bath, Maine") is looked up once, when the weather starts, and the reading then carries the place it resolved to and the name the lookup knows it by. A name nothing matches leaves the weather empty, and `problem` says so.

`every:` is in seconds, and never goes below sixty. The default asks every fifteen minutes, which is how often the conditions are updated.

| Call | What it does |
|---|---|
| `start()` | Asks now, then every `interval` seconds. A weather that is already running ignores the call. A name is looked up first, and the forecast is asked once the place is known. |
| `stop()` | Stops asking. What arrived stays readable. |
| `refresh()` | Asks now instead of waiting for the next turn. It does nothing while a request is in flight. |

<a name="reading"></a>

### Reading the sky

Each read is `nil` until the first answer arrives.

| Read | Unit | Meaning |
|---|---|---|
| `temperature` | °C | Air temperature. |
| `apparentTemperature` | °C | What it feels like, wind and humidity included. |
| `humidity` | `0...1` | Relative humidity. |
| `cloudCover` | `0...1` | How much of the sky is cloud. |
| `precipitation` | mm | Rain, showers, and melted snow in the last hour. |
| `snowfall` | mm | Snow in the last hour, as millimeters of snow. |
| `windSpeed` | m/s | Wind speed. |
| `windDirection` | degrees | Where the wind blows from, clockwise from north: 90 is an east wind. |
| `windGusts` | m/s | The strongest gust in the last hour. |
| `pressure` | hPa | Air pressure at sea level. |
| `isDay` | `Bool` | Whether the sun is up there. |
| `condition` | `Condition` | The sky in a word. |
| `sunrise`, `sunset` | `Date` | Today's, there. |

`updateCount` counts the readings that differed from the one before. The service stamps every answer with the time it was generated, so the bytes differ on every poll while the sky does not, and a weather counts readings rather than bytes. `timeSinceUpdate` is seconds since the reading last changed, or `nil` before the first one.

<a name="Reading"></a>

### The whole reading at once

`reading` is a `Weather.Reading`, `nil` before the first answer. It holds every field above and a few more. `place` is the point the answer was read for. `name` is what the lookup calls the place, for a weather made by name. `observedAt` is when the conditions were measured. `code` is the condition as the World Meteorological Organization's number. `highTemperature` and `lowTemperature` are the day's, and `elevation` and `timeZone` are the place's.

Keep one to compare against the next, or build one by hand to draw a sky without asking for it:

```swift
let storm = Weather.Reading(place: Place(latitude: 19.43, longitude: -99.13),
                            temperature: 16, cloudCover: 1, precipitation: 4,
                            windSpeed: 9, windDirection: 240, condition: .thunderstorm)
```

Every field the initializer does not name has a plain default: a still, clear, mild day.

<a name="Condition"></a>

### The sky in a word

`Condition` is an open set of names, so a code the service learns later still arrives, as `Condition(rawValue: "weather code 42")`. The raw value is the word itself (`"partly cloudy"`), so it can be drawn as it is.

| Condition | Codes |
|---|---|
| `.clear`, `.mostlyClear`, `.partlyCloudy`, `.overcast` | 0, 1, 2, 3 |
| `.fog` | 45, 48 |
| `.drizzle`, `.freezingDrizzle` | 51 to 55; 56, 57 |
| `.rain`, `.freezingRain` | 61 to 65; 66, 67 |
| `.snow`, `.snowGrains` | 71 to 75; 77 |
| `.showers`, `.snowShowers` | 80 to 82; 85, 86 |
| `.thunderstorm`, `.hail` | 95; 96, 99 |

`isPrecipitating` is true for anything falling, and `isSnowing` for snow of any kind. The reading's `code` keeps the exact number, which is where light, moderate, and heavy live: 61, 63, and 65 are all `.rain`.

<a name="sun"></a>

### Where the sun is

```swift
place.sun(at date: Date = Date()) -> SunPosition
```

A `SunPosition` is an `elevation` in degrees above the horizon (negative at night) and an `azimuth` in degrees clockwise from north (90 is east). `isUp` is true while any of the disc shows, which is when the center is about 0.83 degrees below the horizon, refraction included. The elevation itself is the geometric height of the sun's center.

```swift
let sun = place.sun(at: Date())
let x = map(sun.azimuth, 60, 300, 0, width)          // east on the left, looking south
let y = horizon - sun.elevation / 90 * height * 0.7
```

The position is the standard low-precision solar model, the one behind the NOAA solar calculator, good to a small fraction of a degree for any date within a few centuries of now. That is enough to place the sun where a viewer would look for it and to know the hour it rises. It needs no network, so a sky can be the right color for the hour before the first reading arrives.

<a name="health"></a>

### How it is going

| Read | Type | Meaning |
|---|---|---|
| `isRunning` | `Bool` | Whether the weather is asking. |
| `isWaiting` | `Bool` | Whether a request is in flight right now. |
| `failureCount` | `Int` | Requests that have failed in a row. Back to zero on the next answer. |
| `problem` | `String?` | Why the last request failed, or why the name could not be found, in a sentence a sketch can draw. `nil` once an answer arrives. |

A failure never clears the last reading. Keep drawing it, with the notice over the top:

```swift
if let problem = sky.problem { drawStatus(problem, style: .warning) }
```

The politeness is the feed's: the next request waits for the last one to finish, a run of failures backs off to eight times the interval, and a name that could not be reached is retried from a minute rather than from the weather's own interval.

<a name="export"></a>

### In an export

In a headless export the weather reads once, while `start()` runs, and holds that reading for every frame. A name is looked up and the forecast fetched before `start()` returns. `timeSinceUpdate` reads zero throughout. An export that fetched per frame would render differently every run.

<a name="source"></a>

### Where the data comes from

The conditions come from [Open-Meteo](https://open-meteo.com), an open service that serves the national weather services' forecasts under the [CC BY 4.0](https://open-meteo.com/en/license) license. It needs no key and no account, and it is free for non-commercial use up to ten thousand requests a day. A sketch asking every fifteen minutes uses about a hundred. A piece sold or shown commercially wants one of the service's own plans, and a page or a print that carries the numbers should say where they came from.

The forecast is read at a grid point near the place, so the `place` on a reading can sit a few kilometers from the one asked for.

<a name="location"></a>

### Where the Mac is

There is no `.here` yet. Give the weather the place or the name, and let it look the rest up. Reading the Mac's own location needs a permission prompt that macOS shows only to an executable carrying an `Info.plist`, which a sketch run from the terminal does not have. A sketch packaged as an app can carry one. That half is still ahead.

### See also

- [`LiveData`](./LiveData.md) - `DataFeed`, the feed a weather is built on, and `PushFeed` for a server that sends rather than answers
- [`Data`](./Data.md) - `loadTable` and `loadJSON`, for a document read once
- [`Atmosphere`](../3D/Atmosphere.md) - the procedural sky the 3D mode lights a scene with, whose sun a reading can steer
- [`Installation`](../Output/Installation.md) - what else changes for a sketch that runs for weeks
