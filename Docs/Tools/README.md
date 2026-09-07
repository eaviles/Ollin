#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Tools</sup>

---

## Tools

- [`Project generator`](./ProjectGenerator.md) - `ollin new` and `ollin generate`: a ready-to-run sketch folder from a few questions. Each template runs for real in the window, so you can watch it before you pick one
- [`Single-file sketches`](./SingleFile.md) - the `ollin` command: run one `.swift` file as a sketch from any directory, with no package needed
- [`The sketch on the phone`](./OnThePhone.md) - `ollin phone`: run the sketch on a paired iPhone or iPad. Every save installs it again, and its clock and parameters carry across, and the parameters stay live on the Mac
- [`Live coding`](./LiveCoding.md) - the OllinLiveCoding performance host: write and evaluate sketch code live, with the code shown over the visuals
- [`Bringing a shader over`](./ShaderImport.md) - `ollin new --from-shader`: translate a GLSL fragment shader into Metal, and get a project built around it
- [`Checking a shader`](./ShaderCheck.md) - `ollin check`: compile a `.metal` file on this machine's GPU. It reports the errors at your own line, what kind of shader it is, and the parameters it reads
- [`Bringing a scene over`](./SceneImport.md) - `ollin new --from-scene`: write a glTF or USD scene out as the sketch that draws it
- [`Writing an extension`](./Extensions.md) - `ollin new --kind extension`: a library that other sketches import, the `ollinx-` naming convention, and the seams to build on
- [`Dragging a shape`](./DragToEdit.md) - Command-drag a shape in the live window or on the performance stage, and the numbers that place it change in your own code
- [`The parameter timeline`](./Timeline.md) - OllinLive's timeline panel: one lane per automated parameter, and a playhead over the sketch clock. You place keys from the inspector's diamonds and drag them by hand, and the panel round-trips to the automation file
- [`The reference offline`](./Reference.md) - `ollin docs` and `ollin examples`: read these pages and every example sketch in the terminal, from the checkout you build against
- [`Profiling`](./Profiling.md) - the inspector's cost row: CPU against GPU on one scale, the draw and pass counts, and a frame handed to Xcode
