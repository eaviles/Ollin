// C shim over the vendored Clipper2 C++ library (see README.md in this
// directory). Exposes just the entry points Ollin's Shape booleans and
// offsetting need, as plain C, so Swift imports this header without C++
// interop. Paths cross the boundary flat: an interleaved x,y double array
// plus a per-path point count array.

#ifndef CCLIPPER2_H
#define CCLIPPER2_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum CC2ClipType {
    CC2ClipTypeUnion = 0,
    CC2ClipTypeIntersection = 1,
    CC2ClipTypeDifference = 2,
    CC2ClipTypeXor = 3
} CC2ClipType;

typedef enum CC2FillRule {
    CC2FillRuleEvenOdd = 0,
    CC2FillRuleNonZero = 1
} CC2FillRule;

typedef enum CC2JoinType {
    CC2JoinTypeMiter = 0,
    CC2JoinTypeBevel = 1,
    CC2JoinTypeRound = 2
} CC2JoinType;

typedef enum CC2EndType {
    CC2EndTypeButt = 0,
    CC2EndTypeSquare = 1,
    CC2EndTypeRound = 2,
    CC2EndTypeJoined = 3
} CC2EndType;

/// An opaque solution: the resulting set of closed paths. Outer boundaries
/// and holes are oppositely wound (non-zero fill reads them correctly).
typedef struct CC2Solution CC2Solution;

/// Boolean operation between two regions. Each side is normalized under its
/// own fill rule first, so a self-overlapping input resolves the way its
/// shape's winding says before the operation. Returns NULL on failure.
CC2Solution *_Nullable cc2_boolean(CC2ClipType op,
                                   const double *_Nullable subjectXY,
                                   const int32_t *_Nullable subjectCounts,
                                   int32_t subjectPathCount,
                                   CC2FillRule subjectFill,
                                   const double *_Nullable clipXY,
                                   const int32_t *_Nullable clipCounts,
                                   int32_t clipPathCount,
                                   CC2FillRule clipFill);

/// Offset (inflate/deflate) a region: positive delta grows it, negative
/// shrinks it. The input is normalized under its fill rule first, so holes
/// move opposite to outers. `miterLimit` caps a miter corner's spike (in
/// multiples of delta) before it falls back to a bevel. Returns NULL on
/// failure.
CC2Solution *_Nullable cc2_offset(const double *_Nullable xy,
                                  const int32_t *_Nullable counts,
                                  int32_t pathCount,
                                  CC2FillRule fill,
                                  double delta,
                                  CC2JoinType join,
                                  double miterLimit);

/// Stroke paths into a filled region: each path is thickened by `halfWidth`
/// on both sides. Open paths take `end` caps; pass CC2EndTypeJoined for a
/// closed path so the stroke runs all the way around it (a band). Unlike
/// cc2_offset the input is not normalized first (an open path must survive
/// as a path), and self-overlaps in the thickened result are unioned clean.
/// Returns NULL on failure.
CC2Solution *_Nullable cc2_stroke(const double *_Nullable xy,
                                  const int32_t *_Nullable counts,
                                  int32_t pathCount,
                                  double halfWidth,
                                  CC2JoinType join,
                                  CC2EndType end,
                                  double miterLimit);

int32_t cc2_solution_path_count(const CC2Solution *_Nonnull solution);
int32_t cc2_solution_path_size(const CC2Solution *_Nonnull solution, int32_t pathIndex);
/// Copies path `pathIndex` into `outXY` as interleaved x,y doubles
/// (`2 * cc2_solution_path_size(...)` values).
void cc2_solution_path_points(const CC2Solution *_Nonnull solution, int32_t pathIndex,
                              double *_Nonnull outXY);
void cc2_solution_destroy(CC2Solution *_Nonnull solution);

#ifdef __cplusplus
}
#endif

#endif /* CCLIPPER2_H */
