// Implementation of the C shim over the vendored Clipper2 library — see
// include/cclipper2.h and README.md in this directory.

#include "cclipper2.h"
#include "clipper2/clipper.h"

#include <new>

using namespace Clipper2Lib;

// Decimal digits Clipper2 keeps when it scales doubles to its int64 core.
// Canvas coordinates are points (thousands at most), so six digits leaves
// the scaled values far inside the int64 range while keeping curve and
// offset geometry exact well below a pixel.
static const int kPrecision = 6;

// How far a round join's arc may stray from the true circle, in points.
// Pinned explicitly so arc quality doesn't drift with the offset distance
// (the library's default scales with delta). A 50th of a point sits far
// under a pixel of anti-aliasing.
static const double kArcTolerance = 0.02;

// Offset results are simplified to this deviation (in points) before they
// return. Load-bearing for repeated offsets: each round join adds arc
// vertices, and feeding an offset back into another offset compounds them
// geometrically — a 300-point blob inset 14 times grew past 40,000 points
// and minutes per cascade. Pruning every vertex whose removal moves the
// outline less than a 100th of a point keeps cascades flat (and invisible
// at render scale).
static const double kSimplifyTolerance = 0.01;

struct CC2Solution {
    PathsD paths;
};

static PathsD makePaths(const double *xy, const int32_t *counts, int32_t pathCount)
{
    PathsD paths;
    if (xy == nullptr || counts == nullptr || pathCount <= 0) return paths;
    paths.reserve(static_cast<size_t>(pathCount));
    size_t cursor = 0;
    for (int32_t p = 0; p < pathCount; ++p) {
        PathD path;
        const size_t n = static_cast<size_t>(counts[p]);
        path.reserve(n);
        for (size_t i = 0; i < n; ++i) {
            path.emplace_back(xy[2 * cursor], xy[2 * cursor + 1]);
            ++cursor;
        }
        paths.push_back(std::move(path));
    }
    return paths;
}

static FillRule fillRule(CC2FillRule fill)
{
    return fill == CC2FillRuleNonZero ? FillRule::NonZero : FillRule::EvenOdd;
}

// Resolve a region to its boundary under its own fill rule (a subjects-only
// union), so self-overlaps and nesting are already decided before the two
// sides meet in one operation, which Clipper2 runs under a single rule.
static PathsD normalized(const PathsD &paths, CC2FillRule fill)
{
    if (paths.empty()) return paths;
    return Union(paths, fillRule(fill), kPrecision);
}

static CC2Solution *solutionFrom(PathsD &&paths)
{
    CC2Solution *solution = new (std::nothrow) CC2Solution;
    if (solution == nullptr) return nullptr;
    solution->paths = std::move(paths);
    return solution;
}

CC2Solution *cc2_boolean(CC2ClipType op,
                         const double *subjectXY, const int32_t *subjectCounts,
                         int32_t subjectPathCount, CC2FillRule subjectFill,
                         const double *clipXY, const int32_t *clipCounts,
                         int32_t clipPathCount, CC2FillRule clipFill)
{
    try {
        const PathsD subjects = normalized(makePaths(subjectXY, subjectCounts, subjectPathCount), subjectFill);
        const PathsD clips = normalized(makePaths(clipXY, clipCounts, clipPathCount), clipFill);
        ClipType type;
        switch (op) {
        case CC2ClipTypeIntersection: type = ClipType::Intersection; break;
        case CC2ClipTypeDifference: type = ClipType::Difference; break;
        case CC2ClipTypeXor: type = ClipType::Xor; break;
        default: type = ClipType::Union; break;
        }
        return solutionFrom(BooleanOp(type, FillRule::NonZero, subjects, clips, kPrecision));
    } catch (...) {
        return nullptr;
    }
}

CC2Solution *cc2_offset(const double *xy, const int32_t *counts, int32_t pathCount,
                        CC2FillRule fill, double delta, CC2JoinType join, double miterLimit)
{
    try {
        const PathsD paths = normalized(makePaths(xy, counts, pathCount), fill);
        JoinType joinType;
        switch (join) {
        case CC2JoinTypeBevel: joinType = JoinType::Bevel; break;
        case CC2JoinTypeRound: joinType = JoinType::Round; break;
        default: joinType = JoinType::Miter; break;
        }
        PathsD inflated = InflatePaths(paths, delta, joinType, EndType::Polygon,
                                       miterLimit, kPrecision, kArcTolerance);
        return solutionFrom(SimplifyPaths(inflated, kSimplifyTolerance, true));
    } catch (...) {
        return nullptr;
    }
}

CC2Solution *cc2_stroke(const double *xy, const int32_t *counts, int32_t pathCount,
                        double halfWidth, CC2JoinType join, CC2EndType end, double miterLimit)
{
    try {
        const PathsD paths = makePaths(xy, counts, pathCount);
        JoinType joinType;
        switch (join) {
        case CC2JoinTypeBevel: joinType = JoinType::Bevel; break;
        case CC2JoinTypeRound: joinType = JoinType::Round; break;
        default: joinType = JoinType::Miter; break;
        }
        EndType endType;
        switch (end) {
        case CC2EndTypeSquare: endType = EndType::Square; break;
        case CC2EndTypeRound: endType = EndType::Round; break;
        case CC2EndTypeJoined: endType = EndType::Joined; break;
        default: endType = EndType::Butt; break;
        }
        const PathsD inflated = InflatePaths(paths, halfWidth, joinType, endType,
                                             miterLimit, kPrecision, kArcTolerance);
        // A path that crosses itself thickens into an overlapping region;
        // union it under non-zero so the result is one clean boundary set.
        const PathsD unioned = Union(inflated, FillRule::NonZero, kPrecision);
        return solutionFrom(SimplifyPaths(unioned, kSimplifyTolerance, true));
    } catch (...) {
        return nullptr;
    }
}

int32_t cc2_solution_path_count(const CC2Solution *solution)
{
    return static_cast<int32_t>(solution->paths.size());
}

int32_t cc2_solution_path_size(const CC2Solution *solution, int32_t pathIndex)
{
    return static_cast<int32_t>(solution->paths[static_cast<size_t>(pathIndex)].size());
}

void cc2_solution_path_points(const CC2Solution *solution, int32_t pathIndex, double *outXY)
{
    const PathD &path = solution->paths[static_cast<size_t>(pathIndex)];
    for (size_t i = 0; i < path.size(); ++i) {
        outXY[2 * i] = path[i].x;
        outXY[2 * i + 1] = path[i].y;
    }
}

void cc2_solution_destroy(CC2Solution *solution)
{
    delete solution;
}
