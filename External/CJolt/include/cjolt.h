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

/// A collision group: a small index every body, character, vehicle, ragdoll,
/// and soft body carries, plus a symmetric table on the world saying which
/// pairs of groups touch. Group 0 is the default one everything starts in, and
/// a world whose table is untouched behaves exactly as one with no groups at
/// all. Indices past `CJOLT_MAX_GROUPS - 1` are rejected by the table calls.
///
/// The group rides in the *object layer*, which is the one thing the library
/// consults everywhere a pair can meet: finding collision pairs (so the contact
/// listener never hears a filtered touch), the query filters, the character's
/// own sweep filters, the wheel collision testers, and the soft-body pass. A
/// per-body collision group would only have reached the narrow phase, and that
/// slot is already spoken for by the filter that keeps one ragdoll's limbs from
/// fighting each other.
#define CJOLT_MAX_GROUPS 64

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
    /// Total mass in kg, overriding what the shape and density would give;
    /// <= 0 computes it from the shape. Ignored by non-dynamic bodies.
    float mass;
    /// Where the center of mass sits relative to the shape's origin, in the
    /// body's local space. Lowering it is what keeps a tall body (a car on its
    /// suspension) from rolling over. The body's reported position stays the
    /// shape origin, so drawing is unaffected.
    float centerOfMass[3];
    bool allowSleep;
    /// A detector volume: it reports overlaps through the contact buffer but
    /// never pushes anything and is never pushed. Overrides `motion` (a sensor
    /// is kinematic and stays awake, so bodies asleep inside one keep
    /// reporting) and lands in its own object layer, which pairs only with
    /// moving bodies.
    bool isSensor;
    /// Which collision group the body is in; 0 is the default group.
    int32_t group;
    /// Which of the six degrees of freedom the body may use, as a mask of
    /// CJOLT_FREEDOM_* bits. 0 means all six (so a zeroed descriptor keeps the
    /// unrestricted default); a mask with no translation and no rotation bit
    /// is rejected the same way.
    uint32_t freedom;
    /// Sweep the body's shape along its path each step instead of only testing
    /// where it lands, so a small quick body cannot pass through a thin wall
    /// between one step and the next. Costs nothing while the body moves less
    /// than about three quarters of its own inner radius per step.
    bool continuous;
} CJoltBodyDesc;

/// The six degrees of freedom a body may be restricted to, in world axes.
enum {
    CJOLT_FREEDOM_MOVE_X = 0x01,
    CJOLT_FREEDOM_MOVE_Y = 0x02,
    CJOLT_FREEDOM_MOVE_Z = 0x04,
    CJOLT_FREEDOM_TURN_X = 0x08,
    CJOLT_FREEDOM_TURN_Y = 0x10,
    CJOLT_FREEDOM_TURN_Z = 0x20,
    CJOLT_FREEDOM_ALL = 0x3f,
};

typedef enum {
    CJOLT_CONSTRAINT_HINGE = 0,    // anchorA + axis; optional angular limits
    CJOLT_CONSTRAINT_POINT = 1,    // anchorA (ball-and-socket)
    CJOLT_CONSTRAINT_DISTANCE = 2, // anchorA on A, anchorB on B; limits = min/max distance
    CJOLT_CONSTRAINT_SLIDER = 3,   // anchorA + axis; optional translation limits
    CJOLT_CONSTRAINT_FIXED = 4,    // weld at current relative pose
    CJOLT_CONSTRAINT_SWING_TWIST = 5, // anchorA + axis; cone + twist limits
} CJoltConstraintType;

typedef struct {
    CJoltConstraintType type;
    float anchorA[3]; // world space
    float anchorB[3]; // world space (distance only)
    float axis[3];    // world space (hinge/slider/swing-twist twist axis)
    bool hasLimits;
    float limitMin, limitMax; // hinge/swing-twist: radians; slider: length; distance: min/max
    /// Distance-constraint spring; frequency <= 0 keeps the limits rigid.
    float frequency, damping;
    /// Swing-twist only: the half angle of the cone the twist axis may swing
    /// inside, in radians (0 locks the swing, pi frees it).
    float coneAngle;
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

/// Sets whether two collision groups collide. Symmetric: setting (a, b) sets
/// (b, a) with it. Passing one group twice says whether that group collides
/// with itself. Out-of-range indices are ignored. Takes effect on the next
/// step; a pair already touching is separated then.
void cjolt_world_set_group_collision(CJoltWorld *world, int32_t groupA,
                                     int32_t groupB, bool collide);

/// Whether two collision groups currently collide (true for anything
/// out of range, which is what an unfiltered world answers).
bool cjolt_world_group_collision(const CJoltWorld *world, int32_t groupA,
                                 int32_t groupB);

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
float cjolt_body_get_gravity_factor(const CJoltWorld *world, CJoltBodyID body);
/// Restricts which degrees of freedom the body may use (a mask of
/// CJOLT_FREEDOM_* bits; 0 means all six). The solver stores the restriction
/// inside the body's mass properties, so this re-derives the inverse mass and
/// inertia: `mass` is the body's own mass in kg, used because a body whose
/// translation was locked reports an inverse mass of zero and cannot say what
/// it weighed; pass <= 0 to take the shape's own. Wakes the body, whose
/// equilibrium has just changed under it.
void cjolt_body_set_freedom(CJoltWorld *world, CJoltBodyID body, uint32_t freedom,
                            float mass);
uint32_t cjolt_body_get_freedom(const CJoltWorld *world, CJoltBodyID body);
/// Turns path sweeping (continuous collision detection) on or off for a body.
void cjolt_body_set_continuous(CJoltWorld *world, CJoltBodyID body, bool continuous);
bool cjolt_body_get_continuous(const CJoltWorld *world, CJoltBodyID body);
/// Moves a body into another collision group. Survives a later motion-type
/// change (the layer carries both, and switching one keeps the other).
void cjolt_body_set_group(CJoltWorld *world, CJoltBodyID body, int32_t group);
int32_t cjolt_body_get_group(const CJoltWorld *world, CJoltBodyID body);

// Buoyancy ------------------------------------------------------------------

/// Fills `outBodies` with the bodies whose bounds overlap the axis-aligned box
/// and `outCenters` (3 floats each) with their centers of mass. Only bodies a
/// buoyancy impulse can move are reported: statics, sensors, kinematic bodies,
/// and soft bodies are left out. Returns how many were written, in ascending
/// handle order so the same simulation floats the same bodies in the same
/// order every run.
int32_t cjolt_world_bodies_in_box(const CJoltWorld *world, const float boxMin[3],
                                  const float boxMax[3], CJoltBodyID *outBodies,
                                  float *outCenters, int32_t capacity);

/// What a sleeping body does when the fluid reaches it. A body that has
/// settled at its waterline and gone to sleep is right to stay there while the
/// fluid is unchanged, so the caller says which kind of change this step is.
typedef enum {
    /// Leave it asleep: the fluid has not moved, so its waterline has not
    /// either.
    CJOLT_BUOYANCY_WAKE_NEVER = 0,
    /// Wake it only if the surface passes through its bounds. This is what a
    /// swell wants: a floating crate wakes to ride the wave while a stone
    /// settled on the bottom, whose submerged volume the wave shape cannot
    /// change, sleeps on.
    CJOLT_BUOYANCY_WAKE_AT_SURFACE = 1,
    /// Wake it wherever it is. This is what a changed level (or density, or
    /// current) wants: the equilibrium itself moved, so a body sleeping at the
    /// old one has to be let go of, however far away the new surface is.
    CJOLT_BUOYANCY_WAKE_ALWAYS = 2,
} CJoltBuoyancyWake;

/// Applies one step of fluid buoyancy and drag to a body, against the fluid
/// surface plane through `surfacePoint` with `surfaceNormal` (a wavy surface
/// passes the local tangent plane under each body). Call once per body per
/// step, before stepping the world.
///
/// `density` is the fluid's, in kg/m^3. The library itself takes a
/// dimensionless factor instead, so the density is divided here by the body's
/// own (its mass over the same total volume the submerged fraction is measured
/// against), which is what puts the waterline where the displaced volume says.
/// `scale` multiplies that factor, for a body that should ride higher or lower
/// than its weight alone would put it.
///
/// Returns true if the body was in the fluid at all.
bool cjolt_body_apply_buoyancy(CJoltWorld *world, CJoltBodyID body,
                               const float surfacePoint[3],
                               const float surfaceNormal[3], float density,
                               float scale, float linearDrag, float angularDrag,
                               const float flow[3], float dt,
                               CJoltBuoyancyWake wake);

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

/// The hinge's current angle (radians), the slider's current offset (meters),
/// or a swing-twist's current swing away from its twist axis (radians),
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

// Characters ----------------------------------------------------------------

/// Opaque character handle: a capsule the library sweeps by hand each update
/// rather than a body the solver integrates. It is not in the broad phase, so
/// it carries an inner kinematic body to give it presence (ray casts, contact
/// events, sensors) among the ordinary bodies.
typedef struct CJoltCharacter CJoltCharacter;

/// Where a character's feet are, which decides whether it may walk.
typedef enum {
    CJOLT_GROUND_ON_GROUND = 0,   // supported, free to move
    CJOLT_GROUND_ON_STEEP = 1,    // supported by a slope too steep to climb
    CJOLT_GROUND_NOT_SUPPORTED = 2, // touching something that can't hold it
    CJOLT_GROUND_IN_AIR = 3,      // touching nothing
} CJoltGroundState;

typedef struct {
    /// A capsule standing on its feet: `radius` and the TOTAL height including
    /// both caps, so the shape spans `position` … `position + height` on +y.
    float radius, height;
    float position[3]; // the feet, in meters
    float rotation[4]; // quaternion x, y, z, w (facing; identity = 0,0,0,1)
    float maxSlopeAngle;  // radians; slopes past it can't be climbed
    float stepHeight;     // tallest stair the character steps onto; 0 = off
    float stickToFloor;   // how far down it may be pulled back onto the floor; 0 = off
    float mass;           // kg, the weight it presses down with
    float maxStrength;    // N, the hardest it can shove a dynamic body; 0 = never
    float predictiveContactDistance;
    float penetrationRecoverySpeed;
    /// Which collision group the character is in; 0 is the default group. It
    /// filters the character's own sweep, its inner body, and which other
    /// characters it can walk into.
    int32_t group;
} CJoltCharacterDesc;

/// Creates a character. Returns NULL if the description is unusable.
CJoltCharacter *cjolt_character_create(CJoltWorld *world,
                                       const CJoltCharacterDesc *desc);
void cjolt_character_destroy(CJoltWorld *world, CJoltCharacter *character);

void cjolt_character_get_position(const CJoltCharacter *character, float out[3]);
void cjolt_character_set_position(CJoltCharacter *character, const float pos[3]);
void cjolt_character_get_rotation(const CJoltCharacter *character, float out[4]);
void cjolt_character_set_rotation(CJoltCharacter *character, const float quat[4]);
void cjolt_character_get_velocity(const CJoltCharacter *character, float out[3]);
void cjolt_character_set_velocity(CJoltCharacter *character, const float v[3]);

/// Live tuning: the knobs a sketch may change between steps.
void cjolt_character_set_max_slope(CJoltCharacter *character, float radians);
void cjolt_character_set_step_height(CJoltCharacter *character, float height);
void cjolt_character_set_stick_to_floor(CJoltCharacter *character, float distance);
void cjolt_character_set_mass(CJoltCharacter *character, float mass);
void cjolt_character_set_max_strength(CJoltCharacter *character, float newtons);
/// Moves a character into another collision group, which filters its sweep,
/// its inner body, and the other characters it can bump into.
void cjolt_character_set_group(CJoltWorld *world, CJoltCharacter *character,
                               int32_t group);

CJoltGroundState cjolt_character_get_ground_state(const CJoltCharacter *character);
void cjolt_character_get_ground_normal(const CJoltCharacter *character, float out[3]);
void cjolt_character_get_ground_velocity(const CJoltCharacter *character, float out[3]);
/// The body the character stands on, or CJOLT_BODY_INVALID in the air.
CJoltBodyID cjolt_character_get_ground_body(const CJoltCharacter *character);
/// The inner kinematic body that represents the character among the bodies.
CJoltBodyID cjolt_character_get_inner_body(const CJoltCharacter *character);
/// Whether a surface with this normal is too steep for the character to walk
/// on (the library's own test, which also honors "no slope limit").
bool cjolt_character_is_slope_too_steep(const CJoltCharacter *character,
                                        const float normal[3]);

/// Sweeps the character through the world by its current velocity, climbing
/// steps and sticking to the floor on the way. Call once per step, before
/// `cjolt_world_step`, with the same dt.
void cjolt_character_update(CJoltWorld *world, CJoltCharacter *character,
                            float dt, const float gravity[3]);

/// Re-reads what the character is standing on after it has been teleported.
void cjolt_character_refresh_contacts(CJoltWorld *world, CJoltCharacter *character);

// Vehicles ------------------------------------------------------------------

/// Opaque vehicle handle: a *constraint* on an ordinary chassis body, not a
/// body of its own. It owns the wheels, the suspension springs, and the engine
/// and gearbox that turn a throttle into wheel torque, and it is registered as
/// a step listener so its wheels are collided and driven inside every step.
typedef struct CJoltVehicle CJoltVehicle;

/// How a wheel finds the ground each step: a downward ray (cheapest, and a
/// narrow wheel drops into gaps it should ride over), a swept sphere, or a
/// swept cylinder (the wheel's real footprint, and the steadiest over rough
/// terrain).
typedef enum {
    CJOLT_WHEEL_CONTACT_RAY = 0,
    CJOLT_WHEEL_CONTACT_SPHERE = 1,
    CJOLT_WHEEL_CONTACT_CYLINDER = 2,
} CJoltWheelContact;

typedef struct {
    /// Where the suspension is bolted to the chassis, in the body's local
    /// space (the same space the collider is described in).
    float position[3];
    float radius, width;
    /// How far below the mounting point the wheel center sits at full
    /// compression and at full droop; the spring's natural length is the max.
    float suspensionMinLength, suspensionMaxLength;
    float suspensionFrequency, suspensionDamping;
    /// How far the suspension (and with it the steering axis) is raked back
    /// from vertical, in radians. A two-wheeler needs it to steer stably.
    float casterAngle;
    float maxSteerAngle;      // radians; 0 = fixed straight ahead
    float maxBrakeTorque;     // N·m
    float maxHandBrakeTorque; // N·m
    /// Scales the tire's friction curves; 1 keeps the library's own tire.
    float grip;
} CJoltWheelDesc;

/// One axle: the wheels that share it (either index may be -1 for a single
/// wheel, as a two-wheeler's are), and whether the engine drives it. A pair
/// with both wheels present is also tied together by an anti-roll bar.
typedef struct {
    int32_t leftWheel, rightWheel;
    bool driven;
} CJoltAxleDesc;

typedef struct {
    const CJoltWheelDesc *wheels;
    int32_t wheelCount;
    const CJoltAxleDesc *axles;
    int32_t axleCount;
    float maxEngineTorque; // N·m
    /// The speed the gearing tops out at, in m/s: the differential ratio is
    /// solved so that top gear at the engine's max RPM turns the driven wheels
    /// this fast. <= 0 keeps the library's own ratio.
    float topSpeed;
    float antiRollStiffness; // N/m across an axle's pair; 0 = no bars
    /// The furthest the chassis may tilt from the world up, in radians;
    /// >= pi lets it roll over freely.
    float maxPitchRollAngle;
    CJoltWheelContact contact;
    /// A two-wheeler that balances itself: adds the lean controller, which
    /// steers into a turn and holds the machine up.
    bool leans;
    float maxLeanAngle; // radians
} CJoltVehicleDesc;

/// Everything a wheel knows about itself after a step.
typedef struct {
    /// The wheel's center in world space, and the rotation that poses a
    /// cylinder modeled along +y onto it (steering and spin included).
    float position[3];
    float rotation[4]; // quaternion x, y, z, w
    float steerAngle;      // radians, positive turns left
    float rotationAngle;   // how far the wheel has rolled, radians [0, 2pi)
    float angularVelocity; // rad/s, positive rolls the vehicle forward
    float suspensionLength;
    bool hasContact;
    CJoltBodyID contactBody;
    float contactNormal[3];
    /// How much the tire is sliding: along the wheel (spin against the road)
    /// and across it (the slip angle, in radians).
    float longitudinalSlip, lateralSlip;
} CJoltWheelState;

/// Builds a vehicle on an existing chassis body. Returns NULL if the body is
/// stale or the description has no wheels.
CJoltVehicle *cjolt_vehicle_create(CJoltWorld *world, CJoltBodyID chassis,
                                   const CJoltVehicleDesc *desc);
void cjolt_vehicle_destroy(CJoltWorld *world, CJoltVehicle *vehicle);

/// Moves a vehicle into another collision group: the chassis body's layer and
/// the wheels' own collision testers, which are built against a layer and so
/// are rebuilt here.
void cjolt_vehicle_set_group(CJoltWorld *world, CJoltVehicle *vehicle,
                             int32_t group);

/// The driver's controls for the coming step. `forward` is -1…1 (the gearbox
/// picks reverse for a negative value), `right` -1…1, `brake` and `handBrake`
/// 0…1. Any nonzero input wakes the chassis, so a parked vehicle may sleep
/// but a driven one never does.
void cjolt_vehicle_set_input(CJoltWorld *world, CJoltVehicle *vehicle,
                             float forward, float right, float brake,
                             float handBrake);

/// Re-applies a wheel's description to a live vehicle: the solver reads these
/// every step, so suspension, steering lock, brakes, and grip can all be
/// tuned while it drives. Which wheels the engine turns is not among them
/// (that is the gearbox, fixed when the vehicle is built).
void cjolt_vehicle_set_wheel_settings(CJoltVehicle *vehicle, int32_t index,
                                      const CJoltWheelDesc *desc);

void cjolt_vehicle_set_engine_torque(CJoltVehicle *vehicle, float maxTorque);
/// Re-solves the differential ratio for a new top speed (m/s).
void cjolt_vehicle_set_top_speed(CJoltVehicle *vehicle, float metersPerSecond);
void cjolt_vehicle_set_wheel_contact(CJoltVehicle *vehicle,
                                     CJoltWheelContact contact);
void cjolt_vehicle_set_max_pitch_roll(CJoltVehicle *vehicle, float radians);
void cjolt_vehicle_set_anti_roll(CJoltVehicle *vehicle, float stiffness);

int32_t cjolt_vehicle_get_wheel_count(const CJoltVehicle *vehicle);
void cjolt_vehicle_get_wheel(const CJoltVehicle *vehicle, int32_t index,
                             CJoltWheelState *out);
float cjolt_vehicle_get_rpm(const CJoltVehicle *vehicle);
/// The gear the box has picked: -1 reverse, 0 neutral, 1 first, and up.
int32_t cjolt_vehicle_get_gear(const CJoltVehicle *vehicle);

// Ragdolls ------------------------------------------------------------------

/// Opaque ragdoll handle: a tree of rigid bodies, one per skeleton joint, hung
/// off each other by swing-twist constraints. Its bodies are ordinary bodies
/// (they collide, report contacts, and can be picked), but they are created and
/// destroyed as a set, share a collision group so neighbouring limbs don't
/// fight, and can be driven together toward a pose.
typedef struct CJoltRagdoll CJoltRagdoll;

/// One limb of a ragdoll: a body standing at its joint's frame, wearing a shape
/// that is offset inside it to fill the bone, plus the constraint to its
/// parent. Parts must be ordered parents before children.
typedef struct {
    /// Index of the parent part, or -1 for the root (which has no constraint).
    int32_t parent;
    /// The limb's shape, and where it sits inside the body. The body's own
    /// origin is the *joint*, so the shape is pushed out along the bone.
    CJoltShapeDesc shape;
    float shapeOffset[3];
    float shapeRotation[4]; // quaternion x, y, z, w (identity = 0,0,0,1)
    /// The body's world pose: the joint's frame in the pose the ragdoll is
    /// built from.
    float position[3];
    float rotation[4];
    /// The limb's mass in kg; <= 0 takes what the shape and density give.
    float mass;
    /// The swing-twist constraint to the parent, in world space at the build
    /// pose (ignored for the root). The bone runs along `twistAxis`, and the
    /// joint may swing that axis anywhere inside a cone of `swingLimit` while
    /// twisting about it between `twistMin` and `twistMax`.
    float pivot[3];
    float twistAxis[3];
    float planeAxis[3];
    float swingLimit;
    float twistMin, twistMax;
} CJoltRagdollPartDesc;

/// Builds a ragdoll and adds it to the world. Masses are balanced across the
/// tree and collisions between each part and its parent (and between parts that
/// already overlap in the build pose) are switched off, so the figure holds
/// together instead of shaking itself apart. Returns NULL if the parts are
/// unusable.
CJoltRagdoll *cjolt_ragdoll_create(CJoltWorld *world,
                                   const CJoltRagdollPartDesc *parts,
                                   int32_t partCount, float friction,
                                   float restitution, int32_t group);
void cjolt_ragdoll_destroy(CJoltWorld *world, CJoltRagdoll *ragdoll);

/// Moves every limb of a figure into another collision group. The filter that
/// keeps a figure's own limbs from fighting each other is a separate thing and
/// is left alone, so two figures in one group still collide with each other.
void cjolt_ragdoll_set_group(CJoltWorld *world, CJoltRagdoll *ragdoll,
                             int32_t group);

int32_t cjolt_ragdoll_part_count(const CJoltRagdoll *ragdoll);
/// The body standing at part `index`'s joint.
CJoltBodyID cjolt_ragdoll_get_body(const CJoltRagdoll *ragdoll, int32_t index);

/// Retune one part's constraint limits while it hangs (no effect on the root).
void cjolt_ragdoll_set_limits(CJoltRagdoll *ragdoll, int32_t index,
                              float swingLimit, float twistMin, float twistMax);

/// Powers every constraint's motors toward a pose given as one quaternion per
/// part (x, y, z, w), each the part's rotation *relative to its parent*. The
/// spring is shaped by `frequency` (Hz) and `damping`; `maxTorque` (N·m) caps
/// how hard a joint may pull, and a non-finite or non-positive value leaves it
/// unlimited. The root has no constraint, so a powered figure still falls as a
/// whole: the motors hold its shape, not its place.
void cjolt_ragdoll_drive_to_pose(CJoltWorld *world, CJoltRagdoll *ragdoll,
                                 const float *localRotations, float frequency,
                                 float damping, float maxTorque);

/// Cuts motor power: the figure goes limp and only its limits hold it.
void cjolt_ragdoll_stop_motors(CJoltRagdoll *ragdoll);

/// Places every part instantly at a pose given as one column-major 4x4 world
/// matrix per part (16 floats each).
void cjolt_ragdoll_set_pose(CJoltWorld *world, CJoltRagdoll *ragdoll,
                            const float *worldMatrices);

/// Drives a kinematic ragdoll toward that same pose over `dt` seconds, so it
/// arrives carrying the velocity that took it there and shoves what it hits.
void cjolt_ragdoll_move_to_pose(CJoltWorld *world, CJoltRagdoll *ragdoll,
                                const float *worldMatrices, float dt);

/// Switches every part between static, kinematic, and dynamic at once.
void cjolt_ragdoll_set_motion(CJoltWorld *world, CJoltRagdoll *ragdoll,
                              CJoltMotionType motion);
void cjolt_ragdoll_activate(CJoltWorld *world, CJoltRagdoll *ragdoll);
bool cjolt_ragdoll_is_active(const CJoltWorld *world, const CJoltRagdoll *ragdoll);
/// Shoves the whole figure with one impulse (N·s), split between the limbs by
/// their share of its mass so every limb takes the same change in velocity and
/// it leaves in one piece.
void cjolt_ragdoll_add_impulse(CJoltWorld *world, CJoltRagdoll *ragdoll,
                               const float impulse[3]);

// Soft bodies ---------------------------------------------------------------

/// Opaque soft-body handle: a body whose state lives in its particles rather
/// than in one pose, simulated by position-based dynamics. It is a real body in
/// the world (it collides with the rigid bodies and its id is reported by ray
/// casts) but it never rotates, its velocity is the average of its particles',
/// and impulses and constraints do not apply to it.
typedef struct CJoltSoftBody CJoltSoftBody;

typedef struct {
    /// The rest shape: particle positions as xyz triples in body-local space,
    /// and the triangles connecting them (3 indices per face). Coincident
    /// positions must already be merged, or the surface has no connectivity and
    /// falls apart into loose triangles.
    const float *positions;
    int32_t vertexCount;
    const uint32_t *indices;
    int32_t indexCount;
    /// One inverse mass per particle (0 pins it to the world). NULL gives every
    /// particle an inverse mass of 1.
    const float *inverseMasses;
    float position[3]; // world placement of the rest shape
    float rotation[4]; // quaternion x, y, z, w (baked into the particles)
    /// Inverse stiffness of the stretch and shear springs, in m/N. 0 is
    /// inextensible; larger is stretchier.
    float compliance;
    /// Inverse stiffness of the fold-resisting constraints between neighbouring
    /// faces, in m/N. Negative switches them off entirely, which is the limp
    /// cloth every fabric wants.
    float bendCompliance;
    /// n * R * T for the gas inside a closed surface: the outward push is
    /// pressure * area / volume, so it grows as the shape is squashed. 0 is a
    /// limp bag.
    float pressure;
    float linearDamping;  // >= 0
    float friction;       // >= 0
    float restitution;    // 0...1
    float gravityFactor;  // 1 = normal gravity
    /// How far a particle's own body extends past its position, which keeps a
    /// surface from z-fighting whatever it lies on.
    float vertexRadius;
    /// Solver iterations per step; more is stiffer and steadier.
    int32_t iterations;
    bool allowSleep;
    /// Collide with both sides of every face (a single-sided sheet lets things
    /// through from behind).
    bool twoSided;
    /// Which collision group the body is in; 0 is the default group.
    int32_t group;
} CJoltSoftBodyDesc;

/// Builds a soft body and adds it to the world. The stretch, shear, and bend
/// constraints are derived from the faces. Returns NULL if the description has
/// no usable surface.
CJoltSoftBody *cjolt_soft_body_create(CJoltWorld *world,
                                      const CJoltSoftBodyDesc *desc);
void cjolt_soft_body_destroy(CJoltWorld *world, CJoltSoftBody *body);

/// The body id the soft body occupies, so a ray cast hit can be recognised.
CJoltBodyID cjolt_soft_body_get_id(const CJoltSoftBody *body);
int32_t cjolt_soft_body_vertex_count(const CJoltSoftBody *body);

/// Copies up to `capacity` particle positions as world-space xyz triples.
/// Returns how many were written.
int32_t cjolt_soft_body_get_positions(const CJoltWorld *world,
                                      const CJoltSoftBody *body, float *out,
                                      int32_t capacity);
/// The average of the particle positions, in world space.
void cjolt_soft_body_get_center(const CJoltWorld *world,
                                const CJoltSoftBody *body, float out[3]);
/// The volume the surface currently encloses (negative if it is inside out).
float cjolt_soft_body_get_volume(const CJoltWorld *world,
                                 const CJoltSoftBody *body);

void cjolt_soft_body_set_pressure(CJoltWorld *world, CJoltSoftBody *body,
                                  float pressure);
void cjolt_soft_body_set_iterations(CJoltWorld *world, CJoltSoftBody *body,
                                    int32_t iterations);
void cjolt_soft_body_set_vertex_radius(CJoltWorld *world, CJoltSoftBody *body,
                                       float radius);

/// A particle's inverse mass: 0 pins it where it is, and anything positive
/// hands it back to the simulation. Position is deliberately not settable:
/// moving a particle outright skips collision detection, so a pinned particle
/// is driven by `cjolt_soft_body_move_vertex` instead.
float cjolt_soft_body_get_vertex_inverse_mass(const CJoltWorld *world,
                                              const CJoltSoftBody *body,
                                              int32_t index);
void cjolt_soft_body_set_vertex_inverse_mass(CJoltWorld *world,
                                             CJoltSoftBody *body, int32_t index,
                                             float inverseMass);
/// Carries a pinned particle to a world-space target over `dt` seconds by
/// giving it the velocity that arrives there, so the surface hanging off it is
/// dragged rather than teleported. Pins the particle if it was free.
void cjolt_soft_body_move_vertex(CJoltWorld *world, CJoltSoftBody *body,
                                 int32_t index, const float target[3], float dt);

/// Pushes the whole body, spread evenly over its particles (N).
void cjolt_soft_body_add_force(CJoltWorld *world, CJoltSoftBody *body,
                               const float force[3]);
void cjolt_soft_body_activate(CJoltWorld *world, CJoltSoftBody *body);
bool cjolt_soft_body_is_active(const CJoltWorld *world,
                               const CJoltSoftBody *body);

// Queries -------------------------------------------------------------------

/// What a query is allowed to see. A zeroed struct (or NULL) is the default:
/// every solid rigid body, sensors and soft bodies transparent, nothing
/// ignored. Filters travel as a struct rather than as call arguments so that
/// a new way to narrow a query (collision layers, groups) adds a field here
/// instead of another parameter to every function below.
typedef struct CJoltQueryFilter {
    /// Bodies the query looks straight through (its own body, usually).
    const CJoltBodyID *ignoreBodies;
    int32_t ignoreCount;
    /// Report detector volumes as well as solid bodies.
    bool includeSensors;
    /// Report soft bodies, which have no rigid pose to hand back and are
    /// therefore invisible to the public query surface. The mouse pick paths
    /// set it, since a soft body is grabbable.
    bool includeSoftBodies;
    /// The collision group the query asks *as*: it sees what a moving body in
    /// that group would touch, so the world's ignore table narrows a question
    /// the same way it narrows a collision. 0, the default group, is what an
    /// unfiltered world always answered.
    int32_t group;
} CJoltQueryFilter;

/// One thing a query found, in solver meters.
typedef struct CJoltQueryHit {
    CJoltBodyID body;
    /// Where the query touched the body, in world space.
    float point[3];
    /// The body's outward surface normal there (unit length).
    float normal[3];
    /// How far along the query the touch is: the distance from a ray's origin,
    /// or how far a swept shape travelled before it landed.
    float distance;
} CJoltQueryHit;

/// Casts a ray (direction scaled by its length) through the world. With
/// `allHits` false only the nearest is reported; otherwise every hit is,
/// nearest first. Returns how many were found, which may exceed `capacity`
/// (only `capacity` are written, so a caller can size a second call from it).
int32_t cjolt_world_cast_ray(const CJoltWorld *world, const float origin[3],
                             const float direction[3],
                             const CJoltQueryFilter *filter, bool allHits,
                             CJoltQueryHit *out, int32_t capacity);

/// Sweeps a shape from `position`/`rotation` along `direction` (scaled by the
/// sweep's length) and reports what it runs into, nearest first. Counting and
/// capacity work as in `cjolt_world_cast_ray`. Mesh and height-field shapes
/// cannot be swept.
int32_t cjolt_world_cast_shape(const CJoltWorld *world,
                               const CJoltShapeDesc *shape,
                               const float position[3], const float rotation[4],
                               const float direction[3],
                               const CJoltQueryFilter *filter, bool allHits,
                               CJoltQueryHit *out, int32_t capacity);

/// The bodies overlapping a shape placed at `position`/`rotation`, in handle
/// order, one entry per body however many of its parts touch. Returns how many
/// were found (see `cjolt_world_cast_ray` for the capacity rule).
int32_t cjolt_world_overlap_shape(const CJoltWorld *world,
                                  const CJoltShapeDesc *shape,
                                  const float position[3],
                                  const float rotation[4],
                                  const CJoltQueryFilter *filter,
                                  CJoltBodyID *out, int32_t capacity);

/// The bodies a world-space point is inside, in handle order.
int32_t cjolt_world_overlap_point(const CJoltWorld *world, const float point[3],
                                  const CJoltQueryFilter *filter,
                                  CJoltBodyID *out, int32_t capacity);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // CJOLT_H
