#!/usr/bin/env python3
"""Scripts/preflight-reach.py: which of preflight's build gates a diff can reach.

    swift package dump-package | Scripts/preflight-reach.py <changed path>...
    Scripts/preflight-reach.py --selftest

A build gate reads what some target builds, and a change can move that only
when it is in the target or in something the target depends on. A change to a
host app cannot move a figure, the phone build, the public listings, or what a
snippet compiles against, and until 2026-11-10 it ran all four gates anyway
because the question asked was only "did anything under Sources/ change".

This reads the package's own description of itself (the manifest, as
`swift package dump-package` prints it) on standard input, takes the changed
paths as arguments, finds the target each one belongs to, and prints one line
per gate, `name=1` when the diff reaches it and `name=0` when it cannot:

    libraries   any library product (the public listings, the API reference)
    snippets    the snippet checker and everything a block can import
    ios         the Ollin product, which is what the phone build compiles
    figures     the figure runner and everything a figure can import

Every doubt answers 1. A change to the manifest or its lock file reaches
everything, and so does a path under Sources/ or External/ that sits in no
target's folder, and so does a gate whose own target the manifest no longer
names. Paths anywhere else (prose, tests, scripts) are not this script's
question and reach nothing here; preflight has its own rules for those.
"""

import json
import sys

GATES = {
    "snippets": ["OllinGuideSnippets"],
    "ios": ["Ollin"],
    "figures": ["OllinGuideFigures"],
}


def reach(manifest, changed):
    targets = {target["name"]: target for target in manifest["targets"]}
    depends = {
        name: [next(iter(entry.values()))[0] for entry in target.get("dependencies", [])]
        for name, target in targets.items()
    }
    folders = {}
    for name, target in targets.items():
        default = ("Tests/" if target.get("type") == "test" else "Sources/") + name
        folders[(target.get("path") or default).rstrip("/") + "/"] = name

    def closure(name):
        seen, pending = set(), [name]
        while pending:
            current = pending.pop()
            if current in seen:
                continue
            seen.add(current)
            pending.extend(depends.get(current, []))
        return seen

    everything = False
    touched = set()
    for path in changed:
        if path in ("Package.swift", "Package.resolved"):
            everything = True
        elif path.startswith(("Sources/", "External/")):
            # The longest folder wins, so a target nested in another's folder
            # keeps its own files.
            owners = [folder for folder in folders if path.startswith(folder)]
            if owners:
                touched.add(folders[max(owners, key=len)])
            else:
                everything = True

    libraries = [
        name
        for product in manifest.get("products", [])
        if "library" in product.get("type", {})
        for name in product.get("targets", [])
    ]
    gates = dict(GATES, libraries=libraries)
    answers = {}
    for gate, roots in gates.items():
        if everything or not roots or any(root not in targets for root in roots):
            answers[gate] = True
            continue
        reached = set().union(*(closure(root) for root in roots))
        answers[gate] = bool(touched & reached)
    return answers


def selftest():
    def target(name, *dependencies, kind="regular", path=None):
        entry = {"name": name, "type": kind, "dependencies": [{"byName": [d, None]} for d in dependencies]}
        if path:
            entry["path"] = path
        return entry

    manifest = {
        "products": [
            {"name": "Ollin", "type": {"library": ["automatic"]}, "targets": ["Ollin"]},
            {"name": "OllinAudio", "type": {"library": ["automatic"]}, "targets": ["OllinAudio"]},
            {"name": "OllinPhysics", "type": {"library": ["automatic"]}, "targets": ["OllinPhysics"]},
            {"name": "OllinLive", "type": {"executable": None}, "targets": ["OllinLive"]},
        ],
        "targets": [
            target("CTess", path="External/CTess"),
            target("CJolt", path="External/CJolt"),
            target("Ollin", "CTess"),
            target("OllinAudio", "Ollin"),
            target("OllinPhysics", "Ollin", "CJolt"),
            target("OllinRuntime", "Ollin"),
            target("OllinGuideSnippets", "Ollin", "OllinRuntime", "OllinAudio", "OllinPhysics", kind="executable"),
            target("OllinGuideFigures", "Ollin", "OllinRuntime", "OllinAudio", "OllinPhysics", kind="executable"),
            target("OllinLive", "Ollin", "OllinRuntime", "OllinAudio", kind="executable"),
            target("OllinTests", "Ollin", kind="test"),
        ],
    }
    none = {"libraries": False, "snippets": False, "ios": False, "figures": False}
    all_of_them = {gate: True for gate in none}
    cases = [
        ("the core reaches everything", ["Sources/Ollin/Core/Sketch.swift"], all_of_them),
        ("a host app reaches nothing", ["Sources/OllinLive/LiveApp.swift"], none),
        ("a satellite reaches all but the phone build", ["Sources/OllinAudio/Synth.swift"],
         dict(all_of_them, ios=False)),
        ("the snippet checker reaches only itself", ["Sources/OllinGuideSnippets/main.swift"],
         dict(none, snippets=True)),
        ("the runtime reaches the two tools that load sketches", ["Sources/OllinRuntime/SketchLoader.swift"],
         dict(none, snippets=True, figures=True)),
        ("a vendored library reaches what depends on it", ["External/CJolt/src/Body.cpp"],
         dict(all_of_them, ios=False)),
        ("the core's own vendored library reaches everything", ["External/CTess/tess.c"], all_of_them),
        ("the manifest reaches everything", ["Package.swift"], all_of_them),
        ("a file under Sources/ in no target reaches everything", ["Sources/Stray.swift"], all_of_them),
        ("a file under External/ in no target reaches everything", ["External/NOTES.md"], all_of_them),
        ("prose and tests are not asked here", ["Docs/README.md", "Tests/OllinTests/A.swift"], none),
        ("one reaching path among others is enough", ["Sources/OllinLive/LiveApp.swift", "Sources/Ollin/A.swift"],
         all_of_them),
    ]
    failed = 0
    for label, changed, expected in cases:
        got = reach(manifest, changed)
        if got != expected:
            failed += 1
            print(f"preflight-reach selftest: {label}: expected {expected}, got {got}", file=sys.stderr)
    # A gate whose target the manifest no longer names cannot be reasoned
    # about, so it runs.
    renamed = dict(manifest, targets=[t for t in manifest["targets"] if t["name"] != "OllinGuideFigures"])
    if not reach(renamed, ["Sources/OllinLive/LiveApp.swift"])["figures"]:
        failed += 1
        print("preflight-reach selftest: a gate whose target is gone must run", file=sys.stderr)
    if failed:
        sys.exit(1)
    print(f"preflight-reach selftest: {len(cases) + 1} readings of a diff land where they should")


def main():
    if sys.argv[1:] == ["--selftest"]:
        selftest()
        return
    manifest = json.load(sys.stdin)
    for gate, reached in sorted(reach(manifest, [path for path in sys.argv[1:] if path]).items()):
        print(f"{gate}={1 if reached else 0}")


if __name__ == "__main__":
    main()
