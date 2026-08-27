import CoreGraphics
import Foundation
import Testing
import Ollin
@testable import OllinVision

/// The tokenizer goldens and the failure paths are gated only on the fetched
/// vocabulary; the real-model tests also need the paired encoders
/// (`Scripts/fetch-models.sh`), soft-skipping elsewhere (CI never fetches the
/// weights).
@Suite struct ConceptTrackerTests {

    static let vocabURL = ModelTrackerTests.model("bpe_simple_vocab_16e6.txt")
    static let imageModelURL = ModelTrackerTests.model("mobileclip_s0_image.mlpackage")
    static let textModelURL = ModelTrackerTests.model("mobileclip_s0_text.mlpackage")

    static var vocabIsFetched: Bool { ModelTrackerTests.isFetched(vocabURL) }
    static var modelsAreFetched: Bool {
        vocabIsFetched && ModelTrackerTests.isFetched(imageModelURL)
            && ModelTrackerTests.isFetched(textModelURL)
    }

    static func tracker(concepts: [String] = []) -> ConceptTracker {
        ConceptTracker(imageModelAt: imageModelURL, textModelAt: textModelURL,
                       vocabAt: vocabURL, concepts: concepts)
    }

    // MARK: Always-on

    @Test func missingFilesSurfaceInsteadOfFailingSilently() async {
        let tracker = ConceptTracker(
            imageModelAt: URL(fileURLWithPath: "/nowhere/image.mlpackage"),
            textModelAt: URL(fileURLWithPath: "/nowhere/text.mlpackage"),
            vocabAt: URL(fileURLWithPath: "/nowhere/vocab.txt"),
            concepts: ["anything"])
        let image = Image(width: 32, height: 32, color: .white)
        await #expect(throws: ConceptTracker.Error.self) {
            _ = try await tracker.detect(in: image)
        }
        #expect(!tracker.isAvailable)
        #expect(tracker.unavailableReason?.contains("/nowhere") == true)
        #expect(!tracker.isLoaded)
    }

    @Test func queryingANewPhraseRegistersIt() {
        let tracker = Self.tracker(concepts: ["one thing"])
        #expect(tracker.confidence(of: "another thing") == 0)
        #expect(tracker.concepts == ["one thing", "another thing"])
        // Registration is case-insensitive: a re-query in different case
        // doesn't add a duplicate.
        #expect(tracker.confidence(of: "Another Thing") == 0)
        #expect(tracker.concepts.count == 2)
    }

    // MARK: Tokenizer (gated on the fetched vocabulary)

    /// Golden sequences, verified token-for-token against the published
    /// reference implementation run over the same vocabulary file: everyday
    /// phrases, casing and extra spaces, contractions, accented words,
    /// digits and punctuation, an emoji's multi-byte split, and words long
    /// enough to break into many pieces.
    @Test func tokenizerMatchesTheReference() throws {
        guard Self.vocabIsFetched else { return }
        let tokenizer = try PhraseTokenizer(vocabAt: Self.vocabURL)
        let goldens: [(String, [Int32])] = [
            ("a photo of a cat", [49406, 320, 1125, 539, 320, 2368, 49407]),
            ("a spooky scene", [49406, 320, 15369, 3562, 49407]),
            ("hello world", [49406, 3306, 1002, 49407]),
            ("a", [49406, 320, 49407]),
            ("!", [49406, 256, 49407]),
            ("How Spooky   does the CAMERA look?",
             [49406, 829, 15369, 1897, 518, 3934, 1012, 286, 49407]),
            ("it's a beautiful day, isn't it?",
             [49406, 585, 568, 320, 1215, 575, 267, 2923, 713, 585, 286, 49407]),
            ("un jardin ensoleillé à Paris",
             [49406, 2271, 37371, 524, 10519, 828, 4166, 21259, 3445, 49407]),
            ("1234 numbers and sym-bols #art",
             [49406, 272, 273, 274, 275, 6121, 537, 40327, 268, 65, 2236, 258, 794, 49407]),
            ("a photo of a cat 🐈", [49406, 320, 1125, 539, 320, 2368, 2074, 486, 49407]),
        ]
        for (phrase, expected) in goldens {
            var padded = expected
            padded.append(contentsOf: [Int32](repeating: 0,
                                              count: tokenizer.contextLength - padded.count))
            #expect(tokenizer.encode(phrase) == padded, "phrase: \(phrase)")
        }
    }

    @Test func tokenizerShapeAndTruncation() throws {
        guard Self.vocabIsFetched else { return }
        let tokenizer = try PhraseTokenizer(vocabAt: Self.vocabURL)
        #expect(tokenizer.vocabularySize == 49408)
        #expect(tokenizer.startToken == 49406)
        #expect(tokenizer.endToken == 49407)

        // Every sequence is exactly the context length.
        #expect(tokenizer.encode("").count == 77)
        #expect(tokenizer.encode("a house by the sea").count == 77)

        // A phrase too long to fit truncates and still ends on the end marker.
        let long = Array(repeating: "extraordinary", count: 100).joined(separator: " ")
        let tokens = tokenizer.encode(long)
        #expect(tokens.count == 77)
        #expect(tokens[0] == tokenizer.startToken)
        #expect(tokens[76] == tokenizer.endToken)
        #expect(!tokens.contains(0))
    }

    // MARK: Real model (soft-gated on the downloaded weights)

    /// The end-to-end pin: a staged solid-color picture ranks its own color's
    /// phrase first, the shares sum to 1, and `similarity` agrees with the
    /// ranking. A wrong tokenizer, a wrong embedding decode, or a broken
    /// normalization all fail this.
    @Test func aRedPictureRanksTheRedPhraseFirst() async throws {
        guard Self.modelsAreFetched else { return }
        let tracker = Self.tracker(concepts: ["a plain red picture",
                                              "a plain blue picture"])
        let red = Image(width: 256, height: 256,
                        color: Color(red: 0.85, green: 0.1, blue: 0.1, alpha: 1))
        let scores = try await tracker.detect(in: red)
        #expect(tracker.isLoaded)
        #expect(scores.count == 2)
        #expect(scores.first?.label == "a plain red picture")
        #expect(scores.first!.confidence > 0.5)
        let total = scores.reduce(0) { $0 + $1.confidence }
        #expect(abs(total - 1) < 1e-6)
    }

    /// Real footage: the flying dancers' scene prefers a matching phrase over
    /// an absurd one, through the same still path.
    @Test func realFootagePrefersTheMatchingPhrase() async throws {
        guard Self.modelsAreFetched else { return }
        let frame = try await ModelTrackerTests.clipFrame(at: 6)
        let tracker = Self.tracker(concepts: ["people performing on a tall pole",
                                              "a bowl of soup on a table"])
        let scores = try await tracker.detect(in: Image(cgImage: frame))
        #expect(scores.first?.label == "people performing on a tall pole")
        #expect(scores.first!.confidence > 0.6)
    }

    /// The embedding surface: unit length, and a phrase sits closer to its
    /// paraphrase than to an unrelated phrase.
    @Test func embeddingsAreUnitLengthAndMeaningful() async throws {
        guard Self.modelsAreFetched else { return }
        let tracker = Self.tracker()
        let cat = try await tracker.embedding(of: "a photo of a cat")
        let kitten = try await tracker.embedding(of: "a picture of a kitten")
        let engine = try await tracker.embedding(of: "a diagram of a jet engine")
        #expect(cat.count == 512)
        let length = cat.reduce(0) { $0 + $1 * $1 }.squareRoot()
        #expect(abs(length - 1) < 1e-3)
        func dot(_ a: [Double], _ b: [Double]) -> Double {
            zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        }
        #expect(dot(cat, kitten) > dot(cat, engine))
    }

    /// The live path over a hand-fired frame source: the models load in the
    /// background, frames flow, the scores publish, and a phrase added
    /// mid-run joins the scoring on a later frame.
    @Test @MainActor func liveWiringPublishesAndFollowsNewPhrases() async throws {
        guard Self.modelsAreFetched else { return }
        let source = FrameSourceTests.ManualFrameSource()
        let tracker = ConceptTracker(source,
                                     imageModelAt: Self.imageModelURL,
                                     textModelAt: Self.textModelURL,
                                     vocabAt: Self.vocabURL,
                                     concepts: ["a plain red picture",
                                                "a plain blue picture"])
        let red = Image(width: 128, height: 128,
                        color: Color(red: 0.85, green: 0.1, blue: 0.1, alpha: 1))
        let cgImage = red.currentCGImage()

        // The tap takes a frame the way a capture queue would. Its analysis
        // runs on a background task, so nothing here waits on it: a deadline
        // over that task reads a saturated full-suite machine as a failure.
        source.frameTap?(cgImage)

        // The still path awaits the model load and the two phrase encodings
        // deterministically; then the live analyze path runs inline. A loaded
        // machine makes both slower, never absent.
        _ = try await tracker.detect(in: red)
        await SourceAnalyzers.analyzer(for: source).analyzeNow(FrameBox(cgImage))
        #expect(tracker.labels.count == 2)
        #expect(tracker.top?.label == "a plain red picture")
        #expect(tracker.confidence(of: "a plain red picture") > 0.5)
        #expect(tracker.similarity(of: "a plain red picture")
                > tracker.similarity(of: "a plain blue picture"))
        #expect(tracker.imageEmbedding?.count == 512)

        // A phrase first seen mid-run: reads 0 now, scored on a later frame.
        // The read queues it for the background text-encoder drain; awaiting
        // its embedding encodes it here instead, into the same cache, so the
        // frame below scores three phrases with no clock involved.
        _ = tracker.confidence(of: "a solid green picture")
        _ = try await tracker.embedding(of: "a solid green picture")
        await SourceAnalyzers.analyzer(for: source).analyzeNow(FrameBox(cgImage))
        #expect(tracker.labels.count == 3)
        let total = tracker.labels.reduce(0) { $0 + $1.confidence }
        #expect(abs(total - 1) < 1e-6)
    }
}
