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
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>
#include <Jolt/Physics/Collision/Shape/ConvexHullShape.h>
#include <Jolt/Physics/Collision/Shape/CylinderShape.h>
#include <Jolt/Physics/Collision/Shape/HeightFieldShape.h>
#include <Jolt/Physics/Collision/Shape/MeshShape.h>
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
#include <Jolt/RegisterTypes.h>

#include <algorithm>
#include <cfloat>
#include <cmath>
#include <mutex>
#include <thread>
#include <vector>

#include "../include/cjolt.h"

namespace {

using namespace JPH;

// Object layers: statics only pair with moving bodies, and the ghost layer
// (grab anchors) pairs with nothing, so a grab can never nudge the scene by
// collision, only through its constraint.
namespace Layers {
constexpr ObjectLayer NON_MOVING = 0;
constexpr ObjectLayer MOVING = 1;
constexpr ObjectLayer GHOST = 2;
constexpr ObjectLayer NUM_LAYERS = 3;
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
        default: return false; // ghosts collide with nothing
        }
    }
};

class ObjectLayerPairFilterImpl final : public ObjectLayerPairFilter {
public:
    bool ShouldCollide(ObjectLayer inObject1, ObjectLayer inObject2) const override {
        if (inObject1 == Layers::GHOST || inObject2 == Layers::GHOST) { return false; }
        if (inObject1 == Layers::NON_MOVING && inObject2 == Layers::NON_MOVING) {
            return false;
        }
        return true;
    }
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

} // namespace

struct CJoltConstraint {
    JPH::Ref<JPH::Constraint> constraint;
    // Grabs carry the hidden static anchor their drag spring hangs on.
    JPH::BodyID grabAnchor = JPH::BodyID();
    JPH::BodyID grabbedBody = JPH::BodyID();
};

struct CJoltWorld {
    JPH::TempAllocatorImpl tempAllocator;
    JPH::JobSystemThreadPool jobSystem;
    BPLayerInterfaceImpl broadPhaseLayers;
    ObjectVsBroadPhaseLayerFilterImpl objectVsBroadPhase;
    ObjectLayerPairFilterImpl objectPairs;
    JPH::PhysicsSystem physics;
    std::vector<CJoltConstraint *> constraints;

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
    return world;
}

void cjolt_world_destroy(CJoltWorld *world) {
    if (world == nullptr) { return; }
    for (CJoltConstraint *constraint : world->constraints) {
        world->physics.RemoveConstraint(constraint->constraint);
        delete constraint;
    }
    world->constraints.clear();
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
    // A dynamic body cannot ride a static-only shape (mesh, height field, or
    // a compound containing one); keep the body but pin it in place.
    if (shape->MustBeStatic() && motion != EMotionType::Static) {
        motion = EMotionType::Static;
        layer = Layers::NON_MOVING;
    }

    BodyCreationSettings settings(shape, RVec3(vec3(desc->position)),
                                  quat(desc->rotation), motion, layer);
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
    if (!w->physics.GetNarrowPhaseQuery().CastRay(ray, hit, broadPhaseFilter,
                                                  objectFilter)) {
        return false;
    }
    if (outBody != nullptr) { *outBody = hit.mBodyID.GetIndexAndSequenceNumber(); }
    if (outFraction != nullptr) { *outFraction = hit.mFraction; }
    return true;
}
