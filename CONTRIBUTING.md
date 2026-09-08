# Contributing to Ollin

Ollin is alpha and pre-1.0, and it is built on nights and weekends. Contributions and ideas are welcome. This page collects the practical details, and the README's [Status & contributing](README.md#status--contributing) section sets the expectations.

## Where to start

- [`ROADMAP.md`](ROADMAP.md) is the best place to find work. Its [Up next](ROADMAP.md#up-next) section lists items that fit small, self-contained pull requests.
- Check [`CAPABILITIES.md`](CAPABILITIES.md) before you assume a capability is missing. It has one bullet per shipped capability, with pointers to its example, tests, and docs.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) explains how the larger systems work inside. [`DESIGN-NOTES.md`](DESIGN-NOTES.md) covers the intent behind the work that is still planned.

## Before a large change

Open an issue first and talk the change through. A small, self-contained fix or addition can go straight to a pull request.

## Working on the code

You need macOS 26+ with a Metal-capable GPU and a Swift 6 toolchain.

- Run an example to see the framework working: `swift run --package-path Examples Example-Basic-HelloCircle`.
- Run the tests for the area you touched with `Scripts/test.sh <Suite>`. `Scripts/test.sh quick` runs the pass that takes under a minute, and the full suite takes many minutes.
- Run `Scripts/preflight.sh` before every commit. It reads your diff and runs every gate that applies and nothing else (tests, link checks, prose lint). It also says what it skipped and why.
- A change to the public API fails preflight until you run `Scripts/api-surface.sh --record` and commit the rewritten listing under `API/` with it. That diff is how a reviewer sees what the surface gained, lost, or renamed; the changelog names a rename by both names.
- A new capability ships with an example, a test, and a `Docs/` page. The full ship checklist is in `CLAUDE.md`.
- A change a user would notice gets a line under *Unreleased* in [`CHANGELOG.md`](CHANGELOG.md). A rename names both the old and the new spelling in that line.

## Examples and attribution

Port a sketch only when its license permits redistribution under MIT. Name its source, author, URL, and license in the file header. The header template and the full rules are in [`Examples/README.md`](Examples/README.md) and the README's [Influences & attribution](README.md#influences--attribution) section. When you are unsure of a sketch's origin or license, open an issue and ask first.

## Conduct and license

The [code of conduct](CODE_OF_CONDUCT.md) applies to all project spaces. Contributions are accepted under the [MIT license](LICENSE).
