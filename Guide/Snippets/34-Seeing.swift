// The names Chapter 34's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".
// Two things stay out. The chapter's `camera`: inside a sketch the bare name
// is the sketch's camera(_:) method, which a name declared here cannot outrank.
// And OllinVision: every preamble's imports reach every page, and its Body and
// Body3D would make the physics chapters' own types ambiguous.
import OllinSamplePhotos
import OllinScreen
import OllinVideo

// The film a fragment plays, and the screen it reads.
@MainActor let player = try! VideoPlayer(url: SampleClip.dance.url)
@MainActor let screen = ScreenCapture(.mainDisplay)
