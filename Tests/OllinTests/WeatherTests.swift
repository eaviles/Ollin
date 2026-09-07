import Foundation
import Testing
@testable import Ollin

/// `Weather`: the forecast document read into a reading, the lookup of a
/// place by name, the two chained reads an export makes before `start()`
/// returns, and the sun's position computed from a place and a clock. Every
/// request is answered by the `StubServer` the feed suite drives, so nothing
/// here needs a socket, a server, or the sky.
///
/// Deliberately not `@MainActor`, for the reason the feed suites give: nothing
/// here may wait behind the drawing suites.
@Suite
struct WeatherTests {

    struct Timeout: Error {}

    /// Probes before reading the clock, so a starved test never gives up with
    /// the answer already in hand.
    func waitFor<T>(timeout: Double = 20.0, _ probe: () -> T?) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let value = probe() { return value }
            if Date() >= deadline { throw Timeout() }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// One forecast answer as the service writes it: local times, an offset,
    /// percentages, wind already in meters per second, snow in centimeters.
    static let forecast = #"""
    {"latitude":19.437609,"longitude":-99.10715,"generationtime_ms":0.18,
     "utc_offset_seconds":-21600,"timezone":"America/Mexico_City","elevation":2238.0,
     "current":{"time":"2026-09-06T17:45","interval":900,"temperature_2m":17.8,
       "relative_humidity_2m":73,"apparent_temperature":18.0,"is_day":1,
       "precipitation":0.10,"snowfall":0.20,"weather_code":51,"cloud_cover":98,
       "pressure_msl":1014.7,"wind_speed_10m":1.40,"wind_direction_10m":270,"wind_gusts_10m":5.20},
     "daily":{"time":["2026-09-06"],"sunrise":["2026-09-06T06:22"],"sunset":["2026-09-06T18:47"],
       "temperature_2m_max":[22.0],"temperature_2m_min":[13.2]}}
    """#

    /// The same sky a quarter hour later, unchanged but for the generation
    /// time the service stamps on every answer.
    static let forecastAgain = forecast.replacingOccurrences(of: "\"generationtime_ms\":0.18", with: "\"generationtime_ms\":0.31")

    static let lookup = #"""
    {"results":[{"id":3522507,"name":"Oaxaca City","latitude":17.06025,"longitude":-96.72544,
      "elevation":1571.0,"country_code":"MX","timezone":"America/Mexico_City","country":"Mexico",
      "admin1":"Oaxaca"}],"generationtime_ms":0.5}
    """#

    static let mexicoCity = Place(latitude: 19.4326, longitude: -99.1332)

    /// A weather whose forecast and lookup go to their own stub paths. The
    /// interval is far past any test's lifetime, so nothing fires behind an
    /// assertion; a test drives a second read with `refresh()`.
    func makeWeather(at place: Place? = WeatherTests.mexicoCity, in name: String? = nil,
                     forecast: String = WeatherTests.forecast, lookup: String = WeatherTests.lookup)
        -> (weather: Weather, forecastPath: String, lookupPath: String) {

        let forecastPath = StubServer.claimPath()
        let lookupPath = StubServer.claimPath()
        StubServer.answer(StubServer.Answer(body: forecast), at: forecastPath)
        StubServer.answer(StubServer.Answer(body: lookup), at: lookupPath)
        let weather = Weather(at: place, in: name, every: 100_000,
                              forecastAddress: "https://weather.test\(forecastPath)",
                              geocodingAddress: "https://weather.test\(lookupPath)",
                              answeredBy: [StubServer.self])
        return (weather, forecastPath, lookupPath)
    }

    // MARK: Reading the answer

    @Test func theDocumentReadsIntoAReadingInPlainUnits() throws {
        let json = try #require(JSON(data: Data(WeatherTests.forecast.utf8)))
        let reading = try #require(Weather.reading(from: json, at: WeatherTests.mexicoCity, name: nil, timeZone: nil))

        #expect(reading.temperature == 17.8)
        #expect(reading.apparentTemperature == 18.0)
        #expect(reading.humidity == 0.73)
        #expect(reading.cloudCover == 0.98)
        #expect(reading.precipitation == 0.1)
        #expect(abs(reading.snowfall - 2) < 1e-9)          // centimeters in, millimeters out
        #expect(reading.windSpeed == 1.4)
        #expect(reading.windDirection == 270)
        #expect(reading.windGusts == 5.2)
        #expect(reading.pressure == 1014.7)
        #expect(reading.isDay)
        #expect(reading.code == 51)
        #expect(reading.condition == .drizzle)
        #expect(reading.highTemperature == 22)
        #expect(reading.lowTemperature == 13.2)
        #expect(reading.elevation == 2238)
        #expect(reading.timeZone?.identifier == "America/Mexico_City")
        // The answer's own coordinates are the grid point it was read for.
        #expect(abs(reading.place.latitude - 19.437609) < 1e-9)
        #expect(abs(reading.place.longitude + 99.10715) < 1e-9)
    }

    @Test func localTimesBecomeInstantsThroughTheAnswersOffset() throws {
        let json = try #require(JSON(data: Data(WeatherTests.forecast.utf8)))
        let reading = try #require(Weather.reading(from: json, at: WeatherTests.mexicoCity, name: nil, timeZone: nil))

        // 17:45 at UTC-6 is 23:45 UTC.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let observed = utc.dateComponents([.hour, .minute], from: reading.observedAt)
        #expect(observed.hour == 23 && observed.minute == 45)
        let sunrise = utc.dateComponents([.day, .hour, .minute], from: try #require(reading.sunrise))
        #expect(sunrise.day == 6 && sunrise.hour == 12 && sunrise.minute == 22)
        let sunset = utc.dateComponents([.day, .hour, .minute], from: try #require(reading.sunset))
        #expect(sunset.day == 7 && sunset.hour == 0 && sunset.minute == 47)
    }

    @Test func aDocumentWithNoConditionsIsNotAReading() throws {
        let json = try #require(JSON(data: Data(#"{"latitude": 1, "current": {"time": "2026-09-06T17:45"}}"#.utf8)))
        #expect(Weather.reading(from: json, at: WeatherTests.mexicoCity, name: nil, timeZone: nil) == nil)
        #expect(Weather.date(from: "not a time", offsetSeconds: 0) == nil)
    }

    @Test func everyPublishedCodeHasAWord() {
        let expected: [Int: Weather.Condition] = [
            0: .clear, 1: .mostlyClear, 2: .partlyCloudy, 3: .overcast,
            45: .fog, 48: .fog, 51: .drizzle, 53: .drizzle, 55: .drizzle,
            56: .freezingDrizzle, 57: .freezingDrizzle, 61: .rain, 63: .rain, 65: .rain,
            66: .freezingRain, 67: .freezingRain, 71: .snow, 73: .snow, 75: .snow,
            77: .snowGrains, 80: .showers, 81: .showers, 82: .showers,
            85: .snowShowers, 86: .snowShowers, 95: .thunderstorm, 96: .hail, 99: .hail,
        ]
        for (code, condition) in expected {
            #expect(Weather.Condition(code: code) == condition, "code \(code)")
            // The word's own code maps back to the same word.
            #expect(Weather.Condition(code: condition.code) == condition, "code \(code)")
        }
        // A code the service learns later still arrives, as itself.
        let unknown = Weather.Condition(code: 42)
        #expect(unknown.rawValue == "weather code 42")
        #expect(unknown.code == 42)
        #expect(Weather.Condition.rain.isPrecipitating)
        #expect(!Weather.Condition.rain.isSnowing)
        #expect(Weather.Condition.snowShowers.isSnowing)
        #expect(!Weather.Condition.overcast.isPrecipitating)
        #expect("\(Weather.Condition.partlyCloudy)" == "partly cloudy")
    }

    @Test func theUrlAsksForEverythingTheReadingNeeds() {
        let weather = Weather(at: Place(latitude: 19.4326, longitude: -99.1332))
        let url = weather.forecastURL(for: weather.place!)
        #expect(url.hasPrefix("https://api.open-meteo.com/v1/forecast?"))
        #expect(url.contains("latitude=19.4326"))
        #expect(url.contains("longitude=-99.1332"))
        #expect(url.contains("wind_speed_unit=ms"))
        #expect(url.contains("timezone=auto"))
        for field in Weather.currentFields { #expect(url.contains(field), Comment(rawValue: field)) }
        #expect(url.contains("sunrise,sunset"))
        #expect(weather.geocodingURL(for: "Bath, Maine").contains("name=Bath,%20Maine"))
        // Politeness has a floor.
        #expect(Weather(at: weather.place!, every: 5).interval == 60)
    }

    // MARK: Asking

    @Test func aFixedPlaceReadsTheForecastAndCountsOnlyChanges() async throws {
        let (weather, forecastPath, lookupPath) = makeWeather()
        defer { weather.stop() }

        #expect(weather.reading == nil)
        #expect(weather.temperature == nil)
        #expect(weather.updateCount == 0)

        weather.start()
        let reading = try await waitFor { weather.reading }
        #expect(reading.condition == .drizzle)
        #expect(weather.temperature == 17.8)
        #expect(weather.cloudCover == 0.98)
        #expect(weather.isDay == true)
        #expect(weather.updateCount == 1)
        #expect(weather.problem == nil)
        #expect(weather.isRunning)
        // No name was given, so nothing was looked up.
        #expect(StubServer.asks(at: lookupPath).isEmpty)
        #expect(StubServer.asks(at: forecastPath).count == 1)

        // The same sky again, with a fresh generation stamp: the bytes differ
        // and the reading does not, so this is not an update.
        StubServer.answer(StubServer.Answer(body: WeatherTests.forecastAgain), at: forecastPath)
        weather.refresh()
        _ = try await waitFor { StubServer.asks(at: forecastPath).count >= 2 ? true : nil }
        _ = try await waitFor { weather.isWaiting ? nil : true }
        #expect(weather.updateCount == 1)

        // A change in the sky is.
        let warmer = WeatherTests.forecast.replacingOccurrences(of: "\"temperature_2m\":17.8", with: "\"temperature_2m\":21.5")
        StubServer.answer(StubServer.Answer(body: warmer), at: forecastPath)
        weather.refresh()
        _ = try await waitFor { weather.updateCount >= 2 ? true : nil }
        #expect(weather.temperature == 21.5)
    }

    @Test func aNameIsLookedUpFirstAndTheForecastAskedWhereItPoints() async throws {
        let (weather, forecastPath, lookupPath) = makeWeather(at: nil, in: "Oaxaca")
        defer { weather.stop() }
        #expect(weather.place == nil)
        #expect(weather.name == "Oaxaca")

        weather.start()
        let reading = try await waitFor { weather.reading }

        let lookups = StubServer.asks(at: lookupPath)
        #expect(lookups.count == 1)
        let forecasts = StubServer.asks(at: forecastPath)
        #expect(forecasts.count == 1)
        // The forecast was asked at the place the lookup found, not nowhere.
        #expect(reading.name == "Oaxaca City, Oaxaca, Mexico")
        #expect(reading.timeZone?.identifier == "America/Mexico_City")
        #expect(weather.problem == nil)
    }

    @Test func theForecastGoesToTheLookedUpCoordinates() async throws {
        // The stub keys on path alone, so the coordinates are checked through
        // the address the weather builds rather than the stub's record.
        let (weather, _, _) = makeWeather(at: nil, in: "Oaxaca")
        let url = weather.forecastURL(for: Place(latitude: 17.06025, longitude: -96.72544))
        #expect(url.contains("latitude=17.060"))
        #expect(url.contains("longitude=-96.725"))
    }

    @Test func aNameNothingMatchesSaysSo() async throws {
        let (weather, forecastPath, _) = makeWeather(at: nil, in: "Nowhere Particular",
                                                      lookup: #"{"generationtime_ms":0.4}"#)
        defer { weather.stop() }
        weather.start()
        let problem = try await waitFor { weather.problem }
        #expect(problem == "no place named Nowhere Particular")
        #expect(weather.reading == nil)
        #expect(StubServer.asks(at: forecastPath).isEmpty)
    }

    @Test func aFailureKeepsTheLastReadingAndSaysWhy() async throws {
        let (weather, forecastPath, _) = makeWeather()
        defer { weather.stop() }
        weather.start()
        _ = try await waitFor { weather.reading }

        StubServer.answer(StubServer.Answer(status: 503), at: forecastPath)
        weather.refresh()
        let problem = try await waitFor { weather.problem }
        #expect(problem == "the server answered 503")
        #expect(weather.temperature == 17.8)
        #expect(weather.failureCount == 1)
    }

    @Test func stopEndsBothReadsAndKeepsTheReading() async throws {
        let (weather, _, _) = makeWeather()
        weather.start()
        _ = try await waitFor { weather.reading }
        weather.stop()
        #expect(!weather.isRunning)
        #expect(weather.reading != nil)
        // A second start is a fresh run, not a no-op on a stopped one.
        weather.start()
        #expect(weather.isRunning)
        weather.stop()
    }

    // MARK: A reading by hand

    @Test func aReadingBuiltByHandFillsItsOwnGaps() {
        let reading = Weather.Reading(place: WeatherTests.mexicoCity, temperature: 24, condition: .rain)
        #expect(reading.apparentTemperature == 24)
        #expect(reading.windGusts == 0)
        #expect(reading.code == 63)
        #expect(reading.condition.isPrecipitating)
    }
}

/// The export contract. A headless drive owns the main thread, so that is
/// where a weather asks whether it is being exported, and `start()` only
/// believes the flag there. Its own suite, `@MainActor`, for the reasons the
/// feed's export suite gives: the suite above must touch the main actor
/// nowhere, and the flag set here is process-wide, so only a test that holds
/// the main thread may set it, and never across a suspension.
@Suite @MainActor
struct WeatherExportTests {

    private func makeWeather(at place: Place? = WeatherTests.mexicoCity, in name: String? = nil)
        -> (weather: Weather, forecastPath: String, lookupPath: String) {
        let forecastPath = StubServer.claimPath()
        let lookupPath = StubServer.claimPath()
        StubServer.answer(StubServer.Answer(body: WeatherTests.forecast), at: forecastPath)
        StubServer.answer(StubServer.Answer(body: WeatherTests.lookup), at: lookupPath)
        let weather = Weather(at: place, in: name, every: 100_000,
                              forecastAddress: "https://weather.test\(forecastPath)",
                              geocodingAddress: "https://weather.test\(lookupPath)",
                              answeredBy: [StubServer.self])
        return (weather, forecastPath, lookupPath)
    }

    /// A weather made for a name reads its lookup and then its forecast before
    /// `start()` returns, so `setup()` hands one sky to every frame.
    @Test func anExportReadsTheNameAndTheForecastBeforeStartReturns() {
        let (weather, forecastPath, lookupPath) = makeWeather(at: nil, in: "Oaxaca")
        defer { weather.stop() }

        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        weather.start()

        #expect(StubServer.asks(at: lookupPath).count == 1)
        #expect(StubServer.asks(at: forecastPath).count == 1)
        #expect(weather.reading?.name == "Oaxaca City, Oaxaca, Mexico")
        #expect(weather.temperature == 17.8)
        #expect(weather.updateCount == 1)
        #expect(weather.timeSinceUpdate == 0)
    }

    @Test func anExportOfAFixedPlaceReadsOnce() {
        let (weather, forecastPath, _) = makeWeather()
        defer { weather.stop() }

        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        weather.start()

        #expect(StubServer.asks(at: forecastPath).count == 1)
        #expect(weather.condition == .drizzle)
        #expect(weather.timeSinceUpdate == 0)
    }
}

/// `Place.sun(at:)`, checked against moments whose answer is known: the sun's
/// height at the minute a forecast calls sunrise, and where it stands at solar
/// noon on either side of the equator.
@Suite
struct SunPositionTests {

    func instant(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// How far apart two headings are, the short way round.
    func turn(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    @Test func theSunIsOnTheHorizonAtTheForecastsSunrise() {
        // Mexico City, 2026-09-06: the forecast says the sun rises at 06:22 and
        // sets at 18:47 local time, UTC-6. Sunrise is when the center of the
        // disc is about 0.83 degrees below the horizon; a forecast rounds to
        // the minute, which moves the height by a quarter degree.
        let place = Place(latitude: 19.4326, longitude: -99.1332)
        let rise = place.sun(at: instant(2026, 9, 6, 12, 22))
        #expect(abs(rise.elevation - -0.833) < 0.6, "sunrise elevation \(rise.elevation)")
        #expect(rise.azimuth > 70 && rise.azimuth < 100, "sunrise azimuth \(rise.azimuth)")
        #expect(!rise.isUp || rise.elevation < 0)

        let set = place.sun(at: instant(2026, 9, 7, 0, 47))
        #expect(abs(set.elevation - -0.833) < 0.6, "sunset elevation \(set.elevation)")
        #expect(set.azimuth > 260 && set.azimuth < 290, "sunset azimuth \(set.azimuth)")

        // A minute later than sunrise the sun is higher; a minute later than
        // sunset it is lower.
        #expect(place.sun(at: instant(2026, 9, 6, 12, 30)).elevation > rise.elevation)
        #expect(place.sun(at: instant(2026, 9, 7, 0, 55)).elevation < set.elevation)
    }

    @Test func atSolarNoonTheSunIsDueSouthNorthOfTheTropics() {
        // Greenwich on 2026-11-03, the day the equation of time peaks near
        // +16.4 minutes: solar noon is about 11:44 UTC, and the sun stands
        // due south, 90 degrees less the latitude plus the declination, about
        // 23.5 degrees up.
        let greenwich = Place(latitude: 51.4779, longitude: 0)
        let noon = greenwich.sun(at: instant(2026, 11, 3, 11, 44))
        #expect(turn(noon.azimuth, 180) < 0.6, "noon azimuth \(noon.azimuth)")
        #expect(abs(noon.elevation - 23.5) < 1, "noon elevation \(noon.elevation)")
        #expect(noon.isUp)

        // Half a day later it is well below the horizon, to the north.
        let midnight = greenwich.sun(at: instant(2026, 11, 3, 23, 44))
        #expect(midnight.elevation < -50)
        #expect(turn(midnight.azimuth, 0) < 2, "midnight azimuth \(midnight.azimuth)")
    }

    @Test func atSolarNoonTheSunIsDueNorthSouthOfTheTropics() {
        // Buenos Aires on 2026-09-06: solar noon is about 15:52 UTC (four
        // minutes of longitude per degree, less the equation of time), and
        // from there the sun stands to the north.
        let buenosAires = Place(latitude: -34.6037, longitude: -58.3816)
        let noon = buenosAires.sun(at: instant(2026, 9, 6, 15, 52))
        #expect(turn(noon.azimuth, 0) < 1.5, "noon azimuth \(noon.azimuth)")
        #expect(abs(noon.elevation - 49) < 1.5, "noon elevation \(noon.elevation)")
    }

    @Test func theAzimuthWalksEastToWestThroughTheDay() {
        let place = Place(latitude: 19.4326, longitude: -99.1332)
        let morning = place.sun(at: instant(2026, 9, 6, 15, 0)).azimuth    // 09:00 local
        let afternoon = place.sun(at: instant(2026, 9, 6, 21, 0)).azimuth  // 15:00 local
        #expect(morning > 60 && morning < 120, "morning \(morning)")
        #expect(afternoon > 240 && afternoon < 300, "afternoon \(afternoon)")
    }
}
