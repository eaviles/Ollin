import Foundation

/// Pursuit: every runner heads straight at whoever it was told to run at, and
/// the paths they leave behind are the drawing.
///
/// The classic figure is a ring. Put runners on the corners of a regular
/// polygon, tell each one to chase the next, and start them together. Each
/// runner turns as its target moves, so nobody ever runs in a straight line.
/// The ring shrinks and turns at the same time, the runners meet in the middle,
/// and the four facts about that are exact rather than approximate:
///
/// - **The shape holds.** The ring stays a regular polygon at every step. It
///   only gets smaller and turns. That is true because every runner moves at
///   the same moment, off the positions everyone held before the step.
/// - **The path is a logarithmic spiral.** The angle between a runner's path
///   and the line to the center never changes. It stays at 90 degrees minus
///   `chasing * 180 / sides`.
/// - **The distance is known.** A runner that starts `radius` from the center
///   covers `radius / sin(chasing * pi / sides)` before it arrives. For a
///   square that is exactly one side of the square.
/// - **A fixed step never reaches the middle.** A runner covers the same
///   distance every step and overshoots a little each time, so it can never
///   come nearer the center than one stride times `cos(chasing * pi / sides)`.
///   The gap between neighbors falls to one stride at the circle of radius
///   `stride / (2 * sin(chasing * pi / sides))`, and a runner lands on its
///   target rather than running past it, so no chase ever goes further in
///   than that. `catchDistance` defaults to two strides, which calls it over
///   one ring earlier, before the last few steps stop going anywhere.
///
/// A runner that follows nobody holds its heading and runs straight. That is
/// how the other classic case is written, the one where a fast runner chases a
/// quarry crossing in front of it. From a square-on start, a pursuer of speed
/// 1 catches a quarry of speed `k` after `a / (1 - k * k)`, where `a` is the
/// gap they started with. At `k` of 1 or more it never catches at all.
///
/// Hold one and step it each frame, or run the whole chase in `setup()` and
/// draw the trails. Either way the product is geometry, ready for stroking,
/// hatching, shape booleans, and a pen plotter. Nothing here is random, so the
/// same start always runs the same chase.
///
/// ```swift
/// // The whole chase, worked out once:
/// let chase = Pursuit.ring(sides: 6, center: center, radius: 420)
/// chase.recordEvery = 8
/// chase.run()
///
/// // In draw():
/// noFill(); stroke(.white); strokeWeight(1)
/// for line in chase.web { drawPolyline(line.points) }
/// stroke(Color(hex: 0xE0724A)); strokeWeight(3)
/// for trail in chase.trails { drawPolyline(trail.points) }
/// ```
public final class Pursuit {

    /// One runner in the chase.
    public struct Runner: Equatable, Sendable {
        /// Where it stands now.
        public internal(set) var position: Vector2
        /// The index of the runner it follows. `nil` holds the heading, which
        /// is how a quarry that runs in a straight line is written.
        public var chases: Int?
        /// How far it covers per step, as a multiple of the chase's `stepSize`.
        /// A runner of speed 2 covers twice the ground of a runner of speed 1.
        public var speed: Double
        /// The way it faces now, as a unit vector. It only matters at the start
        /// when the chase has a `maxTurn`, since a runner that can turn freely
        /// faces its target again on the first step.
        public internal(set) var heading: Vector2
        /// Everywhere it has been, in order. The first point is where it began.
        public internal(set) var trail: [Vector2]
        /// The distance it has covered so far.
        public internal(set) var distanceTraveled: Double
        /// `true` once it has reached the runner it follows. It stops there.
        public internal(set) var hasArrived: Bool

        /// A runner at `position`. Give `chases` the index of the one it
        /// follows, or leave it out to make a quarry that runs straight.
        ///
        /// A `heading` of zero aims it at the one it follows, which is what you
        /// want unless you are starting a runner off facing the wrong way.
        public init(position: Vector2, chases: Int? = nil, speed: Double = 1,
                    heading: Vector2 = .zero) {
            self.position = position
            self.chases = chases
            self.speed = speed
            self.heading = heading
            self.trail = [position]
            self.distanceTraveled = 0
            self.hasArrived = false
        }

        /// A runner that follows the runner at `index`.
        public static func chasing(_ index: Int, from position: Vector2,
                                   speed: Double = 1) -> Runner {
            Runner(position: position, chases: index, speed: speed)
        }

        /// A quarry that follows nobody and runs straight along `heading`.
        public static func holding(_ heading: Vector2, from position: Vector2,
                                   speed: Double = 1) -> Runner {
            Runner(position: position, speed: speed, heading: heading)
        }
    }

    /// The runners, in the order they were given. Their indices are what
    /// `chases` points at.
    public private(set) var runners: [Runner]
    /// How many steps have been taken.
    public private(set) var stepsTaken = 0
    /// The chase lines kept along the way, every `recordEvery` steps, starting
    /// with the line-up you began with. Empty while `recordEvery` is 0.
    public private(set) var web: [Contour] = []

    /// The distance a runner of speed 1 covers in one step. Everything else
    /// about the chase is measured against it.
    public var stepSize: Double
    /// A runner this close to the one it follows has arrived and stops.
    /// Defaults to twice the step, for the reason in the type's own notes.
    public var catchDistance: Double
    /// The most a runner may turn in one step, in radians. `nil`, the default,
    /// lets it turn on the spot, which is the classic curve. A value makes a
    /// runner that swings wide and can overshoot, and 0 makes one that cannot
    /// turn at all.
    public var maxTurn: Double?
    /// Keep the chase lines into `web` every this many steps. 0 keeps none.
    public var recordEvery = 0

    /// A chase between `runners`, each one following the index it names.
    ///
    /// - Parameters:
    ///   - runners: who is running, and who each one follows.
    ///   - stepSize: how far a runner of speed 1 covers per step. Smaller
    ///     steps trace a finer curve and take longer to arrive.
    ///   - catchDistance: how close counts as arrived. Defaults to twice the
    ///     step, which is the smallest gap a fixed step can close on a ring.
    public init(runners: [Runner], stepSize: Double = 1, catchDistance: Double? = nil) {
        self.stepSize = stepSize
        self.catchDistance = catchDistance ?? stepSize * 2
        self.runners = runners
        for index in self.runners.indices {
            self.runners[index].heading = Pursuit.startingHeading(of: index, among: self.runners)
        }
    }

    /// Runners on the corners of a regular polygon, each chasing the one
    /// `chasing` places around the ring. This is the figure the whole idea is
    /// known by: the mice, the beetles, the four dogs.
    ///
    /// - Parameters:
    ///   - sides: how many runners, and so how many corners.
    ///   - center: the middle of the ring, where they will meet.
    ///   - radius: how far each runner starts from that middle.
    ///   - chasing: how many places ahead its target sits. 1 is the classic
    ///     ring. Half of `sides` sends everyone straight at the runner
    ///     opposite, with no spiral at all.
    ///   - speed: how fast they all run, as a multiple of `stepSize`.
    ///   - turn: the angle the ring starts turned by, in radians.
    ///   - stepSize: the distance per step. Defaults to a three-hundredth of
    ///     the radius, which draws a smooth spiral at canvas sizes.
    public static func ring(sides: Int, center: Vector2, radius: Double,
                            chasing: Int = 1, speed: Double = 1, turn: Double = 0,
                            stepSize: Double? = nil) -> Pursuit {
        let count = Swift.max(sides, 2)
        let ahead = Swift.min(Swift.max(chasing, 1), count - 1)
        let step = stepSize ?? Swift.max(radius, 1e-9) / 300
        let runners = (0 ..< count).map { index -> Runner in
            let angle = turn + Double(index) * 2 * .pi / Double(count)
            let corner = center + Vector2(cos(angle), sin(angle)) * radius
            return Runner(position: corner, chases: (index + ahead) % count, speed: speed)
        }
        return Pursuit(runners: runners, stepSize: step)
    }

    /// `true` once every runner that follows another has reached it. A chase
    /// of nothing but quarries is finished before it starts, since there is
    /// nobody left to arrive.
    public var isFinished: Bool {
        runners.allSatisfy { $0.chases == nil || $0.hasArrived }
    }

    /// Each runner's path so far, as an open contour.
    public var trails: [Contour] {
        runners.map { Contour($0.trail, closed: false) }
    }

    /// The chase lines as they stand now: one two-point contour per runner
    /// that follows another, drawn from the runner to its target. On a ring
    /// these are the sides of the polygon.
    public var links: [Contour] {
        runners.indices.compactMap { index in
            guard let target = target(of: index) else { return nil }
            return Contour([runners[index].position, runners[target].position], closed: false)
        }
    }

    /// Take `count` steps. Everybody moves at the same moment, off the
    /// positions they all held before the step, which is what keeps a ring a
    /// ring.
    public func step(_ count: Int = 1) {
        for _ in 0 ..< Swift.max(count, 0) { advance() }
    }

    /// Step until every chaser has arrived, or until `limit` steps have been
    /// taken, whichever comes first. A chase that can never end (a quarry as
    /// fast as the one behind it) stops at the limit.
    public func run(limit: Int = 100_000) {
        var taken = 0
        while !isFinished && taken < limit {
            advance()
            taken += 1
        }
    }

    // MARK: - The step

    private func advance() {
        guard !isFinished else { return }
        if recordEvery > 0, stepsTaken % recordEvery == 0 { web.append(contentsOf: links) }

        let before = runners
        for index in runners.indices where !runners[index].hasArrived {
            var runner = runners[index]
            if let target = target(of: index) {
                let toTarget = before[target].position - before[index].position
                let gap = toTarget.length
                if gap > 1e-12 {
                    runner.heading = turning(runner.heading, toward: toTarget / gap)
                }
                // A runner never runs past the one it caught, however fast it
                // is, so its own stride is a floor under the catch distance.
                if gap <= Swift.max(catchDistance, runner.speed * stepSize) {
                    runner.position = before[target].position
                    runner.distanceTraveled += gap
                    runner.trail.append(runner.position)
                    runner.hasArrived = true
                    runners[index] = runner
                    continue
                }
            }
            let covered = runner.speed * stepSize
            runner.position = before[index].position + runner.heading * covered
            runner.distanceTraveled += covered
            runner.trail.append(runner.position)
            runners[index] = runner
        }
        stepsTaken += 1
    }

    /// The index a runner follows, once it is checked: a runner chasing itself
    /// or an index nobody holds is a runner chasing nobody.
    private func target(of index: Int) -> Int? {
        guard let target = runners[index].chases,
              target != index, runners.indices.contains(target) else { return nil }
        return target
    }

    private func turning(_ heading: Vector2, toward wanted: Vector2) -> Vector2 {
        guard let maxTurn else { return wanted }
        let delta = heading.angle(to: wanted)
        if abs(delta) <= maxTurn { return wanted }
        return heading.rotated(by: delta < 0 ? -maxTurn : maxTurn)
    }

    private static func startingHeading(of index: Int, among runners: [Runner]) -> Vector2 {
        let given = runners[index].heading
        if given.lengthSquared > 1e-24 { return given.normalized }
        if let target = runners[index].chases, target != index,
           runners.indices.contains(target) {
            let toTarget = runners[target].position - runners[index].position
            if toTarget.lengthSquared > 1e-24 { return toTarget.normalized }
        }
        return .unitX
    }
}
