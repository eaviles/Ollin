// CJolt: Ollin's C bridge over the vendored Jolt Physics library.
// This header is the target's public surface: pure C, flat POD types, opaque
// handles. Swift imports this module only; the JPH C++ API never crosses it.
// See README.md in this directory for provenance and the update recipe.

#ifndef CJOLT_H
#define CJOLT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque world: owns the physics system, its allocators, and its job threads.
typedef struct CJoltWorld CJoltWorld;

/// Opaque constraint handle (joints and grabs).
typedef struct CJoltConstraint CJoltConstraint;

/// Body handle. `CJOLT_BODY_INVALID` means "no body"; passing it where a
/// constraint endpoint is expected anchors that end to the world.
typedef uint32_t CJoltBodyID;
#define CJOLT_BODY_INVALID 0xffffffffu

typedef enum {
    CJOLT_MOTION_STATIC = 0,
    CJOLT_MOTION_KINEMATIC = 1,
    CJOLT_MOTION_DYNAMIC = 2,
} CJoltMotionType;

typedef enum {
    CJOLT_SHAPE_BOX = 0,              // a, b, c = half extents
    CJOLT_SHAPE_SPHERE = 1,           // a = radius
    CJOLT_SHAPE_CAPSULE = 2,          // a = cylinder half height, b = radius
    CJOLT_SHAPE_CYLINDER = 3,         // a = half height, b = radius
    CJOLT_SHAPE_CONVEX_HULL = 4,      // points/pointCount
    CJOLT_SHAPE_MESH = 5,             // points + indices (static bodies only)
    CJOLT_SHAPE_TAPERED_CAPSULE = 6,  // a = cap-center half height, b = top radius, c = bottom radius (both > 0)
    CJOLT_SHAPE_TAPERED_CYLINDER = 7, // a = half height, b = top radius, c = bottom radius (a cone at b = 0)
    CJOLT_SHAPE_HEIGHT_FIELD = 8,     // heights/sampleCount + fieldOffset/fieldScale (static bodies only)
    CJOLT_SHAPE_COMPOUND = 9,         // children/childCount
} CJoltShapeType;

typedef struct CJoltShapeDesc CJoltShapeDesc;

/// One child of a compound shape: a shape at a fixed local pose inside the
/// body. Children may themselves be compounds (the tree is built recursively).
typedef struct {
    const CJoltShapeDesc *shape;
    float position[3];
    float rotation[4]; // quaternion x, y, z, w (identity = 0,0,0,1)
} CJoltShapeChild;

struct CJoltShapeDesc {
    CJoltShapeType type;
    float a, b, c;
    /// Hull/mesh vertices as xyz triples; pointCount is the vertex count.
    const float *points;
    int32_t pointCount;
    /// Mesh triangle indices, 3 per triangle; indexCount is the index count.
    const uint32_t *indices;
    int32_t indexCount;
    /// Height-field samples: sampleCount * sampleCount heights, row major with
    /// the row index running along +z. The surface is
    /// fieldOffset + fieldScale * (x, heights[z * sampleCount + x], z);
    /// sampleCount must be a multiple of 2 (a power of 2 stores best).
    const float *heights;
    int32_t sampleCount;
    float fieldOffset[3];
    float fieldScale[3];
    /// Compound children (used when type is CJOLT_SHAPE_COMPOUND).
    const CJoltShapeChild *children;
    int32_t childCount;
    /// kg/m³ for dynamic mass; <= 0 uses the library default (1000).
    float density;
};

typedef struct {
    CJoltShapeDesc shape;
    float position[3];
    float rotation[4]; // quaternion x, y, z, w (identity = 0,0,0,1)
    CJoltMotionType motion;
    float friction;       // >= 0
    float restitution;    // 0...1
    float linearDamping;  // >= 0
    float angularDamping; // >= 0
    float gravityFactor;  // 1 = normal gravity
    bool allowSleep;
    /// A detector volume: it reports overlaps through the contact buffer but
    /// never pushes anything and is never pushed. Overrides `motion` (a sensor
    /// is kinematic and stays awake, so bodies asleep inside one keep
    /// reporting) and lands in its own object layer, which pairs only with
    /// moving bodies.
    bool isSensor;
} CJoltBodyDesc;

typedef enum {
    CJOLT_CONSTRAINT_HINGE = 0,    // anchorA + axis; optional angular limits
    CJOLT_CONSTRAINT_POINT = 1,    // anchorA (ball-and-socket)
    CJOLT_CONSTRAINT_DISTANCE = 2, // anchorA on A, anchorB on B; limits = min/max distance
    CJOLT_CONSTRAINT_SLIDER = 3,   // anchorA + axis; optional translation limits
    CJOLT_CONSTRAINT_FIXED = 4,    // weld at current relative pose
} CJoltConstraintType;

typedef struct {
    CJoltConstraintType type;
    float anchorA[3]; // world space
    float anchorB[3]; // world space (distance only)
    float axis[3];    // world space (hinge/slider)
    bool hasLimits;
    float limitMin, limitMax; // hinge: radians; slider: length; distance: min/max
    /// Distance-constraint spring; frequency <= 0 keeps the limits rigid.
    float frequency, damping;
} CJoltConstraintDesc;

// World ---------------------------------------------------------------------

/// Creates a world. `maxBodies` bounds the body count for the world's life.
CJoltWorld *cjolt_world_create(float gravityX, float gravityY, float gravityZ,
                               uint32_t maxBodies);
void cjolt_world_destroy(CJoltWorld *world);
void cjolt_world_set_gravity(CJoltWorld *world, float x, float y, float z);
/// Advances the simulation. Returns 0 on success (a nonzero value reports the
/// library's update-error bits, e.g. an overflowed manifold cache).
int cjolt_world_step(CJoltWorld *world, float dt, int collisionSteps);
/// Rebuilds the broad-phase tree; call after inserting many static bodies.
void cjolt_world_optimize(CJoltWorld *world);

// Bodies --------------------------------------------------------------------

CJoltBodyID cjolt_body_create(CJoltWorld *world, const CJoltBodyDesc *desc);
void cjolt_body_destroy(CJoltWorld *world, CJoltBodyID body);

void cjolt_body_get_position(const CJoltWorld *world, CJoltBodyID body, float out[3]);
void cjolt_body_get_rotation(const CJoltWorld *world, CJoltBodyID body, float out[4]);
/// Writes the body's world transform as a column-major 4x4 matrix.
void cjolt_body_get_transform(const CJoltWorld *world, CJoltBodyID body, float out[16]);
void cjolt_body_set_position(CJoltWorld *world, CJoltBodyID body, const float pos[3],
                             bool activate);
void cjolt_body_set_rotation(CJoltWorld *world, CJoltBodyID body, const float quat[4],
                             bool activate);
void cjolt_body_get_linear_velocity(const CJoltWorld *world, CJoltBodyID body, float out[3]);
void cjolt_body_set_linear_velocity(CJoltWorld *world, CJoltBodyID body, const float v[3]);
void cjolt_body_get_angular_velocity(const CJoltWorld *world, CJoltBodyID body, float out[3]);
void cjolt_body_set_angular_velocity(CJoltWorld *world, CJoltBodyID body, const float v[3]);
void cjolt_body_add_force(CJoltWorld *world, CJoltBodyID body, const float force[3]);
void cjolt_body_add_force_at(CJoltWorld *world, CJoltBodyID body, const float force[3],
                             const float worldPoint[3]);
void cjolt_body_add_impulse(CJoltWorld *world, CJoltBodyID body, const float impulse[3]);
void cjolt_body_add_torque(CJoltWorld *world, CJoltBodyID body, const float torque[3]);
/// Drives a kinematic body toward a target pose over `dt` seconds.
void cjolt_body_move_kinematic(CJoltWorld *world, CJoltBodyID body, const float pos[3],
                               const float quat[4], float dt);
/// The body's mass in kg (0 for static and kinematic bodies).
float cjolt_body_get_mass(const CJoltWorld *world, CJoltBodyID body);
/// Switches a body between static, kinematic, and dynamic.
void cjolt_body_set_motion(CJoltWorld *world, CJoltBodyID body, CJoltMotionType motion);
bool cjolt_body_is_active(const CJoltWorld *world, CJoltBodyID body);
void cjolt_body_activate(CJoltWorld *world, CJoltBodyID body);
void cjolt_body_set_friction(CJoltWorld *world, CJoltBodyID body, float friction);
void cjolt_body_set_restitution(CJoltWorld *world, CJoltBodyID body, float restitution);
void cjolt_body_set_gravity_factor(CJoltWorld *world, CJoltBodyID body, float factor);

// Constraints ---------------------------------------------------------------

/// Connects two bodies (either may be CJOLT_BODY_INVALID for the world).
/// Returns NULL if a body handle is stale or the description is unusable.
CJoltConstraint *cjolt_constraint_create(CJoltWorld *world, CJoltBodyID bodyA,
                                         CJoltBodyID bodyB,
                                         const CJoltConstraintDesc *desc);
void cjolt_constraint_destroy(CJoltWorld *world, CJoltConstraint *constraint);

typedef enum {
    CJOLT_MOTOR_OFF = 0,
    CJOLT_MOTOR_VELOCITY = 1,
    CJOLT_MOTOR_POSITION = 2,
} CJoltMotorState;

/// Powers a hinge or slider motor (a no-op on the other constraint kinds) and
/// wakes both bodies. `target` is rad/s (hinge) or m/s (slider) for a velocity
/// motor, radians or meters for a position motor. `frequency` (Hz) and
/// `damping` (ratio) shape the position servo's spring; a velocity motor
/// ignores them. `maxEffort` caps the torque (N·m) or force (N) the motor may
/// apply; a non-finite or non-positive value leaves it unlimited.
void cjolt_constraint_set_motor(CJoltWorld *world, CJoltConstraint *constraint,
                                CJoltMotorState state, float target,
                                float frequency, float damping, float maxEffort);

/// Passive resistance while a hinge/slider motor is off: a drag torque (N·m)
/// or force (N) the joint's motion must overcome.
void cjolt_constraint_set_friction(CJoltWorld *world, CJoltConstraint *constraint,
                                   float friction);

/// Softens a hinge/slider's limits: past an end a spring at `frequency`/
/// `damping` pulls back instead of a hard stop. `frequency` <= 0 restores the
/// hard stop.
void cjolt_constraint_set_limit_spring(CJoltWorld *world, CJoltConstraint *constraint,
                                       float frequency, float damping);

/// The hinge's current angle (radians) or the slider's current offset (meters)
/// relative to the pose the constraint was created at; 0 for other kinds.
float cjolt_constraint_current(const CJoltWorld *world, const CJoltConstraint *constraint);

// Grab (mouse drag) ---------------------------------------------------------

/// Hangs `body` on a soft drag spring anchored at a world-space point.
CJoltConstraint *cjolt_grab_begin(CJoltWorld *world, CJoltBodyID body,
                                  const float worldPoint[3]);
/// Moves the grab anchor to a world-space target.
void cjolt_grab_move(CJoltWorld *world, CJoltConstraint *grab, const float target[3]);
void cjolt_grab_end(CJoltWorld *world, CJoltConstraint *grab);

// Contacts ------------------------------------------------------------------

typedef enum {
    CJOLT_CONTACT_BEGAN = 0,
    CJOLT_CONTACT_ENDED = 1,
} CJoltContactPhase;

/// One touch event between two bodies, buffered during a step. Events are per
/// *body pair*: the shapes of a compound or the triangles of a mesh may touch
/// in many places, but a pair reports one began when the first of them lands
/// and one ended when the last of them lifts.
typedef struct {
    CJoltContactPhase phase;
    /// The pair, always ordered so `bodyA` < `bodyB`.
    CJoltBodyID bodyA, bodyB;
    /// Where they touched, in world space (zero for an ended event: the
    /// solver reports only the pair once a contact is gone).
    float point[3];
    /// Unit normal pointing from `bodyA` toward `bodyB` (zero when ended).
    float normal[3];
    /// Closing speed along the normal at the moment of touch, in m/s, before
    /// the solver answers the collision; 0 when ended.
    float speed;
} CJoltContactEvent;

/// How many contact events are buffered from the last step.
int32_t cjolt_world_contact_count(const CJoltWorld *world);

/// Copies up to `capacity` buffered events into `out` and empties the buffer.
/// Events come out in a fixed order (by pair, then phase) rather than the
/// order the solver's worker threads happened to record them, so a replay of
/// the same simulation reads the same list. Returns how many were written.
int32_t cjolt_world_drain_contacts(CJoltWorld *world, CJoltContactEvent *out,
                                   int32_t capacity);

// Queries -------------------------------------------------------------------

/// Casts a ray (direction scaled by length) against the moving bodies.
/// Sensors are transparent to it. On a hit, writes the body and the fraction
/// along the ray.
bool cjolt_world_ray_cast(const CJoltWorld *world, const float origin[3],
                          const float direction[3], CJoltBodyID *outBody,
                          float *outFraction);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // CJOLT_H
