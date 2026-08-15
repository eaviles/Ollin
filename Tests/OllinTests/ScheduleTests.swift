import Foundation
import Testing
@testable import Ollin

/// Probes for a piece that keeps hours.
///
/// The whole feature is one reading: given a moment, which part of the day is
/// this, and is the piece on screen during it. Everything the host does hangs
/// off that answer, and the answer is arithmetic on a clock, so it is checked
/// here against the hours where clock arithmetic goes wrong: the stretch that
/// runs past midnight, and the small hours before the first part of the day
/// begins.
@Suite
struct ScheduleTests {

    /// A fixed calendar, so the reading under test is the schedule's rather than
    /// the machine's time zone.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func moment(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 15,
                                           hour: hour, minute: minute))!
    }

    // MARK: Nothing declared

    @Test func aPieceWithNoScheduleIsAlwaysOn() {
        let schedule = Installation.Schedule.always
        #expect(schedule.period(at: moment(3), calendar: calendar) == nil)
        #expect(schedule.shows(at: moment(3), calendar: calendar))
        #expect(schedule.progress(at: moment(3), calendar: calendar) == 0)
        #expect(Installation.on.schedule == .always)
    }

    // MARK: Opening hours

    @Test func openingHoursShowThePieceBetweenThem() {
        let schedule = Installation.Schedule.open(from: 10, to: 18)
        #expect(!schedule.shows(at: moment(9, 59), calendar: calendar))
        #expect(schedule.shows(at: moment(10, 0), calendar: calendar))
        #expect(schedule.shows(at: moment(17, 59), calendar: calendar))
        #expect(!schedule.shows(at: moment(18, 0), calendar: calendar))
    }

    /// The hours that break a schedule read as a list: two in the morning is
    /// before every part of the day starts, and it belongs to the one that
    /// began last night and has not ended. Read as "the first part that has not
    /// started yet", the piece would come on at midnight in an empty building.
    @Test func theSmallHoursBelongToLastNight() {
        let schedule = Installation.Schedule.open(from: 10, to: 18)
        #expect(!schedule.shows(at: moment(2), calendar: calendar))
        #expect(!schedule.shows(at: moment(0, 0), calendar: calendar))
        #expect(schedule.period(at: moment(2), calendar: calendar)?.shows == false)
    }

    @Test func aScheduleOpenAtMidnightIsOnThroughIt() {
        let schedule = Installation.Schedule.open(from: 0, to: 6)
        #expect(schedule.shows(at: moment(0), calendar: calendar))
        #expect(schedule.shows(at: moment(5, 59), calendar: calendar))
        #expect(!schedule.shows(at: moment(6), calendar: calendar))
        #expect(!schedule.shows(at: moment(23), calendar: calendar))
    }

    // MARK: Parts of the day

    private var day: Installation.Schedule {
        [.from(6, "dawn"), .from(10, "day"), .from(18, "dusk"), .from(22, "night")]
    }

    @Test func eachPartRunsUntilTheNextOne() {
        #expect(day.period(at: moment(6), calendar: calendar)?.name == "dawn")
        #expect(day.period(at: moment(9, 59), calendar: calendar)?.name == "dawn")
        #expect(day.period(at: moment(10), calendar: calendar)?.name == "day")
        #expect(day.period(at: moment(18, 1), calendar: calendar)?.name == "dusk")
        #expect(day.period(at: moment(21), calendar: calendar)?.name == "dusk")
        #expect(day.period(at: moment(22), calendar: calendar)?.name == "night")
    }

    /// The night runs past midnight, which is the one part of a day that a list
    /// of start times cannot express by itself.
    @Test func aNightRunsPastMidnight() {
        #expect(day.period(at: moment(23, 30), calendar: calendar)?.name == "night")
        #expect(day.period(at: moment(0, 1), calendar: calendar)?.name == "night")
        #expect(day.period(at: moment(5, 59), calendar: calendar)?.name == "night")
    }

    /// Written in any order, read in the right one.
    @Test func thePartsSortThemselves() {
        let jumbled: Installation.Schedule = [.from(22, "night"), .from(6, "dawn"),
                                              .from(10, "day"), .from(18, "dusk")]
        #expect(jumbled == day)
        #expect(jumbled.period(at: moment(0, 30), calendar: calendar)?.name == "night")
    }

    // MARK: How far through

    @Test func progressRunsFromOneStartToTheNext() {
        #expect(abs(day.progress(at: moment(6), calendar: calendar)) < 0.001)
        #expect(abs(day.progress(at: moment(8), calendar: calendar) - 0.5) < 0.001)
        #expect(abs(day.progress(at: moment(9, 59), calendar: calendar) - 1) < 0.01)
    }

    /// The same measurement across midnight: the night is eight hours long, and
    /// two in the morning is halfway through it.
    @Test func progressCrossesMidnightToo() {
        #expect(abs(day.progress(at: moment(2), calendar: calendar) - 0.5) < 0.001)
        #expect(abs(day.progress(at: moment(22), calendar: calendar)) < 0.001)
    }

    /// One part of the day is the whole day, not a moment of it.
    @Test func aSinglePartLastsAllDay() {
        let all: Installation.Schedule = [.from(0, "all day")]
        #expect(all.progress(at: moment(0), calendar: calendar) == 0)
        #expect(abs(all.progress(at: moment(12), calendar: calendar) - 0.5) < 0.001)
        #expect(all.nextChange(at: moment(12), calendar: calendar) == 0)
    }

    // MARK: Times of day

    @Test func anHourOnItsOwnIsATimeOfDay() {
        let ten: Installation.Schedule.Time = 10
        #expect(ten == .at(10, 0))
        #expect(Installation.Schedule.Time.at(9, 30).minutes == 570)
        #expect(Installation.Schedule.Time.at(9, 30) < 10)
        #expect(Installation.Schedule.Time.at(9, 30).text == "09:30")
    }

    /// A time outside the day would never come round, since every reading
    /// compares minutes since midnight. So one is wrapped into the day instead
    /// of sitting there as a part that never starts.
    @Test func aTimeOutsideTheDayIsWrappedIntoIt() {
        #expect(Installation.Schedule.Time.at(24) == 0)
        #expect(Installation.Schedule.Time.at(25, 30) == .at(1, 30))
        #expect(Installation.Schedule.Time.at(9, 90) == .at(10, 30))
        #expect(Installation.Schedule.Time.at(-1) == 23)
    }

    @Test func theNextChangeIsWhenTheNextPartStarts() {
        #expect(day.nextChange(at: moment(7), calendar: calendar) == 10)
        #expect(day.nextChange(at: moment(23), calendar: calendar) == 6)   // round to tomorrow
        #expect(Installation.Schedule.always.nextChange(at: moment(7), calendar: calendar) == nil)
    }

    // MARK: What the sketch reads

    /// The read works at a desk as much as on a wall, so a piece that changes
    /// through the day can be worked on at any hour of it. Checked with a
    /// schedule of one part, which reads the same whenever the test runs.
    @Test @MainActor func aSketchReadsThePartOfTheDayItIsIn() {
        final class Keeper: Sketch {
            override var installation: Installation {
                Installation(schedule: [.from(0, "all day")])
            }
        }
        final class Plain: Sketch {}
        #expect(Keeper().scheduledPeriod == "all day")
        #expect((0...1).contains(Keeper().scheduledProgress))
        #expect(Plain().scheduledPeriod == nil)
        #expect(Plain().scheduledProgress == 0)
    }
}
