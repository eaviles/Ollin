import Foundation
import os

/// The weather over one place, read again and again, so a sketch can draw
/// the sky outside.
///
/// A `Weather` is a `DataFeed` that already knows the address to ask and the
/// shape of the answer. Make one for a place, or for a place by name, `start()`
/// it, then read the current conditions in `draw()`:
///
/// ```swift
/// let sky = Weather(in: "Oaxaca")
///
/// override func setup() { sky.start() }
///
/// override func draw() {
///     background(sky.isDay == true ? .white : .black)
///     let clouds = sky.cloudCover ?? 0
///     drawCircle(center: center, radius: 100 + clouds * 200)
/// }
/// ```
///
/// Everything a feed does, this does: the request runs on a background queue,
/// the answer is parsed there, nothing throws, a failure keeps the last good
/// reading and says why in `problem`, and a headless export reads once and
/// holds that reading for every frame. Until the first answer every reading is
/// `nil`, and `reading` holds the whole answer at once for a sketch that wants
/// to keep or compare it.
///
/// Readings are in plain units: degrees Celsius, meters per second, millimeters
/// of water in the last hour, hectopascals, and fractions of one for humidity
/// and cloud cover. The sun's own position is not fetched at all: `Place.sun(at:)`
/// computes it from the place and the clock.
///
/// The conditions come from Open-Meteo (open-meteo.com), which serves the
/// national weather services' forecasts with no key, free for non-commercial
/// use, under the CC BY 4.0 license. Asking every fifteen minutes, the default,
/// is well within its limits, and `every:` never goes below a minute.
public final class Weather: @unchecked Sendable {

    /// The place the weather is read for, when one was given. A weather made
    /// for a name reads `nil` here, and the place the name turned out to be is
    /// on the reading.
    public let place: Place?

    /// The name the weather was made for, when one was given.
    public let name: String?

    /// Seconds between requests. Never below sixty.
    public let interval: Double

    private static let forecastAddress = "https://api.open-meteo.com/v1/forecast"
    private static let geocodingAddress = "https://geocoding-api.open-meteo.com/v1/search"

    private let forecastAddress: String
    private let geocodingAddress: String
    private let protocolClasses: [AnyClass]?

    private struct State: Sendable {
        var running = false
        var headless = false
        var geocoder: DataFeed?
        var forecast: DataFeed?
        var reading: Reading?
        var updates = 0
        var lastUpdate: Date?
        /// Why the name could not be found, when that is what went wrong.
        var lookupProblem: String?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    // MARK: Lifecycle

    /// The weather over `place`, read every `interval` seconds.
    public convenience init(at place: Place, every interval: Double = 900) {
        self.init(place: place, name: nil, interval: interval)
    }

    /// The weather over a latitude and longitude, read every `interval` seconds.
    public convenience init(latitude: Double, longitude: Double, every interval: Double = 900) {
        self.init(place: Place(latitude: latitude, longitude: longitude), name: nil, interval: interval)
    }

    /// The weather over the place called `name` ("Oaxaca", "Tromsø", "Bath,
    /// Maine"), read every `interval` seconds.
    ///
    /// The name is looked up once, when the weather starts, and the reading
    /// then carries the place it was taken for and the name the lookup knows
    /// it by. A name nothing matches leaves the weather empty, and `problem`
    /// says so.
    public convenience init(in name: String, every interval: Double = 900) {
        self.init(place: nil, name: name, interval: interval)
    }

    /// A weather whose requests are answered by `protocolClasses` at the given
    /// addresses rather than by the network, for the tests.
    convenience init(at place: Place?, in name: String? = nil, every interval: Double = 900,
                     forecastAddress: String, geocodingAddress: String,
                     answeredBy protocolClasses: [AnyClass]) {
        self.init(place: place, name: name, interval: interval,
                  forecastAddress: forecastAddress, geocodingAddress: geocodingAddress,
                  protocolClasses: protocolClasses)
    }

    private init(place: Place?, name: String?, interval: Double,
                 forecastAddress: String = Weather.forecastAddress,
                 geocodingAddress: String = Weather.geocodingAddress,
                 protocolClasses: [AnyClass]? = nil) {
        self.place = place
        self.name = name
        self.interval = max(60, interval)
        self.forecastAddress = forecastAddress
        self.geocodingAddress = geocodingAddress
        self.protocolClasses = protocolClasses
    }

    deinit { stop() }

    /// Asks now, and then every `interval` seconds. Calling it on a weather
    /// that is already running does nothing.
    ///
    /// A weather made for a name looks the name up first, and asks for the
    /// forecast once the place is known. In a headless export both reads
    /// happen before this returns, so every exported frame draws the same sky.
    public func start() {
        let headless = Thread.isMainThread && OllinApp.isRenderingHeadless
        let go: Bool = state.withLock {
            guard !$0.running else { return false }
            $0.running = true
            $0.headless = headless
            return true
        }
        guard go else { return }

        if let place {
            startForecast(at: place, name: nil, timeZone: nil, headless: headless)
        } else if let name {
            lookUp(name, headless: headless)
        }
    }

    /// Stops asking. What arrived stays readable.
    public func stop() {
        let feeds: (DataFeed?, DataFeed?) = state.withLock {
            $0.running = false
            let feeds = ($0.geocoder, $0.forecast)
            $0.geocoder = nil
            $0.forecast = nil
            return feeds
        }
        feeds.0?.stop()
        feeds.1?.stop()
    }

    /// Asks now rather than waiting for the next turn. Does nothing while a
    /// request is already in flight, or during a headless export.
    public func refresh() {
        state.withLock { $0.forecast }?.refresh()
    }

    // MARK: What came back

    /// The latest conditions, or `nil` before the first answer arrives.
    public var reading: Reading? { state.withLock { $0.reading } }

    /// Air temperature in degrees Celsius.
    public var temperature: Double? { reading?.temperature }

    /// What the temperature feels like, wind and humidity included, in degrees
    /// Celsius.
    public var apparentTemperature: Double? { reading?.apparentTemperature }

    /// Relative humidity, `0...1`.
    public var humidity: Double? { reading?.humidity }

    /// How much of the sky is cloud, `0...1`.
    public var cloudCover: Double? { reading?.cloudCover }

    /// Rain, showers, and melted snow in the last hour, in millimeters.
    public var precipitation: Double? { reading?.precipitation }

    /// Snow in the last hour, in millimeters of snow.
    public var snowfall: Double? { reading?.snowfall }

    /// Wind speed in meters per second.
    public var windSpeed: Double? { reading?.windSpeed }

    /// Where the wind blows from, in degrees clockwise from north.
    public var windDirection: Double? { reading?.windDirection }

    /// The strongest gust in the last hour, in meters per second.
    public var windGusts: Double? { reading?.windGusts }

    /// Air pressure at sea level, in hectopascals.
    public var pressure: Double? { reading?.pressure }

    /// Whether the sun is up there.
    public var isDay: Bool? { reading?.isDay }

    /// The sky in a word: `.clear`, `.rain`, `.fog`, and so on.
    public var condition: Condition? { reading?.condition }

    /// When the sun rose, or rises, today there.
    public var sunrise: Date? { reading?.sunrise }

    /// When the sun set, or sets, today there.
    public var sunset: Date? { reading?.sunset }

    /// How many readings have differed from the one before. An answer that
    /// changed nothing does not count.
    public var updateCount: Int { state.withLock { $0.updates } }

    /// Seconds since the reading last changed, or `nil` before the first one.
    /// A headless export reads zero.
    public var timeSinceUpdate: Double? {
        let (last, headless) = state.withLock { ($0.lastUpdate, $0.headless) }
        guard let last else { return nil }
        return headless ? 0 : Date().timeIntervalSince(last)
    }

    // MARK: How it is going

    /// Whether the weather is asking.
    public var isRunning: Bool { state.withLock { $0.running } }

    /// Whether a request is in flight right now.
    public var isWaiting: Bool {
        let (geocoder, forecast) = state.withLock { ($0.geocoder, $0.forecast) }
        return geocoder?.isWaiting == true || forecast?.isWaiting == true
    }

    /// Requests that have failed in a row. Back to zero on the next answer.
    public var failureCount: Int {
        let (geocoder, forecast) = state.withLock { ($0.geocoder, $0.forecast) }
        return (forecast ?? geocoder)?.failureCount ?? 0
    }

    /// Why the last request failed, in a sentence a sketch can draw, or why the
    /// name could not be found. `nil` once an answer arrives.
    public var problem: String? {
        let (lookup, geocoder, forecast) = state.withLock { ($0.lookupProblem, $0.geocoder, $0.forecast) }
        if let lookup { return lookup }
        if let forecast { return forecast.problem }
        return geocoder?.problem
    }

    // MARK: Asking

    private func makeFeed(_ address: String, every interval: Double) -> DataFeed {
        if let protocolClasses {
            return DataFeed(address, every: interval, as: .json, answeredBy: protocolClasses)
        }
        return DataFeed(address, every: interval, as: .json)
    }

    /// The forecast address for `place`: the current conditions, today's sun
    /// times and extremes, wind in meters per second, and times in the place's
    /// own zone, which is how the answer says what "today" means there.
    func forecastURL(for place: Place) -> String {
        var components = URLComponents(string: forecastAddress) ?? URLComponents()
        components.queryItems = [
            URLQueryItem(name: "latitude", value: Weather.format(place.latitude)),
            URLQueryItem(name: "longitude", value: Weather.format(place.longitude)),
            URLQueryItem(name: "current", value: Weather.currentFields.joined(separator: ",")),
            URLQueryItem(name: "daily", value: "sunrise,sunset,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        return components.string ?? forecastAddress
    }

    /// The lookup address for `name`: the single best match.
    func geocodingURL(for name: String) -> String {
        var components = URLComponents(string: geocodingAddress) ?? URLComponents()
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components.string ?? geocodingAddress
    }

    static let currentFields = [
        "temperature_2m", "relative_humidity_2m", "apparent_temperature", "is_day",
        "precipitation", "snowfall", "weather_code", "cloud_cover", "pressure_msl",
        "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m",
    ]

    private static func format(_ degrees: Double) -> String {
        String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), degrees)
    }

    private func lookUp(_ name: String, headless: Bool) {
        // A miss backs off from a minute rather than from the weather's own
        // interval: a network blip on launch should not cost a quarter hour.
        let geocoder = makeFeed(geocodingURL(for: name), every: 60)
        state.withLock { $0.geocoder = geocoder }
        if !headless {
            // Live, the answer comes on the network queue. Headless, it is in
            // by the time `start()` returns, and it is read below on the same
            // thread, because a forecast started from the network queue would
            // not know it belongs to the export.
            geocoder.onChange = { [weak self, weak geocoder] in
                guard let self, let geocoder else { return }
                self.resolve(from: geocoder, headless: false)
            }
        }
        geocoder.start()
        if headless { resolve(from: geocoder, headless: true) }
    }

    /// Reads the lookup's answer and starts the forecast at the place found.
    private func resolve(from geocoder: DataFeed, headless: Bool) {
        let go: Bool = state.withLock { $0.running && $0.geocoder === geocoder }
        guard go else { return }

        let result = geocoder.json["results"][0]
        guard let latitude = result["latitude"].number, let longitude = result["longitude"].number else {
            if geocoder.updateCount > 0 {
                // The lookup answered, and knows no such place. Asking again
                // would not change that.
                state.withLock { $0.lookupProblem = "no place named \(name ?? "")" }
                geocoder.stop()
            }
            return
        }
        let place = Place(latitude: latitude, longitude: longitude)
        let found = [result["name"].text, result["admin1"].text, result["country"].text]
            .compactMap { $0 }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined(separator: ", ")
        let zone = result["timezone"].text.flatMap(TimeZone.init(identifier:))

        geocoder.stop()
        state.withLock {
            $0.geocoder = nil
            $0.lookupProblem = nil
        }
        startForecast(at: place, name: found.isEmpty ? nil : found, timeZone: zone, headless: headless)
    }

    private func startForecast(at place: Place, name: String?, timeZone: TimeZone?, headless: Bool) {
        let forecast = makeFeed(forecastURL(for: place), every: interval)
        let go: Bool = state.withLock {
            guard $0.running, $0.forecast == nil else { return false }
            $0.forecast = forecast
            return true
        }
        guard go else { return }
        // The parse runs on the network queue, never in a frame, and in an
        // export it runs before `start()` returns. Both captures are weak: a
        // feed that held its own hook would never go away.
        forecast.onChange = { [weak self, weak forecast] in
            guard let self, let forecast else { return }
            self.take(from: forecast, at: place, name: name, timeZone: timeZone)
        }
        forecast.start()
    }

    /// Reads the forecast's answer into a reading, and counts it only when
    /// something in it changed: the answer carries its own generation time,
    /// so the bytes differ on every poll while the sky does not.
    private func take(from forecast: DataFeed, at place: Place, name: String?, timeZone: TimeZone?) {
        guard let reading = Weather.reading(from: forecast.json, at: place, name: name, timeZone: timeZone) else { return }
        state.withLock {
            guard $0.forecast === forecast, $0.reading != reading else { return }
            $0.reading = reading
            $0.updates += 1
            $0.lastUpdate = Date()
        }
    }

    // MARK: Reading the answer

    /// The forecast document as a reading, or `nil` when it is not one.
    static func reading(from json: JSON, at place: Place, name: String?, timeZone: TimeZone?) -> Reading? {
        let current = json["current"]
        guard let temperature = current["temperature_2m"].number,
              let code = current["weather_code"].int else { return nil }

        let offset = json["utc_offset_seconds"].int ?? 0
        let daily = json["daily"]
        let zone = timeZone ?? json["timezone"].text.flatMap(TimeZone.init(identifier:))
        let resolved = Place(latitude: json["latitude"].number ?? place.latitude,
                             longitude: json["longitude"].number ?? place.longitude)

        return Reading(
            place: resolved,
            name: name,
            observedAt: Weather.date(from: current["time"].text, offsetSeconds: offset) ?? Date(),
            temperature: temperature,
            apparentTemperature: current["apparent_temperature"].number ?? temperature,
            humidity: (current["relative_humidity_2m"].number ?? 0) / 100,
            cloudCover: (current["cloud_cover"].number ?? 0) / 100,
            precipitation: current["precipitation"].number ?? 0,
            snowfall: (current["snowfall"].number ?? 0) * 10,
            windSpeed: current["wind_speed_10m"].number ?? 0,
            windDirection: current["wind_direction_10m"].number ?? 0,
            windGusts: current["wind_gusts_10m"].number ?? 0,
            pressure: current["pressure_msl"].number ?? 0,
            isDay: (current["is_day"].int ?? 1) != 0,
            condition: Condition(code: code),
            code: code,
            sunrise: Weather.date(from: daily["sunrise"][0].text, offsetSeconds: offset),
            sunset: Weather.date(from: daily["sunset"][0].text, offsetSeconds: offset),
            highTemperature: daily["temperature_2m_max"][0].number,
            lowTemperature: daily["temperature_2m_min"][0].number,
            elevation: json["elevation"].number,
            timeZone: zone
        )
    }

    /// A local time the answer writes as `2026-09-06T17:45`, with the offset
    /// the same answer gives for the place, as an instant.
    static func date(from text: String?, offsetSeconds: Int) -> Date? {
        guard let text else { return nil }
        let parts = text.split(whereSeparator: { $0 == "-" || $0 == "T" || $0 == ":" }).compactMap { Int($0) }
        guard parts.count >= 5 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = parts[3]
        components.minute = parts[4]
        components.second = parts.count > 5 ? parts[5] : 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: offsetSeconds) ?? TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: components)
    }
}

extension Weather {

    /// The conditions over a place at one moment, in plain units.
    ///
    /// A sketch usually reads one field at a time straight off the `Weather`.
    /// The whole reading is here for a sketch that keeps or compares them, and
    /// for building one by hand, to draw a sky without asking for it.
    public struct Reading: Hashable, Sendable {

        /// Where the reading is for. For a weather made by name this is the
        /// place the name resolved to.
        public var place: Place

        /// What the lookup calls the place ("Oaxaca City, Oaxaca, Mexico"), for
        /// a weather made by name. `nil` for one made from a place.
        public var name: String?

        /// When the conditions were measured.
        public var observedAt: Date

        /// Air temperature in degrees Celsius.
        public var temperature: Double

        /// What the temperature feels like, in degrees Celsius.
        public var apparentTemperature: Double

        /// Relative humidity, `0...1`.
        public var humidity: Double

        /// How much of the sky is cloud, `0...1`.
        public var cloudCover: Double

        /// Rain, showers, and melted snow in the last hour, in millimeters.
        public var precipitation: Double

        /// Snow in the last hour, in millimeters of snow.
        public var snowfall: Double

        /// Wind speed in meters per second.
        public var windSpeed: Double

        /// Where the wind blows from, in degrees clockwise from north.
        public var windDirection: Double

        /// The strongest gust in the last hour, in meters per second.
        public var windGusts: Double

        /// Air pressure at sea level, in hectopascals.
        public var pressure: Double

        /// Whether the sun is up.
        public var isDay: Bool

        /// The sky in a word.
        public var condition: Condition

        /// The condition as the World Meteorological Organization's code:
        /// 0 is clear, 61 to 65 rain from light to heavy, 95 a thunderstorm.
        public var code: Int

        /// Today's sunrise there, when the answer carried one.
        public var sunrise: Date?

        /// Today's sunset there, when the answer carried one.
        public var sunset: Date?

        /// Today's high, in degrees Celsius.
        public var highTemperature: Double?

        /// Today's low, in degrees Celsius.
        public var lowTemperature: Double?

        /// Height above sea level, in meters.
        public var elevation: Double?

        /// The place's own time zone.
        public var timeZone: TimeZone?

        public init(place: Place, name: String? = nil, observedAt: Date = Date(),
                    temperature: Double, apparentTemperature: Double? = nil,
                    humidity: Double = 0.5, cloudCover: Double = 0,
                    precipitation: Double = 0, snowfall: Double = 0,
                    windSpeed: Double = 0, windDirection: Double = 0, windGusts: Double? = nil,
                    pressure: Double = 1013.25, isDay: Bool = true,
                    condition: Condition = .clear, code: Int? = nil,
                    sunrise: Date? = nil, sunset: Date? = nil,
                    highTemperature: Double? = nil, lowTemperature: Double? = nil,
                    elevation: Double? = nil, timeZone: TimeZone? = nil) {
            self.place = place
            self.name = name
            self.observedAt = observedAt
            self.temperature = temperature
            self.apparentTemperature = apparentTemperature ?? temperature
            self.humidity = humidity
            self.cloudCover = cloudCover
            self.precipitation = precipitation
            self.snowfall = snowfall
            self.windSpeed = windSpeed
            self.windDirection = windDirection
            self.windGusts = windGusts ?? windSpeed
            self.pressure = pressure
            self.isDay = isDay
            self.condition = condition
            self.code = code ?? condition.code
            self.sunrise = sunrise
            self.sunset = sunset
            self.highTemperature = highTemperature
            self.lowTemperature = lowTemperature
            self.elevation = elevation
            self.timeZone = timeZone
        }
    }

    /// The sky in a word.
    ///
    /// An open set: the names below are the ones the forecast can say today,
    /// and a code it learns later still arrives, as `Condition(rawValue:)` with
    /// the code spelled out. The raw value is the word itself, so it can be
    /// drawn as it is.
    public struct Condition: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

        public let rawValue: String

        public init(rawValue: String) { self.rawValue = rawValue }

        public var description: String { rawValue }

        public static let clear = Condition(rawValue: "clear")
        public static let mostlyClear = Condition(rawValue: "mostly clear")
        public static let partlyCloudy = Condition(rawValue: "partly cloudy")
        public static let overcast = Condition(rawValue: "overcast")
        public static let fog = Condition(rawValue: "fog")
        public static let drizzle = Condition(rawValue: "drizzle")
        public static let freezingDrizzle = Condition(rawValue: "freezing drizzle")
        public static let rain = Condition(rawValue: "rain")
        public static let freezingRain = Condition(rawValue: "freezing rain")
        public static let snow = Condition(rawValue: "snow")
        public static let snowGrains = Condition(rawValue: "snow grains")
        public static let showers = Condition(rawValue: "showers")
        public static let snowShowers = Condition(rawValue: "snow showers")
        public static let thunderstorm = Condition(rawValue: "thunderstorm")
        public static let hail = Condition(rawValue: "thunderstorm with hail")

        /// The condition for a World Meteorological Organization weather code.
        public init(code: Int) {
            switch code {
            case 0: self = .clear
            case 1: self = .mostlyClear
            case 2: self = .partlyCloudy
            case 3: self = .overcast
            case 45, 48: self = .fog
            case 51, 53, 55: self = .drizzle
            case 56, 57: self = .freezingDrizzle
            case 61, 63, 65: self = .rain
            case 66, 67: self = .freezingRain
            case 71, 73, 75: self = .snow
            case 77: self = .snowGrains
            case 80, 81, 82: self = .showers
            case 85, 86: self = .snowShowers
            case 95: self = .thunderstorm
            case 96, 99: self = .hail
            default: self = Condition(rawValue: "weather code \(code)")
            }
        }

        /// The code the condition stands for, the moderate one where a
        /// condition spans several.
        public var code: Int {
            switch self {
            case .clear: 0
            case .mostlyClear: 1
            case .partlyCloudy: 2
            case .overcast: 3
            case .fog: 45
            case .drizzle: 53
            case .freezingDrizzle: 56
            case .rain: 63
            case .freezingRain: 66
            case .snow: 73
            case .snowGrains: 77
            case .showers: 81
            case .snowShowers: 85
            case .thunderstorm: 95
            case .hail: 96
            default: Int(rawValue.split(separator: " ").last ?? "") ?? -1
            }
        }

        /// Whether something is falling: drizzle, rain, snow, showers, a storm.
        public var isPrecipitating: Bool {
            switch self {
            case .drizzle, .freezingDrizzle, .rain, .freezingRain, .snow, .snowGrains,
                 .showers, .snowShowers, .thunderstorm, .hail: true
            default: false
            }
        }

        /// Whether what is falling is snow.
        public var isSnowing: Bool {
            switch self {
            case .snow, .snowGrains, .snowShowers: true
            default: false
            }
        }
    }
}
