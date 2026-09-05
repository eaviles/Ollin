#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Tools](./README.md) → `Checking a shader`</sup>

---

# Checking a shader

A sketch compiles the shaders you write for it. So the only way to find out whether a shader compiles is to launch something that draws it. When it does not compile, the first sign is a layer that stays blank.

`ollin check` answers the question without a sketch. Pass it a `.metal` file. It compiles that file on this machine's GPU, the same way a running sketch would, then reports what it found.

```sh
ollin check Ripple.metal
```

```
Ripple.metal: ok
  a filter, because it reads one layer
  reads parameters 0, 1, so pass 2 floats
  includes /Users/you/Sketches/helpers.metal
```

Use it while you are editing a shader on its own, after bringing one over with [`--from-shader`](./ShaderImport.md), or before you give one to somebody else.

## What it tells you

**Errors, at your own line.** The compiler sees a composed source that holds Ollin's shader library and a wrapper around what you wrote. The message you get names your own file and your own line instead of that composed source.

```
Ripple.metal:12:15: error: use of undeclared identifier 'noize'
    float v = noize(uv);
              ^
```

A mistake inside a file your shader [includes](../Shaders/Shaders.md#pulling-in-another-file) is reported against **that** file, at its own line.

**What the shader is.** The number of layers a shader reads decides what it can be. A shader that reads no layer is a generator, one layer makes it a filter, and two make it a combine. The check works that out from the readers you call, `sample` and `sampleAux`, and reports it. Read that line before you wire the shader into a chain that expects something else.

**The parameters it reads.** The check lists every `param(info, i)` written out in the source, so you know how many floats to pass:

```
  reads parameters 0, 1, 2, so pass 3 floats
```

The check also calls out a gap in the numbering, because an index nothing writes reads as zero, which is usually a mistake:

```
  reads parameters 0, 2, and skips 1, which nothing would write
```

The check cannot see an index the shader works out while it runs. So the list covers what the shader asks for openly, and it is not a promise that the shader asks for nothing else.

**The files it includes**, in the order they were read.

## Naming the shape yourself

By default, the shape follows the layer readers the shader calls. Name the shape yourself when you want the shader compiled a particular way:

```sh
ollin check Ripple.metal --as combine
```

The shapes are `generator`, `filter`, and `combine`. A shader compiled as the wrong shape fails, and that failure is useful. It is how you find out that a shader you meant as a generator reads a layer after all.

## Checking against a narrowed library

A `Shader` can take `using:` to splice in only part of Ollin's shader library, which cuts compile time. Pass the same list to the check, so a shader written that way is compiled the way it runs:

```sh
ollin check Ripple.metal --using noise,sdf
```

The sections are `color`, `hash`, `noise`, `sdf`, `domain`, and `visual`, plus `all` (the default) and `none`. If the shader calls a helper from a section it did not ask for, that helper shows up as an undeclared identifier. Catching that is what the narrowed check is for.

## Several files at once

```sh
ollin check Shaders/*.metal
```

The check reports on each file on its own. The command exits nonzero if any of them failed, so you can use it in a script or a build step.

---

### See also

- [User-supplied shaders](../Shaders/Shaders.md): the contract a shader file has to meet, and the library it can call
- [Bringing a shader over](./ShaderImport.md): translate a GLSL fragment shader into a project
- [Compute and GPU particles](../Shaders/Compute.md): the same path, written as a compute kernel
- [Single-file sketches](./SingleFile.md): the rest of what the `ollin` command does
