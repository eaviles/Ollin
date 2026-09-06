#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Output</sup>

---

## Output

- [`Export`](./Export.md) - save frames as raster (PNG, sequences), motion (video, animated GIF), or vector (SVG for pen plotters, PDF for print)
- [`Web page`](./Web.md) - `--export-web` records what a sketch draws and writes a page that plays it back in a browser. The page is one self-contained file, or a fragment for a page of your own
- [`Path-traced export`](./PathTraced.md) - `--path-traced` renders the same 3D scene offline by tracing light paths. That gives you soft shadows, color bleed, mirror-in-mirror reflections, and a lens with depth of field
- [`Recording`](./Recording.md) - record a live run while you play it. The picture and the sketch's own sound (or the room's) are written into one movie in real time
- [`Installation`](./Installation.md) - leave a piece running for days. The piece runs full screen with no pointer, and its clock survives a week. A watch starts the piece again if it stops, and the piece can run only during the building's hours
- [`A sketch as an app`](./App.md) - wrap a finished piece as a signed, double-clickable Mac app with its own icon. The app runs on a machine that has never had the toolchain installed
- [`Screen saver`](./ScreenSaver.md) - wrap a sketch as the machine's screen saver, so the work runs when nobody is at the desk
- [`Wallpaper`](./Wallpaper.md) - run a sketch as the desktop wallpaper. It sits behind the icons on every display and moves all day while the machine is used for everything else
- [`Menu bar`](./MenuBar.md) - run a sketch as a small live strip among the menu bar's status items. It sits beside the clock for the whole working day
- [`Fabrication`](./Fabrication.md) - write a `Mesh` as STL, OBJ, or 3MF for 3D printing, with real units and a printability check
- [`G-code`](./GCode.md) - write a frame's line work as a program that a pen plotter, laser cutter, or CNC router runs directly. Ollin orders the paths to keep travel short
- [`Print separations`](./PrintSeparations.md) - split a sketch into per-ink grayscale masters for risograph and screen printing, with an overprint preview and registration marks
- [`Print color`](./PrintColor.md) - soft-proof a canvas against a press profile and flag the colors that ink cannot reach. It also splits the canvas into process-color plates, with their total-ink figures
- [`Spatial`](./Spatial.md) - write a 3D frame or a `Scene` as USDZ. You can open a piece in that format in Quick Look, send it in a message, and place it on a real table in AR
