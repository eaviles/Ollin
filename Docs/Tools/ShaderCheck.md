#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Tools](./README.md) → `Checking a shader`</sup>

---

# Checking a shader

A shader you write for a sketch is compiled by the sketch. So the only way to learn whether it compiles is to launch something that draws it. When it does not, the first sign is a layer that stays blank.

`ollin check` closes that loop. Hand it a `.metal` file and it compiles it on this machine's GPU, the same way a running sketch would, and says what it found.

```sh
ollin check Ripple.metal
```

```
Ripple.metal: ok
  a filter, because it reads one layer
  reads parameters 0, 1, so pass 2 floats
  includes /Users/you/Sketches/helpers.metal
```

Reach for it while you are editing a shader on its own, after bringing one over with [`--from-shader`](./ShaderImport.md), or before handing one to somebody else.

## What it tells you

**Errors, at your own line.** The compiler sees a composed source, with Ollin's shader library and a wrapper around what you wrote. The message you get names your file and your line instead.

```
Ripple.metal:12:15: error: use of undeclared identifier 'noize'
    float v = noize(uv);
              ^
```

A mistake inside a file your shader [includes](../Shaders/Shaders.md#pulling-in-another-file) is reported against **that** file, at its own line.

**What the shader is.** How many layers a shader reads decides what it can be: none makes it a generator, one a filter, two a combine. The check works that out from the readers you call, `sample` and `sampleAux`, and says so. It is worth seeing before you wire the shader into a chain that expects something else.

**The parameters it reads.** Every `param(info, i)` in plain sight, so you know how many floats to pass:

```
  reads parameters 0, 1, 2, so pass 3 floats
```

A gap is called out, since an index nothing writes reads as zero and is usually a slip:

```
  reads parameters 0, 2, and skips 1, which nothing would write
```

An index the shader works out while it runs cannot be seen from here, so this is what the shader asks for openly, not a promise that it asks for nothing else.

**The files it includes**, in the order they were read.

## Naming the shape yourself

Left alone, the shape follows the layer readers the shader calls. Name it instead when you want the shader compiled a particular way:

```sh
ollin check Ripple.metal --as combine
```

The shapes are `generator`, `filter`, and `combine`. A shader compiled as the wrong shape fails, which is itself useful. It is how you find out that a shader you meant as a generator is quietly reading a layer.

## Checking against a narrowed library

A `Shader` can take `using:` to splice only part of Ollin's shader library, which trims compile time. Pass the same list to the check, so a shader written that way is compiled the way it runs:

```sh
ollin check Ripple.metal --using noise,sdf
```

The sections are `color`, `hash`, `noise`, `sdf`, `domain`, and `visual`, plus `all` (the default) and `none`. A helper the shader calls but did not ask for shows up as an undeclared identifier, which is the point.

## Several files at once

```sh
ollin check Shaders/*.metal
```

Each file is reported on its own. The command exits nonzero if any of them failed, so it fits in a script or a build step.

---

### See also

- [User-supplied shaders](../Shaders/Shaders.md): the contract a shader file has to meet, and the library it can call
- [Bringing a shader over](./ShaderImport.md): translate a GLSL fragment shader into a project
- [Compute and GPU particles](../Shaders/Compute.md): the kernel sibling of the same path
- [Single-file sketches](./SingleFile.md): the rest of what the `ollin` command does
