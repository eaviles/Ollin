#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Vision</sup>

---

## Vision

- [`Vision`](./Vision.md) - `import OllinVision` reads the Mac's camera (built-in, Continuity, or external) and runs Apple's on-device perception. The results arrive as typed values you read in `draw()`. Those values come from sixteen trackers: detection (rectangles, barcodes/QR, text/OCR, contours into vector `Shape`s), tracking (a patch you point at, parabolic trajectories, dense optical flow), segmentation (person and subject mattes and cutouts), pose (face landmarks, hand and body skeletons, the 3D body in meters), classification, and saliency. You can also use any custom Core ML model
