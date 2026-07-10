import Ollin

/// Maze generation, three textures: the walls of a perfect maze stroke as
/// clean merged line-work while its longest corridor-to-corridor path traces
/// itself through. Each re-roll cycles the carving algorithm, and the
/// difference is the point: `.backtracker` wanders in long rivers, `.kruskal`
/// scatters short dead ends everywhere, `.wilson` samples every possible maze
/// with no bias at all.
@main
final class MazePaths: Sketch {
    private let algorithms: [(Maze.Algorithm, String)] = [
        (.backtracker, "recursive backtracker"),
        (.kruskal, "kruskal"),
        (.wilson, "wilson"),
    ]

    override func draw() {
        let framesPerRoll = 260
        let roll = frameCount / framesPerRoll
        seed(roll + 5)
        let (algorithm, name) = algorithms[roll % algorithms.count]

        background(Color(hex: 0x101318))
        let rect = bounds.inset(by: .all(70 * scale))
        let maze = maze(columns: 21, rows: 21, algorithm: algorithm)

        stroke(Color(hex: 0xD8DEE9))
        strokeWeight(5 * scale)
        strokeCap(.round)
        drawMaze(maze, in: rect)

        // The longest path in the maze, revealed over the roll.
        let route = maze.contour(of: maze.longestPath(), in: rect)
        let progress = Double(frameCount % framesPerRoll) / Double(framesPerRoll - 40)
        let visible = Int(Double(route.points.count) * min(1, progress))
        if visible > 1 {
            stroke(Color(hex: 0xF6511D))
            strokeWeight(7 * scale)
            drawPolyline(Array(route.points.prefix(visible)), closed: false)
            fill(Color(hex: 0xF6511D))
            noStroke()
            drawCircle(center: route.points[visible - 1], radius: 9 * scale)
        }

        drawCaption(name)
    }
}
