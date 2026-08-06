// CJolt: Ollin's C bridge over the vendored Jolt Physics library.
// The only compilation unit in the repo that includes Jolt's C++ headers, so
// the JPH_* define-consistency rule holds by construction: every unit that
// sees a Jolt header lives in this one target with one set of settings.

#include <Jolt/Jolt.h>

#include <Jolt/Core/Factory.h>
#include <Jolt/Core/JobSystemThreadPool.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Body/BodyLock.h>
#include <Jolt/Physics/Collision/BroadPhase/BroadPhaseQuery.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/CollidePointResult.h>
#include <Jolt/Physics/Collision/CollideShape.h>
#include <Jolt/Physics/Collision/CollisionCollectorImpl.h>
#include <Jolt/Physics/Collision/ContactListener.h>
#include <Jolt/Physics/Collision/NarrowPhaseQuery.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/ShapeCast.h>
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
#include <Jolt/Physics/Constraints/GearConstraint.h>
#include <Jolt/Physics/Constraints/HingeConstraint.h>
#include <Jolt/Physics/Constraints/PathConstraint.h>
#include <Jolt/Physics/Constraints/PathConstraintPathHermite.h>
#include <Jolt/Physics/Constraints/PointConstraint.h>
#include <Jolt/Physics/Constraints/PulleyConstraint.h>
#include <Jolt/Physics/Constraints/RackAndPinionConstraint.h>
#include <Jolt/Physics/Constraints/SixDOFConstraint.h>
#include <Jolt/Physics/Constraints/SliderConstraint.h>
#include <Jolt/Physics/Constraints/SwingTwistConstraint.h>
#include <Jolt/Physics/PhysicsSettings.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/Ragdoll/Ragdoll.h>
#include <Jolt/Physics/SoftBody/SoftBodyContactListener.h>
#include <Jolt/Physics/SoftBody/SoftBodyCreationSettings.h>
#include <Jolt/Physics/SoftBody/SoftBodyManifold.h>
#include <Jolt/Physics/SoftBody/SoftBodyMotionProperties.h>
#include <Jolt/Physics/SoftBody/SoftBodySharedSettings.h>
#include <Jolt/Physics/Vehicle/MotorcycleController.h>
#include <Jolt/Physics/Vehicle/TrackedVehicleController.h>
#include <Jolt/Physics/Vehicle/VehicleCollisionTester.h>
#include <Jolt/Physics/Vehicle/VehicleConstraint.h>
#include <Jolt/Physics/Vehicle/WheeledVehicleController.h>
#include <Jolt/RegisterTypes.h>

#include <algorithm>
#include <cfloat>
#include <cmath>
#include <map>
#include <mutex>
#include <set>
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

// An object layer carries two things at once: what KIND of thing it is in the
// low two bits, and which collision GROUP it belongs to above them. Group 0
// leaves the layer numerically identical to the four fixed kinds, so a world
// that never mentions a group is indistinguishable from an ungrouped one.
//
// The kinds: statics only pair with moving bodies, the ghost kind (grab
// anchors) pairs with nothing, so a grab can never nudge the scene by
// collision, only through its constraint, and the sensor kind pairs only
// with moving bodies, since a detector volume has nothing to report about
// scenery that never moves or about another detector.
namespace Layers {
constexpr ObjectLayer NON_MOVING = 0;
constexpr ObjectLayer MOVING = 1;
constexpr ObjectLayer GHOST = 2;
constexpr ObjectLayer SENSOR = 3;
constexpr ObjectLayer KIND_BITS = 2;
constexpr ObjectLayer KIND_MASK = 3;
} // namespace Layers

/// The kind half of a layer (what the fixed rules are written against).
constexpr ObjectLayer layerKind(ObjectLayer layer) { return layer & Layers::KIND_MASK; }

/// The group half of a layer.
constexpr int32_t layerGroup(ObjectLayer layer) { return int32_t(layer >> Layers::KIND_BITS); }

/// The layer a thing of this kind in this group lives in. An out-of-range
/// group falls back to the default one rather than aliasing another group.
constexpr ObjectLayer layerFor(int32_t group, ObjectLayer kind) {
    const int32_t clamped = (group > 0 && group < CJOLT_MAX_GROUPS) ? group : 0;
    return ObjectLayer((uint32_t(clamped) << Layers::KIND_BITS) | kind);
}

/// Which groups collide with which: one bit per ordered pair, kept symmetric
/// by writing both ends. Everything collides until a caller says otherwise,
/// the diagonal included (two crates in one group still stack).
///
/// Written only from the main thread between steps, and read from the solver's
/// worker threads while one runs, which is safe because a step never writes it.
class GroupTable {
public:
    /// All bits set: everything collides with everything until told otherwise.
    GroupTable() {
        for (uint64_t &row : mRows) { row = ~uint64_t(0); }
    }

    void set(int32_t a, int32_t b, bool collide) {
        if (!inRange(a) || !inRange(b)) { return; }
        const uint64_t bitA = uint64_t(1) << uint32_t(b);
        const uint64_t bitB = uint64_t(1) << uint32_t(a);
        if (collide) {
            mRows[a] |= bitA;
            mRows[b] |= bitB;
        } else {
            mRows[a] &= ~bitA;
            mRows[b] &= ~bitB;
        }
    }

    bool collides(int32_t a, int32_t b) const {
        if (!inRange(a) || !inRange(b)) { return true; }
        return (mRows[a] & (uint64_t(1) << uint32_t(b))) != 0;
    }

private:
    static constexpr bool inRange(int32_t group) {
        return group >= 0 && group < CJOLT_MAX_GROUPS;
    }

    static_assert(CJOLT_MAX_GROUPS == 64, "a row holds one bit per group");
    uint64_t mRows[CJOLT_MAX_GROUPS] = {};
};

namespace BroadPhaseLayers {
constexpr BroadPhaseLayer NON_MOVING(0);
constexpr BroadPhaseLayer MOVING(1);
constexpr uint NUM_LAYERS(2);
} // namespace BroadPhaseLayers

class BPLayerInterfaceImpl final : public BroadPhaseLayerInterface {
public:
    uint GetNumBroadPhaseLayers() const override { return BroadPhaseLayers::NUM_LAYERS; }

    BroadPhaseLayer GetBroadPhaseLayer(ObjectLayer inLayer) const override {
        return layerKind(inLayer) == Layers::NON_MOVING ? BroadPhaseLayers::NON_MOVING
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
        // Groups are settled per pair in the narrow filter below; a broad-phase
        // tree holds every group at once, so only the kind can be answered here.
        switch (layerKind(inLayer1)) {
        case Layers::NON_MOVING: return inLayer2 == BroadPhaseLayers::MOVING;
        case Layers::MOVING: return true;
        case Layers::SENSOR: return inLayer2 == BroadPhaseLayers::MOVING;
        default: return false; // ghosts collide with nothing
        }
    }
};

class ObjectLayerPairFilterImpl final : public ObjectLayerPairFilter {
public:
    GroupTable groups;

    bool ShouldCollide(ObjectLayer inObject1, ObjectLayer inObject2) const override {
        const ObjectLayer kind1 = layerKind(inObject1);
        const ObjectLayer kind2 = layerKind(inObject2);
        if (kind1 == Layers::GHOST || kind2 == Layers::GHOST) { return false; }
        if (kind1 == Layers::SENSOR || kind2 == Layers::SENSOR) {
            if (kind1 != Layers::MOVING && kind2 != Layers::MOVING) { return false; }
        } else if (kind1 == Layers::NON_MOVING && kind2 == Layers::NON_MOVING) {
            return false;
        }
        return groups.collides(layerGroup(inObject1), layerGroup(inObject2));
    }
};

/// Everything that moves, whatever group it is in: the buoyancy sweep's filter.
/// It has to test the kind rather than compare whole layers, since a moving
/// body in any group is one the impulse must reach.
class MovingKindLayerFilter final : public ObjectLayerFilter {
public:
    bool ShouldCollide(ObjectLayer inLayer) const override {
        return layerKind(inLayer) == Layers::MOVING;
    }
};

/// A vehicle's wheels see the solid scene except their own chassis: the same
/// sensor rule the queries use (a detector volume is a region to be inside,
/// never a surface to stand on), plus the self-collision the collision
/// tester's default filter would otherwise have handled on its own.
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
//
// Soft bodies come through a second listener the solver keeps for them, whose
// shape is entirely different (see the soft half below), and both are recorded
// into this one buffer so a sketch reads one list.
class ContactRecorder final : public ContactListener,
                              public SoftBodyContactListener {
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

    // The soft half. A soft body is outside the listener above: the solver
    // keeps a separate one for it, and hands it a whole contact *set* in one
    // callback (once per collision pass, and only when something touched),
    // never a parting. So began and ended are derived rather than reported:
    // the set is accumulated as it arrives and diffed against the previous
    // step's by `finishSoftStep` once the step has returned.
    void OnSoftBodyContactAdded(const Body &inSoftBody,
                                const SoftBodyManifold &inManifold) override {
        const RMat44 com = inSoftBody.GetCenterOfMassTransform();
        // The body still carries the velocity it arrived with: the update
        // averages the new particle velocities into it *after* this callback.
        // So this is the approach speed, which is what an impact asks for, and
        // reading the other body's would be a race.
        const Vec3 approach = inSoftBody.GetLinearVelocity();
        const CJoltBodyID soft = inSoftBody.GetID().GetIndexAndSequenceNumber();

        std::lock_guard<std::mutex> lock(mMutex);
        for (const SoftBodyVertex &vertex : inManifold.GetVertices()) {
            if (!inManifold.HasContact(vertex)) { continue; }
            const BodyID other = inManifold.GetContactBodyID(vertex);
            if (other.IsInvalid()) { continue; }
            // Both are in the soft body's own space, and the normal points out
            // of the soft body into whatever the particle landed on.
            const Vec3 point = Vec3(com * inManifold.GetLocalContactPoint(vertex));
            const Vec3 normal = com.Multiply3x3(inManifold.GetContactNormal(vertex));
            noteSoftTouch(soft, other.GetIndexAndSequenceNumber(), point, normal,
                          approach);
        }
        // A sensor is reported without a per-particle plane, so its touch
        // carries neither point nor normal, the way a parting does.
        for (uint index = 0; index < inManifold.GetNumSensorContacts(); ++index) {
            const BodyID sensor = inManifold.GetSensorContactBodyID(index);
            if (sensor.IsInvalid()) { continue; }
            noteSoftTouch(soft, sensor.GetIndexAndSequenceNumber(), Vec3::sZero(),
                          Vec3::sZero(), Vec3::sZero());
        }
    }

    /// Turns this step's soft-body contact sets into began and ended events.
    /// Runs on the main thread once the step has returned, so a soft body that
    /// reported nothing is the one whose touches have ended.
    ///
    /// With one deliberate exception: a soft body that has settled and gone to
    /// sleep is not *asked* who it is touching, which is not the same as
    /// having let go, so its list is held rather than emptied. (A rigid pile
    /// does drop its contacts on sleeping, but that is the solver reporting a
    /// removal; here the diff is ours to make.) It is also what tells the
    /// buoyancy pass that a sunk sheet is lying on something rather than
    /// stalled in mid water.
    void finishSoftStep(PhysicsSystem &inSystem) {
        std::lock_guard<std::mutex> lock(mMutex);
        for (const auto &entry : mSoftSeen) {
            if (!mSoftPairs.insert({entry.first, entry.second.soft}).second) {
                continue;
            }
            CJoltContactEvent event{};
            event.phase = CJOLT_CONTACT_BEGAN;
            event.bodyA = CJoltBodyID(entry.first >> 32);
            event.bodyB = CJoltBodyID(entry.first & 0xffffffffull);
            store(entry.second.point, event.point);
            store(entry.second.normal, event.normal);
            event.speed = entry.second.speed;
            mEvents.push_back(event);
        }
        for (auto entry = mSoftPairs.begin(); entry != mSoftPairs.end();) {
            if (mSoftSeen.find(entry->first) != mSoftSeen.end()) {
                ++entry;
                continue;
            }
            BodyLockRead lock(inSystem.GetBodyLockInterface(), BodyID(entry->second));
            if (lock.Succeeded() && !lock.GetBody().IsActive()) {
                ++entry; // asleep, so nothing has changed: hold the touch
                continue;
            }
            CJoltContactEvent event{};
            event.phase = CJOLT_CONTACT_ENDED;
            event.bodyA = CJoltBodyID(entry->first >> 32);
            event.bodyB = CJoltBodyID(entry->first & 0xffffffffull);
            mEvents.push_back(event);
            entry = mSoftPairs.erase(entry);
        }
        mSoftSeen.clear();
    }

    /// Whether a soft body is resting against anything at all, which is what
    /// says that its weight is being carried rather than that it has stalled.
    bool isSoftTouching(CJoltBodyID soft) {
        std::lock_guard<std::mutex> lock(mMutex);
        for (const auto &entry : mSoftPairs) {
            if (entry.second == soft) { return true; }
        }
        return false;
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
    /// What a soft body's first touching particle saw, kept until the step is
    /// over and the pair can be compared with the previous step's.
    struct SoftTouch {
        Vec3 point = Vec3::sZero();
        Vec3 normal = Vec3::sZero();
        float speed = 0.0f;
        CJoltBodyID soft = 0;
    };

    /// Records one soft-body-to-body touch for this step. The first particle
    /// to report a pair is the one whose point and normal the event carries.
    void noteSoftTouch(CJoltBodyID soft, CJoltBodyID other, Vec3Arg point,
                       Vec3Arg normal, Vec3Arg approach) {
        const uint64_t key = pairKey(soft, other);
        if (mSoftSeen.find(key) != mSoftSeen.end()) { return; }
        SoftTouch touch;
        touch.soft = soft;
        touch.point = point;
        // A pair is stored low id first and a contact's normal always runs
        // from the first toward the second, so it turns around when the soft
        // body is the second of the two.
        touch.normal = soft <= other ? normal : -normal;
        // Along the normal out of the soft body, the approach velocity is the
        // closing speed whichever way round the pair ended up stored.
        touch.speed = std::max(0.0f, approach.Dot(normal));
        mSoftSeen[key] = touch;
    }

    static uint64_t pairKey(CJoltBodyID inA, CJoltBodyID inB) {
        const uint64_t a = inA;
        const uint64_t b = inB;
        return a <= b ? (a << 32) | b : (b << 32) | a;
    }

    static uint64_t pairKey(const BodyID &inA, const BodyID &inB) {
        return pairKey(inA.GetIndexAndSequenceNumber(),
                       inB.GetIndexAndSequenceNumber());
    }

    std::mutex mMutex;
    std::unordered_map<uint64_t, int> mPairs;
    // Ordered, so the soft diff walks its pairs the same way every run; the
    // drain sorts what leaves anyway, but a stable walk keeps the two halves
    // of the buffer from depending on hash order.
    std::map<uint64_t, SoftTouch> mSoftSeen;
    // Pair key -> which of the two is the soft body.
    std::map<uint64_t, CJoltBodyID> mSoftPairs;
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

/// A character's collision group, which rides in the library's own user-data
/// slot on the character (the bridge owns that slot; nothing else uses it).
/// Keeping it there rather than in the wrapper is what lets the filter below
/// answer for a bare `CharacterVirtual *` without searching for its wrapper.
inline int32_t characterGroup(const CharacterVirtual *character) {
    return int32_t(character->GetUserData());
}

/// Characters sweep against each other through this list rather than through
/// the broad phase, so the object-layer table that filters everything else
/// never sees a character-against-character pair. This hands the library's own
/// loop a list with the ignored groups left out, one call at a time, so a group
/// a character walks through is walked through by every path it has.
///
/// Called only from `cjolt_character_update`, on the one thread that steps the
/// world, which is what makes the scratch list safe.
class GroupedCharacterCollision final : public CharacterVsCharacterCollision {
public:
    CJoltWorld *world = nullptr;

    void Add(CharacterVirtual *inCharacter) { mAll.Add(inCharacter); }
    void Remove(const CharacterVirtual *inCharacter) { mAll.Remove(inCharacter); }

    void CollideCharacter(const CharacterVirtual *inCharacter,
                          RMat44Arg inCenterOfMassTransform,
                          const CollideShapeSettings &inCollideShapeSettings,
                          RVec3Arg inBaseOffset,
                          CollideShapeCollector &ioCollector) const override {
        visibleTo(inCharacter).CollideCharacter(inCharacter, inCenterOfMassTransform,
                                                inCollideShapeSettings, inBaseOffset,
                                                ioCollector);
    }

    void CastCharacter(const CharacterVirtual *inCharacter,
                       RMat44Arg inCenterOfMassTransform, Vec3Arg inDirection,
                       const ShapeCastSettings &inShapeCastSettings,
                       RVec3Arg inBaseOffset,
                       CastShapeCollector &ioCollector) const override {
        visibleTo(inCharacter).CastCharacter(inCharacter, inCenterOfMassTransform,
                                             inDirection, inShapeCastSettings,
                                             inBaseOffset, ioCollector);
    }

private:
    /// The characters this one can touch, refilled per call.
    const CharacterVsCharacterCollisionSimple &visibleTo(const CharacterVirtual *self) const;

    CharacterVsCharacterCollisionSimple mAll;
    mutable CharacterVsCharacterCollisionSimple mVisible;
};

/// A vehicle: the constraint that owns the wheels, the three collision testers
/// it can switch between, the filter they all share, and the driven-wheel
/// radius the top-speed gearing is solved against.
struct CJoltVehicle {
    JPH::Ref<JPH::VehicleConstraint> constraint;
    JPH::Ref<JPH::VehicleCollisionTester> testers[3];
    VehicleGroundFilter groundFilter;
    CJoltVehicleKind kind = CJOLT_VEHICLE_WHEELED;
    float drivenWheelRadius = 0.3f;
    /// The top speed the gearing was solved against (m/s), kept so a change to
    /// which wheels are driven can re-solve it against the new radius.
    float topSpeed = 0;
    /// The narrowest wheel, which sizes the sphere tester, and which of the
    /// three testers is in use: both are needed to build the set again when the
    /// vehicle changes collision group (a tester is made against one layer).
    float wheelWidth = 0.2f;
    int contactIndex = 0;
};

/// A ragdoll: the library's own body-per-joint figure, kept alive together with
/// the settings that built it (they carry the body-to-constraint map the pose
/// drivers walk).
struct CJoltRagdoll {
    JPH::Ref<JPH::RagdollSettings> settings;
    JPH::Ref<JPH::Ragdoll> ragdoll;
};

/// A soft body: the shared settings that describe its particles and springs,
/// plus the body it was added to the world as. The settings are owned per body
/// rather than shared, since each one is built from its own mesh.
struct CJoltSoftBody {
    JPH::Ref<JPH::SoftBodySharedSettings> settings;
    JPH::BodyID id;
    /// Where each rod the caller handed over ended up in the solver's own list,
    /// and whether its two ends were swapped on the way. The solver reorders
    /// rods so it can solve them in parallel, and reverses one whose direction
    /// disagrees with its neighbour's, so this is what lets a read-back speak
    /// in the caller's terms.
    std::vector<uint32_t> rodIndex;
    std::vector<bool> rodFlipped;
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
    GroupedCharacterCollision characterCollision;
    std::vector<CJoltCharacter *> characters;
    std::vector<CJoltVehicle *> vehicles;
    std::vector<CJoltRagdoll *> ragdolls;
    std::vector<CJoltSoftBody *> softBodies;
    // Every ragdoll gets its own collision group, so the filter table that
    // stops one figure's limbs from fighting each other never stops two
    // figures from colliding.
    uint32_t nextRagdollGroup = 1;

    CJoltWorld()
        : tempAllocator(16 * 1024 * 1024),
          jobSystem(JPH::cMaxPhysicsJobs, JPH::cMaxPhysicsBarriers,
                    std::clamp(int(std::thread::hardware_concurrency()) - 1, 1, 8)) {
        characterCollision.world = this;
    }
};

const CharacterVsCharacterCollisionSimple &
GroupedCharacterCollision::visibleTo(const CharacterVirtual *self) const {
    const GroupTable &groups = world->objectPairs.groups;
    const int32_t group = characterGroup(self);
    mVisible.mCharacters.clear();
    for (CharacterVirtual *other : mAll.mCharacters) {
        // `self` stays in the list: the library's own loop skips it, and
        // leaving it out would be a second place that rule is written.
        if (other == self || groups.collides(group, characterGroup(other))) {
            mVisible.mCharacters.push_back(other);
        }
    }
    return mVisible;
}

namespace {

// Constraint endpoints resolve to Body pointers; the invalid id anchors to the
// world. Called only from the main thread between steps, so the no-lock
// interface is safe.
Body *resolveBody(CJoltWorld *world, CJoltBodyID id) {
    if (id == CJOLT_BODY_INVALID) { return &Body::sFixedToWorld; }
    return world->physics.GetBodyLockInterfaceNoLock().TryGetBody(BodyID(id));
}

// The end of a hinge or slider that actually moves, plus that body's own
// constraint axis in its centre-of-mass space, which is what a gear or a rack
// and pinion is written against.
struct LinkEnd {
    Body *body = nullptr;
    Vec3 axis = Vec3::sAxisX();
};

// The moving end is the one that is not static; when both can move it is the
// second body, matching the order every `connect` call is written in (the
// anchor first, the part that turns second).
bool resolveLinkEnd(Constraint *constraint, bool wantsHinge, LinkEnd &out) {
    const EConstraintSubType subType = constraint->GetSubType();
    if (subType != (wantsHinge ? EConstraintSubType::Hinge
                               : EConstraintSubType::Slider)) {
        return false;
    }
    TwoBodyConstraint *pair = static_cast<TwoBodyConstraint *>(constraint);
    Body *first = pair->GetBody1();
    Body *second = pair->GetBody2();
    if (first == nullptr || second == nullptr) { return false; }
    const bool useFirst = second->IsStatic() && !first->IsStatic();
    out.body = useFirst ? first : second;
    if (out.body->IsStatic()) { return false; }
    if (wantsHinge) {
        HingeConstraint *hinge = static_cast<HingeConstraint *>(constraint);
        out.axis = useFirst ? hinge->GetLocalSpaceHingeAxis1()
                            : hinge->GetLocalSpaceHingeAxis2();
    } else {
        // A slider keeps no public accessor for its axis, but its constraint
        // frame's first column is exactly that direction in the body's space.
        const Mat44 frame = useFirst ? pair->GetConstraintToBody1Matrix()
                                     : pair->GetConstraintToBody2Matrix();
        out.axis = frame.GetColumn3(0).Normalized();
    }
    return true;
}

// A freedom mask as the library spells it. The bit values match, so this is a
// cast plus two sanity rules: an empty descriptor field (0) means the
// unrestricted default, and a mask that forbids every degree of freedom is
// invalid in the library (it would divide by a zero mass), so it reads as
// unrestricted too. Use a static body to hold something still.
EAllowedDOFs allowedDOFs(uint32_t freedom) {
    const uint32_t bits = freedom & uint32_t(CJOLT_FREEDOM_ALL);
    return bits == 0 ? EAllowedDOFs::All : EAllowedDOFs(bits);
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
    // One recorder answers both listeners: a soft body's touches are reported
    // through a separate channel but land in the same buffer.
    world->physics.SetSoftBodyContactListener(&world->contacts);
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
    // Ragdolls own constraints *and* bodies, and both leave through the
    // system, so they come off while it is still alive too.
    for (CJoltRagdoll *ragdoll : world->ragdolls) {
        ragdoll->ragdoll->RemoveFromPhysicsSystem();
        delete ragdoll;
    }
    world->ragdolls.clear();
    // Soft bodies are ordinary bodies, so they leave through the body
    // interface; only the settings that describe their springs are ours.
    for (CJoltSoftBody *soft : world->softBodies) {
        world->physics.GetBodyInterface().RemoveBody(soft->id);
        world->physics.GetBodyInterface().DestroyBody(soft->id);
        delete soft;
    }
    world->softBodies.clear();
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
    // A soft body's contacts arrive as a set rather than as events, so the
    // began and ended of it are worked out here, once every pass has reported.
    world->contacts.finishSoftStep(world->physics);
    return int(error);
}

void cjolt_world_optimize(CJoltWorld *world) { world->physics.OptimizeBroadPhase(); }

void cjolt_world_set_group_collision(CJoltWorld *world, int32_t groupA, int32_t groupB,
                                     bool collide) {
    if (world == nullptr) { return; }
    world->objectPairs.groups.set(groupA, groupB, collide);
}

bool cjolt_world_group_collision(const CJoltWorld *world, int32_t groupA,
                                 int32_t groupB) {
    if (world == nullptr) { return true; }
    return world->objectPairs.groups.collides(groupA, groupB);
}

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
    ObjectLayer kind = Layers::NON_MOVING;
    switch (desc->motion) {
    case CJOLT_MOTION_STATIC: break;
    case CJOLT_MOTION_KINEMATIC:
        motion = EMotionType::Kinematic;
        kind = Layers::MOVING;
        break;
    case CJOLT_MOTION_DYNAMIC:
        motion = EMotionType::Dynamic;
        kind = Layers::MOVING;
        break;
    }
    // A sensor is a detector volume, not a solid: it goes in the layer that
    // pairs only with moving bodies, and it is kinematic and kept awake so it
    // keeps reporting a body that falls asleep inside it (a static sensor
    // only ever sees active bodies, and the contact is dropped the moment one
    // settles, which is the wrong answer for a pressure plate).
    if (desc->isSensor) {
        motion = EMotionType::Kinematic;
        kind = Layers::SENSOR;
    }
    // A dynamic body cannot ride a static-only shape (mesh, height field, or
    // a compound containing one); keep the body but pin it in place.
    if (shape->MustBeStatic() && motion != EMotionType::Static) {
        motion = EMotionType::Static;
        kind = desc->isSensor ? Layers::SENSOR : Layers::NON_MOVING;
    }

    BodyCreationSettings settings(shape, RVec3(vec3(desc->position)),
                                  quat(desc->rotation), motion,
                                  layerFor(desc->group, kind));
    settings.mIsSensor = desc->isSensor;
    settings.mFriction = std::max(0.0f, desc->friction);
    settings.mRestitution = std::clamp(desc->restitution, 0.0f, 1.0f);
    settings.mLinearDamping = std::max(0.0f, desc->linearDamping);
    settings.mAngularDamping = std::max(0.0f, desc->angularDamping);
    settings.mGravityFactor = desc->gravityFactor;
    settings.mAllowSleeping = desc->allowSleep;
    // Motion the body already has. A zeroed descriptor creates it at rest,
    // which is what every ordinary caller wants; a restored snapshot hands
    // each body back the velocity it was captured with.
    settings.mLinearVelocity = vec3(desc->linearVelocity);
    settings.mAngularVelocity = vec3(desc->angularVelocity);
    settings.mAllowedDOFs = allowedDOFs(desc->freedom);
    // Sweeping the shape along its path is what stops a small quick body from
    // stepping straight through a thin wall. The solver only pays for it once
    // the body actually moves a good fraction of its own inner radius in a
    // step, so it costs nothing while the body is slow.
    settings.mMotionQuality = desc->continuous ? EMotionQuality::LinearCast
                                               : EMotionQuality::Discrete;
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

    // A body asked to start settled is added without being activated, which is
    // what "asleep" is: it holds its pose exactly and costs nothing to step
    // until something touches it.
    const bool activate = motion != EMotionType::Static && !desc->startAsleep;
    BodyID id = world->physics.GetBodyInterface().CreateAndAddBody(
        settings, activate ? EActivation::Activate : EActivation::DontActivate);
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

void cjolt_body_set_pose(CJoltWorld *world, CJoltBodyID body, const float pos[3],
                         const float q[4], bool activate) {
    world->physics.GetBodyInterface().SetPositionAndRotation(
        BodyID(body), RVec3(vec3(pos)), quat(q),
        activate ? EActivation::Activate : EActivation::DontActivate);
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
    if (inverseMass > 0) { return 1.0f / inverseMass; }
    // A body whose travel is locked has no mass the solver can be pushed by,
    // but it still weighs what its shape says: report that rather than the
    // zero that reads as weightless.
    return resolved->GetShape()->GetMassProperties().mMass;
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
    ObjectLayer kind = Layers::NON_MOVING;
    switch (motion) {
    case CJOLT_MOTION_STATIC: break;
    case CJOLT_MOTION_KINEMATIC:
        type = EMotionType::Kinematic;
        kind = Layers::MOVING;
        break;
    case CJOLT_MOTION_DYNAMIC:
        type = EMotionType::Dynamic;
        kind = Layers::MOVING;
        break;
    }
    bodies.SetMotionType(id, type,
                         type == EMotionType::Static ? EActivation::DontActivate
                                                     : EActivation::Activate);
    // The layer carries the kind and the group together, so changing one has
    // to keep the other: a body let go from static keeps the group it was in.
    bodies.SetObjectLayer(id, layerFor(layerGroup(bodies.GetObjectLayer(id)), kind));
}

void cjolt_body_set_group(CJoltWorld *world, CJoltBodyID body, int32_t group) {
    BodyInterface &bodies = world->physics.GetBodyInterface();
    BodyID id{body};
    const ObjectLayer layer = bodies.GetObjectLayer(id);
    if (layer == cObjectLayerInvalid) { return; }
    bodies.SetObjectLayer(id, layerFor(group, layerKind(layer)));
    // A pair that has just become able to touch has to be looked at again, and
    // a sleeping body is looked at by nothing.
    if (bodies.GetMotionType(id) != EMotionType::Static) { bodies.ActivateBody(id); }
}

int32_t cjolt_body_get_group(const CJoltWorld *world, CJoltBodyID body) {
    CJoltWorld *w = const_cast<CJoltWorld *>(world);
    const ObjectLayer layer = w->physics.GetBodyInterface().GetObjectLayer(BodyID(body));
    return layer == cObjectLayerInvalid ? 0 : layerGroup(layer);
}

bool cjolt_body_is_active(const CJoltWorld *world, CJoltBodyID body) {
    CJoltWorld *w = const_cast<CJoltWorld *>(world);
    return w->physics.GetBodyInterface().IsActive(BodyID(body));
}

void cjolt_body_activate(CJoltWorld *world, CJoltBodyID body) {
    world->physics.GetBodyInterface().ActivateBody(BodyID(body));
}

void cjolt_body_deactivate(CJoltWorld *world, CJoltBodyID body) {
    world->physics.GetBodyInterface().DeactivateBody(BodyID(body));
}

void cjolt_body_set_friction(CJoltWorld *world, CJoltBodyID body, float friction) {
    world->physics.GetBodyInterface().SetFriction(BodyID(body), std::max(0.0f, friction));
}

void cjolt_body_set_restitution(CJoltWorld *world, CJoltBodyID body, float restitution) {
    world->physics.GetBodyInterface().SetRestitution(BodyID(body),
                                                     std::clamp(restitution, 0.0f, 1.0f));
}

float cjolt_body_get_friction(const CJoltWorld *world, CJoltBodyID body) {
    CJoltWorld *w = const_cast<CJoltWorld *>(world);
    return w->physics.GetBodyInterface().GetFriction(BodyID(body));
}

float cjolt_body_get_restitution(const CJoltWorld *world, CJoltBodyID body) {
    CJoltWorld *w = const_cast<CJoltWorld *>(world);
    return w->physics.GetBodyInterface().GetRestitution(BodyID(body));
}

void cjolt_body_set_gravity_factor(CJoltWorld *world, CJoltBodyID body, float factor) {
    world->physics.GetBodyInterface().SetGravityFactor(BodyID(body), factor);
}

float cjolt_body_get_gravity_factor(const CJoltWorld *world, CJoltBodyID body) {
    CJoltWorld *w = const_cast<CJoltWorld *>(world);
    return w->physics.GetBodyInterface().GetGravityFactor(BodyID(body));
}

void cjolt_body_set_freedom(CJoltWorld *world, CJoltBodyID body, uint32_t freedom,
                            float mass) {
    Body *resolved = resolveBody(world, body);
    if (resolved == nullptr) { return; }
    // Not `IsDynamic`: a body created static keeps its motion properties (it
    // may be let go later), so a restriction set now is waiting for it.
    MotionProperties *motion = resolved->GetMotionPropertiesUnchecked();
    if (motion == nullptr) { return; }

    // The restriction lives inside the mass properties (a locked axis is one
    // the solver gives infinite mass or inertia), so it cannot be assigned on
    // its own: the whole set is re-derived from the shape and scaled back to
    // the mass the body actually has. That mass comes from the caller because
    // a body whose translation is already locked reports an inverse mass of
    // zero and so cannot say what it weighed.
    MassProperties properties = resolved->GetShape()->GetMassProperties();
    if (mass > 0) { properties.ScaleToMass(mass); }
    motion->SetMassProperties(allowedDOFs(freedom), properties);

    // Whatever held it in place a moment ago may not any more.
    world->physics.GetBodyInterface().ActivateBody(BodyID(body));
}

uint32_t cjolt_body_get_freedom(const CJoltWorld *world, CJoltBodyID body) {
    Body *resolved = resolveBody(const_cast<CJoltWorld *>(world), body);
    const MotionProperties *motion =
        resolved == nullptr ? nullptr : resolved->GetMotionPropertiesUnchecked();
    if (motion == nullptr) { return uint32_t(CJOLT_FREEDOM_ALL); }
    return uint32_t(motion->GetAllowedDOFs());
}

void cjolt_body_set_continuous(CJoltWorld *world, CJoltBodyID body, bool continuous) {
    world->physics.GetBodyInterface().SetMotionQuality(
        BodyID(body), continuous ? EMotionQuality::LinearCast
                                 : EMotionQuality::Discrete);
}

bool cjolt_body_get_continuous(const CJoltWorld *world, CJoltBodyID body) {
    CJoltWorld *w = const_cast<CJoltWorld *>(world);
    return w->physics.GetBodyInterface().GetMotionQuality(BodyID(body))
        == EMotionQuality::LinearCast;
}

// Buoyancy ------------------------------------------------------------------

int32_t cjolt_world_bodies_in_box(const CJoltWorld *world, const float boxMin[3],
                                  const float boxMax[3], CJoltBodyID *outBodies,
                                  float *outCenters, int32_t capacity) {
    if (capacity <= 0) { return 0; }
    CJoltWorld *w = const_cast<CJoltWorld *>(world);

    // The broad phase reports whatever overlaps the box; which of those can
    // actually take an impulse is decided below.
    class Collector : public CollideShapeBodyCollector {
    public:
        explicit Collector(std::vector<BodyID> &ids) : mIDs(ids) {}
        virtual void AddHit(const BodyID &id) override { mIDs.push_back(id); }

    private:
        std::vector<BodyID> &mIDs;
    };

    std::vector<BodyID> hits;
    Collector collector(hits);
    AABox box(Vec3(boxMin[0], boxMin[1], boxMin[2]),
              Vec3(boxMax[0], boxMax[1], boxMax[2]));
    w->physics.GetBroadPhaseQuery().CollideAABox(
        box, collector, SpecifiedBroadPhaseLayerFilter(BroadPhaseLayers::MOVING),
        MovingKindLayerFilter());

    // The tree hands them back in whatever order it walked; sorting makes the
    // caller's per-body pass replay identically.
    std::sort(hits.begin(), hits.end());

    int32_t written = 0;
    for (const BodyID &id : hits) {
        if (written >= capacity) { break; }
        Body *body = resolveBody(w, id.GetIndexAndSequenceNumber());
        // Only a dynamic rigid body has the mass and the motion properties the
        // impulse is expressed in: a sensor or a character's kinematic stand-in
        // would be nudged off its driven path, and the library's buoyancy is
        // not implemented for soft bodies at all.
        if (body == nullptr || !body->IsRigidBody() || !body->IsDynamic()
            || body->IsSensor()) {
            continue;
        }
        outBodies[written] = id.GetIndexAndSequenceNumber();
        RVec3 center = body->GetCenterOfMassPosition();
        outCenters[3 * written + 0] = float(center.GetX());
        outCenters[3 * written + 1] = float(center.GetY());
        outCenters[3 * written + 2] = float(center.GetZ());
        written += 1;
    }
    return written;
}

bool cjolt_body_apply_buoyancy(CJoltWorld *world, CJoltBodyID bodyID,
                               const float surfacePoint[3],
                               const float surfaceNormal[3], float density,
                               float scale, float linearDrag, float angularDrag,
                               const float flow[3], float dt,
                               CJoltBuoyancyWake wake) {
    Body *body = resolveBody(world, bodyID);
    if (body == nullptr || !body->IsRigidBody() || !body->IsDynamic()
        || body->IsSensor()) {
        return false;
    }

    RVec3 point(surfacePoint[0], surfacePoint[1], surfacePoint[2]);
    Vec3 normal(surfaceNormal[0], surfaceNormal[1], surfaceNormal[2]);
    if (normal.IsNearZero()) { return false; }
    normal = normal.Normalized();

    if (!body->IsActive()) {
        if (wake == CJOLT_BUOYANCY_WAKE_NEVER) { return false; }
        if (wake == CJOLT_BUOYANCY_WAKE_AT_SURFACE) {
            // A surface that is merely rolling only concerns what it passes
            // through. Anything wholly below it has nothing to ride (its
            // submerged volume is already all of it, whatever shape the swell
            // takes), so a sunk pile settles instead of being stirred awake
            // every step.
            const AABox &bounds = body->GetWorldSpaceBounds();
            float distance = normal.Dot(Vec3(bounds.GetCenter() - point));
            float reach = bounds.GetExtent().Dot(normal.Abs());
            if (std::abs(distance) > reach) { return false; }
        }
        world->physics.GetBodyInterface().ActivateBody(BodyID(bodyID));
    }

    float totalVolume = 0.0f, submergedVolume = 0.0f;
    Vec3 relativeCenterOfBuoyancy;
    body->GetSubmergedVolume(point, normal, totalVolume, submergedVolume,
                             relativeCenterOfBuoyancy);
    if (submergedVolume <= 0.0f || totalVolume <= 0.0f) { return false; }

    // The library wants the ratio of the fluid's density to the body's own
    // rather than a density, so the body's is formed here from the very volume
    // the submerged fraction was just measured against. Anything else (the
    // shape's own reported volume, say) would put the waterline slightly off
    // what the displaced volume says.
    const float inverseMass = body->GetMotionProperties()->GetInverseMass();
    const float buoyancy = scale * density * totalVolume * inverseMass;

    Vec3 flowVelocity(flow[0], flow[1], flow[2]);
    return body->ApplyBuoyancyImpulse(totalVolume, submergedVolume,
                                      relativeCenterOfBuoyancy, buoyancy,
                                      linearDrag, angularDrag, flowVelocity,
                                      world->physics.GetGravity(), dt);
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
    case CJOLT_CONSTRAINT_SWING_TWIST: {
        SwingTwistConstraintSettings settings;
        settings.mSpace = EConstraintSpace::WorldSpace;
        settings.mPosition1 = settings.mPosition2 = RVec3(vec3(desc->anchorA));
        Vec3 axis = vec3(desc->axis);
        if (axis.LengthSq() < 1.0e-12f) { axis = Vec3::sAxisY(); }
        axis = axis.Normalized();
        settings.mTwistAxis1 = settings.mTwistAxis2 = axis;
        settings.mPlaneAxis1 = settings.mPlaneAxis2 = axis.GetNormalizedPerpendicular();
        // A circular cone: the axis may lean the same amount in every
        // direction, so which perpendicular the plane axis landed on doesn't
        // change the shape of the limit.
        const float cone = std::clamp(desc->coneAngle, 0.0f, JPH_PI);
        settings.mNormalHalfConeAngle = cone;
        settings.mPlaneHalfConeAngle = cone;
        if (desc->hasLimits) {
            settings.mTwistMinAngle = std::clamp(desc->limitMin, -JPH_PI, 0.0f);
            settings.mTwistMaxAngle = std::clamp(desc->limitMax, 0.0f, JPH_PI);
        } else {
            settings.mTwistMinAngle = -JPH_PI;
            settings.mTwistMaxAngle = JPH_PI;
        }
        constraint = settings.Create(*a, *b);
        break;
    }
    case CJOLT_CONSTRAINT_PATH: {
        if (desc->pathPoints == nullptr || desc->pathPointCount < 2) {
            return nullptr;
        }
        // The path arrives in world space and lives in body 1's frame, so a
        // track carried by a moving body rides it. Leaving the settings' own
        // path transform at identity makes path space exactly body 1's own,
        // so the points only need that body's inverse world transform.
        const RMat44 toBody1 = a->GetWorldTransform().InversedRotationTranslation();
        Ref<PathConstraintPathHermite> path = new PathConstraintPathHermite();
        path->SetIsLooping(desc->pathLooping);
        for (int i = 0; i < desc->pathPointCount; ++i) {
            const float *p = desc->pathPoints + 9 * i;
            path->AddPoint(Vec3(toBody1 * RVec3(vec3(p))),
                           toBody1.Multiply3x3(vec3(p + 3)),
                           toBody1.Multiply3x3(vec3(p + 6)));
        }

        PathConstraintSettings settings;
        settings.mPath = path;
        settings.mPathPosition = RVec3::sZero();
        settings.mPathRotation = Quat::sIdentity();
        switch (desc->pathAlignment) {
        case CJOLT_PATH_ROLL:
            settings.mRotationConstraintType =
                EPathRotationConstraintType::ConstrainAroundTangent;
            break;
        case CJOLT_PATH_FOLLOW:
            settings.mRotationConstraintType =
                EPathRotationConstraintType::ConstrainToPath;
            break;
        case CJOLT_PATH_FIXED:
            settings.mRotationConstraintType =
                EPathRotationConstraintType::FullyConstrained;
            break;
        case CJOLT_PATH_FREE:
            settings.mRotationConstraintType = EPathRotationConstraintType::Free;
            break;
        }
        // The rider joins the path wherever it already is.
        settings.mPathFraction =
            path->GetClosestPoint(Vec3(toBody1 * b->GetPosition()), 0.0f);
        constraint = settings.Create(*a, *b);
        break;
    }
    case CJOLT_CONSTRAINT_PULLEY: {
        // The library's pulley reads a kinematic end's inertia as though it
        // were an ordinary body, which traps in a checked build and shoves the
        // driven body around in a release one. Every other constraint part
        // asks `IsDynamic`, this one asks `IsStatic`, so the case is refused
        // here rather than patched into the vendored source.
        if (a->IsKinematic() || b->IsKinematic()) { return nullptr; }
        PulleyConstraintSettings settings;
        settings.mSpace = EConstraintSpace::WorldSpace;
        settings.mBodyPoint1 = RVec3(vec3(desc->anchorA));
        settings.mFixedPoint1 = RVec3(vec3(desc->overA));
        settings.mBodyPoint2 = RVec3(vec3(desc->anchorB));
        settings.mFixedPoint2 = RVec3(vec3(desc->overB));
        settings.mRatio = desc->ratio > 0 ? desc->ratio : 1.0f;
        // A rope resists being lengthened but not shortened, so by default it
        // is only capped at the length it has now; -1 means "measure it from
        // where the bodies are". A taut linkage pins both ends of that range.
        settings.mMinLength = desc->hasLimits ? -1.0f : 0.0f;
        settings.mMaxLength = -1.0f;
        constraint = settings.Create(*a, *b);
        break;
    }
    case CJOLT_CONSTRAINT_SIX_DOF: {
        SixDOFConstraintSettings settings;
        settings.mSpace = EConstraintSpace::WorldSpace;
        settings.mPosition1 = settings.mPosition2 = RVec3(vec3(desc->anchorA));
        // The world's own axes, so a freedom names the same direction here
        // that it names on a body.
        settings.mAxisX1 = settings.mAxisX2 = Vec3::sAxisX();
        settings.mAxisY1 = settings.mAxisY2 = Vec3::sAxisY();
        // A pyramid swing is the one that takes limits that aren't symmetric.
        settings.mSwingType = ESwingType::Pyramid;
        using EAxis = SixDOFConstraintSettings::EAxis;
        for (int i = 0; i < EAxis::Num; ++i) {
            const EAxis axis = EAxis(i);
            if ((desc->freedom & (1u << i)) == 0) {
                settings.MakeFixedAxis(axis);
                continue;
            }
            const bool turns = i >= EAxis::NumTranslation;
            if (turns ? desc->hasRotationLimits : desc->hasLimits) {
                settings.SetLimitedAxis(axis,
                                        turns ? desc->rotationMin : desc->limitMin,
                                        turns ? desc->rotationMax : desc->limitMax);
            } else {
                settings.MakeFreeAxis(axis);
            }
        }
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

CJoltConstraint *cjolt_constraint_link(CJoltWorld *world, CJoltConstraint *a,
                                       CJoltConstraint *b, CJoltLinkType type,
                                       float ratio) {
    if (world == nullptr || a == nullptr || b == nullptr) { return nullptr; }
    LinkEnd pinion, driven;
    if (!resolveLinkEnd(a->constraint, true, pinion)) { return nullptr; }
    if (!resolveLinkEnd(b->constraint, type == CJOLT_LINK_GEAR, driven)) {
        return nullptr;
    }

    Constraint *constraint = nullptr;
    if (type == CJOLT_LINK_GEAR) {
        GearConstraintSettings settings;
        settings.mSpace = EConstraintSpace::LocalToBodyCOM;
        settings.mHingeAxis1 = pinion.axis;
        settings.mHingeAxis2 = driven.axis;
        settings.mRatio = ratio;
        GearConstraint *gear =
            static_cast<GearConstraint *>(settings.Create(*pinion.body, *driven.body));
        // Handing it the two hinges lets it measure its own drift and correct
        // it, so meshed teeth never walk out of step over a long run.
        gear->SetConstraints(a->constraint.GetPtr(), b->constraint.GetPtr());
        constraint = gear;
    } else {
        RackAndPinionConstraintSettings settings;
        settings.mSpace = EConstraintSpace::LocalToBodyCOM;
        settings.mHingeAxis = pinion.axis;
        settings.mSliderAxis = driven.axis;
        settings.mRatio = ratio;
        RackAndPinionConstraint *rack = static_cast<RackAndPinionConstraint *>(
            settings.Create(*pinion.body, *driven.body));
        rack->SetConstraints(a->constraint.GetPtr(), b->constraint.GetPtr());
        constraint = rack;
    }

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
    case EConstraintSubType::SwingTwist: {
        SwingTwistConstraint *joint = static_cast<SwingTwistConstraint *>(constraint);
        MotorSettings &motor = joint->GetTwistMotorSettings();
        motor.mSpringSettings = servo;
        if (limited) { motor.SetTorqueLimit(maxEffort); }
        else { motor.SetTorqueLimits(-FLT_MAX, FLT_MAX); }
        // One number about a joint that bends in every direction is the roll
        // about its own axis, so only the twist motor runs here and the bone
        // keeps swinging freely. Pointing it somewhere is the orientation
        // motor's job.
        joint->SetSwingMotorState(EMotorState::Off);
        joint->SetTargetAngularVelocityCS(
            Vec3(state == CJOLT_MOTOR_VELOCITY ? target : 0, 0, 0));
        if (state == CJOLT_MOTOR_POSITION) {
            joint->SetTargetOrientationCS(Quat::sRotation(Vec3::sAxisX(), target));
        }
        joint->SetTwistMotorState(motorState);
        break;
    }
    case EConstraintSubType::Path: {
        PathConstraint *path = static_cast<PathConstraint *>(constraint);
        const PathConstraintPath *curve = path->GetPath();
        if (curve == nullptr) { return; }
        MotorSettings &motor = path->GetPositionMotorSettings();
        motor.mSpringSettings = servo;
        if (limited) { motor.SetForceLimit(maxEffort); }
        else { motor.SetForceLimits(-FLT_MAX, FLT_MAX); }
        path->SetTargetVelocity(state == CJOLT_MOTOR_VELOCITY ? target : 0);
        if (state == CJOLT_MOTOR_POSITION) {
            // A target along a path is a fraction of the whole curve, so the
            // caller's 0…1 is scaled by however many segments it has.
            const float span = curve->GetPathMaxFraction();
            const float fraction = target * span;
            path->SetTargetPathFraction(
                curve->IsLooping() ? fraction : std::clamp(fraction, 0.0f, span));
        }
        path->SetPositionMotorState(motorState);
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
    case EConstraintSubType::SwingTwist:
        static_cast<SwingTwistConstraint *>(constraint)->SetMaxFrictionTorque(drag);
        break;
    case EConstraintSubType::Path:
        static_cast<PathConstraint *>(constraint)->SetMaxFrictionForce(drag);
        break;
    default:
        break;
    }
}

void cjolt_constraint_set_orientation_motor(CJoltWorld *world,
                                            CJoltConstraint *wrapper,
                                            const float direction[3], float twist,
                                            float frequency, float damping,
                                            float maxTorque) {
    if (wrapper == nullptr) { return; }
    Constraint *constraint = wrapper->constraint;
    if (constraint->GetSubType() != EConstraintSubType::SwingTwist) { return; }
    SwingTwistConstraint *joint = static_cast<SwingTwistConstraint *>(constraint);

    const SpringSettings servo(ESpringMode::FrequencyAndDamping,
                               std::max(frequency, 0.0f), std::max(damping, 0.0f));
    const bool limited = std::isfinite(maxTorque) && maxTorque > 0;
    for (MotorSettings *motor :
         {&joint->GetSwingMotorSettings(), &joint->GetTwistMotorSettings()}) {
        motor->mSpringSettings = servo;
        if (limited) { motor->SetTorqueLimit(maxTorque); }
        else { motor->SetTorqueLimits(-FLT_MAX, FLT_MAX); }
    }

    // The target is an orientation in the joint's own space, where the twist
    // axis is x, so a world direction comes back through body 1's rotation and
    // then the constraint frame before the shortest-arc turn onto it.
    Vec3 aim = vec3(direction);
    if (aim.LengthSq() < 1.0e-12f) { aim = Vec3::sAxisX(); }
    const Quat toConstraint =
        (joint->GetBody1()->GetRotation() * joint->GetConstraintToBody1()).Conjugated();
    const Vec3 local = toConstraint * aim.Normalized();
    const Quat swing = Quat::sFromTo(Vec3::sAxisX(), local);
    joint->SetTargetOrientationCS(swing * Quat::sRotation(Vec3::sAxisX(), twist));
    joint->SetSwingMotorState(EMotorState::Position);
    joint->SetTwistMotorState(EMotorState::Position);

    BodyInterface &bodies = world->physics.GetBodyInterface();
    bodies.ActivateBody(joint->GetBody1()->GetID());
    bodies.ActivateBody(joint->GetBody2()->GetID());
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
    case EConstraintSubType::SwingTwist: {
        // How far the joint is bent: the swing half of the relative rotation,
        // as an unsigned angle, which is the number the cone limit bounds.
        Quat swing, twist;
        static_cast<const SwingTwistConstraint *>(constraint)
            ->GetRotationInConstraintSpace()
            .GetSwingTwist(swing, twist);
        return 2.0f * ACos(std::clamp(std::abs(swing.GetW()), 0.0f, 1.0f));
    }
    case EConstraintSubType::Path: {
        const PathConstraint *path = static_cast<const PathConstraint *>(constraint);
        const PathConstraintPath *curve = path->GetPath();
        if (curve == nullptr) { return 0; }
        const float span = curve->GetPathMaxFraction();
        return span > 0 ? path->GetPathFraction() / span : 0;
    }
    default:
        return 0;
    }
}

float cjolt_constraint_twist(const CJoltWorld *, const CJoltConstraint *wrapper) {
    if (wrapper == nullptr) { return 0; }
    const Constraint *constraint = wrapper->constraint.GetPtr();
    if (constraint->GetSubType() != EConstraintSubType::SwingTwist) { return 0; }
    // The twist half of the relative rotation is a turn about the joint's own
    // axis, which the library keeps as constraint-space x.
    Quat swing, twist;
    static_cast<const SwingTwistConstraint *>(constraint)
        ->GetRotationInConstraintSpace()
        .GetSwingTwist(swing, twist);
    return 2.0f * std::atan2(twist.GetX(), twist.GetW());
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
    settings->mInnerBodyLayer = layerFor(desc->group, Layers::MOVING);

    CJoltCharacter *wrapper = new CJoltCharacter();
    // The group travels as the character's user data, which is what lets the
    // character-against-character filter answer for a bare character pointer.
    const uint64_t group = uint64_t(uint32_t(
        (desc->group > 0 && desc->group < CJOLT_MAX_GROUPS) ? desc->group : 0));
    wrapper->character = new CharacterVirtual(settings, RVec3(vec3(desc->position)),
                                              quat(desc->rotation), group,
                                              &world->physics);
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

    // The character sees the world as a moving body of its own group would.
    const ObjectLayer layer = layerFor(characterGroup(self), Layers::MOVING);
    self->ExtendedUpdate(dt, vec3(gravity), settings,
                         world->physics.GetDefaultBroadPhaseLayerFilter(layer),
                         world->physics.GetDefaultLayerFilter(layer), {}, {},
                         world->tempAllocator);
}

void cjolt_character_set_group(CJoltWorld *world, CJoltCharacter *character,
                               int32_t group) {
    if (world == nullptr || character == nullptr) { return; }
    const int32_t clamped = (group > 0 && group < CJOLT_MAX_GROUPS) ? group : 0;
    character->character->SetUserData(uint64_t(uint32_t(clamped)));
    // The stand-in body is an ordinary body, so everything else filters against
    // it through the layer the way it does for any other.
    const BodyID inner = character->character->GetInnerBodyID();
    if (!inner.IsInvalid()) {
        BodyInterface &bodies = world->physics.GetBodyInterface();
        bodies.SetObjectLayer(inner, layerFor(clamped, Layers::MOVING));
    }
}

void cjolt_character_refresh_contacts(CJoltWorld *world, CJoltCharacter *character) {
    if (world == nullptr || character == nullptr) { return; }
    const ObjectLayer layer =
        layerFor(characterGroup(character->character), Layers::MOVING);
    character->character->RefreshContacts(
        world->physics.GetDefaultBroadPhaseLayerFilter(layer),
        world->physics.GetDefaultLayerFilter(layer), {}, {},
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

WheeledVehicleController *wheeledOf(const CJoltVehicle *vehicle) {
    if (vehicle->kind == CJOLT_VEHICLE_TRACKED) { return nullptr; }
    return static_cast<WheeledVehicleController *>(
        vehicle->constraint->GetController());
}

TrackedVehicleController *trackedOf(const CJoltVehicle *vehicle) {
    if (vehicle->kind != CJOLT_VEHICLE_TRACKED) { return nullptr; }
    return static_cast<TrackedVehicleController *>(
        vehicle->constraint->GetController());
}

/// The engine and the gearbox live on both controllers but not on the base
/// class they share, so reaching either is a branch on the kind.
VehicleEngine &engineOf(const CJoltVehicle *vehicle) {
    TrackedVehicleController *tracked = trackedOf(vehicle);
    return tracked != nullptr ? tracked->GetEngine()
                              : wheeledOf(vehicle)->GetEngine();
}

VehicleTransmission &transmissionOf(const CJoltVehicle *vehicle) {
    TrackedVehicleController *tracked = trackedOf(vehicle);
    return tracked != nullptr ? tracked->GetTransmission()
                              : wheeledOf(vehicle)->GetTransmission();
}

/// Builds the three wheel collision testers against an object layer. A tester
/// takes its layer at construction, so a vehicle that changes collision group
/// needs a new set rather than a setter.
void buildVehicleTesters(CJoltVehicle *vehicle, ObjectLayer layer) {
    vehicle->testers[0] = new VehicleCollisionTesterRay(layer);
    vehicle->testers[1] =
        new VehicleCollisionTesterCastSphere(layer, 0.5f * vehicle->wheelWidth);
    vehicle->testers[2] = new VehicleCollisionTesterCastCylinder(layer);
    for (Ref<VehicleCollisionTester> &tester : vehicle->testers) {
        // Overriding the body filter replaces the default one that hides the
        // vehicle from itself, so this filter has to do that job too.
        tester->SetBodyFilter(&vehicle->groundFilter);
    }
}

/// Writes a wheel description onto a wheel's settings. Every one of these is
/// read again on each step, so the same function serves the initial build and
/// a live retune. What each drivetrain does with the tire's friction differs
/// (curves against slip for a rolling wheel, a flat pair of coefficients for a
/// track), so that half lives in the overloads below.
void applyWheelDesc(WheelSettings &wheel, const CJoltWheelDesc &desc) {
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
}

/// A rolling wheel: steering, brakes, and friction curves read against slip.
/// The curves are rebuilt from the library's own tire before grip scales them,
/// so repeated calls cannot compound.
void applyWheelDesc(WheelSettingsWV &wheel, const CJoltWheelDesc &desc) {
    applyWheelDesc(static_cast<WheelSettings &>(wheel), desc);
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

/// A road wheel under a track. It never steers, its brakes belong to the track
/// rather than to it, and its friction is a flat pair of coefficients (a track
/// lays the same rubber down however fast the band is running), so grip scales
/// two numbers instead of two curves.
void applyWheelDesc(WheelSettingsTV &wheel, const CJoltWheelDesc &desc) {
    applyWheelDesc(static_cast<WheelSettings &>(wheel), desc);
    const WheelSettingsTV band;
    const float grip = desc.grip > 0 ? desc.grip : 1.0f;
    wheel.mLongitudinalFriction = band.mLongitudinalFriction * grip;
    wheel.mLateralFriction = band.mLateralFriction * grip;
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

    const bool tracked = desc->kind == CJOLT_VEHICLE_TRACKED;
    const bool leans = desc->kind == CJOLT_VEHICLE_LEANING;

    float narrowest = FLT_MAX;
    for (int32_t i = 0; i < desc->wheelCount; ++i) {
        WheelSettings *wheel = nullptr;
        if (tracked) {
            WheelSettingsTV *road = new WheelSettingsTV();
            applyWheelDesc(*road, desc->wheels[i]);
            wheel = road;
        } else {
            WheelSettingsWV *tire = new WheelSettingsWV();
            applyWheelDesc(*tire, desc->wheels[i]);
            wheel = tire;
        }
        narrowest = std::min(narrowest, wheel->mWidth);
        vehicle.mWheels.push_back(wheel);
    }

    const auto wheelInRange = [&](int32_t index) {
        return index >= 0 && index < desc->wheelCount;
    };

    // The wheels pair across the machine whatever drives them, and a pair is
    // tied by an anti-roll bar so the outside wheel's compression lifts the
    // inside one. A lone wheel has nothing to tie to.
    for (int32_t i = 0; i < desc->axleCount; ++i) {
        const CJoltAxleDesc &axle = desc->axles[i];
        const int32_t left = wheelInRange(axle.leftWheel) ? axle.leftWheel : -1;
        const int32_t right = wheelInRange(axle.rightWheel) ? axle.rightWheel : -1;
        if (left >= 0 && right >= 0 && desc->antiRollStiffness > 0) {
            VehicleAntiRollBar bar;
            bar.mLeftWheel = left;
            bar.mRightWheel = right;
            bar.mStiffness = desc->antiRollStiffness;
            vehicle.mAntiRollBars.push_back(bar);
        }
    }

    VehicleControllerSettings *controllerSettings = nullptr;
    float drivenRadius = vehicle.mWheels[0]->mRadius;

    if (tracked) {
        TrackedVehicleControllerSettings *controller =
            new TrackedVehicleControllerSettings();
        controller->mEngine.mMaxTorque = std::max(desc->maxEngineTorque, 1.0f);
        // Every wheel must belong to exactly one track: the controller looks up
        // each wheel's track by an index it fills in from these lists, and a
        // wheel no track claims would keep the -1 it was born with.
        std::vector<bool> claimed(size_t(desc->wheelCount), false);
        for (int32_t side = 0; side < 2; ++side) {
            const CJoltTrackDesc &band = desc->tracks[side];
            if (band.wheels == nullptr || band.wheelCount < 1 ||
                !wheelInRange(band.drivenWheel)) {
                delete controller;
                return nullptr;
            }
            for (int32_t i = 0; i < band.wheelCount; ++i) {
                const int32_t index = band.wheels[i];
                if (!wheelInRange(index) || claimed[size_t(index)]) {
                    delete controller;
                    return nullptr;
                }
                claimed[size_t(index)] = true;
            }
        }
        for (bool wheelHasTrack : claimed) {
            if (!wheelHasTrack) {
                delete controller;
                return nullptr;
            }
        }
        drivenRadius = 0.5f * (vehicle.mWheels[desc->tracks[0].drivenWheel]->mRadius +
                               vehicle.mWheels[desc->tracks[1].drivenWheel]->mRadius);
        const Array<float> &gears = controller->mTransmission.mGearRatios;
        const float ratio = solveDifferentialRatio(
            controller->mEngine.mMaxRPM, gears.empty() ? 1.0f : gears.back(),
            desc->topSpeed, drivenRadius);
        for (int32_t side = 0; side < 2; ++side) {
            const CJoltTrackDesc &band = desc->tracks[side];
            VehicleTrackSettings &track = controller->mTracks[side];
            track.mWheels.clear();
            for (int32_t i = 0; i < band.wheelCount; ++i) {
                track.mWheels.push_back(uint(band.wheels[i]));
            }
            track.mDrivenWheel = uint(band.drivenWheel);
            track.mInertia = std::max(band.inertia, 0.01f);
            track.mAngularDamping = std::max(band.angularDamping, 0.0f);
            track.mMaxBrakeTorque = std::max(band.maxBrakeTorque, 0.0f);
            track.mDifferentialRatio = ratio;
        }
        controllerSettings = controller;
    } else {
        WheeledVehicleControllerSettings *controller =
            leans ? new MotorcycleControllerSettings()
                  : new WheeledVehicleControllerSettings();
        controller->mEngine.mMaxTorque = std::max(desc->maxEngineTorque, 1.0f);
        if (leans) {
            MotorcycleControllerSettings *bike =
                static_cast<MotorcycleControllerSettings *>(controller);
            bike->mMaxLeanAngle =
                std::clamp(desc->maxLeanAngle, 0.0f, 0.5f * JPH_PI);
        }

        // Which axles the engine turns, and how big their wheels are: the
        // differential ratio is solved once against that radius so every driven
        // axle shares one gearing.
        int drivenAxles = 0;
        float radiusSum = 0;
        int drivenWheels = 0;
        for (int32_t i = 0; i < desc->axleCount; ++i) {
            const CJoltAxleDesc &axle = desc->axles[i];
            if (!axle.driven) { continue; }
            ++drivenAxles;
            for (int32_t index : {axle.leftWheel, axle.rightWheel}) {
                if (wheelInRange(index)) {
                    radiusSum += vehicle.mWheels[index]->mRadius;
                    ++drivenWheels;
                }
            }
        }
        if (drivenWheels > 0) { drivenRadius = radiusSum / float(drivenWheels); }
        const Array<float> &gears = controller->mTransmission.mGearRatios;
        const float ratio = solveDifferentialRatio(
            controller->mEngine.mMaxRPM, gears.empty() ? 1.0f : gears.back(),
            desc->topSpeed, drivenRadius);

        for (int32_t i = 0; i < desc->axleCount; ++i) {
            const CJoltAxleDesc &axle = desc->axles[i];
            if (!axle.driven) { continue; }
            const int32_t left = wheelInRange(axle.leftWheel) ? axle.leftWheel : -1;
            const int32_t right = wheelInRange(axle.rightWheel) ? axle.rightWheel : -1;
            if (left < 0 && right < 0) { continue; }
            VehicleDifferentialSettings differential;
            differential.mLeftWheel = left;
            differential.mRightWheel = right;
            differential.mDifferentialRatio = ratio;
            differential.mEngineTorqueRatio = 1.0f / float(drivenAxles);
            controller->mDifferentials.push_back(differential);
        }
        // The controller's torque ratios must add up over at least one driven
        // differential, so a vehicle always has something the engine turns; the
        // caller picks which axle rather than leaving it to chance.
        if (controller->mDifferentials.empty()) {
            delete controller;
            return nullptr;
        }
        controllerSettings = controller;
    }

    vehicle.mController = controllerSettings;

    CJoltVehicle *wrapper = new CJoltVehicle();
    wrapper->kind = desc->kind;
    wrapper->drivenWheelRadius = drivenRadius;
    wrapper->topSpeed = desc->topSpeed;
    wrapper->groundFilter.chassis = chassis->GetID();
    wrapper->wheelWidth = narrowest;
    buildVehicleTesters(wrapper, chassis->GetObjectLayer());
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
    if (TrackedVehicleController *tracked = trackedOf(vehicle)) {
        // A tracked machine has no steering angle: it turns by running one
        // track faster than the other. Full lock runs the inside band
        // backwards, which is the pivot turn on the spot. Neither ratio may be
        // exactly zero (the controller divides by them), so a stopped band is
        // spelled as a very slow one.
        const float turn = std::clamp(right, -1.0f, 1.0f);
        const auto alive = [](float ratio) {
            return std::abs(ratio) < 1.0e-3f ? (ratio < 0 ? -1.0e-3f : 1.0e-3f)
                                             : ratio;
        };
        const float left = turn < 0 ? 1.0f + 2.0f * turn : 1.0f;
        const float inner = turn > 0 ? 1.0f - 2.0f * turn : 1.0f;
        // A tank has one brake pedal; the hand brake pulls the same one.
        tracked->SetDriverInput(std::clamp(forward, -1.0f, 1.0f), alive(left),
                                alive(inner),
                                std::clamp(std::max(brake, handBrake), 0.0f, 1.0f));
    } else {
        wheeledOf(vehicle)->SetDriverInput(std::clamp(forward, -1.0f, 1.0f),
                                           std::clamp(right, -1.0f, 1.0f),
                                           std::clamp(brake, 0.0f, 1.0f),
                                           std::clamp(handBrake, 0.0f, 1.0f));
    }
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
    WheelSettings *settings =
        const_cast<WheelSettings *>(wheel->GetSettings());
    if (vehicle->kind == CJOLT_VEHICLE_TRACKED) {
        applyWheelDesc(*static_cast<WheelSettingsTV *>(settings), *desc);
    } else {
        applyWheelDesc(*static_cast<WheelSettingsWV *>(settings), *desc);
    }
}

void cjolt_vehicle_set_engine_torque(CJoltVehicle *vehicle, float maxTorque) {
    if (vehicle == nullptr) { return; }
    engineOf(vehicle).mMaxTorque = std::max(maxTorque, 1.0f);
}

namespace {

/// Re-solves the gearing for the vehicle's remembered top speed and pushes it
/// onto whatever carries it: a wheeled vehicle's differentials, a tracked one's
/// two bands.
void applyGearing(CJoltVehicle *vehicle) {
    const Array<float> &gears = transmissionOf(vehicle).mGearRatios;
    const float ratio = solveDifferentialRatio(
        engineOf(vehicle).mMaxRPM, gears.empty() ? 1.0f : gears.back(),
        vehicle->topSpeed, vehicle->drivenWheelRadius);
    if (TrackedVehicleController *tracked = trackedOf(vehicle)) {
        for (VehicleTrack &track : tracked->GetTracks()) {
            track.mDifferentialRatio = ratio;
        }
    } else {
        for (VehicleDifferentialSettings &d :
             wheeledOf(vehicle)->GetDifferentials()) {
            d.mDifferentialRatio = ratio;
        }
    }
}

} // namespace

void cjolt_vehicle_set_top_speed(CJoltVehicle *vehicle, float metersPerSecond) {
    if (vehicle == nullptr) { return; }
    vehicle->topSpeed = metersPerSecond;
    applyGearing(vehicle);
}

void cjolt_vehicle_set_drive(CJoltVehicle *vehicle, const CJoltAxleDesc *axles,
                             int32_t axleCount, const CJoltTrackDesc *tracks) {
    if (vehicle == nullptr) { return; }
    const int32_t wheelCount = int32_t(vehicle->constraint->GetWheels().size());
    const auto wheelInRange = [&](int32_t index) {
        return index >= 0 && index < wheelCount;
    };
    const auto radiusOf = [&](int32_t index) {
        return vehicle->constraint->GetWheel(uint(index))->GetSettings()->mRadius;
    };

    if (TrackedVehicleController *tracked = trackedOf(vehicle)) {
        if (tracks == nullptr) { return; }
        for (int32_t side = 0; side < 2; ++side) {
            if (!wheelInRange(tracks[side].drivenWheel)) { return; }
        }
        float radiusSum = 0;
        for (int32_t side = 0; side < 2; ++side) {
            tracked->GetTracks()[side].mDrivenWheel =
                uint(tracks[side].drivenWheel);
            tracked->GetTracks()[side].mMaxBrakeTorque =
                std::max(tracks[side].maxBrakeTorque, 0.0f);
            radiusSum += radiusOf(tracks[side].drivenWheel);
        }
        vehicle->drivenWheelRadius = 0.5f * radiusSum;
        applyGearing(vehicle);
        return;
    }

    if (axles == nullptr || axleCount < 1) { return; }
    int drivenAxles = 0;
    float radiusSum = 0;
    int drivenWheels = 0;
    for (int32_t i = 0; i < axleCount; ++i) {
        if (!axles[i].driven) { continue; }
        ++drivenAxles;
        for (int32_t index : {axles[i].leftWheel, axles[i].rightWheel}) {
            if (wheelInRange(index)) {
                radiusSum += radiusOf(index);
                ++drivenWheels;
            }
        }
    }
    // The torque split must sum to one over at least one differential, so a
    // drive nothing turns is refused rather than left half-applied.
    if (drivenAxles < 1 || drivenWheels < 1) { return; }

    WheeledVehicleController::Differentials rebuilt;
    for (int32_t i = 0; i < axleCount; ++i) {
        if (!axles[i].driven) { continue; }
        const int32_t left = wheelInRange(axles[i].leftWheel) ? axles[i].leftWheel : -1;
        const int32_t right = wheelInRange(axles[i].rightWheel) ? axles[i].rightWheel : -1;
        if (left < 0 && right < 0) { continue; }
        VehicleDifferentialSettings differential;
        differential.mLeftWheel = left;
        differential.mRightWheel = right;
        differential.mEngineTorqueRatio = 1.0f / float(drivenAxles);
        rebuilt.push_back(differential);
    }
    if (rebuilt.empty()) { return; }
    wheeledOf(vehicle)->GetDifferentials() = rebuilt;
    vehicle->drivenWheelRadius = radiusSum / float(drivenWheels);
    applyGearing(vehicle);
}

void cjolt_vehicle_set_wheel_contact(CJoltVehicle *vehicle,
                                     CJoltWheelContact contact) {
    if (vehicle == nullptr) { return; }
    int index = contact == CJOLT_WHEEL_CONTACT_RAY      ? 0
                : contact == CJOLT_WHEEL_CONTACT_SPHERE ? 1
                                                        : 2;
    vehicle->contactIndex = index;
    vehicle->constraint->SetVehicleCollisionTester(vehicle->testers[index]);
}

void cjolt_vehicle_set_group(CJoltWorld *world, CJoltVehicle *vehicle, int32_t group) {
    if (world == nullptr || vehicle == nullptr) { return; }
    const ObjectLayer layer = layerFor(group, Layers::MOVING);
    // The chassis is an ordinary body and filters through its own layer; the
    // wheels feel the ground through testers built against one.
    BodyInterface &bodies = world->physics.GetBodyInterface();
    bodies.SetObjectLayer(vehicle->groundFilter.chassis, layer);
    buildVehicleTesters(vehicle, layer);
    vehicle->constraint->SetVehicleCollisionTester(
        vehicle->testers[vehicle->contactIndex]);
    bodies.ActivateBody(vehicle->groundFilter.chassis);
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
    // Slip is a rolling wheel's measurement: a road wheel under a track only
    // ever turns as fast as the band it rides, so there is nothing to report.
    if (vehicle->kind != CJOLT_VEHICLE_TRACKED) {
        const WheelWV *wv = static_cast<const WheelWV *>(wheel);
        out->longitudinalSlip = wv->mLongitudinalSlip;
        out->lateralSlip = wv->mLateralSlip;
    }
}

float cjolt_vehicle_get_rpm(const CJoltVehicle *vehicle) {
    if (vehicle == nullptr) { return 0; }
    return engineOf(vehicle).GetCurrentRPM();
}

int32_t cjolt_vehicle_get_gear(const CJoltVehicle *vehicle) {
    if (vehicle == nullptr) { return 0; }
    return int32_t(transmissionOf(vehicle).GetCurrentGear());
}

float cjolt_vehicle_get_clutch(const CJoltVehicle *vehicle) {
    if (vehicle == nullptr) { return 0; }
    return transmissionOf(vehicle).GetClutchFriction();
}

void cjolt_vehicle_set_wheel_motion(CJoltVehicle *vehicle, int32_t index,
                                    float angularVelocity, float rotationAngle) {
    if (vehicle == nullptr) { return; }
    const Wheels &wheels = vehicle->constraint->GetWheels();
    if (index < 0 || index >= int32_t(wheels.size())) { return; }
    Wheel *wheel = wheels[index];
    wheel->SetAngularVelocity(angularVelocity);
    wheel->SetRotationAngle(rotationAngle);
}

void cjolt_vehicle_set_drivetrain(CJoltVehicle *vehicle, float rpm, int32_t gear,
                                  float clutch) {
    if (vehicle == nullptr) { return; }
    VehicleController *controller = vehicle->constraint->GetController();
    if (auto *wheeled = dynamic_cast<WheeledVehicleController *>(controller)) {
        wheeled->GetEngine().SetCurrentRPM(rpm);
        wheeled->GetTransmission().Set(int(gear),
                                       std::min(std::max(clutch, 0.0f), 1.0f));
    } else if (auto *tracked = dynamic_cast<TrackedVehicleController *>(controller)) {
        tracked->GetEngine().SetCurrentRPM(rpm);
        tracked->GetTransmission().Set(int(gear),
                                       std::min(std::max(clutch, 0.0f), 1.0f));
    }
}

float cjolt_vehicle_get_track_speed(const CJoltVehicle *vehicle, int32_t side) {
    if (vehicle == nullptr || side < 0 || side > 1) { return 0; }
    TrackedVehicleController *tracked = trackedOf(vehicle);
    if (tracked == nullptr) { return 0; }
    const VehicleTrack &track = tracked->GetTracks()[side];
    const Wheel *driven = vehicle->constraint->GetWheel(track.mDrivenWheel);
    return track.mAngularVelocity * driven->GetSettings()->mRadius;
}

// Ragdolls ------------------------------------------------------------------

namespace {

/// A column-major 4x4 read out of 16 floats.
Mat44 matrix4(const float *m) {
    return Mat44(Vec4(m[0], m[1], m[2], m[3]), Vec4(m[4], m[5], m[6], m[7]),
                 Vec4(m[8], m[9], m[10], m[11]), Vec4(m[12], m[13], m[14], m[15]));
}

/// The limb shape pushed out along its bone: the body's origin is the joint, so
/// the capsule that fills the bone sits off-center inside it.
Ref<Shape> makeRagdollPartShape(const CJoltRagdollPartDesc &part) {
    Ref<Shape> shape = makeShape(part.shape);
    if (shape == nullptr) { return nullptr; }
    const Vec3 offset = vec3(part.shapeOffset);
    const Quat rotation = quat(part.shapeRotation);
    if (offset.LengthSq() < 1.0e-12f && rotation.IsClose(Quat::sIdentity())) {
        return shape;
    }
    Shape::ShapeResult result =
        RotatedTranslatedShapeSettings(offset, rotation, shape).Create();
    if (result.HasError()) { return shape; }
    return result.Get();
}

} // namespace

CJoltRagdoll *cjolt_ragdoll_create(CJoltWorld *world,
                                   const CJoltRagdollPartDesc *parts,
                                   int32_t partCount, float friction,
                                   float restitution, int32_t group) {
    if (parts == nullptr || partCount <= 0) { return nullptr; }

    Ref<Skeleton> skeleton = new Skeleton;
    for (int32_t i = 0; i < partCount; ++i) {
        // Parents must already be in the array: every algorithm that walks a
        // skeleton relies on it, and the caller builds the list by a top-down
        // walk, so a backward reference is a bug rather than a shape to honor.
        const int parent = parts[i].parent;
        if (parent >= i) { return nullptr; }
        char name[16];
        snprintf(name, sizeof(name), "j%d", int(i));
        skeleton->AddJoint(name, parent);
    }

    Ref<RagdollSettings> settings = new RagdollSettings;
    settings->mSkeleton = skeleton;
    settings->mParts.resize(size_t(partCount));
    Array<Mat44> jointMatrices;
    jointMatrices.reserve(size_t(partCount));

    for (int32_t i = 0; i < partCount; ++i) {
        const CJoltRagdollPartDesc &desc = parts[i];
        Ref<Shape> shape = makeRagdollPartShape(desc);
        if (shape == nullptr || shape->MustBeStatic()) { return nullptr; }

        RagdollSettings::Part &part = settings->mParts[size_t(i)];
        part.SetShape(shape);
        part.mPosition = RVec3(vec3(desc.position));
        part.mRotation = quat(desc.rotation);
        part.mMotionType = EMotionType::Dynamic;
        part.mObjectLayer = layerFor(group, Layers::MOVING);
        part.mFriction = std::max(0.0f, friction);
        part.mRestitution = std::clamp(restitution, 0.0f, 1.0f);
        part.mLinearDamping = 0.05f;
        part.mAngularDamping = 0.05f;
        // A limp figure may be switched to kinematic to follow an animation
        // exactly, so every part keeps the right to change motion type.
        part.mAllowDynamicOrKinematic = true;
        if (desc.mass > 0) {
            part.mOverrideMassProperties = EOverrideMassProperties::CalculateInertia;
            part.mMassPropertiesOverride.mMass = desc.mass;
        }
        jointMatrices.push_back(Mat44::sRotationTranslation(part.mRotation,
                                                            Vec3(part.mPosition)));

        if (desc.parent < 0) { continue; }
        SwingTwistConstraintSettings *constraint = new SwingTwistConstraintSettings;
        constraint->mSpace = EConstraintSpace::WorldSpace;
        constraint->mPosition1 = constraint->mPosition2 = RVec3(vec3(desc.pivot));
        Vec3 twist = vec3(desc.twistAxis);
        twist = twist.LengthSq() > 1.0e-12f ? twist.Normalized() : Vec3::sAxisY();
        Vec3 plane = vec3(desc.planeAxis);
        plane = plane.LengthSq() > 1.0e-12f
                    ? (plane - twist * plane.Dot(twist)) : Vec3::sZero();
        plane = plane.LengthSq() > 1.0e-12f ? plane.Normalized()
                                            : twist.GetNormalizedPerpendicular();
        constraint->mTwistAxis1 = constraint->mTwistAxis2 = twist;
        constraint->mPlaneAxis1 = constraint->mPlaneAxis2 = plane;
        const float cone = std::clamp(desc.swingLimit, 0.0f, JPH_PI);
        constraint->mNormalHalfConeAngle = cone;
        constraint->mPlaneHalfConeAngle = cone;
        constraint->mTwistMinAngle = std::clamp(desc.twistMin, -JPH_PI, 0.0f);
        constraint->mTwistMaxAngle = std::clamp(desc.twistMax, 0.0f, JPH_PI);
        settings->mParts[size_t(i)].mToParent = constraint;
    }

    // Balance the masses down the tree and grow each parent's inertia to carry
    // its children: without it a light hand on a heavy arm makes the solver
    // fight itself and the figure jitters apart.
    settings->Stabilize();
    // Joints nearer the root are solved first, so the heavy end of the figure
    // settles before the light one hangs off it.
    settings->CalculateConstraintPriorities();
    // Neighbouring limbs (and any pair that already overlaps in this pose)
    // stop colliding, while limbs of *other* ragdolls still do.
    settings->DisableParentChildCollisions(jointMatrices.data(), 0.0f);
    settings->CalculateBodyIndexToConstraintIndex();

    Ragdoll *created =
        settings->CreateRagdoll(world->nextRagdollGroup++, 0, &world->physics);
    if (created == nullptr) { return nullptr; }

    CJoltRagdoll *wrapper = new CJoltRagdoll();
    wrapper->settings = settings;
    wrapper->ragdoll = created;
    wrapper->ragdoll->AddToPhysicsSystem(EActivation::Activate);
    world->ragdolls.push_back(wrapper);
    return wrapper;
}

void cjolt_ragdoll_destroy(CJoltWorld *world, CJoltRagdoll *ragdoll) {
    if (ragdoll == nullptr) { return; }
    // The constraints hold the bodies, so the whole set leaves the world before
    // the ragdoll's own destructor destroys them.
    ragdoll->ragdoll->RemoveFromPhysicsSystem();
    world->ragdolls.erase(
        std::remove(world->ragdolls.begin(), world->ragdolls.end(), ragdoll),
        world->ragdolls.end());
    delete ragdoll;
}

int32_t cjolt_ragdoll_part_count(const CJoltRagdoll *ragdoll) {
    if (ragdoll == nullptr) { return 0; }
    return int32_t(ragdoll->ragdoll->GetBodyCount());
}

CJoltBodyID cjolt_ragdoll_get_body(const CJoltRagdoll *ragdoll, int32_t index) {
    if (ragdoll == nullptr || index < 0 ||
        index >= int32_t(ragdoll->ragdoll->GetBodyCount())) {
        return CJOLT_BODY_INVALID;
    }
    return ragdoll->ragdoll->GetBodyID(index).GetIndexAndSequenceNumber();
}

void cjolt_ragdoll_set_limits(CJoltRagdoll *ragdoll, int32_t index,
                              float swingLimit, float twistMin, float twistMax) {
    if (ragdoll == nullptr) { return; }
    const int constraintIndex =
        ragdoll->settings->GetConstraintIndexForBodyIndex(index);
    if (constraintIndex < 0) { return; }
    TwoBodyConstraint *constraint = ragdoll->ragdoll->GetConstraint(constraintIndex);
    if (constraint->GetSubType() != EConstraintSubType::SwingTwist) { return; }
    SwingTwistConstraint *joint = static_cast<SwingTwistConstraint *>(constraint);
    const float cone = std::clamp(swingLimit, 0.0f, JPH_PI);
    joint->SetNormalHalfConeAngle(cone);
    joint->SetPlaneHalfConeAngle(cone);
    joint->SetTwistMinAngle(std::clamp(twistMin, -JPH_PI, 0.0f));
    joint->SetTwistMaxAngle(std::clamp(twistMax, 0.0f, JPH_PI));
}

void cjolt_ragdoll_drive_to_pose(CJoltWorld *, CJoltRagdoll *ragdoll,
                                 const float *localRotations, float frequency,
                                 float damping, float maxTorque) {
    if (ragdoll == nullptr || localRotations == nullptr) { return; }
    const SpringSettings servo(ESpringMode::FrequencyAndDamping,
                               std::max(frequency, 0.0f), std::max(damping, 0.0f));
    const bool limited = std::isfinite(maxTorque) && maxTorque > 0;
    const int count = int(ragdoll->ragdoll->GetBodyCount());
    for (int i = 0; i < count; ++i) {
        const int constraintIndex =
            ragdoll->settings->GetConstraintIndexForBodyIndex(i);
        if (constraintIndex < 0) { continue; }
        TwoBodyConstraint *constraint = ragdoll->ragdoll->GetConstraint(constraintIndex);
        if (constraint->GetSubType() != EConstraintSubType::SwingTwist) { continue; }
        SwingTwistConstraint *joint = static_cast<SwingTwistConstraint *>(constraint);
        for (MotorSettings *motor :
             {&joint->GetSwingMotorSettings(), &joint->GetTwistMotorSettings()}) {
            motor->mSpringSettings = servo;
            if (limited) { motor->SetTorqueLimit(maxTorque); }
            else { motor->SetTorqueLimits(-FLT_MAX, FLT_MAX); }
        }
        joint->SetSwingMotorState(EMotorState::Position);
        joint->SetTwistMotorState(EMotorState::Position);
        joint->SetTargetOrientationBS(quat(localRotations + 4 * i));
    }
    // A sleeping figure never feels its motors change.
    ragdoll->ragdoll->Activate();
}

void cjolt_ragdoll_stop_motors(CJoltRagdoll *ragdoll) {
    if (ragdoll == nullptr) { return; }
    const int count = int(ragdoll->ragdoll->GetConstraintCount());
    for (int i = 0; i < count; ++i) {
        TwoBodyConstraint *constraint = ragdoll->ragdoll->GetConstraint(i);
        if (constraint->GetSubType() != EConstraintSubType::SwingTwist) { continue; }
        SwingTwistConstraint *joint = static_cast<SwingTwistConstraint *>(constraint);
        joint->SetSwingMotorState(EMotorState::Off);
        joint->SetTwistMotorState(EMotorState::Off);
    }
}

void cjolt_ragdoll_set_pose(CJoltWorld *world, CJoltRagdoll *ragdoll,
                            const float *worldMatrices) {
    if (ragdoll == nullptr || worldMatrices == nullptr) { return; }
    BodyInterface &bodies = world->physics.GetBodyInterface();
    const int count = int(ragdoll->ragdoll->GetBodyCount());
    for (int i = 0; i < count; ++i) {
        const Mat44 pose = matrix4(worldMatrices + 16 * i);
        bodies.SetPositionAndRotation(ragdoll->ragdoll->GetBodyID(i),
                                      RVec3(pose.GetTranslation()),
                                      pose.GetQuaternion(), EActivation::Activate);
    }
    // The impulses the solver warm-started from belong to the old pose.
    ragdoll->ragdoll->ResetWarmStart();
}

void cjolt_ragdoll_move_to_pose(CJoltWorld *world, CJoltRagdoll *ragdoll,
                                const float *worldMatrices, float dt) {
    if (ragdoll == nullptr || worldMatrices == nullptr || dt <= 0) { return; }
    BodyInterface &bodies = world->physics.GetBodyInterface();
    const int count = int(ragdoll->ragdoll->GetBodyCount());
    for (int i = 0; i < count; ++i) {
        const Mat44 pose = matrix4(worldMatrices + 16 * i);
        bodies.MoveKinematic(ragdoll->ragdoll->GetBodyID(i),
                             RVec3(pose.GetTranslation()), pose.GetQuaternion(), dt);
    }
}

void cjolt_ragdoll_set_motion(CJoltWorld *world, CJoltRagdoll *ragdoll,
                              CJoltMotionType motion) {
    if (ragdoll == nullptr) { return; }
    EMotionType type = EMotionType::Dynamic;
    ObjectLayer kind = Layers::MOVING;
    switch (motion) {
    case CJOLT_MOTION_STATIC:
        type = EMotionType::Static;
        kind = Layers::NON_MOVING;
        break;
    case CJOLT_MOTION_KINEMATIC: type = EMotionType::Kinematic; break;
    case CJOLT_MOTION_DYNAMIC: break;
    }
    BodyInterface &bodies = world->physics.GetBodyInterface();
    const int count = int(ragdoll->ragdoll->GetBodyCount());
    for (int i = 0; i < count; ++i) {
        const BodyID id = ragdoll->ragdoll->GetBodyID(i);
        bodies.SetMotionType(id, type,
                             type == EMotionType::Static ? EActivation::DontActivate
                                                         : EActivation::Activate);
        // The group half of the layer survives a motion change, as it does for
        // an ordinary body.
        bodies.SetObjectLayer(id, layerFor(layerGroup(bodies.GetObjectLayer(id)), kind));
    }
}

void cjolt_ragdoll_set_group(CJoltWorld *world, CJoltRagdoll *ragdoll, int32_t group) {
    if (world == nullptr || ragdoll == nullptr) { return; }
    BodyInterface &bodies = world->physics.GetBodyInterface();
    const int count = int(ragdoll->ragdoll->GetBodyCount());
    for (int i = 0; i < count; ++i) {
        const BodyID id = ragdoll->ragdoll->GetBodyID(i);
        bodies.SetObjectLayer(id, layerFor(group, layerKind(bodies.GetObjectLayer(id))));
    }
    ragdoll->ragdoll->Activate();
}

void cjolt_ragdoll_activate(CJoltWorld *, CJoltRagdoll *ragdoll) {
    if (ragdoll == nullptr) { return; }
    ragdoll->ragdoll->Activate();
}

bool cjolt_ragdoll_is_active(const CJoltWorld *, const CJoltRagdoll *ragdoll) {
    if (ragdoll == nullptr) { return false; }
    return ragdoll->ragdoll->IsActive();
}

void cjolt_ragdoll_add_impulse(CJoltWorld *world, CJoltRagdoll *ragdoll,
                               const float impulse[3]) {
    if (ragdoll == nullptr) { return; }
    // One impulse for the whole figure, split between the limbs by their share
    // of its mass, so every limb takes the same change in velocity and the
    // figure leaves in one piece. (The library's own AddImpulse gives each body
    // the impulse whole, which shoves the light limbs much harder than the
    // heavy ones and pulls the figure apart as it goes.)
    BodyInterface &bodies = world->physics.GetBodyInterface();
    const int count = int(ragdoll->ragdoll->GetBodyCount());
    float total = 0;
    for (int i = 0; i < count; ++i) {
        BodyLockRead lock(world->physics.GetBodyLockInterface(),
                          ragdoll->ragdoll->GetBodyID(i));
        if (!lock.Succeeded()) { continue; }
        const MotionProperties *motion = lock.GetBody().GetMotionPropertiesUnchecked();
        if (lock.GetBody().IsDynamic() && motion != nullptr) {
            total += 1.0f / motion->GetInverseMass();
        }
    }
    if (total <= 0) { return; }
    ragdoll->ragdoll->Activate();
    for (int i = 0; i < count; ++i) {
        const BodyID id = ragdoll->ragdoll->GetBodyID(i);
        float mass = 0;
        {
            BodyLockRead lock(world->physics.GetBodyLockInterface(), id);
            if (!lock.Succeeded() || !lock.GetBody().IsDynamic()) { continue; }
            const MotionProperties *motion = lock.GetBody().GetMotionPropertiesUnchecked();
            if (motion == nullptr) { continue; }
            mass = 1.0f / motion->GetInverseMass();
        }
        bodies.AddImpulse(id, vec3(impulse) * (mass / total));
    }
}

// Soft bodies ---------------------------------------------------------------

namespace {

// Reading or writing particle state needs the body, and every soft-body call
// runs on the main thread between steps, so the no-lock interface is enough.
SoftBodyMotionProperties *softMotion(const CJoltWorld *world,
                                     const CJoltSoftBody *soft) {
    if (soft == nullptr) { return nullptr; }
    Body *body = const_cast<CJoltWorld *>(world)
                     ->physics.GetBodyLockInterfaceNoLock()
                     .TryGetBody(soft->id);
    if (body == nullptr || !body->IsSoftBody()) { return nullptr; }
    return static_cast<SoftBodyMotionProperties *>(body->GetMotionProperties());
}

Body *softBody(const CJoltWorld *world, const CJoltSoftBody *soft) {
    if (soft == nullptr) { return nullptr; }
    return const_cast<CJoltWorld *>(world)
        ->physics.GetBodyLockInterfaceNoLock()
        .TryGetBody(soft->id);
}

} // namespace

CJoltSoftBody *cjolt_soft_body_create(CJoltWorld *world,
                                      const CJoltSoftBodyDesc *desc) {
    if (world == nullptr || desc == nullptr) { return nullptr; }
    if (desc->positions == nullptr || desc->vertexCount < 2) { return nullptr; }
    bool hasRods = desc->rods != nullptr && desc->rodCount > 0;
    if (!hasRods
        && (desc->indices == nullptr || desc->indexCount < 3
            || desc->vertexCount < 3)) {
        return nullptr;
    }

    Ref<SoftBodySharedSettings> settings = new SoftBodySharedSettings;
    settings->mVertices.reserve(size_t(desc->vertexCount));
    for (int32_t i = 0; i < desc->vertexCount; ++i) {
        SoftBodySharedSettings::Vertex v;
        v.mPosition = Float3(desc->positions[i * 3], desc->positions[i * 3 + 1],
                             desc->positions[i * 3 + 2]);
        float inverseMass = desc->inverseMasses ? desc->inverseMasses[i] : 1.0f;
        v.mInvMass = std::max(0.0f, inverseMass);
        settings->mVertices.push_back(v);
    }

    // A face whose corners repeat, or whose corners sit on top of each other,
    // would give the constraint builder a zero-length spring; drop it rather
    // than let the library trip over it.
    const uint32_t vertexCount = uint32_t(desc->vertexCount);
    for (int32_t i = 0; desc->indices != nullptr && i + 2 < desc->indexCount;
         i += 3) {
        uint32_t a = desc->indices[i], b = desc->indices[i + 1],
                 c = desc->indices[i + 2];
        if (a >= vertexCount || b >= vertexCount || c >= vertexCount) { continue; }
        if (a == b || b == c || a == c) { continue; }
        Vec3 pa(settings->mVertices[a].mPosition);
        Vec3 pb(settings->mVertices[b].mPosition);
        Vec3 pc(settings->mVertices[c].mPosition);
        if ((pb - pa).LengthSq() <= 0.0f || (pc - pb).LengthSq() <= 0.0f
            || (pa - pc).LengthSq() <= 0.0f) {
            continue;
        }
        settings->AddFace(SoftBodySharedSettings::Face(a, b, c));
    }
    // A body with rods needs no surface at all: a rope is nothing but its
    // spine. Without them a triangle is the smallest thing that can be
    // simulated, so an unusable mesh is still refused.
    if (settings->mFaces.empty() && !hasRods) { return nullptr; }

    // Which particles a skeleton carries, built before the constraints so the
    // long range attachments can already see which ones are kinematic.
    if (desc->skinned != nullptr && desc->skinnedCount > 0
        && desc->inverseBinds != nullptr && desc->inverseBindCount > 0) {
        settings->mInvBindMatrices.reserve(size_t(desc->inverseBindCount));
        for (int32_t i = 0; i < desc->inverseBindCount; ++i) {
            settings->mInvBindMatrices.emplace_back(
                uint32(i), matrix4(desc->inverseBinds + i * 16));
        }
        settings->mSkinnedConstraints.reserve(size_t(desc->skinnedCount));
        for (int32_t i = 0; i < desc->skinnedCount; ++i) {
            const CJoltSoftSkinVertex &in = desc->skinned[i];
            if (in.vertex < 0 || uint32_t(in.vertex) >= vertexCount) { continue; }
            SoftBodySharedSettings::Skinned skinned;
            skinned.mVertex = uint32(in.vertex);
            // The library spells "no limit" as FLT_MAX, so an infinity from the
            // caller (the natural way to say a particle is free) becomes that.
            skinned.mMaxDistance = std::isfinite(in.maxDistance)
                ? std::max(0.0f, in.maxDistance) : FLT_MAX;
            skinned.mBackStopDistance = std::isfinite(in.backStopDistance)
                ? in.backStopDistance : FLT_MAX;
            skinned.mBackStopRadius =
                in.backStopRadius > 0.0f ? in.backStopRadius : 40.0f;
            int slot = 0;
            for (int w = 0; w < 4 && slot < 4; ++w) {
                if (!(in.weights[w] > 0.0f)) { continue; }
                if (in.joints[w] >= uint32_t(desc->inverseBindCount)) { continue; }
                skinned.mWeights[slot++] = SoftBodySharedSettings::SkinWeight(
                    in.joints[w], in.weights[w]);
            }
            // Nothing carries it, so it is ordinary cloth.
            if (slot == 0) { continue; }
            skinned.NormalizeWeights();
            settings->mSkinnedConstraints.push_back(skinned);
            // A particle held exactly where the skin puts it is kinematic: the
            // springs must not drag it off, and it is what the long range
            // attachments measure the rest of the surface against.
            if (skinned.mMaxDistance <= 0.0f) {
                settings->mVertices[skinned.mVertex].mInvMass = 0.0f;
            }
        }
    }

    // Cosserat rods, built before the constraints for the same reason the skin
    // is: the long range attachments are derived in there from whatever the
    // particles are connected by, and a rope's connections are its rods.
    std::vector<uint32_t> rodPairs;
    std::vector<bool> rodFlipped;
    if (hasRods) {
        settings->mRodStretchShearConstraints.reserve(size_t(desc->rodCount));
        for (int32_t i = 0; i < desc->rodCount; ++i) {
            uint32_t a = desc->rods[i * 2], b = desc->rods[i * 2 + 1];
            if (a >= vertexCount || b >= vertexCount || a == b) { continue; }
            // A rod of no length has no direction to carry, and the library
            // asserts on one rather than working around it.
            if ((Vec3(settings->mVertices[b].mPosition)
                 - Vec3(settings->mVertices[a].mPosition)).LengthSq() <= 0.0f) {
                continue;
            }
            rodPairs.push_back(a);
            rodPairs.push_back(b);
            settings->mRodStretchShearConstraints.emplace_back(
                a, b, std::max(0.0f, desc->rodCompliance));
        }
        uint32_t rodCount = uint32_t(settings->mRodStretchShearConstraints.size());
        for (int32_t i = 0; desc->rodLinks != nullptr && i < desc->rodLinkCount;
             ++i) {
            uint32_t a = desc->rodLinks[i * 2], b = desc->rodLinks[i * 2 + 1];
            if (a >= rodCount || b >= rodCount || a == b) { continue; }
            settings->mRodBendTwistConstraints.emplace_back(
                a, b, std::max(0.0f, desc->rodBendCompliance));
        }
        // Works out each rod's length, its share of the mass, and the twist-free
        // frame it rests in. It also reverses any rod pointing against its
        // neighbour, which is what has to be measured rather than assumed, and
        // has to be measured here while the rods are still in the caller's own
        // order.
        settings->CalculateRodProperties();
        for (size_t i = 0; i * 2 + 1 < rodPairs.size(); ++i) {
            rodFlipped.push_back(
                settings->mRodStretchShearConstraints[i].mVertex[0] != rodPairs[i * 2]);
        }

        // A rod's frame is seeded from its Bishop quaternion and read nowhere
        // else once the body is running, and the rest rotations between rods
        // have already been worked out above, so writing the caller's own
        // orientations over it stands a rope back up mid-motion while leaving
        // the shape it wants to return to alone.
        if (desc->rodRotations != nullptr) {
            Quat inverse = quat(desc->rotation).Normalized().Conjugated();
            const Quat reverse = Quat(1.0f, 0.0f, 0.0f, 0.0f);
            for (size_t i = 0; i < settings->mRodStretchShearConstraints.size(); ++i) {
                Quat given(desc->rodRotations[i * 4], desc->rodRotations[i * 4 + 1],
                           desc->rodRotations[i * 4 + 2], desc->rodRotations[i * 4 + 3]);
                if (given.LengthSq() <= 0.0f) { continue; }
                if (rodFlipped[i]) { given = given * reverse; }
                settings->mRodStretchShearConstraints[i].mBishop =
                    (inverse * given.Normalized()).Normalized();
            }
        }
    }

    // The dihedral bend constraint is the one that works on a curved surface:
    // it holds the angle two faces already meet at, where the cheaper distance
    // form assumes they started in a plane.
    SoftBodySharedSettings::VertexAttributes attributes;
    attributes.mCompliance = std::max(0.0f, desc->compliance);
    attributes.mShearCompliance = attributes.mCompliance;
    bool bends = desc->bendCompliance >= 0.0f;
    attributes.mBendCompliance = bends ? std::max(0.0f, desc->bendCompliance) : FLT_MAX;
    switch (desc->lraType) {
    case CJOLT_SOFT_LRA_EUCLIDEAN:
        attributes.mLRAType = SoftBodySharedSettings::ELRAType::EuclideanDistance;
        break;
    case CJOLT_SOFT_LRA_GEODESIC:
        attributes.mLRAType = SoftBodySharedSettings::ELRAType::GeodesicDistance;
        break;
    default:
        attributes.mLRAType = SoftBodySharedSettings::ELRAType::None;
        break;
    }
    attributes.mLRAMaxDistanceMultiplier =
        desc->lraStretch > 0.0f ? desc->lraStretch : 1.0f;
    settings->CreateConstraints(&attributes, 1,
                                bends ? SoftBodySharedSettings::EBendType::Dihedral
                                      : SoftBodySharedSettings::EBendType::None);
    // Works out which faces each skinned particle's normal comes from, which
    // is what the back stop pushes along. A no-op when nothing is skinned.
    settings->CalculateSkinnedConstraintNormals();
    // Optimize reorders the rods so they can be solved in parallel, so the
    // remap is the other half of speaking in the caller's terms.
    SoftBodySharedSettings::OptimizationResults optimization;
    settings->Optimize(optimization);

    SoftBodyCreationSettings creation(settings, RVec3(vec3(desc->position)),
                                      quat(desc->rotation),
                                      layerFor(desc->group, Layers::MOVING));
    creation.mNumIterations = uint32_t(std::max(1, desc->iterations));
    creation.mLinearDamping = std::max(0.0f, desc->linearDamping);
    creation.mFriction = std::max(0.0f, desc->friction);
    creation.mRestitution = std::clamp(desc->restitution, 0.0f, 1.0f);
    creation.mPressure = std::max(0.0f, desc->pressure);
    creation.mGravityFactor = desc->gravityFactor;
    creation.mVertexRadius = std::max(0.0f, desc->vertexRadius);
    creation.mAllowSleeping = desc->allowSleep;
    creation.mFacesDoubleSided = desc->twoSided;

    BodyID id = world->physics.GetBodyInterface().CreateAndAddSoftBody(
        creation, EActivation::Activate);
    if (id.IsInvalid()) { return nullptr; }

    CJoltSoftBody *soft = new CJoltSoftBody{settings, id};
    for (size_t i = 0; i * 2 + 1 < rodPairs.size(); ++i) {
        soft->rodIndex.push_back(optimization.mRodStretchShearConstraintRemap[i]);
        soft->rodFlipped.push_back(rodFlipped[i]);
    }
    world->softBodies.push_back(soft);
    return soft;
}

void cjolt_soft_body_destroy(CJoltWorld *world, CJoltSoftBody *body) {
    if (world == nullptr || body == nullptr) { return; }
    world->physics.GetBodyInterface().RemoveBody(body->id);
    world->physics.GetBodyInterface().DestroyBody(body->id);
    world->softBodies.erase(
        std::remove(world->softBodies.begin(), world->softBodies.end(), body),
        world->softBodies.end());
    delete body;
}

CJoltBodyID cjolt_soft_body_get_id(const CJoltSoftBody *body) {
    if (body == nullptr) { return CJOLT_BODY_INVALID; }
    return body->id.GetIndexAndSequenceNumber();
}

int32_t cjolt_soft_body_vertex_count(const CJoltSoftBody *body) {
    if (body == nullptr) { return 0; }
    return int32_t(body->settings->mVertices.size());
}

int32_t cjolt_soft_body_get_positions(const CJoltWorld *world,
                                      const CJoltSoftBody *body, float *out,
                                      int32_t capacity) {
    SoftBodyMotionProperties *motion = softMotion(world, body);
    Body *jbody = softBody(world, body);
    if (motion == nullptr || jbody == nullptr || out == nullptr) { return 0; }
    // Particles are stored relative to the body's center of mass, which the
    // solver re-centres every step; the transform is what puts them back.
    RMat44 com = jbody->GetCenterOfMassTransform();
    const Array<SoftBodyMotionProperties::Vertex> &vertices = motion->GetVertices();
    int32_t count = std::min(capacity, int32_t(vertices.size()));
    for (int32_t i = 0; i < count; ++i) {
        Vec3 world_position = Vec3(com * vertices[size_t(i)].mPosition);
        store(world_position, out + i * 3);
    }
    return count;
}

int32_t cjolt_soft_body_get_velocities(const CJoltWorld *world,
                                       const CJoltSoftBody *body, float *out,
                                       int32_t capacity) {
    SoftBodyMotionProperties *motion = softMotion(world, body);
    if (motion == nullptr || out == nullptr) { return 0; }
    const Array<SoftBodyMotionProperties::Vertex> &vertices = motion->GetVertices();
    int32_t count = std::min(capacity, int32_t(vertices.size()));
    for (int32_t i = 0; i < count; ++i) {
        // Velocities are already relative to nothing but the world: the centre
        // of mass moves, it does not rotate the frame.
        store(vertices[size_t(i)].mVelocity, out + i * 3);
    }
    return count;
}

void cjolt_soft_body_set_state(CJoltWorld *world, CJoltSoftBody *body,
                               const float *positions, const float *velocities,
                               int32_t count) {
    SoftBodyMotionProperties *motion = softMotion(world, body);
    Body *jbody = softBody(world, body);
    if (motion == nullptr || jbody == nullptr || positions == nullptr) { return; }
    // Particles are held relative to the body's centre of mass, so a world
    // position has to come back through that transform, the way the read does.
    RMat44 inverse = jbody->GetCenterOfMassTransform().InversedRotationTranslation();
    Array<SoftBodyMotionProperties::Vertex> &vertices = motion->GetVertices();
    int32_t n = std::min(count, int32_t(vertices.size()));
    for (int32_t i = 0; i < n; ++i) {
        SoftBodyMotionProperties::Vertex &vertex = vertices[size_t(i)];
        vertex.mPosition = Vec3(inverse * RVec3(vec3(positions + i * 3)));
        vertex.mPreviousPosition = vertex.mPosition;
        vertex.mVelocity = velocities != nullptr ? vec3(velocities + i * 3)
                                                 : Vec3::sZero();
    }
    world->physics.GetBodyInterface().ActivateBody(jbody->GetID());
}

void cjolt_soft_body_get_center(const CJoltWorld *world,
                                const CJoltSoftBody *body, float out[3]) {
    Body *jbody = softBody(world, body);
    if (jbody == nullptr || out == nullptr) {
        if (out != nullptr) { store(Vec3::sZero(), out); }
        return;
    }
    store(Vec3(jbody->GetCenterOfMassPosition()), out);
}

int32_t cjolt_soft_body_rod_count(const CJoltSoftBody *body) {
    if (body == nullptr) { return 0; }
    return int32_t(body->rodIndex.size());
}

int32_t cjolt_soft_body_get_rod_rotations(const CJoltWorld *world,
                                          const CJoltSoftBody *body, float *out,
                                          int32_t capacity) {
    SoftBodyMotionProperties *motion = softMotion(world, body);
    Body *jbody = softBody(world, body);
    if (motion == nullptr || jbody == nullptr || out == nullptr) { return 0; }
    // Rod orientations are held in the same frame the particles are, so the
    // body's own rotation is what takes one into the world.
    Quat body_rotation = jbody->GetRotation();
    // Half a turn about the rod's own x axis, which sends its +z the other way
    // and leaves a right-handed frame: what a rod the solver reversed needs to
    // point the way the caller asked for.
    const Quat reverse = Quat(1.0f, 0.0f, 0.0f, 0.0f);
    int32_t count = std::min(capacity, int32_t(body->rodIndex.size()));
    for (int32_t i = 0; i < count; ++i) {
        Quat rotation = body_rotation * motion->GetRodRotation(body->rodIndex[size_t(i)]);
        if (body->rodFlipped[size_t(i)]) { rotation = rotation * reverse; }
        Vec4 v = rotation.GetXYZW();
        out[i * 4] = v.GetX();
        out[i * 4 + 1] = v.GetY();
        out[i * 4 + 2] = v.GetZ();
        out[i * 4 + 3] = v.GetW();
    }
    return count;
}

float cjolt_soft_body_get_volume(const CJoltWorld *world,
                                 const CJoltSoftBody *body) {
    SoftBodyMotionProperties *motion = softMotion(world, body);
    return motion == nullptr ? 0.0f : motion->GetVolume();
}

void cjolt_soft_body_set_pressure(CJoltWorld *world, CJoltSoftBody *body,
                                  float pressure) {
    SoftBodyMotionProperties *motion = softMotion(world, body);
    if (motion == nullptr) { return; }
    motion->SetPressure(std::max(0.0f, pressure));
    world->physics.GetBodyInterface().ActivateBody(body->id);
}

void cjolt_soft_body_set_iterations(CJoltWorld *world, CJoltSoftBody *body,
                                    int32_t iterations) {
    SoftBodyMotionProperties *motion = softMotion(world, body);
    if (motion == nullptr) { return; }
    motion->SetNumIterations(uint32_t(std::max(1, iterations)));
}

void cjolt_soft_body_set_vertex_radius(CJoltWorld *world, CJoltSoftBody *body,
                                       float radius) {
    SoftBodyMotionProperties *motion = softMotion(world, body);
    if (motion == nullptr) { return; }
    motion->SetVertexRadius(std::max(0.0f, radius));
}

float cjolt_soft_body_get_vertex_inverse_mass(const CJoltWorld *world,
                                              const CJoltSoftBody *body,
                                              int32_t index) {
    SoftBodyMotionProperties *motion = softMotion(world, body);
    if (motion == nullptr || index < 0
        || size_t(index) >= motion->GetVertices().size()) {
        return 0.0f;
    }
    return motion->GetVertex(uint(index)).mInvMass;
}

void cjolt_soft_body_set_vertex_inverse_mass(CJoltWorld *world,
                                             CJoltSoftBody *body, int32_t index,
                                             float inverseMass) {
    SoftBodyMotionProperties *motion = softMotion(world, body);
    if (motion == nullptr || index < 0
        || size_t(index) >= motion->GetVertices().size()) {
        return;
    }
    SoftBodyMotionProperties::Vertex &v = motion->GetVertex(uint(index));
    v.mInvMass = std::max(0.0f, inverseMass);
    // A pinned particle keeps whatever velocity it had, which would carry it
    // away from the spot it is meant to hold.
    if (v.mInvMass <= 0.0f) { v.mVelocity = Vec3::sZero(); }
    world->physics.GetBodyInterface().ActivateBody(body->id);
}

void cjolt_soft_body_move_vertex(CJoltWorld *world, CJoltSoftBody *body,
                                 int32_t index, const float target[3],
                                 float dt) {
    SoftBodyMotionProperties *motion = softMotion(world, body);
    Body *jbody = softBody(world, body);
    if (motion == nullptr || jbody == nullptr || target == nullptr
        || index < 0 || size_t(index) >= motion->GetVertices().size()
        || dt <= 0.0f) {
        return;
    }
    SoftBodyMotionProperties::Vertex &v = motion->GetVertex(uint(index));
    v.mInvMass = 0.0f;
    RMat44 com = jbody->GetCenterOfMassTransform();
    Vec3 current = Vec3(com * v.mPosition);
    // Velocities are stored in the body's own space, so the world-space step
    // comes back through the transform's rotation.
    v.mVelocity = com.Multiply3x3Transposed((vec3(target) - current) / dt);
    world->physics.GetBodyInterface().ActivateBody(body->id);
}

int32_t cjolt_soft_body_skinned_count(const CJoltSoftBody *body) {
    if (body == nullptr) { return 0; }
    return int32_t(body->settings->mSkinnedConstraints.size());
}

void cjolt_soft_body_skin(CJoltWorld *world, CJoltSoftBody *body,
                          const float *jointMatrices, int32_t jointCount,
                          bool hardSkinAll) {
    SoftBodyMotionProperties *motion = softMotion(world, body);
    Body *jbody = softBody(world, body);
    if (motion == nullptr || jbody == nullptr || jointMatrices == nullptr) { return; }
    if (body->settings->mSkinnedConstraints.empty()) { return; }
    // Every inverse bind names a joint, and the library reads that slot without
    // checking it in a release build.
    if (jointCount < int32_t(body->settings->mInvBindMatrices.size())) { return; }

    // The library wants the joints in the body's own frame, so the conversion
    // lives here, where the body is, rather than in every caller.
    const RMat44 com = jbody->GetCenterOfMassTransform();
    const RMat44 inverse = com.InversedRotationTranslation();
    Array<Mat44> local;
    local.reserve(size_t(jointCount));
    for (int32_t i = 0; i < jointCount; ++i) {
        local.push_back(Mat44(inverse * matrix4(jointMatrices + i * 16)));
    }
    motion->SkinVertices(com, local.data(), uint(jointCount), hardSkinAll,
                         world->tempAllocator);
    // A surface stood on a fresh pose has to be awake to answer it, and one
    // that has just been carried somewhere has to re-centre.
    if (hardSkinAll) {
        world->physics.GetBodyInterface().ActivateBody(body->id);
    }
}

void cjolt_soft_body_set_skin_enabled(CJoltWorld *world, CJoltSoftBody *body,
                                      bool enabled) {
    SoftBodyMotionProperties *motion = softMotion(world, body);
    if (motion == nullptr) { return; }
    motion->SetEnableSkinConstraints(enabled);
    world->physics.GetBodyInterface().ActivateBody(body->id);
}

void cjolt_soft_body_set_skin_slack(CJoltWorld *world, CJoltSoftBody *body,
                                    float multiplier) {
    SoftBodyMotionProperties *motion = softMotion(world, body);
    if (motion == nullptr) { return; }
    motion->SetSkinnedMaxDistanceMultiplier(std::max(0.0f, multiplier));
    world->physics.GetBodyInterface().ActivateBody(body->id);
}

void cjolt_soft_body_add_force(CJoltWorld *world, CJoltSoftBody *body,
                               const float force[3]) {
    if (world == nullptr || body == nullptr || force == nullptr) { return; }
    world->physics.GetBodyInterface().AddForce(body->id, vec3(force));
}

void cjolt_soft_body_activate(CJoltWorld *world, CJoltSoftBody *body) {
    if (world == nullptr || body == nullptr) { return; }
    world->physics.GetBodyInterface().ActivateBody(body->id);
}

bool cjolt_soft_body_is_active(const CJoltWorld *world,
                               const CJoltSoftBody *body) {
    if (world == nullptr || body == nullptr) { return false; }
    return world->physics.GetBodyInterface().IsActive(body->id);
}

bool cjolt_soft_body_apply_buoyancy(CJoltWorld *world, CJoltSoftBody *body,
                                    const float *heights, int32_t heightCount,
                                    float buoyancy, float density,
                                    float linearDrag, float dragArea, float band,
                                    const float flow[3], float dt,
                                    CJoltBuoyancyWake wake) {
    SoftBodyMotionProperties *motion = softMotion(world, body);
    Body *jbody = softBody(world, body);
    if (motion == nullptr || jbody == nullptr || heights == nullptr
        || dt <= 0.0f || buoyancy <= 0.0f) {
        return false;
    }
    Array<SoftBodyMotionProperties::Vertex> &vertices = motion->GetVertices();
    if (size_t(heightCount) < vertices.size()) { return false; }

    // Half the ramp: a particle a full band under the surface is wholly in the
    // water, one a band above it is wholly out. Without it a flat sheet has no
    // waterline to hold, since every particle of it crosses at once.
    const float half = std::max(band, 1.0e-4f);
    bool anyWet = false, anyDry = false;
    for (size_t index = 0; index < vertices.size(); ++index) {
        if (vertices[index].mInvMass <= 0.0f) { continue; } // pinned, so held
        if (heights[index] < half) { anyWet = true; } else { anyDry = true; }
    }
    if (!anyWet) { return false; }

    if (!jbody->IsActive()) {
        bool waking = wake == CJOLT_BUOYANCY_WAKE_ALWAYS;
        // The same rule the rigid path follows: a rolling surface only concerns
        // what it passes through, which for a body made of particles is exactly
        // the one with some of them out of the water and some in. A sheet
        // settled on the bottom sleeps on instead of being stirred every step.
        if (!waking && wake == CJOLT_BUOYANCY_WAKE_AT_SURFACE) { waking = anyDry; }
        // A body heavier than the fluid has no depth at which the fluid could
        // hold it, so it has not settled, it has stalled: a sheet's area for
        // its weight is enormous, so drag holds it below the solver's own sleep
        // threshold and it would otherwise hang in mid water reading as though
        // it floated. Resting against something is what says its weight is
        // carried after all (and a sleeping soft body keeps its touches, so
        // that answer holds rather than flickering).
        if (!waking && buoyancy < 1.0f
            && !world->contacts.isSoftTouching(
                    body->id.GetIndexAndSequenceNumber())) {
            waking = true;
        }
        if (!waking) { return false; }
        world->physics.GetBodyInterface().ActivateBody(body->id);
    }

    // Velocities are in the body's own frame, so the transform carries the
    // change back in.
    const RMat44 com = jbody->GetCenterOfMassTransform();
    const Vec3 gravity = world->physics.GetGravity() * motion->GetGravityFactor();
    const Vec3 current = vec3(flow);
    const float dragScale = 0.5f * std::max(0.0f, density)
                            * std::max(0.0f, linearDrag) * std::max(0.0f, dragArea);

    for (size_t index = 0; index < vertices.size(); ++index) {
        SoftBodyMotionProperties::Vertex &v = vertices[index];
        if (v.mInvMass <= 0.0f) { continue; } // a pinned particle holds
        const float submerged =
            std::clamp(0.5f - 0.5f * heights[index] / half, 0.0f, 1.0f);
        if (submerged <= 0.0f) { continue; }

        // Buoyancy is the fluid's density over the body's, so what it adds is
        // that ratio of a gravity, upward: it needs neither the particle's mass
        // nor its share of a volume the surface may not even enclose.
        Vec3 change = (-buoyancy * submerged * dt) * gravity;

        if (dragScale > 0.0f) {
            const Vec3 velocity = com.Multiply3x3(v.mVelocity);
            const Vec3 relative = current - velocity;
            const float speed = relative.Length();
            if (speed > 1.0e-6f) {
                Vec3 drag = (dragScale * submerged * speed * v.mInvMass * dt)
                            * relative;
                // Drag may only take relative motion away, never push the
                // particle past the water it is moving through.
                const float delta = drag.Length();
                if (delta > speed) { drag *= speed / delta; }
                change += drag;
            }
        }
        v.mVelocity += com.Multiply3x3Transposed(change);
    }
    return true;
}

// Queries -------------------------------------------------------------------

namespace {

/// The body-level half of a query's filter. Two of the three decisions here
/// are about what a query is even asking: a sensor is a region to be inside
/// rather than a surface to hit, and a soft body has no rigid pose to hand
/// back, so both are transparent unless the caller says otherwise.
class QueryBodyFilter final : public BodyFilter {
public:
    explicit QueryBodyFilter(const CJoltQueryFilter *filter) : mFilter(filter) {}

    bool ShouldCollide(const BodyID &inBodyID) const override {
        if (mFilter == nullptr || mFilter->ignoreBodies == nullptr) { return true; }
        const CJoltBodyID id = inBodyID.GetIndexAndSequenceNumber();
        for (int32_t index = 0; index < mFilter->ignoreCount; ++index) {
            if (mFilter->ignoreBodies[index] == id) { return false; }
        }
        return true;
    }

    bool ShouldCollideLocked(const Body &inBody) const override {
        if (inBody.IsSensor()) {
            return mFilter != nullptr && mFilter->includeSensors;
        }
        if (!inBody.IsRigidBody()) {
            return mFilter != nullptr && mFilter->includeSoftBodies;
        }
        return true;
    }

private:
    const CJoltQueryFilter *mFilter;
};

/// A query sees the world the way a moving body does: statics stay visible,
/// ghosts (the grab anchors) never are.
struct QueryFilters {
    explicit QueryFilters(CJoltWorld *world, const CJoltQueryFilter *filter)
        : broadPhase(world->objectVsBroadPhase, asLayer(filter)),
          objects(world->objectPairs, asLayer(filter)), bodies(filter) {}

    /// The layer a query asks as: a moving body of the filter's own group, so
    /// the world's ignore table narrows the question exactly as it narrows a
    /// collision. A null filter asks as the default group, which sees
    /// everything.
    static ObjectLayer asLayer(const CJoltQueryFilter *filter) {
        return layerFor(filter != nullptr ? filter->group : 0, Layers::MOVING);
    }

    DefaultBroadPhaseLayerFilter broadPhase;
    DefaultObjectLayerFilter objects;
    QueryBodyFilter bodies;
};

/// The surface normal where a ray landed, which only the body itself can
/// answer (the sub shape id names the face, and a mesh's faces each have their
/// own). Zero if the body has gone in the meantime.
Vec3 surfaceNormal(CJoltWorld *world, const BodyID &id, const SubShapeID &subShape,
                   RVec3Arg point) {
    BodyLockRead lock(world->physics.GetBodyLockInterface(), id);
    if (!lock.Succeeded()) { return Vec3::sZero(); }
    return lock.GetBody().GetWorldSpaceSurfaceNormal(subShape, point);
}

void writeHit(CJoltQueryHit &out, const BodyID &id, Vec3Arg point,
              Vec3Arg normal, float distance) {
    out.body = id.GetIndexAndSequenceNumber();
    store(point, out.point);
    store(normal, out.normal);
    out.distance = distance;
}

/// Copies collected body ids out, one per body and in handle order: the tree
/// hands them back in whatever order it walked, and a compound's parts or a
/// mesh's triangles each report their own hit.
int32_t writeBodies(std::vector<BodyID> &ids, CJoltBodyID *out, int32_t capacity) {
    std::sort(ids.begin(), ids.end());
    ids.erase(std::unique(ids.begin(), ids.end()), ids.end());
    const int32_t found = int32_t(ids.size());
    for (int32_t index = 0; index < found && index < capacity; ++index) {
        out[index] = ids[size_t(index)].GetIndexAndSequenceNumber();
    }
    return found;
}

/// The shape a shape query is asking with, placed in the world. Returns null
/// for a shape the narrow phase cannot cast or collide *with* (a mesh or a
/// height field is scenery, not a probe).
Ref<Shape> queryShape(const CJoltShapeDesc *desc) {
    if (desc == nullptr) { return nullptr; }
    Ref<Shape> shape = makeShape(*desc);
    if (shape == nullptr || shape->MustBeStatic()) { return nullptr; }
    return shape;
}

} // namespace

int32_t cjolt_world_cast_ray(const CJoltWorld *world, const float origin[3],
                             const float direction[3],
                             const CJoltQueryFilter *filter, bool allHits,
                             CJoltQueryHit *out, int32_t capacity) {
    if (world == nullptr || origin == nullptr || direction == nullptr) { return 0; }
    CJoltWorld *w = const_cast<CJoltWorld *>(world);
    const Vec3 along = vec3(direction);
    const float length = along.Length();
    if (length <= 0.0f) { return 0; }
    RRayCast ray{RVec3(vec3(origin)), along};
    QueryFilters filters(w, filter);

    if (!allHits) {
        RayCastResult hit;
        if (!w->physics.GetNarrowPhaseQuery().CastRay(ray, hit, filters.broadPhase,
                                                      filters.objects,
                                                      filters.bodies)) {
            return 0;
        }
        if (out != nullptr && capacity > 0) {
            const RVec3 point = ray.GetPointOnRay(hit.mFraction);
            writeHit(out[0], hit.mBodyID, Vec3(point),
                     surfaceNormal(w, hit.mBodyID, hit.mSubShapeID2, point),
                     hit.mFraction * length);
        }
        return 1;
    }

    AllHitCollisionCollector<CastRayCollector> collector;
    RayCastSettings settings;
    w->physics.GetNarrowPhaseQuery().CastRay(ray, settings, collector,
                                             filters.broadPhase, filters.objects,
                                             filters.bodies);
    collector.Sort();
    const int32_t found = int32_t(collector.mHits.size());
    for (int32_t index = 0; index < found && index < capacity; ++index) {
        const RayCastResult &hit = collector.mHits[size_t(index)];
        const RVec3 point = ray.GetPointOnRay(hit.mFraction);
        writeHit(out[index], hit.mBodyID, Vec3(point),
                 surfaceNormal(w, hit.mBodyID, hit.mSubShapeID2, point),
                 hit.mFraction * length);
    }
    return found;
}

int32_t cjolt_world_cast_shape(const CJoltWorld *world,
                               const CJoltShapeDesc *shape,
                               const float position[3], const float rotation[4],
                               const float direction[3],
                               const CJoltQueryFilter *filter, bool allHits,
                               CJoltQueryHit *out, int32_t capacity) {
    if (world == nullptr || position == nullptr || rotation == nullptr
        || direction == nullptr) {
        return 0;
    }
    Ref<Shape> probe = queryShape(shape);
    if (probe == nullptr) { return 0; }
    CJoltWorld *w = const_cast<CJoltWorld *>(world);
    const Vec3 along = vec3(direction);
    const float length = along.Length();
    if (length <= 0.0f) { return 0; }

    const RMat44 start =
        RMat44::sRotationTranslation(quat(rotation), RVec3(vec3(position)));
    RShapeCast cast = RShapeCast::sFromWorldTransform(probe, Vec3::sReplicate(1),
                                                      start, along);
    ShapeCastSettings settings;
    QueryFilters filters(w, filter);

    // Hits come back relative to a base offset, which is only there for
    // precision far from the origin; zero keeps them in world space.
    if (!allHits) {
        ClosestHitCollisionCollector<CastShapeCollector> collector;
        w->physics.GetNarrowPhaseQuery().CastShape(cast, settings, RVec3::sZero(),
                                                   collector, filters.broadPhase,
                                                   filters.objects, filters.bodies);
        if (!collector.HadHit()) { return 0; }
        if (out != nullptr && capacity > 0) {
            const ShapeCastResult &hit = collector.mHit;
            // The penetration axis runs from the swept shape into what it hit,
            // so the surface's own outward normal is its opposite.
            writeHit(out[0], hit.mBodyID2, hit.mContactPointOn2,
                     -hit.mPenetrationAxis.NormalizedOr(Vec3::sZero()),
                     hit.mFraction * length);
        }
        return 1;
    }

    AllHitCollisionCollector<CastShapeCollector> collector;
    w->physics.GetNarrowPhaseQuery().CastShape(cast, settings, RVec3::sZero(),
                                               collector, filters.broadPhase,
                                               filters.objects, filters.bodies);
    collector.Sort();
    const int32_t found = int32_t(collector.mHits.size());
    for (int32_t index = 0; index < found && index < capacity; ++index) {
        const ShapeCastResult &hit = collector.mHits[size_t(index)];
        writeHit(out[index], hit.mBodyID2, hit.mContactPointOn2,
                 -hit.mPenetrationAxis.NormalizedOr(Vec3::sZero()),
                 hit.mFraction * length);
    }
    return found;
}

int32_t cjolt_world_overlap_shape(const CJoltWorld *world,
                                  const CJoltShapeDesc *shape,
                                  const float position[3],
                                  const float rotation[4],
                                  const CJoltQueryFilter *filter,
                                  CJoltBodyID *out, int32_t capacity) {
    if (world == nullptr || position == nullptr || rotation == nullptr) { return 0; }
    Ref<Shape> probe = queryShape(shape);
    if (probe == nullptr) { return 0; }
    CJoltWorld *w = const_cast<CJoltWorld *>(world);

    const RMat44 centerOfMass =
        RMat44::sRotationTranslation(quat(rotation), RVec3(vec3(position)))
            .PreTranslated(probe->GetCenterOfMass());
    CollideShapeSettings settings;
    QueryFilters filters(w, filter);
    AllHitCollisionCollector<CollideShapeCollector> collector;
    w->physics.GetNarrowPhaseQuery().CollideShape(probe, Vec3::sReplicate(1),
                                                  centerOfMass, settings,
                                                  RVec3::sZero(), collector,
                                                  filters.broadPhase,
                                                  filters.objects, filters.bodies);
    std::vector<BodyID> ids;
    ids.reserve(collector.mHits.size());
    for (const CollideShapeResult &hit : collector.mHits) { ids.push_back(hit.mBodyID2); }
    return writeBodies(ids, out, capacity);
}

int32_t cjolt_world_overlap_point(const CJoltWorld *world, const float point[3],
                                  const CJoltQueryFilter *filter,
                                  CJoltBodyID *out, int32_t capacity) {
    if (world == nullptr || point == nullptr) { return 0; }
    CJoltWorld *w = const_cast<CJoltWorld *>(world);
    QueryFilters filters(w, filter);
    AllHitCollisionCollector<CollidePointCollector> collector;
    w->physics.GetNarrowPhaseQuery().CollidePoint(RVec3(vec3(point)), collector,
                                                  filters.broadPhase,
                                                  filters.objects, filters.bodies);
    std::vector<BodyID> ids;
    ids.reserve(collector.mHits.size());
    for (const CollidePointResult &hit : collector.mHits) { ids.push_back(hit.mBodyID); }
    return writeBodies(ids, out, capacity);
}
