#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Tools</sup>

---

## Tools

- [`Project generator`](./ProjectGenerator.md) - `ollin new` and `ollin generate`: a ready-to-run sketch folder from a few questions, with templates you can watch running before you pick one
- [`Single-file sketches`](./SingleFile.md) - the `ollin` command: run one `.swift` file as a sketch from anywhere, no package needed
- [`Live coding`](./LiveCoding.md) - the OllinLiveCoding performance host: write and evaluate sketch code live, with the code shown over the visuals
- [`Bringing a shader over`](./ShaderImport.md) - `ollin new --from-shader`: translate a GLSL fragment shader into Metal and get a project around it
- [`Checking a shader`](./ShaderCheck.md) - `ollin check`: compile a `.metal` file on this machine's GPU and see the errors at your own line, what the shader is, and the parameters it reads
- [`Bringing a scene over`](./SceneImport.md) - `ollin new --from-scene`: a glTF or USD scene written out as the sketch that draws it
- [`Writing an extension`](./Extensions.md) - `ollin new --kind extension`: a library other sketches import, the `ollinx-` naming convention, and the seams to build on
- [`Dragging a shape`](./DragToEdit.md) - Command-drag a shape in the live window and the numbers that place it change in your own file
- [`Profiling`](./Profiling.md) - the inspector's cost row: CPU against GPU on one scale, the draw and pass counts, and a frame handed to Xcode
