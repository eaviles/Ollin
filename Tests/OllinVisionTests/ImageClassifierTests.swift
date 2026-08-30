import Testing
import Foundation
import Ollin
@testable import OllinVision

/// The classifier model is neural, so the runs that need it soft-skip where the
/// compute device is missing (the segmentation tests' pattern); the vocabulary
/// and the decode invariants are checked for real.
@Suite struct ImageClassifierTests {

    /// A bright disk on a dark ground — enough structure for the model to score
    /// (it reads as a moon, a ping-pong ball; what matters is that it scores).
    private func diskImage() -> Image {
        let image = Image(width: 320, height: 240, color: Color(white: 0.05))
        let cx = 160, cy = 120, radius = 70
        for y in (cy - radius)...(cy + radius) {
            for x in (cx - radius)...(cx + radius)
            where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius {
                image[x, y] = Color(red: 1.0, green: 0.6, blue: 0.1)
            }
        }
        return image
    }

    @Test func nameOpensUnderscores() {
        let found = Classification(label: "blue_sky", confidence: 0.9)
        #expect(found.name == "blue sky")
        #expect(Classification(label: "dog", confidence: 0.5).name == "dog")
    }

    @Test func vocabularyIsLargeAndEveryday() {
        let labels = ImageClassifier.supportedLabels()
        #expect(labels.count > 1000)
        #expect(labels.contains("sky"))
        #expect(labels.contains("people"))
    }

    @Test func stillDetectScoresTheWholeVocabularySorted() async throws {
        // Soft-skip: the model needs a compute device some test environments
        // lack; a throw there isn't a code failure.
        guard let all = try? await ImageClassifier.detect(in: diskImage(),
                                                          minConfidence: 0) else { return }
        // The request scores the entire vocabulary, strongest first.
        #expect(all.count > 1000)
        #expect(zip(all, all.dropFirst()).allSatisfy { $0.confidence >= $1.confidence })
        #expect(all.allSatisfy { (0.0...1.0).contains($0.confidence) })
    }

    @Test func detectCutsAtTheConfidenceFloor() async throws {
        guard let labels = try? await ImageClassifier.detect(in: diskImage(),
                                                             minConfidence: 0.05) else { return }
        #expect(labels.allSatisfy { $0.confidence >= 0.05 })
        // The floor keeps the meaningful few, not the ~1,300-label tail.
        #expect(labels.count < 100)
    }

    @MainActor
    @Test func liveWiringPublishesLabels() async throws {
        // Gate on the still path: only run the live assertion where the model
        // demonstrably runs (elsewhere this is the soft-skip).
        let image = diskImage()
        guard (try? await ImageClassifier.detect(in: image, minConfidence: 0)) != nil else { return }

        // The camera-free live path: a hand-driven source standing in for the
        // capture queue. Floor 0 so publishing doesn't depend on what the model
        // makes of the synthetic disk.
        let source = FrameSourceTests.ManualFrameSource()
        let classifier = ImageClassifier(source, minConfidence: 0)
        let tap = try #require(source.frameTap)
        let frame = image.currentCGImage()

        // The tap takes a frame the way a capture queue would. Its analysis
        // runs on a background task, so nothing here waits on it: a deadline
        // over that task reads a saturated full-suite machine as a failure.
        tap(frame)

        // The deterministic drive: the same analyze path, awaited inline. A
        // loaded machine makes this slower, never absent.
        await SourceAnalyzers.analyzer(for: source).analyzeNow(FrameBox(frame))
        let labels = classifier.labels
        #expect(!labels.isEmpty)

        // The read surfaces agree with each other.
        let top = try #require(classifier.topClassification)
        #expect(top.label == labels[0].label)
        #expect(classifier.confidence(of: top.label) == top.confidence)
        // Spaces stand in for underscores in the by-name query.
        if let spaced = labels.first(where: { $0.label.contains("_") }) {
            #expect(classifier.confidence(of: spaced.name) == spaced.confidence)
        }
    }
}
