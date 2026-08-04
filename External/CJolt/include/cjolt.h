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
