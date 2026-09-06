#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Vision</sup>

---

## Vision

- [`Vision`](./Vision.md) - `import OllinVision` reads the Mac's camera (built-in, Continuity, or external) and runs Apple's on-device perception. The results arrive as typed values you read in `draw()`. Those values come from eighteen trackers: detection (rectangles, barcodes/QR, text/OCR, contours into vector `Shape`s), tracking (a patch you point at, parabolic trajectories, dense optical flow), segmentation (person and subject mattes and cutouts, and whatever you point at), pose (face landmarks, hand and body skeletons, the 3D body in meters), classification (fixed labels, or any phrases you type), saliency, and steady depth from a video depth model. You can also use any custom Core ML model
