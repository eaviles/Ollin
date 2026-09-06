#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Video</sup>

---

## Video

- [`Video`](./Video.md) - `import OllinVideo` to play a video file into a sketch as a live image. Each decoded frame arrives as a GPU texture that you draw with `drawImage`, and a CPU `snapshot()` gives you the pixels for reads and analysis
- [`Slit scan`](./SlitScan.md) - `SlitScan` keeps a rolling history of frames and reads it back through a per-pixel time delay. That gives you, for example, the classic scan, time ripples, displacement maps
