import Foundation

public extension Installation {

    /// What the piece does at different times of day.
    ///
    /// A piece on a wall is in a building, and buildings have hours. Two things
    /// follow from that, and both are this one value:
    ///
    /// ```swift
    /// // The gallery is open from ten to six. Outside that the screen is dark
    /// // and the display is allowed to sleep.
    /// Installation(schedule: .open(from: 10, to: 18))
    ///
    /// // Or name the parts of the day, and let the piece read which one it is
    /// // in. Each part runs until the next one starts, and the last runs round
    /// // to the first.
    /// Installation(schedule: [.from(6, "dawn"), .from(10, "day"),
    ///                         .from(18, "dusk"), .from(22, "night")])
    /// ```
    ///
    /// The sketch reads the part it is in with ``Sketch/scheduledPeriod`` and
    /// ``Sketch/scheduledProgress``. That read works anywhere, at a desk as much
    /// as on a wall, so a piece that changes through the day can be worked on;
    /// going dark is the half that needs the installation, since only the piece
    /// that owns its window can take the screen away.
    struct Schedule: Sendable, Equatable, ExpressibleByArrayLiteral {

        /// The piece runs all day, every day. The default.
        public static let always = Schedule([])

        /// The parts of the day, in the order they start.
        public let periods: [Period]

        public init(_ periods: [Period]) {
            self.periods = periods.sorted { $0.start < $1.start }
        }

        public init(arrayLiteral elements: Period...) {
            self.init(elements)
        }

        /// Show the piece between these two times each day, and show nothing
        /// outside them. Opening hours, written the short way.
        public static func open(from: Time, to: Time) -> Schedule {
            Schedule([Period(from: from, "open"), .dark(from: to)])
        }

        // MARK: Reading it

        /// The part of the day `date` falls in, or `nil` when the schedule
        /// names no parts at all.
        ///
        /// A time before the first part of the day belongs to the last one,
        /// which started yesterday and has not ended yet. That is what makes a
        /// night that runs past midnight one part rather than two.
        public func period(at date: Date, calendar: Calendar = .current) -> Period? {
            guard !periods.isEmpty else { return nil }
            let now = Time(date, calendar: calendar)
            return periods.last { $0.start <= now } ?? periods.last
        }

        /// How far through its part of the day `date` is, from 0 at its start to
        /// 1 at the next one. Zero when the schedule names no parts.
        ///
        /// This is the dial for a piece that changes with the day rather than
        /// switching: a colour that warms towards evening, a pace that slows
        /// after dark.
        public func progress(at date: Date, calendar: Calendar = .current) -> Double {
            guard let current = period(at: date, calendar: calendar),
                  let index = periods.firstIndex(of: current)
            else { return 0 }
            let now = Time(date, calendar: calendar)
            let next = periods[(index + 1) % periods.count].start
            // A part of the day whose next start is its own start is the only
            // part there is, so it lasts the whole day rather than no time.
            let measured = Time.wrappedMinutes(from: current.start, to: next)
            let length = measured > 0 ? measured : 24 * 60
            return Double(Time.wrappedMinutes(from: current.start, to: now)) / Double(length)
        }

        /// Whether the piece is on screen at `date`.
        public func shows(at date: Date, calendar: Calendar = .current) -> Bool {
            period(at: date, calendar: calendar)?.shows ?? true
        }

        /// When the part of the day `date` falls in gives way to the next one,
        /// for the line in the log that says how long the piece will be dark.
        public func nextChange(at date: Date, calendar: Calendar = .current) -> Time? {
            guard let current = period(at: date, calendar: calendar),
                  let index = periods.firstIndex(of: current)
            else { return nil }
            return periods[(index + 1) % periods.count].start
        }

        // MARK: The pieces of it

        /// One part of the day: when it starts, what it is called, and whether
        /// there is anything on screen during it.
        public struct Period: Sendable, Equatable {

            /// When this part of the day begins.
            public var start: Time
            /// What the sketch reads while it is on. Yours to choose; a piece
            /// that only keeps opening hours never reads it.
            public var name: String
            /// Whether the piece is on screen during it. A part that shows
            /// nothing takes the picture away and lets the display sleep.
            public var shows: Bool

            public init(from start: Time, _ name: String, shows: Bool = true) {
                self.start = start
                self.name = name
                self.shows = shows
            }

            /// A part of the day with the piece on screen.
            public static func from(_ start: Time, _ name: String) -> Period {
                Period(from: start, name)
            }

            /// A part of the day with nothing on screen: the hours the building
            /// is shut.
            public static func dark(from start: Time) -> Period {
                Period(from: start, "dark", shows: false)
            }
        }

        /// A time of day, to the minute, in the machine's own time zone.
        ///
        /// Written as an hour where an hour is all it is (`18`), and as
        /// ``at(_:_:)`` where the minutes matter (`.at(18, 30)`).
        public struct Time: Sendable, Equatable, Comparable, ExpressibleByIntegerLiteral {

            public var hour: Int
            public var minute: Int

            /// A time of day, wrapped into one. Midnight can be said as either
            /// end of the day (`24` is `00:00`), and minutes past sixty carry
            /// into the hour rather than making a time the clock never reaches:
            /// every reading here compares minutes since midnight, so a time
            /// outside the day would simply never come round.
            public init(_ hour: Int, _ minute: Int = 0) {
                let day = 24 * 60
                let total = ((hour * 60 + minute) % day + day) % day
                self.hour = total / 60
                self.minute = total % 60
            }

            public init(integerLiteral hour: Int) {
                self.init(hour)
            }

            /// A time of day with minutes in it.
            public static func at(_ hour: Int, _ minute: Int = 0) -> Time {
                Time(hour, minute)
            }

            /// The clock time `date` reads, in the machine's own time zone.
            public init(_ date: Date, calendar: Calendar = .current) {
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                self.init(parts.hour ?? 0, parts.minute ?? 0)
            }

            /// Minutes since midnight, which is what the comparisons are made on.
            public var minutes: Int { hour * 60 + minute }

            public static func < (a: Time, b: Time) -> Bool { a.minutes < b.minutes }

            /// Minutes from one time to another, forward round the clock, so a
            /// stretch that runs past midnight measures as the hours it lasts
            /// rather than as a negative day. A time to itself is no minutes at
            /// all rather than a whole day, since the reading it is wanted for
            /// most is how far into a stretch a moment is.
            static func wrappedMinutes(from: Time, to: Time) -> Int {
                let span = to.minutes - from.minutes
                return span >= 0 ? span : span + 24 * 60
            }

            /// `09:30`, for the log.
            public var text: String { String(format: "%02d:%02d", hour, minute) }
        }
    }
}

public extension Sketch {

    /// The name of the part of the day the piece is in, from the
    /// ``Installation/Schedule`` it declared, or `nil` when it declared no
    /// parts.
    ///
    /// ```swift
    /// override func draw() {
    ///     background(scheduledPeriod == "night" ? Color(white: 0.04) : .white)
    /// }
    /// ```
    ///
    /// It reads the same at a desk as on a wall, so a piece that changes through
    /// the day can be worked on at any hour of it.
    var scheduledPeriod: String? {
        installation.schedule.period(at: Date())?.name
    }

    /// How far through its part of the day the piece is, from 0 at its start to
    /// 1 at the next one. Zero when the piece declared no parts.
    var scheduledProgress: Double {
        installation.schedule.progress(at: Date())
    }
}
