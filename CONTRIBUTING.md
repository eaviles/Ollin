# Contributing to Ollin

Ollin is alpha and pre-1.0, built nights and weekends. Contributions and ideas are genuinely welcome; this page collects the practical details, and the README's [Status & contributing](README.md#status--contributing) section sets the expectations.

## Where to start

- [`ROADMAP.md`](ROADMAP.md) is the best source of work, and its [Up next](ROADMAP.md#up-next) section maps onto small, self-contained pull requests.
- Before assuming a capability is missing, check [`CAPABILITIES.md`](CAPABILITIES.md): one bullet per shipped capability, with pointers to its example, tests, and docs.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) explains how the larger systems work inside, and [`DESIGN-NOTES.md`](DESIGN-NOTES.md) covers the intent behind what's still planned.

## Before a large change

Please open an issue first and talk it through. Small, self-contained fixes and additions can go straight to a pull request.

## Working on the code

You need macOS 26+ with a Metal-capable GPU and a Swift 6 toolchain.

- Run an example to see the framework working: `swift run --package-path Examples Example-Basic-HelloCircle`.
- Run the tests for the area you touched: `Scripts/test.sh <Suite>`. `Scripts/test.sh quick` is the sub-minute pass; the full suite takes many minutes.
- Run `Scripts/preflight.sh` before every commit. It reads your diff, runs exactly the gates that apply (tests, link checks, prose lint), and says what it skipped and why.
- A new capability ships with an example, a test, and a `Docs/` page; `CLAUDE.md` carries the full ship checklist.
- A change a user would notice gets a line under *Unreleased* in [`CHANGELOG.md`](CHANGELOG.md), and a rename names the old and new spelling there.

## Examples and attribution

Only port a sketch whose license permits redistribution under MIT, and name its source, author, URL, and license in the file header. The header template and the full rules live in [`Examples/README.md`](Examples/README.md) and the README's [Influences & attribution](README.md#influences--attribution) section. When you're unsure of a sketch's origin or license, open an issue and ask first.

## Conduct and license

The [code of conduct](CODE_OF_CONDUCT.md) applies to all project spaces. Contributions are accepted under the [MIT license](LICENSE).
