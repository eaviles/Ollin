import Testing
import Foundation
@testable import Ollin

struct IKChainTests {

    private func maxLengthError(_ chain: IKChain) -> Double {
        var worst = 0.0
        for i in 0 ..< chain.lengths.count {
            let actual = chain.joints[i].distance(to: chain.joints[i + 1])
            worst = max(worst, abs(actual - chain.lengths[i]))
        }
        return worst
    }

    private func maxBendAngle(_ chain: IKChain) -> Double {
        var worst = 0.0
        for i in 1 ..< chain.lengths.count {
            let inbound = chain.joints[i] - chain.joints[i - 1]
            let outbound = chain.joints[i + 1] - chain.joints[i]
            worst = max(worst, abs(inbound.angle(to: outbound)))
        }
        return worst
    }

    @Test func bothSolversReachAReachableTarget() {
        let target = Vector2(180, 140)
        for solver in [IKChain.Solver.fabrik, .ccd] {
            let chain = IKChain(from: .zero, segments: 8, length: 40)
            chain.solver = solver
            let reached = chain.reach(toward: target, iterations: 40, tolerance: 0.5)
            #expect(reached)
            #expect(chain.tip.distance(to: target) <= 0.5)
            #expect(chain.base == .zero)                 // the base stayed planted
            #expect(maxLengthError(chain) < 1e-9)        // segments stayed rigid
        }
    }

    @Test func unreachableTargetStretchesStraight() {
        let chain = IKChain(from: Vector2(100, 100), segments: 5, length: 30)
        let target = Vector2(1000, 100)                  // far beyond the 150 reach
        chain.reach(toward: target)
        #expect(maxLengthError(chain) < 1e-9)
        #expect(chain.tip.distance(to: Vector2(250, 100)) < 1e-6)  // full reach, dead ahead
        #expect(maxBendAngle(chain) < 1e-9)              // perfectly straight
    }

    @Test func dragPinsTheTipAndFreesTheBase() {
        let chain = IKChain(from: .zero, segments: 6, length: 25)
        let target = Vector2(300, -80)
        chain.drag(to: target)
        #expect(chain.tip == target)                     // pinned exactly
        #expect(chain.base != .zero)                     // the base trailed along
        #expect(maxLengthError(chain) < 1e-9)
    }

    @Test func stiffnessLimitHolds() {
        for solver in [IKChain.Solver.fabrik, .ccd] {
            let chain = IKChain(from: .zero, segments: 10, length: 30)
            chain.solver = solver
            chain.maxBend = 0.3
            // A tour of awkward targets, including behind the base.
            for target in [Vector2(120, 200), Vector2(-150, 40), Vector2(60, -180), Vector2(10, 10)] {
                chain.reach(toward: target, iterations: 30)
                #expect(maxLengthError(chain) < 1e-9)
                #expect(maxBendAngle(chain) <= 0.3 + 1e-9)
            }
        }
    }

    @Test func aConstrainedImpossibleTargetSettlesWithoutSpinning() {
        // Stiff enough that folding back to a point right behind the base is
        // impossible: the solve must stop (stall detection), keep the rig
        // valid, and report that it fell short.
        let chain = IKChain(from: .zero, segments: 6, length: 40)
        chain.maxBend = 0.15
        let reached = chain.reach(toward: Vector2(-5, 0), iterations: 200, tolerance: 0.5)
        #expect(!reached)
        #expect(maxLengthError(chain) < 1e-9)
        #expect(maxBendAngle(chain) <= 0.15 + 1e-9)
        for joint in chain.joints {
            #expect(joint.x.isFinite && joint.y.isFinite)
        }
    }

    @Test func solvingIsDeterministic() {
        func run() -> [Vector2] {
            let chain = IKChain(from: Vector2(200, 200), segments: 12, length: 20)
            for i in 0 ..< 60 {
                let phase = Double(i) / 60 * .tau
                chain.reach(toward: Vector2(200 + cos(phase) * 180, 200 + sin(phase) * 180))
            }
            return chain.joints
        }
        #expect(run() == run())
    }

    @Test func layoutInitializerBuildsAStraightChain() {
        let chain = IKChain(from: Vector2(10, 20), segments: 4, length: 50, angle: 0)
        #expect(chain.joints.count == 5)
        #expect(chain.totalLength == 200)
        #expect(chain.joints[4].distance(to: Vector2(210, 20)) < 1e-12)
    }

    @Test func moveBaseCarriesThePoseRigidly() {
        let chain = IKChain(from: .zero, segments: 5, length: 30)
        chain.reach(toward: Vector2(80, 90))
        let pose = chain.joints.map { $0 - chain.base }
        chain.moveBase(to: Vector2(500, 400))
        #expect(chain.base == Vector2(500, 400))
        for (i, offset) in pose.enumerated() {
            #expect(chain.joints[i].distance(to: Vector2(500, 400) + offset) < 1e-9)
        }
    }
}
