// CJolt: Ollin's C bridge over the vendored Jolt Physics library.
// The only compilation unit in the repo that includes Jolt's C++ headers, so
// the JPH_* define-consistency rule holds by construction: every unit that
// sees a Jolt header lives in this one target with one set of settings.

#include <Jolt/Jolt.h>

#include <Jolt/Core/Factory.h>
#include <Jolt/Core/JobSystemThreadPool.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/ContactListener.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Character/CharacterVirtual.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>
#include <Jolt/Physics/Collision/Shape/ConvexHullShape.h>
#include <Jolt/Physics/Collision/Shape/CylinderShape.h>
#include <Jolt/Physics/Collision/Shape/HeightFieldShape.h>
#include <Jolt/Physics/Collision/Shape/MeshShape.h>
#include <Jolt/Physics/Collision/Shape/OffsetCenterOfMassShape.h>
#include <Jolt/Physics/Collision/Shape/RotatedTranslatedShape.h>
#include <Jolt/Physics/Collision/Shape/SphereShape.h>
#include <Jolt/Physics/Collision/Shape/StaticCompoundShape.h>
#include <Jolt/Physics/Collision/Shape/TaperedCapsuleShape.h>
#include <Jolt/Physics/Collision/Shape/TaperedCylinderShape.h>
#include <Jolt/Physics/Constraints/DistanceConstraint.h>
#include <Jolt/Physics/Constraints/FixedConstraint.h>
#include <Jolt/Physics/Constraints/HingeConstraint.h>
#include <Jolt/Physics/Constraints/PointConstraint.h>
#include <Jolt/Physics/Constraints/SliderConstraint.h>
#include <Jolt/Physics/PhysicsSettings.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/Vehicle/MotorcycleController.h>
#include <Jolt/Physics/Vehicle/VehicleCollisionTester.h>
#include <Jolt/Physics/Vehicle/VehicleConstraint.h>
#include <Jolt/Physics/Vehicle/WheeledVehicleController.h>
#include <Jolt/RegisterTypes.h>

#include <algorithm>
#include <cfloat>
#include <cmath>
#include <mutex>
#include <thread>
#include <unordered_map>
#include <vector>

#include "../include/cjolt.h"

namespace {

using namespace JPH;

Vec3 vec3(const float v[3]) { return Vec3(v[0], v[1], v[2]); }

Quat quat(const float q[4]) {
    Quat value(q[0], q[1], q[2], q[3]);
    if (value.LengthSq() < 1.0e-12f) { return Quat::sIdentity(); }
    return value.Normalized();
}

void store(Vec3Arg v, float out[3]) {
    out[0] = v.GetX();
    out[1] = v.GetY();
    out[2] = v.GetZ();
}

void store(QuatArg q, float out[4]) {
    out[0] = q.GetX();
    out[1] = q.GetY();
    out[2] = q.GetZ();
    out[3] = q.GetW();
}

// Object layers: statics only pair with moving bodies, the ghost layer (grab
// anchors) pairs with nothing, so a grab can never nudge the scene by
// collision, only through its constraint, and the sensor layer pairs only
// with moving bodies, since a detector volume has nothing to report about
// scenery that never moves or about another detector.
namespace Layers {
constexpr ObjectLayer NON_MOVING = 0;
constexpr ObjectLayer MOVING = 1;
constexpr ObjectLayer GHOST = 2;
constexpr ObjectLayer SENSOR = 3;
constexpr ObjectLayer NUM_LAYERS = 4;
} // namespace Layers

namespace BroadPhaseLayers {
constexpr BroadPhaseLayer NON_MOVING(0);
constexpr BroadPhaseLayer MOVING(1);
constexpr uint NUM_LAYERS(2);
} // namespace BroadPhaseLayers

class BPLayerInterfaceImpl final : public BroadPhaseLayerInterface {
public:
    uint GetNumBroadPhaseLayers() const override { return BroadPhaseLayers::NUM_LAYERS; }

    BroadPhaseLayer GetBroadPhaseLayer(ObjectLayer inLayer) const override {
        return inLayer == Layers::NON_MOVING ? BroadPhaseLayers::NON_MOVING
                                             : BroadPhaseLayers::MOVING;
    }

#if defined(JPH_EXTERNAL_PROFILE) || defined(JPH_PROFILE_ENABLED)
    const char *GetBroadPhaseLayerName(BroadPhaseLayer inLayer) const override {
        return inLayer == BroadPhaseLayers::NON_MOVING ? "NON_MOVING" : "MOVING";
    }
#endif
};

class ObjectVsBroadPhaseLayerFilterImpl final : public ObjectVsBroadPhaseLayerFilter {
public:
    bool ShouldCollide(ObjectLayer inLayer1, BroadPhaseLayer inLayer2) const override {
        switch (inLayer1) {
        case Layers::NON_MOVING: return inLayer2 == BroadPhaseLayers::MOVING;
        case Layers::MOVING: return true;
        case Layers::SENSOR: return inLayer2 == BroadPhaseLayers::MOVING;
        default: return false; // ghosts collide with nothing
        }
    }
};

class ObjectLayerPairFilterImpl final : public ObjectLayerPairFilter {
public:
    bool ShouldCollide(ObjectLayer inObject1, ObjectLayer inObject2) const override {
        if (inObject1 == Layers::GHOST || inObject2 == Layers::GHOST) { return false; }
        if (inObject1 == Layers::SENSOR || inObject2 == Layers::SENSOR) {
            return inObject1 == Layers::MOVING || inObject2 == Layers::MOVING;
        }
        if (inObject1 == Layers::NON_MOVING && inObject2 == Layers::NON_MOVING) {
            return false;
        }
        return true;
    }
};

/// Ray casts see the solid scene: a sensor is a region to be inside, never a
/// surface to hit, so picking with the cursor looks straight through one.
class NonSensorBodyFilter final : public BodyFilter {
public:
    bool ShouldCollideLocked(const Body &inBody) const override {
        return !inBody.IsSensor();
    }
};

/// A vehicle's wheels see the solid scene except their own chassis: the same
/// sensor rule as a ray cast, plus the self-collision the collision tester's
/// default filter would otherwise have handled on its own.
class VehicleGroundFilter final : public BodyFilter {
public:
    BodyID chassis;

    bool ShouldCollide(const BodyID &inBodyID) const override {
        return inBodyID != chassis;
    }

    bool ShouldCollideLocked(const Body &inBody) const override {
        return !inBody.IsSensor();
    }
};

// Contact events are recorded on the solver's worker threads while a step is
// running, several at once, with every body locked: the listener may only read
// what it is handed, and it may never call anything of Ollin's. So it buffers
// into a mutex-guarded list, which the main thread drains once the step has
// returned (the C cousin of the render-thread-closure rule).
//
// The buffer speaks in body *pairs*, not sub-shapes. A compound's parts and a
// mesh's triangles each report their own contact, so the listener counts a
// pair's live contacts and emits one began as the count leaves zero and one
// ended as it returns, which is the granularity a sketch asks about.
class ContactRecorder final : public ContactListener {
public:
    void OnContactAdded(const Body &inBody1, const Body &inBody2,
                        const ContactManifold &inManifold,
                        ContactSettings &) override {
        // The manifold's normal moves body 2 out of collision, so it points
        // from body 1 toward body 2, and the pair is closing when its relative
        // velocity (v2 - v1, the solver's own measure) runs against it. Both
        // velocities are still pre-solve here, so this is the impact's own
        // speed rather than what is left after the bounce.
        const RVec3 point = inManifold.mRelativeContactPointsOn1.empty()
                                ? inManifold.mBaseOffset
                                : inManifold.GetWorldSpaceContactPointOn1(0);
        const Vec3 closing =
            inBody1.GetPointVelocity(point) - inBody2.GetPointVelocity(point);

        std::lock_guard<std::mutex> lock(mMutex);
        if (mPairs[pairKey(inBody1.GetID(), inBody2.GetID())]++ > 0) {
            return; // another sub shape of a pair already touching
        }
        CJoltContactEvent event{};
        event.phase = CJOLT_CONTACT_BEGAN;
        event.bodyA = inBody1.GetID().GetIndexAndSequenceNumber();
        event.bodyB = inBody2.GetID().GetIndexAndSequenceNumber();
        store(Vec3(point), event.point);
        store(inManifold.mWorldSpaceNormal, event.normal);
        event.speed = std::max(0.0f, closing.Dot(inManifold.mWorldSpaceNormal));
        mEvents.push_back(event);
    }

    void OnContactRemoved(const SubShapeIDPair &inPair) override {
        // Nothing here may touch the bodies: one of them may already have been
        // destroyed. Only the ids are safe, which is why an ended event
        // carries no point or normal.
        std::lock_guard<std::mutex> lock(mMutex);
        auto entry = mPairs.find(pairKey(inPair.GetBody1ID(), inPair.GetBody2ID()));
        if (entry == mPairs.end() || --entry->second > 0) { return; }
        mPairs.erase(entry);
        CJoltContactEvent event{};
        event.phase = CJOLT_CONTACT_ENDED;
        event.bodyA = inPair.GetBody1ID().GetIndexAndSequenceNumber();
        event.bodyB = inPair.GetBody2ID().GetIndexAndSequenceNumber();
        mEvents.push_back(event);
    }

    int32_t count() {
        std::lock_guard<std::mutex> lock(mMutex);
        return int32_t(mEvents.size());
    }

    int32_t drain(CJoltContactEvent *outEvents, int32_t inCapacity) {
        std::lock_guard<std::mutex> lock(mMutex);
        // Worker threads record in whatever order they finish, so the list is
        // put in pair order before it leaves: a replayed simulation then reads
        // its events in the same order every run.
        std::sort(mEvents.begin(), mEvents.end(),
                  [](const CJoltContactEvent &l, const CJoltContactEvent &r) {
                      if (l.bodyA != r.bodyA) { return l.bodyA < r.bodyA; }
                      if (l.bodyB != r.bodyB) { return l.bodyB < r.bodyB; }
                      return int(l.phase) < int(r.phase);
                  });
        const int32_t written = std::min(inCapacity, int32_t(mEvents.size()));
        if (outEvents != nullptr && written > 0) {
            std::copy(mEvents.begin(), mEvents.begin() + written, outEvents);
        }
        mEvents.clear();
        return written;
    }

private:
    static uint64_t pairKey(const BodyID &inA, const BodyID &inB) {
        const uint64_t a = inA.GetIndexAndSequenceNumber();
        const uint64_t b = inB.GetIndexAndSequenceNumber();
        return a <= b ? (a << 32) | b : (b << 32) | a;
    }

    std::mutex mMutex;
    std::unordered_map<uint64_t, int> mPairs;
    std::vector<CJoltContactEvent> mEvents;
};

// Library-wide setup: allocator, RTTI factory, and the type registry are
// process-global and shared by every world.
void ensureLibraryInitialized() {
    static std::once_flag once;
    std::call_once(once, [] {
        RegisterDefaultAllocator();
        Factory::sInstance = new Factory();
        RegisterTypes();
    });
}

} // namespace

struct CJoltConstraint {
    JPH::Ref<JPH::Constraint> constraint;
    // Grabs carry the hidden static anchor their drag spring hangs on.
    JPH::BodyID grabAnchor = JPH::BodyID();
    JPH::BodyID grabbedBody = JPH::BodyID();
};

/// A walking character: a capsule the library sweeps by hand, plus the two
/// distances the combined update needs (they are arguments to ExtendedUpdate,
/// not state on the character, so the wrapper keeps them).
struct CJoltCharacter {
    JPH::Ref<JPH::CharacterVirtual> character;
    float stepHeight = 0.0f;
    float stickToFloor = 0.0f;
};

/// A vehicle: the constraint that owns the wheels, the three collision testers
/// it can switch between, the filter they all share, and the driven-wheel
/// radius the top-speed gearing is solved against.
struct CJoltVehicle {
    JPH::Ref<JPH::VehicleConstraint> constraint;
    JPH::Ref<JPH::VehicleCollisionTester> testers[3];
    VehicleGroundFilter groundFilter;
    float drivenWheelRadius = 0.3f;
};

struct CJoltWorld {
    JPH::TempAllocatorImpl tempAllocator;
    JPH::JobSystemThreadPool jobSystem;
    BPLayerInterfaceImpl broadPhaseLayers;
    ObjectVsBroadPhaseLayerFilterImpl objectVsBroadPhase;
    ObjectLayerPairFilterImpl objectPairs;
    // Declared before the physics system, which holds a pointer to it, so the
    // recorder outlives every step that could still be writing into it.
    ContactRecorder contacts;
    JPH::PhysicsSystem physics;
    std::vector<CJoltConstraint *> constraints;
    // Characters are not in the broad phase, so they can only be collided
    // against each other through this list, which each one is registered in.
    JPH::CharacterVsCharacterCollisionSimple characterCollision;
    std::vector<CJoltCharacter *> characters;
    std::vector<CJoltVehicle *> vehicles;

    CJoltWorld()
        : tempAllocator(16 * 1024 * 1024),
          jobSystem(JPH::cMaxPhysicsJobs, JPH::cMaxPhysicsBarriers,
                    std::clamp(int(std::thread::hardware_concurrency()) - 1, 1, 8)) {}
};

namespace {

// Constraint endpoints resolve to Body pointers; the invalid id anchors to the
// world. Called only from the main thread between steps, so the no-lock
// interface is safe.
Body *resolveBody(CJoltWorld *world, CJoltBodyID id) {
    if (id == CJOLT_BODY_INVALID) { return &Body::sFixedToWorld; }
    return world->physics.GetBodyLockInterfaceNoLock().TryGetBody(BodyID(id));
}

Ref<Shape> makeShape(const CJoltShapeDesc &desc) {
    const float density = desc.density > 0 ? desc.density : 1000.0f;
    switch (desc.type) {
    case CJOLT_SHAPE_BOX: {
        Vec3 half(std::max(desc.a, 1.0e-3f), std::max(desc.b, 1.0e-3f),
                  std::max(desc.c, 1.0e-3f));
        // The convex radius may not exceed the smallest half extent.
        float radius = std::min(cDefaultConvexRadius, 0.5f * half.ReduceMin());
        BoxShape *shape = new BoxShape(half, radius);
        shape->SetDensity(density);
        return shape;
    }
    case CJOLT_SHAPE_SPHERE: {
        SphereShape *shape = new SphereShape(std::max(desc.a, 1.0e-3f));
        shape->SetDensity(density);
        return shape;
    }
    case CJOLT_SHAPE_CAPSULE: {
        CapsuleShape *shape =
            new CapsuleShape(std::max(desc.a, 1.0e-3f), std::max(desc.b, 1.0e-3f));
        shape->SetDensity(density);
        return shape;
    }
    case CJOLT_SHAPE_CYLINDER: {
        float halfHeight = std::max(desc.a, 1.0e-3f);
        float radius = std::max(desc.b, 1.0e-3f);
        float convexRadius =
            std::min(cDefaultConvexRadius, 0.5f * std::min(halfHeight, radius));
        CylinderShape *shape = new CylinderShape(halfHeight, radius, convexRadius);
        shape->SetDensity(density);
        return shape;
    }
    case CJOLT_SHAPE_CONVEX_HULL: {
        if (desc.points == nullptr || desc.pointCount < 4) { return nullptr; }
        Array<Vec3> points;
        points.reserve(size_t(desc.pointCount));
        for (int32_t i = 0; i < desc.pointCount; ++i) {
            points.push_back(vec3(desc.points + 3 * i));
        }
        ConvexHullShapeSettings settings(points);
        settings.SetDensity(density);
        Shape::ShapeResult result = settings.Create();
        if (result.HasError()) { return nullptr; }
        return result.Get();
    }
    case CJOLT_SHAPE_MESH: {
        if (desc.points == nullptr || desc.indices == nullptr || desc.indexCount < 3) {
            return nullptr;
        }
        VertexList vertices;
        vertices.reserve(size_t(desc.pointCount));
        for (int32_t i = 0; i < desc.pointCount; ++i) {
            const float *p = desc.points + 3 * i;
            vertices.push_back(Float3(p[0], p[1], p[2]));
        }
        IndexedTriangleList triangles;
        triangles.reserve(size_t(desc.indexCount / 3));
        for (int32_t i = 0; i + 2 < desc.indexCount; i += 3) {
            triangles.push_back(
                IndexedTriangle(desc.indices[i], desc.indices[i + 1], desc.indices[i + 2]));
        }
        MeshShapeSettings settings(std::move(vertices), std::move(triangles));
        Shape::ShapeResult result = settings.Create();
        if (result.HasError()) { return nullptr; }
        return result.Get();
    }
    case CJOLT_SHAPE_TAPERED_CAPSULE: {
        // Both cap radii must be positive; a fully-contained cap collapses to
        // a sphere inside the library, which is the right degenerate answer.
        TaperedCapsuleShapeSettings settings(std::max(desc.a, 0.0f),
                                             std::max(desc.b, 1.0e-3f),
                                             std::max(desc.c, 1.0e-3f));
        settings.SetDensity(density);
        Shape::ShapeResult result = settings.Create();
        if (result.HasError()) { return nullptr; }
        return result.Get();
    }
    case CJOLT_SHAPE_TAPERED_CYLINDER: {
        // A zero top radius is a cone. The convex radius may not exceed the
        // smaller cap radius (the library clamps it again internally).
        float halfHeight = std::max(desc.a, 1.0e-3f);
        float top = std::max(desc.b, 0.0f);
        float bottom = std::max(desc.c, 0.0f);
        if (std::max(top, bottom) < 1.0e-3f) { return nullptr; }
        float convexRadius =
            std::min(cDefaultConvexRadius, 0.5f * std::min(halfHeight, std::max(top, bottom)));
        TaperedCylinderShapeSettings settings(halfHeight, top, bottom, convexRadius);
        settings.SetDensity(density);
        Shape::ShapeResult result = settings.Create();
        if (result.HasError()) { return nullptr; }
        return result.Get();
    }
    case CJOLT_SHAPE_HEIGHT_FIELD: {
        if (desc.heights == nullptr || desc.sampleCount < 4) { return nullptr; }
        HeightFieldShapeSettings settings(desc.heights, vec3(desc.fieldOffset),
                                          vec3(desc.fieldScale),
                                          uint32(desc.sampleCount));
        // Full-precision samples: heights quantize per block against its own
        // min/max, and 16 bits makes the surface match the source field to
        // well under a visible error at any terrain scale.
        settings.mBitsPerSample = 16;
        Shape::ShapeResult result = settings.Create();
        if (result.HasError()) { return nullptr; }
        return result.Get();
    }
    case CJOLT_SHAPE_COMPOUND: {
        if (desc.children == nullptr || desc.childCount < 1) { return nullptr; }
        StaticCompoundShapeSettings settings;
        for (int32_t i = 0; i < desc.childCount; ++i) {
            const CJoltShapeChild &child = desc.children[i];
            if (child.shape == nullptr) { return nullptr; }
            Ref<Shape> childShape = makeShape(*child.shape);
            if (childShape == nullptr) { return nullptr; }
            settings.AddShape(vec3(child.position), quat(child.rotation), childShape);
        }
        // A single posed child becomes a rotated/translated shape and a single
        // unposed child becomes the child itself (the library's collapse).
        Shape::ShapeResult result = settings.Create();
        if (result.HasError()) { return nullptr; }
        return result.Get();
    }
    }
    return nullptr;
}

} // namespace

// World ---------------------------------------------------------------------

CJoltWorld *cjolt_world_create(float gravityX, float gravityY, float gravityZ,
                               uint32_t maxBodies) {
    ensureLibraryInitialized();
    CJoltWorld *world = new CJoltWorld();
    const uint bodies = std::max(64u, maxBodies);
    world->physics.Init(bodies, 0, std::max(1024u, bodies), std::max(1024u, bodies),
                        world->broadPhaseLayers, world->objectVsBroadPhase,
                        world->objectPairs);
    world->physics.SetGravity(Vec3(gravityX, gravityY, gravityZ));
    world->physics.SetContactListener(&world->contacts);
    return world;
}

void cjolt_world_destroy(CJoltWorld *world) {
    if (world == nullptr) { return; }
    // Vehicles first: each is a constraint *and* a step listener, and both
    // registrations have to come off while the system is still alive.
    for (CJoltVehicle *vehicle : world->vehicles) {
        world->physics.RemoveStepListener(vehicle->constraint);
        world->physics.RemoveConstraint(vehicle->constraint);
        delete vehicle;
    }
    world->vehicles.clear();
    for (CJoltConstraint *constraint : world->constraints) {
        world->physics.RemoveConstraint(constraint->constraint);
        delete constraint;
    }
    world->constraints.clear();
    // Characters before the world: releasing one destroys its inner body
    // through the physics system, which has to still be alive to hear it.
    for (CJoltCharacter *character : world->characters) {
        world->characterCollision.Remove(character->character);
        delete character;
    }
    world->characters.clear();
    delete world;
}

void cjolt_world_set_gravity(CJoltWorld *world, float x, float y, float z) {
    world->physics.SetGravity(Vec3(x, y, z));
}

int cjolt_world_step(CJoltWorld *world, float dt, int collisionSteps) {
    EPhysicsUpdateError error = world->physics.Update(
        dt, std::max(1, collisionSteps), &world->tempAllocator, &world->jobSystem);
    return int(error);
}

void cjolt_world_optimize(CJoltWorld *world) { world->physics.OptimizeBroadPhase(); }

// Bodies --------------------------------------------------------------------

CJoltBodyID cjolt_body_create(CJoltWorld *world, const CJoltBodyDesc *desc) {
    Ref<Shape> shape = makeShape(desc->shape);
    if (shape == nullptr) { return CJOLT_BODY_INVALID; }

    // Moving the center of mass wraps the finished shape rather than changing
    // it: the body's reported position stays the shape's origin, so whatever
    // the sketch draws is unmoved while the mass hangs somewhere else.
    const Vec3 centerOfMass = vec3(desc->centerOfMass);
    if (centerOfMass.LengthSq() > 0) {
        Shape::ShapeResult offset =
            OffsetCenterOfMassShapeSettings(centerOfMass, shape).Create();
        if (!offset.HasError()) { shape = offset.Get(); }
    }

    EMotionType motion = EMotionType::Static;
    ObjectLayer layer = Layers::NON_MOVING;
    switch (desc->motion) {
    case CJOLT_MOTION_STATIC: break;
    case CJOLT_MOTION_KINEMATIC:
        motion = EMotionType::Kinematic;
        layer = Layers::MOVING;
        break;
    case CJOLT_MOTION_DYNAMIC:
        motion = EMotionType::Dynamic;
        layer = Layers::MOVING;
        break;
    }
    // A sensor is a detector volume, not a solid: it goes in the layer that
    // pairs only with moving bodies, and it is kinematic and kept awake so it
    // keeps reporting a body that falls asleep inside it (a static sensor
    // only ever sees active bodies, and the contact is dropped the moment one
    // settles, which is the wrong answer for a pressure plate).
    if (desc->isSensor) {
        motion = EMotionType::Kinematic;
        layer = Layers::SENSOR;
    }
    // A dynamic body cannot ride a static-only shape (mesh, height field, or
    // a compound containing one); keep the body but pin it in place.
    if (shape->MustBeStatic() && motion != EMotionType::Static) {
        motion = EMotionType::Static;
        layer = desc->isSensor ? Layers::SENSOR : Layers::NON_MOVING;
    }

    BodyCreationSettings settings(shape, RVec3(vec3(desc->position)),
                                  quat(desc->rotation), motion, layer);
    settings.mIsSensor = desc->isSensor;
    settings.mFriction = std::max(0.0f, desc->friction);
    settings.mRestitution = std::clamp(desc->restitution, 0.0f, 1.0f);
    settings.mLinearDamping = std::max(0.0f, desc->linearDamping);
    settings.mAngularDamping = std::max(0.0f, desc->angularDamping);
    settings.mGravityFactor = desc->gravityFactor;
    settings.mAllowSleeping = desc->allowSleep;
    // Bodies may switch motion type later (a static anchor released to fall).
    // Not with a static-only shape, though: allowing the switch makes body
    // creation compute mass properties, which a mesh or height field cannot
    // provide (a real trap inside the library, not just a bad number).
    settings.mAllowDynamicOrKinematic = !shape->MustBeStatic();
    // An explicit mass replaces the one the shape's volume and density give,
    // with the inertia recomputed for the shape at that mass (a car is 1500 kg
    // however big the box around it is).
    if (desc->mass > 0 && motion == EMotionType::Dynamic) {
        settings.mOverrideMassProperties = EOverrideMassProperties::CalculateInertia;
        settings.mMassPropertiesOverride.mMass = desc->mass;
    }

    BodyID id = world->physics.GetBodyInterface().CreateAndAddBody(
        settings, motion == EMotionType::Static ? EActivation::DontActivate
                                                : EActivation::Activate);
    return id.IsInvalid() ? CJOLT_BODY_INVALID : id.GetIndexAndSequenceNumber();
}

void cjolt_body_destroy(CJoltWorld *world, CJoltBodyID body) {
    BodyID id{body};
    BodyInterface &bodies = world->physics.GetBodyInterface();
    bodies.RemoveBody(id);
    bodies.DestroyBody(id);
}

void cjolt_body_get_position(const CJoltWorld *world, CJoltBodyID body, float out[3]) {
    CJoltWorld *w = const_cast<CJoltWorld *>(world);
    store(Vec3(w->physics.GetBodyInterface().GetPosition(BodyID(body))), out);
}

void cjolt_body_get_rotation(const CJoltWorld *world, CJoltBodyID body, float out[4]) {
    CJoltWorld *w = const_cast<CJoltWorld *>(world);
    store(w->physics.GetBodyInterface().GetRotation(BodyID(body)), out);
}

void cjolt_body_get_transform(const CJoltWorld *world, CJoltBodyID body, float out[16]) {
    CJoltWorld *w = const_cast<CJoltWorld *>(world);
    RMat44 transform = w->physics.GetBodyInterface().GetWorldTransform(BodyID(body));
    for (int column = 0; column < 4; ++column) {
        Vec4 value = transform.GetColumn4(column);
        out[4 * column + 0] = value.GetX();
        out[4 * column + 1] = value.GetY();
        out[4 * column + 2] = value.GetZ();
        out[4 * column + 3] = value.GetW();
    }
}

void cjolt_body_set_position(CJoltWorld *world, CJoltBodyID body, const float pos[3],
                             bool activate) {
    world->physics.GetBodyInterface().SetPosition(
        BodyID(body), RVec3(vec3(pos)),
        activate ? EActivation::Activate : EActivation::DontActivate);
}

void cjolt_body_set_rotation(CJoltWorld *world, CJoltBodyID body, const float q[4],
                             bool activate) {
    world->physics.GetBodyInterface().SetRotation(
        BodyID(body), quat(q), activate ? EActivation::Activate : EActivation::DontActivate);
}

void cjolt_body_get_linear_velocity(const CJoltWorld *world, CJoltBodyID body,
                                    float out[3]) {
    CJoltWorld *w = const_cast<CJoltWorld *>(world);
    store(w->physics.GetBodyInterface().GetLinearVelocity(BodyID(body)), out);
}

void cjolt_body_set_linear_velocity(CJoltWorld *world, CJoltBodyID body, const float v[3]) {
    world->physics.GetBodyInterface().SetLinearVelocity(BodyID(body), vec3(v));
}

void cjolt_body_get_angular_velocity(const CJoltWorld *world, CJoltBodyID body,
                                     float out[3]) {
    CJoltWorld *w = const_cast<CJoltWorld *>(world);
    store(w->physics.GetBodyInterface().GetAngularVelocity(BodyID(body)), out);
}

void cjolt_body_set_angular_velocity(CJoltWorld *world, CJoltBodyID body,
                                     const float v[3]) {
    world->physics.GetBodyInterface().SetAngularVelocity(BodyID(body), vec3(v));
}

void cjolt_body_add_force(CJoltWorld *world, CJoltBodyID body, const float force[3]) {
    world->physics.GetBodyInterface().AddForce(BodyID(body), vec3(force));
}

void cjolt_body_add_force_at(CJoltWorld *world, CJoltBodyID body, const float force[3],
                             const float worldPoint[3]) {
    world->physics.GetBodyInterface().AddForce(BodyID(body), vec3(force),
                                               RVec3(vec3(worldPoint)));
}

void cjolt_body_add_impulse(CJoltWorld *world, CJoltBodyID body, const float impulse[3]) {
    world->physics.GetBodyInterface().AddImpulse(BodyID(body), vec3(impulse));
}

void cjolt_body_add_torque(CJoltWorld *world, CJoltBodyID body, const float torque[3]) {
    world->physics.GetBodyInterface().AddTorque(BodyID(body), vec3(torque));
}

void cjolt_body_move_kinematic(CJoltWorld *world, CJoltBodyID body, const float pos[3],
                               const float q[4], float dt) {
    world->physics.GetBodyInterface().MoveKinematic(BodyID(body), RVec3(vec3(pos)),
                                                    quat(q), std::max(dt, 1.0e-4f));
}

float cjolt_body_get_mass(const CJoltWorld *world, CJoltBodyID body) {
    CJoltWorld *w = const_cast<CJoltWorld *>(world);
    Body *resolved = resolveBody(w, body);
    if (resolved == nullptr || !resolved->IsDynamic()) { return 0.0f; }
    float inverseMass = resolved->GetMotionProperties()->GetInverseMass();
    return inverseMass > 0 ? 1.0f / inverseMass : 0.0f;
}

void cjolt_body_set_motion(CJoltWorld *world, CJoltBodyID body, CJoltMotionType motion) {
    BodyInterface &bodies = world->physics.GetBodyInterface();
    BodyID id{body};
    // A static-only shape (mesh, height field) can never start moving.
    if (motion != CJOLT_MOTION_STATIC) {
        RefConst<Shape> shape = bodies.GetShape(id);
        if (shape != nullptr && shape->MustBeStatic()) { return; }
    }
    EMotionType type = EMotionType::Static;
    ObjectLayer layer = Layers::NON_MOVING;
    switch (motion) {
    case CJOLT_MOTION_STATIC: break;
    case CJOLT_MOTION_KINEMATIC:
        type = EMotionType::Kinematic;
        layer = Layers::MOVING;
        break;
    case CJOLT_MOTION_DYNAMIC:
        type = EMotionType::Dynamic;
        layer = Layers::MOVING;
        break;
    }
    bodies.SetMotionType(id, type,
                         type == EMotionType::Static ? EActivation::DontActivate
                                                     : EActivation::Activate);
    bodies.SetObjectLayer(id, layer);
}

bool cjolt_body_is_active(const CJoltWorld *world, CJoltBodyID body) {
    CJoltWorld *w = const_cast<CJoltWorld *>(world);
    return w->physics.GetBodyInterface().IsActive(BodyID(body));
}

void cjolt_body_activate(CJoltWorld *world, CJoltBodyID body) {
    world->physics.GetBodyInterface().ActivateBody(BodyID(body));
}

void cjolt_body_set_friction(CJoltWorld *world, CJoltBodyID body, float friction) {
    world->physics.GetBodyInterface().SetFriction(BodyID(body), std::max(0.0f, friction));
}

void cjolt_body_set_restitution(CJoltWorld *world, CJoltBodyID body, float restitution) {
    world->physics.GetBodyInterface().SetRestitution(BodyID(body),
                                                     std::clamp(restitution, 0.0f, 1.0f));
}

void cjolt_body_set_gravity_factor(CJoltWorld *world, CJoltBodyID body, float factor) {
    world->physics.GetBodyInterface().SetGravityFactor(BodyID(body), factor);
}

// Constraints ---------------------------------------------------------------

CJoltConstraint *cjolt_constraint_create(CJoltWorld *world, CJoltBodyID bodyA,
                                         CJoltBodyID bodyB,
                                         const CJoltConstraintDesc *desc) {
    Body *a = resolveBody(world, bodyA);
    Body *b = resolveBody(world, bodyB);
    if (a == nullptr || b == nullptr) { return nullptr; }

    Constraint *constraint = nullptr;
    switch (desc->type) {
    case CJOLT_CONSTRAINT_HINGE: {
        HingeConstraintSettings settings;
        settings.mSpace = EConstraintSpace::WorldSpace;
        settings.mPoint1 = settings.mPoint2 = RVec3(vec3(desc->anchorA));
        Vec3 axis = vec3(desc->axis);
        if (axis.LengthSq() < 1.0e-12f) { axis = Vec3::sAxisY(); }
        axis = axis.Normalized();
        settings.mHingeAxis1 = settings.mHingeAxis2 = axis;
        settings.mNormalAxis1 = settings.mNormalAxis2 = axis.GetNormalizedPerpendicular();
        if (desc->hasLimits) {
            settings.mLimitsMin = desc->limitMin;
            settings.mLimitsMax = desc->limitMax;
        }
        constraint = settings.Create(*a, *b);
        break;
    }
    case CJOLT_CONSTRAINT_POINT: {
        PointConstraintSettings settings;
        settings.mSpace = EConstraintSpace::WorldSpace;
        settings.mPoint1 = settings.mPoint2 = RVec3(vec3(desc->anchorA));
        constraint = settings.Create(*a, *b);
        break;
    }
    case CJOLT_CONSTRAINT_DISTANCE: {
        DistanceConstraintSettings settings;
        settings.mSpace = EConstraintSpace::WorldSpace;
        settings.mPoint1 = RVec3(vec3(desc->anchorA));
        settings.mPoint2 = RVec3(vec3(desc->anchorB));
        if (desc->hasLimits) {
            settings.mMinDistance = desc->limitMin;
            settings.mMaxDistance = desc->limitMax;
        }
        if (desc->frequency > 0) {
            settings.mLimitsSpringSettings = SpringSettings(
                ESpringMode::FrequencyAndDamping, desc->frequency, desc->damping);
        }
        constraint = settings.Create(*a, *b);
        break;
    }
    case CJOLT_CONSTRAINT_SLIDER: {
        SliderConstraintSettings settings;
        settings.mSpace = EConstraintSpace::WorldSpace;
        settings.mPoint1 = settings.mPoint2 = RVec3(vec3(desc->anchorA));
        Vec3 axis = vec3(desc->axis);
        if (axis.LengthSq() < 1.0e-12f) { axis = Vec3::sAxisX(); }
        settings.SetSliderAxis(axis.Normalized());
        if (desc->hasLimits) {
            settings.mLimitsMin = desc->limitMin;
            settings.mLimitsMax = desc->limitMax;
        }
        constraint = settings.Create(*a, *b);
        break;
    }
    case CJOLT_CONSTRAINT_FIXED: {
        FixedConstraintSettings settings;
        settings.mSpace = EConstraintSpace::WorldSpace;
        settings.mAutoDetectPoint = true;
        constraint = settings.Create(*a, *b);
        break;
    }
    }
    if (constraint == nullptr) { return nullptr; }

    world->physics.AddConstraint(constraint);
    CJoltConstraint *wrapper = new CJoltConstraint();
    wrapper->constraint = constraint;
    world->constraints.push_back(wrapper);
    return wrapper;
}

void cjolt_constraint_destroy(CJoltWorld *world, CJoltConstraint *constraint) {
    if (constraint == nullptr) { return; }
    world->physics.RemoveConstraint(constraint->constraint);
    world->constraints.erase(
        std::remove(world->constraints.begin(), world->constraints.end(), constraint),
        world->constraints.end());
    delete constraint;
}

void cjolt_constraint_set_motor(CJoltWorld *world, CJoltConstraint *wrapper,
                                CJoltMotorState state, float target,
                                float frequency, float damping, float maxEffort) {
    if (wrapper == nullptr) { return; }
    Constraint *constraint = wrapper->constraint;
    const EMotorState motorState =
        state == CJOLT_MOTOR_VELOCITY   ? EMotorState::Velocity
        : state == CJOLT_MOTOR_POSITION ? EMotorState::Position
                                        : EMotorState::Off;
    const SpringSettings servo(ESpringMode::FrequencyAndDamping,
                               std::max(frequency, 0.0f), std::max(damping, 0.0f));
    const bool limited = std::isfinite(maxEffort) && maxEffort > 0;

    switch (constraint->GetSubType()) {
    case EConstraintSubType::Hinge: {
        HingeConstraint *hinge = static_cast<HingeConstraint *>(constraint);
        MotorSettings &motor = hinge->GetMotorSettings();
        motor.mSpringSettings = servo;
        if (limited) { motor.SetTorqueLimit(maxEffort); }
        else { motor.SetTorqueLimits(-FLT_MAX, FLT_MAX); }
        hinge->SetTargetAngularVelocity(state == CJOLT_MOTOR_VELOCITY ? target : 0);
        if (state == CJOLT_MOTOR_POSITION) { hinge->SetTargetAngle(target); }
        hinge->SetMotorState(motorState);
        break;
    }
    case EConstraintSubType::Slider: {
        SliderConstraint *slider = static_cast<SliderConstraint *>(constraint);
        MotorSettings &motor = slider->GetMotorSettings();
        motor.mSpringSettings = servo;
        if (limited) { motor.SetForceLimit(maxEffort); }
        else { motor.SetForceLimits(-FLT_MAX, FLT_MAX); }
        slider->SetTargetVelocity(state == CJOLT_MOTOR_VELOCITY ? target : 0);
        if (state == CJOLT_MOTOR_POSITION) { slider->SetTargetPosition(target); }
        slider->SetMotorState(motorState);
        break;
    }
    default:
        return;
    }

    // A sleeping pair never feels a motor change; wake both ends (activation
    // skips static bodies internally).
    TwoBodyConstraint *pair = static_cast<TwoBodyConstraint *>(constraint);
    BodyInterface &bodies = world->physics.GetBodyInterface();
    bodies.ActivateBody(pair->GetBody1()->GetID());
    bodies.ActivateBody(pair->GetBody2()->GetID());
}

void cjolt_constraint_set_friction(CJoltWorld *, CJoltConstraint *wrapper,
                                   float friction) {
    if (wrapper == nullptr) { return; }
    Constraint *constraint = wrapper->constraint;
    const float drag = std::max(friction, 0.0f);
    switch (constraint->GetSubType()) {
    case EConstraintSubType::Hinge:
        static_cast<HingeConstraint *>(constraint)->SetMaxFrictionTorque(drag);
        break;
    case EConstraintSubType::Slider:
        static_cast<SliderConstraint *>(constraint)->SetMaxFrictionForce(drag);
        break;
    default:
        break;
    }
}

void cjolt_constraint_set_limit_spring(CJoltWorld *, CJoltConstraint *wrapper,
                                       float frequency, float damping) {
    if (wrapper == nullptr) { return; }
    Constraint *constraint = wrapper->constraint;
    const SpringSettings spring(ESpringMode::FrequencyAndDamping,
                                std::max(frequency, 0.0f), std::max(damping, 0.0f));
    switch (constraint->GetSubType()) {
    case EConstraintSubType::Hinge:
        static_cast<HingeConstraint *>(constraint)->SetLimitsSpringSettings(spring);
        break;
    case EConstraintSubType::Slider:
        static_cast<SliderConstraint *>(constraint)->SetLimitsSpringSettings(spring);
        break;
    default:
        break;
    }
}

float cjolt_constraint_current(const CJoltWorld *, const CJoltConstraint *wrapper) {
    if (wrapper == nullptr) { return 0; }
    const Constraint *constraint = wrapper->constraint.GetPtr();
    switch (constraint->GetSubType()) {
    case EConstraintSubType::Hinge:
        return static_cast<const HingeConstraint *>(constraint)->GetCurrentAngle();
    case EConstraintSubType::Slider:
        return static_cast<const SliderConstraint *>(constraint)->GetCurrentPosition();
    default:
        return 0;
    }
}

// Grab ----------------------------------------------------------------------

CJoltConstraint *cjolt_grab_begin(CJoltWorld *world, CJoltBodyID body,
                                  const float worldPoint[3]) {
    Body *grabbed = resolveBody(world, body);
    if (body == CJOLT_BODY_INVALID || grabbed == nullptr) { return nullptr; }

    BodyInterface &bodies = world->physics.GetBodyInterface();
    // The anchor is a static body that is created but never ADDED to the
    // world: nothing can collide with it, and teleporting it each move keeps
    // its velocity zero, so the spring below can only ever bleed energy.
    // (A kinematic anchor driven by velocity feeds that velocity into the
    // constraint and pumps the dragged body into orbit, a real bug.)
    Body *anchorBody = bodies.CreateBody(
        BodyCreationSettings(new SphereShape(0.01f), RVec3(vec3(worldPoint)),
                             Quat::sIdentity(), EMotionType::Static,
                             Layers::NON_MOVING));
    if (anchorBody == nullptr) { return nullptr; }

    // A soft zero-length spring rather than a rigid weld, so the drag has
    // give and settles when the hand stops.
    DistanceConstraintSettings settings;
    settings.mSpace = EConstraintSpace::WorldSpace;
    settings.mPoint1 = settings.mPoint2 = RVec3(vec3(worldPoint));
    settings.mLimitsSpringSettings.mFrequency = 2.0f;
    settings.mLimitsSpringSettings.mDamping = 1.0f;
    Constraint *constraint = settings.Create(*anchorBody, *grabbed);
    world->physics.AddConstraint(constraint);
    bodies.ActivateBody(BodyID(body));

    CJoltConstraint *wrapper = new CJoltConstraint();
    wrapper->constraint = constraint;
    wrapper->grabAnchor = anchorBody->GetID();
    wrapper->grabbedBody = BodyID(body);
    world->constraints.push_back(wrapper);
    return wrapper;
}

void cjolt_grab_move(CJoltWorld *world, CJoltConstraint *grab, const float target[3]) {
    if (grab == nullptr || grab->grabAnchor.IsInvalid()) { return; }
    BodyInterface &bodies = world->physics.GetBodyInterface();
    bodies.SetPositionAndRotation(grab->grabAnchor, RVec3(vec3(target)),
                                  Quat::sIdentity(), EActivation::DontActivate);
    // Keep the dragged body awake for as long as the hand holds it.
    bodies.ActivateBody(grab->grabbedBody);
}

void cjolt_grab_end(CJoltWorld *world, CJoltConstraint *grab) {
    if (grab == nullptr) { return; }
    BodyID anchor = grab->grabAnchor;
    cjolt_constraint_destroy(world, grab);
    if (!anchor.IsInvalid()) {
        // The anchor was never added to the world, so it is only destroyed.
        world->physics.GetBodyInterface().DestroyBody(anchor);
    }
}

// Contacts ------------------------------------------------------------------

int32_t cjolt_world_contact_count(const CJoltWorld *world) {
    return const_cast<CJoltWorld *>(world)->contacts.count();
}

int32_t cjolt_world_drain_contacts(CJoltWorld *world, CJoltContactEvent *out,
                                   int32_t capacity) {
    return world->contacts.drain(out, capacity);
}

// Characters ----------------------------------------------------------------

namespace {

/// The capsule a character wears, built so the bottom of the shape sits at the
/// origin: the library measures a character from its feet, which is also the
/// point a sketch wants to place and draw from. `height` is the whole standing
/// height including both caps, so the cylinder between them is what is left
/// after the two hemispheres.
Ref<Shape> makeCharacterShape(float radius, float height) {
    const float r = std::max(radius, 1.0e-3f);
    const float cylinderHalf = std::max(0.5f * height - r, 1.0e-3f);
    return RotatedTranslatedShapeSettings(Vec3(0, cylinderHalf + r, 0),
                                          Quat::sIdentity(),
                                          new CapsuleShape(cylinderHalf, r))
        .Create()
        .Get();
}

} // namespace

CJoltCharacter *cjolt_character_create(CJoltWorld *world,
                                       const CJoltCharacterDesc *desc) {
    if (world == nullptr || desc == nullptr) { return nullptr; }
    const float radius = std::max(desc->radius, 1.0e-3f);
    Ref<Shape> shape = makeCharacterShape(radius, desc->height);
    if (shape == nullptr) { return nullptr; }

    Ref<CharacterVirtualSettings> settings = new CharacterVirtualSettings();
    settings->mShape = shape;
    settings->mUp = Vec3::sAxisY();
    settings->mMaxSlopeAngle = desc->maxSlopeAngle;
    settings->mMass = std::max(0.0f, desc->mass);
    settings->mMaxStrength = std::max(0.0f, desc->maxStrength);
    settings->mPredictiveContactDistance = desc->predictiveContactDistance;
    settings->mPenetrationRecoverySpeed = desc->penetrationRecoverySpeed;
    // Only contacts against the lower sphere of the capsule may hold the
    // character up; a hand brushing a wall higher up is something it collides
    // with, not something it stands on.
    settings->mSupportingVolume = Plane(Vec3::sAxisY(), -radius);
    // Mesh scenery is the character's usual floor, and its internal edges are
    // exactly what a swept capsule catches on.
    settings->mEnhancedInternalEdgeRemoval = true;
    // The inner body is what gives the character presence among the ordinary
    // bodies: ray picks find it, the contact listener reports it, sensors see
    // it walk in, and fast bodies cannot pass through it in one step. It is
    // slightly smaller than the character so it never collides before the
    // swept shape does.
    settings->mInnerBodyShape = makeCharacterShape(0.9f * radius, 0.9f * desc->height);
    settings->mInnerBodyLayer = Layers::MOVING;

    CJoltCharacter *wrapper = new CJoltCharacter();
    wrapper->character = new CharacterVirtual(settings, RVec3(vec3(desc->position)),
                                              quat(desc->rotation), 0, &world->physics);
    wrapper->stepHeight = std::max(0.0f, desc->stepHeight);
    wrapper->stickToFloor = std::max(0.0f, desc->stickToFloor);
    // Characters live outside the broad phase, so they can only see each other
    // through the world's list.
    wrapper->character->SetCharacterVsCharacterCollision(&world->characterCollision);
    world->characterCollision.Add(wrapper->character);
    world->characters.push_back(wrapper);
    return wrapper;
}

void cjolt_character_destroy(CJoltWorld *world, CJoltCharacter *character) {
    if (world == nullptr || character == nullptr) { return; }
    world->characterCollision.Remove(character->character);
    world->characters.erase(
        std::remove(world->characters.begin(), world->characters.end(), character),
        world->characters.end());
    // Releasing the last reference destroys the inner body through the system.
    delete character;
}

void cjolt_character_get_position(const CJoltCharacter *character, float out[3]) {
    store(Vec3(character->character->GetPosition()), out);
}

void cjolt_character_set_position(CJoltCharacter *character, const float pos[3]) {
    character->character->SetPosition(RVec3(vec3(pos)));
}

void cjolt_character_get_rotation(const CJoltCharacter *character, float out[4]) {
    store(character->character->GetRotation(), out);
}

void cjolt_character_set_rotation(CJoltCharacter *character, const float q[4]) {
    character->character->SetRotation(quat(q));
}

void cjolt_character_get_velocity(const CJoltCharacter *character, float out[3]) {
    store(character->character->GetLinearVelocity(), out);
}

void cjolt_character_set_velocity(CJoltCharacter *character, const float v[3]) {
    character->character->SetLinearVelocity(vec3(v));
}

void cjolt_character_set_max_slope(CJoltCharacter *character, float radians) {
    character->character->SetMaxSlopeAngle(radians);
}

void cjolt_character_set_step_height(CJoltCharacter *character, float height) {
    character->stepHeight = std::max(0.0f, height);
}

void cjolt_character_set_stick_to_floor(CJoltCharacter *character, float distance) {
    character->stickToFloor = std::max(0.0f, distance);
}

void cjolt_character_set_mass(CJoltCharacter *character, float mass) {
    character->character->SetMass(std::max(0.0f, mass));
}

void cjolt_character_set_max_strength(CJoltCharacter *character, float newtons) {
    character->character->SetMaxStrength(std::max(0.0f, newtons));
}

CJoltGroundState cjolt_character_get_ground_state(const CJoltCharacter *character) {
    switch (character->character->GetGroundState()) {
    case CharacterBase::EGroundState::OnGround: return CJOLT_GROUND_ON_GROUND;
    case CharacterBase::EGroundState::OnSteepGround: return CJOLT_GROUND_ON_STEEP;
    case CharacterBase::EGroundState::NotSupported: return CJOLT_GROUND_NOT_SUPPORTED;
    case CharacterBase::EGroundState::InAir: break;
    }
    return CJOLT_GROUND_IN_AIR;
}

void cjolt_character_get_ground_normal(const CJoltCharacter *character, float out[3]) {
    store(character->character->GetGroundNormal(), out);
}

void cjolt_character_get_ground_velocity(const CJoltCharacter *character, float out[3]) {
    store(character->character->GetGroundVelocity(), out);
}

CJoltBodyID cjolt_character_get_ground_body(const CJoltCharacter *character) {
    const BodyID id = character->character->GetGroundBodyID();
    return id.IsInvalid() ? CJOLT_BODY_INVALID : id.GetIndexAndSequenceNumber();
}

CJoltBodyID cjolt_character_get_inner_body(const CJoltCharacter *character) {
    const BodyID id = character->character->GetInnerBodyID();
    return id.IsInvalid() ? CJOLT_BODY_INVALID : id.GetIndexAndSequenceNumber();
}

bool cjolt_character_is_slope_too_steep(const CJoltCharacter *character,
                                        const float normal[3]) {
    return character->character->IsSlopeTooSteep(vec3(normal));
}

void cjolt_character_update(CJoltWorld *world, CJoltCharacter *character, float dt,
                            const float gravity[3]) {
    if (world == nullptr || character == nullptr || dt <= 0.0f) { return; }
    CharacterVirtual *self = character->character;
    const Vec3 up = self->GetUp();

    // ExtendedUpdate is the combined move: it sweeps the shape, then tries to
    // step onto anything shorter than the step height, then pulls the
    // character back down onto a floor it would otherwise skip off. Both
    // distances run along the character's own up axis.
    CharacterVirtual::ExtendedUpdateSettings settings;
    settings.mStickToFloorStepDown = -up * character->stickToFloor;
    settings.mWalkStairsStepUp = up * character->stepHeight;

    self->ExtendedUpdate(dt, vec3(gravity), settings,
                         world->physics.GetDefaultBroadPhaseLayerFilter(Layers::MOVING),
                         world->physics.GetDefaultLayerFilter(Layers::MOVING), {}, {},
                         world->tempAllocator);
}

void cjolt_character_refresh_contacts(CJoltWorld *world, CJoltCharacter *character) {
    if (world == nullptr || character == nullptr) { return; }
    character->character->RefreshContacts(
        world->physics.GetDefaultBroadPhaseLayerFilter(Layers::MOVING),
        world->physics.GetDefaultLayerFilter(Layers::MOVING), {}, {},
        world->tempAllocator);
}

// Vehicles ------------------------------------------------------------------

namespace {

/// The gearing that makes top gear at the engine's redline turn a wheel of
/// `radius` at `topSpeed`. Engine and wheel are separated by the gearbox ratio
/// times the differential ratio, so with the gearbox fixed there is one number
/// left to solve for.
float solveDifferentialRatio(float maxRPM, float topGear, float topSpeed,
                             float radius) {
    if (topSpeed <= 0 || radius <= 0 || topGear <= 0) { return 3.42f; }
    const float wheelOmega = topSpeed / radius;                     // rad/s
    const float engineOmega = maxRPM * (2.0f * JPH_PI / 60.0f);     // rad/s
    return std::clamp(engineOmega / (wheelOmega * topGear), 0.05f, 200.0f);
}

WheeledVehicleController *controllerOf(const CJoltVehicle *vehicle) {
    return static_cast<WheeledVehicleController *>(
        vehicle->constraint->GetController());
}

/// Writes a wheel description onto a wheel's settings. Every one of these is
/// read again on each step, so the same function serves the initial build and
/// a live retune. The friction curves are rebuilt from the library's own tire
/// before grip scales them, so repeated calls cannot compound.
void applyWheelDesc(WheelSettingsWV &wheel, const CJoltWheelDesc &desc) {
    wheel.mPosition = vec3(desc.position);
    wheel.mRadius = std::max(desc.radius, 1.0e-3f);
    wheel.mWidth = std::max(desc.width, 1.0e-3f);
    wheel.mSuspensionMaxLength = std::max(desc.suspensionMaxLength, 0.0f);
    wheel.mSuspensionMinLength =
        std::clamp(desc.suspensionMinLength, 0.0f, wheel.mSuspensionMaxLength);
    wheel.mSuspensionSpring = SpringSettings(ESpringMode::FrequencyAndDamping,
                                             std::max(desc.suspensionFrequency, 0.01f),
                                             std::max(desc.suspensionDamping, 0.0f));
    // Raking the fork back tilts the suspension and the steering axis
    // together, which is the trail that lets a two-wheeler hold a line.
    if (desc.casterAngle != 0) {
        const float rake = std::clamp(desc.casterAngle, -1.4f, 1.4f);
        wheel.mSuspensionDirection = Vec3(0, -1, std::tan(rake)).Normalized();
        wheel.mSteeringAxis = -wheel.mSuspensionDirection;
    } else {
        wheel.mSuspensionDirection = Vec3(0, -1, 0);
        wheel.mSteeringAxis = Vec3(0, 1, 0);
    }
    wheel.mMaxSteerAngle = std::clamp(desc.maxSteerAngle, 0.0f, 0.5f * JPH_PI);
    wheel.mMaxBrakeTorque = std::max(desc.maxBrakeTorque, 0.0f);
    wheel.mMaxHandBrakeTorque = std::max(desc.maxHandBrakeTorque, 0.0f);

    // Grip scales the tire's own friction curves; the ground body's friction
    // is combined with them by the solver on top of this.
    const WheelSettingsWV tire;
    wheel.mLongitudinalFriction = tire.mLongitudinalFriction;
    wheel.mLateralFriction = tire.mLateralFriction;
    if (desc.grip > 0 && desc.grip != 1.0f) {
        for (LinearCurve::Point &p : wheel.mLongitudinalFriction.mPoints) {
            p.mY *= desc.grip;
        }
        for (LinearCurve::Point &p : wheel.mLateralFriction.mPoints) {
            p.mY *= desc.grip;
        }
    }
}

} // namespace

CJoltVehicle *cjolt_vehicle_create(CJoltWorld *world, CJoltBodyID chassisID,
                                   const CJoltVehicleDesc *desc) {
    if (world == nullptr || desc == nullptr || desc->wheels == nullptr ||
        desc->wheelCount < 1 || chassisID == CJOLT_BODY_INVALID) {
        return nullptr;
    }
    Body *chassis = resolveBody(world, chassisID);
    if (chassis == nullptr) { return nullptr; }

    VehicleConstraintSettings vehicle;
    vehicle.mUp = Vec3::sAxisY();
    vehicle.mForward = Vec3::sAxisZ();
    vehicle.mMaxPitchRollAngle =
        desc->maxPitchRollAngle > 0 ? desc->maxPitchRollAngle : JPH_PI;

    float narrowest = FLT_MAX;
    for (int32_t i = 0; i < desc->wheelCount; ++i) {
        WheelSettingsWV *wheel = new WheelSettingsWV();
        applyWheelDesc(*wheel, desc->wheels[i]);
        narrowest = std::min(narrowest, wheel->mWidth);
        vehicle.mWheels.push_back(wheel);
    }

    const bool leans = desc->leans;
    WheeledVehicleControllerSettings *controller =
        leans ? new MotorcycleControllerSettings()
              : new WheeledVehicleControllerSettings();
    controller->mEngine.mMaxTorque = std::max(desc->maxEngineTorque, 1.0f);
    if (leans) {
        MotorcycleControllerSettings *bike =
            static_cast<MotorcycleControllerSettings *>(controller);
        bike->mMaxLeanAngle = std::clamp(desc->maxLeanAngle, 0.0f, 0.5f * JPH_PI);
    }

    // Which axles the engine turns, and how big their wheels are: the
    // differential ratio is solved once against that radius so every driven
    // axle shares one gearing.
    const auto wheelInRange = [&](int32_t index) {
        return index >= 0 && index < desc->wheelCount;
    };
    int drivenAxles = 0;
    float drivenRadius = 0;
    int drivenWheels = 0;
    for (int32_t i = 0; i < desc->axleCount; ++i) {
        const CJoltAxleDesc &axle = desc->axles[i];
        if (!axle.driven) { continue; }
        ++drivenAxles;
        for (int32_t index : {axle.leftWheel, axle.rightWheel}) {
            if (wheelInRange(index)) {
                drivenRadius += vehicle.mWheels[index]->mRadius;
                ++drivenWheels;
            }
        }
    }
    drivenRadius = drivenWheels > 0 ? drivenRadius / float(drivenWheels)
                                    : vehicle.mWheels[0]->mRadius;
    const Array<float> &gears = controller->mTransmission.mGearRatios;
    const float ratio = solveDifferentialRatio(
        controller->mEngine.mMaxRPM, gears.empty() ? 1.0f : gears.back(),
        desc->topSpeed, drivenRadius);

    for (int32_t i = 0; i < desc->axleCount; ++i) {
        const CJoltAxleDesc &axle = desc->axles[i];
        const int32_t left = wheelInRange(axle.leftWheel) ? axle.leftWheel : -1;
        const int32_t right = wheelInRange(axle.rightWheel) ? axle.rightWheel : -1;
        if (left < 0 && right < 0) { continue; }
        if (axle.driven) {
            VehicleDifferentialSettings differential;
            differential.mLeftWheel = left;
            differential.mRightWheel = right;
            differential.mDifferentialRatio = ratio;
            differential.mEngineTorqueRatio = 1.0f / float(drivenAxles);
            controller->mDifferentials.push_back(differential);
        }
        // An anti-roll bar ties a pair together so the outside wheel's
        // compression lifts the inside one, which is what keeps a car flat
        // through a corner. A lone wheel has nothing to tie to.
        if (left >= 0 && right >= 0 && desc->antiRollStiffness > 0) {
            VehicleAntiRollBar bar;
            bar.mLeftWheel = left;
            bar.mRightWheel = right;
            bar.mStiffness = desc->antiRollStiffness;
            vehicle.mAntiRollBars.push_back(bar);
        }
    }
    // The controller's torque ratios must add up over at least one driven
    // differential, so a vehicle always has something the engine turns; the
    // caller picks which axle rather than leaving it to chance.
    if (controller->mDifferentials.empty()) { return nullptr; }

    vehicle.mController = controller;

    CJoltVehicle *wrapper = new CJoltVehicle();
    wrapper->drivenWheelRadius = drivenRadius;
    wrapper->groundFilter.chassis = chassis->GetID();
    wrapper->testers[0] = new VehicleCollisionTesterRay(Layers::MOVING);
    wrapper->testers[1] =
        new VehicleCollisionTesterCastSphere(Layers::MOVING, 0.5f * narrowest);
    wrapper->testers[2] = new VehicleCollisionTesterCastCylinder(Layers::MOVING);
    for (Ref<VehicleCollisionTester> &tester : wrapper->testers) {
        // Overriding the body filter replaces the default one that hides the
        // vehicle from itself, so this filter has to do that job too.
        tester->SetBodyFilter(&wrapper->groundFilter);
    }
    wrapper->constraint = new VehicleConstraint(*chassis, vehicle);
    cjolt_vehicle_set_wheel_contact(wrapper, desc->contact);

    world->physics.AddConstraint(wrapper->constraint);
    // Without the step listener the wheels are never collided or driven: the
    // vehicle keeps its shape and simply never moves. (Upstream's own header
    // warns about exactly this.)
    world->physics.AddStepListener(wrapper->constraint);
    world->vehicles.push_back(wrapper);
    return wrapper;
}

void cjolt_vehicle_destroy(CJoltWorld *world, CJoltVehicle *vehicle) {
    if (world == nullptr || vehicle == nullptr) { return; }
    world->physics.RemoveStepListener(vehicle->constraint);
    world->physics.RemoveConstraint(vehicle->constraint);
    world->vehicles.erase(
        std::remove(world->vehicles.begin(), world->vehicles.end(), vehicle),
        world->vehicles.end());
    delete vehicle;
}

void cjolt_vehicle_set_input(CJoltWorld *world, CJoltVehicle *vehicle,
                             float forward, float right, float brake,
                             float handBrake) {
    if (vehicle == nullptr) { return; }
    controllerOf(vehicle)->SetDriverInput(std::clamp(forward, -1.0f, 1.0f),
                                          std::clamp(right, -1.0f, 1.0f),
                                          std::clamp(brake, 0.0f, 1.0f),
                                          std::clamp(handBrake, 0.0f, 1.0f));
    // A settled vehicle is allowed to sleep, but one being driven never is.
    if (world != nullptr &&
        (forward != 0 || right != 0 || brake != 0 || handBrake != 0)) {
        world->physics.GetBodyInterface().ActivateBody(
            vehicle->constraint->GetVehicleBody()->GetID());
    }
}

void cjolt_vehicle_set_wheel_settings(CJoltVehicle *vehicle, int32_t index,
                                      const CJoltWheelDesc *desc) {
    if (vehicle == nullptr || desc == nullptr || index < 0 ||
        index >= int32_t(vehicle->constraint->GetWheels().size())) {
        return;
    }
    // The settings object belongs to this constraint alone (the bridge builds
    // one per wheel and hands it to nothing else), and the solver reads every
    // field of it fresh on each step, so writing through the wheel's const
    // handle is safe and takes effect next step.
    const Wheel *wheel = vehicle->constraint->GetWheel(uint(index));
    WheelSettingsWV *settings = const_cast<WheelSettingsWV *>(
        static_cast<const WheelSettingsWV *>(wheel->GetSettings()));
    applyWheelDesc(*settings, *desc);
}

void cjolt_vehicle_set_engine_torque(CJoltVehicle *vehicle, float maxTorque) {
    if (vehicle == nullptr) { return; }
    controllerOf(vehicle)->GetEngine().mMaxTorque = std::max(maxTorque, 1.0f);
}

void cjolt_vehicle_set_top_speed(CJoltVehicle *vehicle, float metersPerSecond) {
    if (vehicle == nullptr) { return; }
    WheeledVehicleController *controller = controllerOf(vehicle);
    const Array<float> &gears = controller->GetTransmission().mGearRatios;
    const float ratio = solveDifferentialRatio(
        controller->GetEngine().mMaxRPM, gears.empty() ? 1.0f : gears.back(),
        metersPerSecond, vehicle->drivenWheelRadius);
    for (VehicleDifferentialSettings &d : controller->GetDifferentials()) {
        d.mDifferentialRatio = ratio;
    }
}

void cjolt_vehicle_set_wheel_contact(CJoltVehicle *vehicle,
                                     CJoltWheelContact contact) {
    if (vehicle == nullptr) { return; }
    int index = contact == CJOLT_WHEEL_CONTACT_RAY      ? 0
                : contact == CJOLT_WHEEL_CONTACT_SPHERE ? 1
                                                        : 2;
    vehicle->constraint->SetVehicleCollisionTester(vehicle->testers[index]);
}

void cjolt_vehicle_set_max_pitch_roll(CJoltVehicle *vehicle, float radians) {
    if (vehicle == nullptr) { return; }
    vehicle->constraint->SetMaxPitchRollAngle(
        std::clamp(radians, 0.0f, JPH_PI));
}

void cjolt_vehicle_set_anti_roll(CJoltVehicle *vehicle, float stiffness) {
    if (vehicle == nullptr) { return; }
    for (VehicleAntiRollBar &bar : vehicle->constraint->GetAntiRollBars()) {
        bar.mStiffness = std::max(stiffness, 0.0f);
    }
}

int32_t cjolt_vehicle_get_wheel_count(const CJoltVehicle *vehicle) {
    if (vehicle == nullptr) { return 0; }
    return int32_t(vehicle->constraint->GetWheels().size());
}

void cjolt_vehicle_get_wheel(const CJoltVehicle *vehicle, int32_t index,
                             CJoltWheelState *out) {
    if (out == nullptr) { return; }
    *out = CJoltWheelState{};
    out->contactBody = CJOLT_BODY_INVALID;
    if (vehicle == nullptr || index < 0 ||
        index >= int32_t(vehicle->constraint->GetWheels().size())) {
        return;
    }
    VehicleConstraint *constraint = vehicle->constraint;
    const Wheel *wheel = constraint->GetWheel(uint(index));

    // The transform poses a cylinder modeled along +y, so the wheel's own
    // rotational axis (its "right") is that y and its "up" is x.
    RMat44 transform = constraint->GetWheelWorldTransform(
        uint(index), Vec3::sAxisY(), Vec3::sAxisX());
    store(Vec3(transform.GetTranslation()), out->position);
    store(transform.GetQuaternion().Normalized(), out->rotation);

    out->steerAngle = wheel->GetSteerAngle();
    out->rotationAngle = wheel->GetRotationAngle();
    out->angularVelocity = wheel->GetAngularVelocity();
    out->suspensionLength = wheel->GetSuspensionLength();
    out->hasContact = wheel->HasContact();
    if (out->hasContact) {
        out->contactBody = wheel->GetContactBodyID().GetIndexAndSequenceNumber();
        store(wheel->GetContactNormal(), out->contactNormal);
    }
    const WheelWV *wv = static_cast<const WheelWV *>(wheel);
    out->longitudinalSlip = wv->mLongitudinalSlip;
    out->lateralSlip = wv->mLateralSlip;
}

float cjolt_vehicle_get_rpm(const CJoltVehicle *vehicle) {
    if (vehicle == nullptr) { return 0; }
    return controllerOf(vehicle)->GetEngine().GetCurrentRPM();
}

int32_t cjolt_vehicle_get_gear(const CJoltVehicle *vehicle) {
    if (vehicle == nullptr) { return 0; }
    return int32_t(controllerOf(vehicle)->GetTransmission().GetCurrentGear());
}

// Queries -------------------------------------------------------------------

bool cjolt_world_ray_cast(const CJoltWorld *world, const float origin[3],
                          const float direction[3], CJoltBodyID *outBody,
                          float *outFraction) {
    CJoltWorld *w = const_cast<CJoltWorld *>(world);
    RRayCast ray{RVec3(vec3(origin)), vec3(direction)};
    RayCastResult hit;
    // Filter as a moving body would: statics stay visible, ghosts never hit.
    DefaultBroadPhaseLayerFilter broadPhaseFilter(w->objectVsBroadPhase, Layers::MOVING);
    DefaultObjectLayerFilter objectFilter(w->objectPairs, Layers::MOVING);
    NonSensorBodyFilter bodyFilter;
    if (!w->physics.GetNarrowPhaseQuery().CastRay(ray, hit, broadPhaseFilter,
                                                  objectFilter, bodyFilter)) {
        return false;
    }
    if (outBody != nullptr) { *outBody = hit.mBodyID.GetIndexAndSequenceNumber(); }
    if (outFraction != nullptr) { *outFraction = hit.mFraction; }
    return true;
}
