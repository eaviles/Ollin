import Testing
import Ollin
@testable import OllinVision

/// Hand pose is hard to synthesize, so detection is checked with a smoke test
/// (no hands in a blank image) and the joint/finger model is checked directly.
@Suite struct HandTrackerTests {

    @Test func blankImageHasNoHands() async throws {
        let image = Image(width: 128, height: 128, color: .white)
        let hands = try await HandTracker.detect(in: image)
        #expect(hands.isEmpty)
    }

    @Test func fingerChainsRunWristToTip() {
        for finger in Finger.allCases {
            let chain = finger.chain
            #expect(chain.count == 5)
            #expect(chain.first == .wrist)
            #expect(HandJoint.tips.contains(chain.last!))
        }
    }

    @Test func tipsAreTheFiveFingertips() {
        #expect(HandJoint.tips.count == 5)
        #expect(Set(HandJoint.tips) == [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip])
    }

    @Test func bonesAndPointsAreEmptyForAnEmptyHand() {
        let hand = Hand(chirality: .unknown, confidence: 0, joints: [:])
        let rect = Rectangle(x: 0, y: 0, width: 100, height: 100)
        #expect(hand.bones(in: rect).isEmpty)
        #expect(hand.points(in: rect).isEmpty)
        #expect(hand.point(.indexTip, in: rect) == nil)
    }
}
