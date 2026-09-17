#!/usr/bin/env python3
"""Read two sets of API listings as a version.

Called by Scripts/api-diff.sh; not meant to be run by hand. Takes the
listings Scripts/api-surface.sh wrote at two points (one directory each, one
file per module) and says what changed between them, what that costs the next
version number, and whether the shim rule holds.

Every line is keyed by its container, spelled as the container's kind and
name rather than its whole head line, so a type that gains a conformance does
not move every member under it. A removed line is paired with an added line
in the same container before either is reported on its own: the same name
with other labels or types is a signature change, the same types under another
name is a rename, and what is left is paired by text similarity and marked as
likely. A removed type folds its members into itself, and a removed type whose
members reappear under another name is a renamed type.

The bump follows the version the diff starts from. At major zero every change
is a minor (a breaking change and a new feature both bump the minor, and a
patch is a release with no public change). From 1.0 on a removal of any kind
is a major, an addition or a deprecation is a minor, and nothing is a patch.

The shim rule is what 1.0 promises: a public spelling never goes away without
its deprecated twin staying behind for a grace cycle. Here that reads as: a
line present at the start and gone at the end, that was not already deprecated
at the start, is a violation. A line that was deprecated at the start and is
gone at the end finished its grace cycle, which the rule allows and the bump
still counts as a major. Before 1.0 the rule is a rehearsal and the violations
are a count in the summary; from 1.0 on, or under --strict, they fail the run.
A second rule reads the working tree rather than the listings: every
`@available(*, deprecated` in Sources/ lives in that module's
Deprecations.swift and names its replacement, so the shims stay in one place
per module and every one of them offers the fix-it. That rule holds in both
modes, since a shim in the wrong file is a defect of the tree and not a
question of version.
"""
import argparse
import difflib
import os
import re
import sys
import tempfile

MARK = "@available(deprecated) "
TYPE_KINDS = ("struct", "class", "enum", "protocol", "extension")
MODIFIERS = {
    "open", "final", "nonisolated", "override", "required", "static",
    "mutating", "prefix", "postfix", "convenience", "@discardableResult",
    "@propertyWrapper", "@resultBuilder", "@dynamicMemberLookup", "@objc",
    "@frozen",
}
LIKELY = 0.75  # how alike two names must be for a leftover pair to be called a rename


class Entry:
    """One line of a listing: where it sits, what it says, and whether it is
    marked deprecated."""

    def __init__(self, path, text, deprecated, depth):
        self.path = path            # the container keys above it
        self.text = text            # the line, unindented and unmarked
        self.deprecated = deprecated
        self.depth = depth
        self.decl = describe(text)

    @property
    def key(self):
        return (self.path, self.text)

    @property
    def container_key(self):
        """The key this line contributes as a container, if it is a type."""
        if self.decl["kind"] != "type":
            return None
        return f"{self.decl['type_kind']} {self.decl['name']}"

    @property
    def own_path(self):
        return self.path + (self.container_key,) if self.container_key else self.path


def split_top(text, sep=","):
    """Split at separators outside every bracket. `->` is not a closing angle."""
    parts, depth, start, i = [], 0, 0, 0
    while i < len(text):
        c = text[i]
        if c == "-" and text[i + 1:i + 2] == ">":
            i += 2
            continue
        if c in "([<":
            depth += 1
        elif c in ")]>":
            depth -= 1
        elif c == sep and depth == 0:
            parts.append(text[start:i])
            start = i + 1
        i += 1
    parts.append(text[start:])
    return [p.strip() for p in parts if p.strip()]


def balanced(text, open_index):
    """The index of the bracket closing the one at `open_index`."""
    depth, i = 0, open_index
    while i < len(text):
        c = text[i]
        if c == "-" and text[i + 1:i + 2] == ">":
            i += 2
            continue
        if c in "([<":
            depth += 1
        elif c in ")]>":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return len(text) - 1


def parameters(inside):
    labels, types, defaults = [], [], []
    for param in split_top(inside):
        label, _, typed = param.partition(":")
        typed = typed.strip()
        default = typed.endswith(" = default")
        if default:
            typed = typed[: -len(" = default")]
        labels.append(label.strip())
        types.append(typed)
        defaults.append(default)
    return tuple(labels), tuple(types), tuple(defaults)


def describe(text):
    """What a listing line declares: its kind, name, labels, types and the rest,
    so two lines can be compared piece by piece."""
    words = text.split(" ")
    mods = []
    while words and (words[0] in MODIFIERS or words[0].startswith("@")):
        mods.append(words.pop(0))
    rest = " ".join(words)
    decl = {"kind": "other", "name": rest, "labels": (), "types": (), "defaults": (),
            "ret": "", "mods": tuple(sorted(mods)), "type_kind": ""}
    if not words:
        return decl
    head = words[0]
    if head in TYPE_KINDS:
        name = re.split(r"[:<]| where ", rest[len(head) + 1:], maxsplit=1)[0].strip()
        decl.update(kind="type", type_kind=head, name=name, ret=rest)
        return decl
    if head == "func":
        body = rest[len("func "):]
        open_index = body.index("(")
        close = balanced(body, open_index)
        labels, types, defaults = parameters(body[open_index + 1:close])
        tail = body[close + 1:].strip()
        decl.update(kind="func", name=body[:open_index], labels=labels, types=types,
                    defaults=defaults, ret=tail)
        return decl
    if head.startswith("init"):
        open_index = rest.index("(")
        close = balanced(rest, open_index)
        labels, types, defaults = parameters(rest[open_index + 1:close])
        decl.update(kind="init", name=rest[:open_index], labels=labels, types=types,
                    defaults=defaults, ret=rest[close + 1:].strip())
        return decl
    if head.startswith("subscript"):
        open_index = rest.index("(")
        close = balanced(rest, open_index)
        labels, types, defaults = parameters(rest[open_index + 1:close])
        decl.update(kind="subscript", name="subscript", labels=labels, types=types,
                    defaults=defaults, ret=rest[close + 1:].strip())
        return decl
    if head in ("var", "let"):
        name, _, typed = rest[len(head) + 1:].partition(":")
        decl.update(kind=head, name=name.strip(), ret=typed.strip())
        return decl
    if head == "case":
        body = rest[len("case "):]
        name = re.split(r"[(\[]", body, maxsplit=1)[0]
        decl.update(kind="case", name=name, ret=body[len(name):])
        return decl
    if head in ("typealias", "associatedtype"):
        body = rest[len(head) + 1:]
        name, _, target = body.partition(" = ")
        decl.update(kind=head, name=name.strip(), ret=target.strip())
        return decl
    return decl


def selector(entry, qualify=True):
    """How the changelog spells a declaration: `Type.name(label:label:)`."""
    decl = entry.decl
    owner = ".".join(k.split(" ", 1)[1] for k in entry.path if not k.startswith("extension "))
    if not owner:
        owner = ".".join(k.split(" ", 1)[1] for k in entry.path)
    if decl["kind"] == "type":
        return f"{owner}.{decl['name']}" if owner and qualify else decl["name"]
    if decl["kind"] in ("func", "subscript"):
        name = decl["name"] + "(" + "".join(f"{l}:" for l in decl["labels"]) + ")"
    elif decl["kind"] == "init":
        name = "init(" + "".join(f"{l}:" for l in decl["labels"]) + ")"
        if owner and qualify:
            return owner + "(" + "".join(f"{l}:" for l in decl["labels"]) + ")"
    elif decl["kind"] == "case":
        name = "." + decl["name"]
        return f"{owner}{name}" if owner and qualify else name
    else:
        name = decl["name"]
    # The facade's own members read bare, the way every sketch calls them.
    if owner and qualify and owner != "Sketch":
        return f"{owner}.{name}"
    return name


def read_listing(path):
    """Every entry of one listing, in file order, plus the members of every
    container by its full path."""
    entries, stack, members = [], [], {}
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            if not line or line.startswith("//"):
                continue
            depth = (len(line) - len(line.lstrip(" "))) // 2
            text = line.strip()
            deprecated = text.startswith(MARK)
            if deprecated:
                text = text[len(MARK):]
            del stack[depth:]
            entry = Entry(tuple(stack), text, deprecated, depth)
            entries.append(entry)
            members.setdefault(entry.path, set()).add(text)
            if entry.container_key:
                stack.append(entry.container_key)
    return entries, members


def read_directory(directory):
    listings = {}
    for name in sorted(os.listdir(directory)):
        if name.endswith(".txt"):
            listings[name[:-4]] = read_listing(os.path.join(directory, name))
    return listings


def score(old, new):
    """How well an old line and a new line pair up, or 0 when they do not.
    Higher is surer: a signature change under the same name, then a rename
    with the same shape, then text similarity."""
    a, b = old.decl, new.decl
    if a["kind"] != "type" and b["kind"] != "type":
        if a["kind"] == b["kind"] and a["name"] == b["name"] and a["mods"] == b["mods"]:
            return 3.0 if a["labels"] == b["labels"] else 2.9
        if a["kind"] == b["kind"] and a["name"] == b["name"]:
            return 2.8
        same_shape = (a["kind"] == b["kind"] and a["types"] == b["types"]
                      and a["ret"] == b["ret"] and a["mods"] == b["mods"]
                      and a["defaults"] == b["defaults"])
        if same_shape and a["kind"] in ("func", "init", "subscript") and a["types"]:
            return 2.0 + (0.1 if a["labels"] == b["labels"] else 0)
        if same_shape and a["kind"] in ("var", "let", "case", "typealias"):
            return 1.9
    elif a["kind"] == "type" and b["kind"] == "type":
        if a["type_kind"] == b["type_kind"] and a["name"] == b["name"]:
            return 3.0
        return 0
    else:
        return 0
    # What is left pairs on the name alone: one name inside the other (a
    # `sources` that became `availableSources()`), or names that mostly agree.
    # The whole line would pair any two short declarations on their keyword.
    x, y = a["name"].lower(), b["name"].lower()
    if not x or not y:
        return 0
    if x in y or y in x:
        return 1.0
    ratio = difflib.SequenceMatcher(None, x, y).ratio()
    return ratio if ratio >= LIKELY else 0


def inherits(head_text):
    """The names after the colon of a type head, and its generic clause."""
    body = head_text.split(" where ", 1)
    names = body[0].partition(":")[2]
    return {n.strip() for n in split_top(names) if n.strip()}, (body[1] if len(body) > 1 else "")


def head_loses(old, new):
    """Whether a type's new head drops something the old one promised: a
    conformance, a raw type, a superclass, or its generic clause."""
    old_names, old_where = inherits(old.decl["ret"])
    new_names, new_where = inherits(new.decl["ret"])
    old_sig = re.search(r"<[^>]*>", old.decl["ret"].split(":")[0])
    new_sig = re.search(r"<[^>]*>", new.decl["ret"].split(":")[0])
    return (not old_names <= new_names or old_where != new_where
            or (old_sig.group(0) if old_sig else "") != (new_sig.group(0) if new_sig else ""))


def classify_pair(old, new, sure):
    a, b = old.decl, new.decl
    if a["kind"] == "type":
        return "changed" if head_loses(old, new) else "extended"
    if a["name"] == b["name"] and a["kind"] == b["kind"]:
        return "changed"
    return "renamed" if sure else "likely renamed"


class ModuleDiff:
    def __init__(self, module):
        self.module = module
        self.added = []            # entries new at the end
        self.removed = []          # entries gone at the end, not deprecated at the start
        self.finished = []         # entries deprecated at the start and gone at the end
        self.pairs = []            # (kind, old entry, new entry, old_was_deprecated)
        self.deprecated = []       # entries marked deprecated at the end but not the start
        self.twins = []            # (old deprecated entry, new entry): a shim with its replacement
        self.added_types = []      # (entry, member count)
        self.removed_types = []    # (entry, member count, was deprecated)
        self.renamed_types = []    # (old entry, new entry)
        self.moved = []            # (old entry, protocol name): a member now supplied by a protocol
        self.is_new_module = False
        self.is_gone_module = False

    @property
    def violations(self):
        """The removals the shim rule forbids: anything that went away without
        having been deprecated first."""
        out = [e for e in self.removed]
        out.extend(old for kind, old, _, was in self.pairs if not was and kind != "extended")
        out.extend(e for e, _, was in self.removed_types if not was)
        out.extend(old for old, _ in self.renamed_types)
        return out

    @property
    def removals(self):
        """Every removal the bump counts, grace cycles included."""
        return (len(self.removed) + len(self.finished)
                + sum(1 for k, *_ in self.pairs if k != "extended")
                + len(self.removed_types) + len(self.renamed_types))

    @property
    def additions(self):
        return (len(self.added) + len(self.added_types)
                + sum(1 for k, *_ in self.pairs if k == "extended"))

    @property
    def is_empty(self):
        return not (self.removals or self.additions or self.deprecated)


def diff_module(module, old, new):
    result = ModuleDiff(module)
    old_entries, old_members = old if old else ([], {})
    new_entries, new_members = new if new else ([], {})
    result.is_new_module = old is None
    result.is_gone_module = new is None
    old_by_key = {e.key: e for e in old_entries}
    new_by_key = {e.key: e for e in new_entries}

    removed = [e for e in old_entries if e.key not in new_by_key]
    added = [e for e in new_entries if e.key not in old_by_key]
    for entry in new_entries:
        twin = old_by_key.get(entry.key)
        if twin is not None and entry.deprecated and not twin.deprecated:
            result.deprecated.append(entry)

    # Whole types first: a removed type folds its members, and a removed type
    # whose members come back under another name is a rename.
    removed_types = [e for e in removed if e.decl["kind"] == "type"]
    added_types = [e for e in added if e.decl["kind"] == "type"]
    removed_type_paths = {e.own_path for e in removed_types}
    added_type_paths = {e.own_path for e in added_types}

    def under(entry, paths):
        return any(entry.path[:len(p)] == p for p in paths)

    def folded_size(entry, members):
        return sum(len(v) for k, v in members.items() if k[:len(entry.own_path)] == entry.own_path)

    # A type whose container key survives (kind and name unchanged) only
    # changed its head line; its members diff on their own.
    surviving = {k for k in new_members} | {e.own_path for e in new_entries if e.container_key}
    paired_types = set()
    for old_type in removed_types:
        if old_type.own_path in surviving:
            continue  # the head changed; handled as a pair below
        best, best_score = None, 0
        old_set = old_members.get(old_type.own_path, set())
        for new_type in added_types:
            if new_type in paired_types or new_type.own_path in {e.own_path for e in old_entries if e.container_key}:
                continue
            if new_type.decl["type_kind"] != old_type.decl["type_kind"]:
                continue
            new_set = new_members.get(new_type.own_path, set())
            union = old_set | new_set
            jaccard = len(old_set & new_set) / len(union) if union else 0
            if jaccard >= 0.8 and jaccard > best_score and old_set:
                best, best_score = new_type, jaccard
        if best is not None:
            paired_types.add(best)
            result.renamed_types.append((old_type, best))
        else:
            result.removed_types.append((old_type, folded_size(old_type, old_members), old_type.deprecated))
    for new_type in added_types:
        if new_type in paired_types or new_type.own_path in {e.own_path for e in old_entries if e.container_key}:
            continue
        result.added_types.append((new_type, folded_size(new_type, new_members)))

    gone_paths = {e.own_path for e in removed_types if e.own_path not in surviving}
    born_paths = {e.own_path for e in added_types if e.own_path not in {x.own_path for x in old_entries if x.container_key}}
    removed = [e for e in removed if not under(e, gone_paths) and e.own_path not in gone_paths]
    added = [e for e in added if not under(e, born_paths) and e.own_path not in born_paths]

    # A member that now comes from a protocol the type conforms to is moved,
    # not removed: its text, with the type's name read as `Self`, sits under
    # that protocol at the end. Several types can move onto one line.
    supplied = {}
    for entry in new_entries:
        if entry.decl["kind"] == "type" or not entry.path:
            continue
        owner = entry.path[-1]
        if owner.startswith("protocol "):
            supplied.setdefault(entry.text, set()).add(owner.split(" ", 1)[1])
    heads = {e.own_path: e for e in new_entries if e.container_key}
    still_removed = []
    for entry in removed:
        owner = entry.path[-1] if entry.path else ""
        kind, _, type_name = owner.partition(" ")
        if kind not in ("struct", "class", "enum") or entry.decl["kind"] == "type":
            still_removed.append(entry)
            continue
        normalized = re.sub(rf"\b{re.escape(type_name)}\b", "Self", entry.text)
        protocols = supplied.get(normalized, set()) | supplied.get(entry.text, set())
        head = heads.get(entry.path)
        conforms = {p for p in protocols if head is None or re.search(rf"\b{re.escape(p)}\b", head.text)}
        if conforms:
            # Several protocols can supply the same line; the one the type
            # gained in this diff is the one it moved onto.
            old_head = next((e for e in old_entries if e.own_path == entry.path and e.container_key), None)
            gained = (inherits(head.text)[0] - inherits(old_head.text)[0]) if head is not None and old_head is not None else set()
            preferred = sorted(conforms & gained) or sorted(conforms)
            result.moved.append((entry, preferred[0]))
        else:
            still_removed.append(entry)
    removed = still_removed

    # Members: pair the removals with the additions in the same container,
    # surest pairs first, each line used once.
    candidates = []
    for old_entry in removed:
        for new_entry in added:
            if old_entry.path != new_entry.path:
                continue
            s = score(old_entry, new_entry)
            if s > 0:
                candidates.append((s, old_entry, new_entry))
    candidates.sort(key=lambda c: (-c[0], c[1].text, c[2].text))
    used_old, used_new = set(), set()
    for s, old_entry, new_entry in candidates:
        if id(old_entry) in used_old or id(new_entry) in used_new:
            continue
        used_old.add(id(old_entry))
        used_new.add(id(new_entry))
        kind = classify_pair(old_entry, new_entry, sure=s >= 1.9)
        result.pairs.append((kind, old_entry, new_entry, old_entry.deprecated))
    for entry in removed:
        if id(entry) in used_old:
            continue
        (result.finished if entry.deprecated else result.removed).append(entry)
    result.added = [e for e in added if id(e) not in used_new]

    # A shim beside its replacement: the deprecated old spelling paired with a
    # new line the same way, so the skeleton can say what it became.
    twin_candidates = []
    for old_entry in result.deprecated:
        for new_entry in result.added:
            if old_entry.path != new_entry.path:
                continue
            s = score(old_entry, new_entry)
            if s > 0:
                twin_candidates.append((s, old_entry, new_entry))
    twin_candidates.sort(key=lambda c: (-c[0], c[1].text, c[2].text))
    used_old, used_new = set(), set()
    for s, old_entry, new_entry in twin_candidates:
        if id(old_entry) in used_old or id(new_entry) in used_new:
            continue
        used_old.add(id(old_entry))
        used_new.add(id(new_entry))
        result.twins.append((old_entry, new_entry))
    return result


def diff_all(old_dir, new_dir, only=None):
    old, new = read_directory(old_dir), read_directory(new_dir)
    modules = sorted(set(old) | set(new))
    if only:
        modules = [m for m in modules if m == only]
    return [diff_module(m, old.get(m), new.get(m)) for m in modules]


# The tree rule: every shim in one file per module, each naming its replacement.
SHIM = re.compile(r"@available\(\*,\s*deprecated")


def source_violations(sources):
    out = []
    for root, _, files in os.walk(sources):
        for name in files:
            if not name.endswith(".swift"):
                continue
            path = os.path.join(root, name)
            with open(path, encoding="utf-8", errors="replace") as handle:
                lines = handle.read().split("\n")
            for number, line in enumerate(lines, 1):
                if not SHIM.search(line):
                    continue
                where = os.path.relpath(path, os.path.dirname(sources.rstrip("/")) or ".")
                if name != "Deprecations.swift":
                    out.append(f"{where}:{number}: a shim outside Deprecations.swift")
                if "renamed:" not in line and "message:" not in line:
                    out.append(f"{where}:{number}: a shim with no renamed: or message:")
    return out


def bump(diffs, from_major):
    removals = sum(d.removals for d in diffs)
    additions = sum(d.additions for d in diffs)
    deprecations = sum(len(d.deprecated) for d in diffs)
    if from_major == 0:
        return "minor" if removals or additions or deprecations else "patch"
    if removals:
        return "major"
    if additions or deprecations:
        return "minor"
    return "patch"


def type_kind_word(entry):
    return entry.decl["type_kind"]


def report(diffs, args, out=sys.stdout):
    label = f"{args.from_label} -> {args.to_label}"
    for d in diffs:
        if d.is_empty and not d.is_new_module and not d.is_gone_module:
            continue
        if d.is_new_module:
            print(f"{d.module}: a new module", file=out)
            continue
        if d.is_gone_module:
            print(f"{d.module}: the module is gone", file=out)
            continue
        counts = []
        if d.additions:
            counts.append(f"{d.additions} added")
        n_removed = len(d.removed) + len(d.finished) + len(d.removed_types)
        if n_removed:
            counts.append(f"{n_removed} removed")
        n_renamed = sum(1 for k, *_ in d.pairs if k != "changed") + len(d.renamed_types)
        if n_renamed:
            counts.append(f"{n_renamed} renamed")
        n_changed = sum(1 for k, *_ in d.pairs if k == "changed")
        if n_changed:
            counts.append(f"{n_changed} changed")
        n_extended = sum(1 for k, *_ in d.pairs if k == "extended")
        if n_extended:
            counts.append(f"{n_extended} extended")
        if d.deprecated:
            counts.append(f"{len(d.deprecated)} deprecated")
        if d.moved:
            counts.append(f"{len(d.moved)} moved onto a protocol")
        print(f"{d.module}: {', '.join(counts)}", file=out)
        for old, new in d.renamed_types:
            print(f"  renamed   {type_kind_word(old)} {selector(old)} -> {selector(new)}", file=out)
        for kind, old, new, was in sorted(d.pairs, key=lambda p: (p[0], selector(p[1]))):
            note = "  (was deprecated)" if was else ""
            what = "type " if old.decl["kind"] == "type" else ""
            if kind == "extended":
                gained = ", ".join(sorted(inherits(new.decl["ret"])[0] - inherits(old.decl["ret"])[0])) or "its declaration"
                print(f"  extended  type {selector(old)} (gains {gained})", file=out)
            elif selector(old) == selector(new):
                print(f"  {kind:<9} {what}{selector(old)}{note}", file=out)
                print(f"              was  {old.text}", file=out)
                print(f"              now  {new.text}", file=out)
            else:
                print(f"  {kind:<9} {what}{selector(old)} -> {selector(new)}{note}", file=out)
        for entry, protocol in sorted(d.moved, key=lambda m: selector(m[0])):
            print(f"  moved     {selector(entry)} -> {protocol}", file=out)
        for entry, size, was in d.removed_types:
            note = "  (was deprecated)" if was else ""
            print(f"  removed   {type_kind_word(entry)} {selector(entry)} ({size} members){note}", file=out)
        for entry in sorted(d.removed, key=selector):
            print(f"  removed   {selector(entry)}", file=out)
        for entry in sorted(d.finished, key=selector):
            print(f"  removed   {selector(entry)}  (deprecated since before {args.from_label})", file=out)
        twinned = {id(o) for o, _ in d.twins}
        for old, new in d.twins:
            print(f"  deprecated {selector(old)} -> {selector(new)}", file=out)
        for entry in sorted(d.deprecated, key=selector):
            if id(entry) not in twinned:
                print(f"  deprecated {selector(entry)}", file=out)
        for entry, size in d.added_types:
            print(f"  added     {type_kind_word(entry)} {selector(entry)} ({size} members)", file=out)
        by_owner = {}
        for entry in d.added:
            if any(entry is n for _, n in d.twins):
                continue
            by_owner.setdefault(entry.path, []).append(entry)
        for path, entries in sorted(by_owner.items()):
            names = ", ".join(sorted(selector(e, qualify=False) for e in entries))
            owner = ".".join(k.split(" ", 1)[1] for k in path) or "(top level)"
            print(f"  added     to {owner}: {names}", file=out)
    return label


def summary(diffs, args, mode, violations, source_problems, out=sys.stdout):
    label = f"{args.from_label} -> {args.to_label}"
    additions = sum(d.additions for d in diffs)
    removals = sum(d.removals for d in diffs)
    deprecations = sum(len(d.deprecated) for d in diffs)
    touched = [d.module for d in diffs if not d.is_empty or d.is_new_module or d.is_gone_module]
    from_major = int(args.from_version.split(".")[0])
    verdict = bump(diffs, from_major)
    era = "0.x" if from_major == 0 else f"{from_major}.x"
    if not touched:
        print(f"api-diff: {label}: no public change; bump {era}: patch", file=out)
    else:
        print(f"api-diff: {label}: +{additions} -{removals}"
              f"{f' ~{deprecations} deprecated' if deprecations else ''}"
              f" across {len(touched)} module{'s' if len(touched) != 1 else ''}"
              f" ({', '.join(touched)}); bump {era}: {verdict}", file=out)
    n = len(violations)
    if n:
        noun = "removal" if n == 1 else "removals"
        if mode == "strict":
            print(f"api-diff: the shim rule fails: {n} {noun} with no deprecated twin", file=out)
        else:
            print(f"api-diff: the shim rule would fail from 1.0 on: {n} {noun} with no deprecated twin"
                  f" (a rehearsal before 1.0, not a failure)", file=out)
    elif touched:
        print("api-diff: the shim rule holds: nothing went away without its deprecated twin", file=out)
    for problem in source_problems:
        print(f"api-diff: {problem}", file=out)


def changelog(diffs, args, out=sys.stdout):
    """The skeleton of a CHANGELOG entry: one bullet per change, in the file's
    own voice, for a person to group and explain."""
    added_lines, changed_lines, deprecated_lines = [], [], []
    for d in diffs:
        if d.is_new_module:
            added_lines.append(f"- **A new module, `{d.module}`.**")
            continue
        if d.is_gone_module:
            changed_lines.append(f"- **The `{d.module}` module is gone.**")
            continue
        for entry, size in d.added_types:
            added_lines.append(f"- **`{selector(entry)}`.** A new {type_kind_word(entry)} with {size} public members.")
        by_owner = {}
        twin_new = {id(n) for _, n in d.twins}
        for entry in d.added:
            if id(entry) in twin_new:
                continue
            by_owner.setdefault(entry.path, []).append(entry)
        for path, entries in sorted(by_owner.items()):
            owner = ".".join(k.split(" ", 1)[1] for k in path) or d.module
            names = ", ".join(f"`{selector(e, qualify=False)}`" for e in sorted(entries, key=selector))
            added_lines.append(f"- **On `{owner}`:** {names}.")
        for kind, old, new, was in d.pairs:
            if kind == "extended":
                gained = ", ".join(f"`{n}`" for n in sorted(inherits(new.decl["ret"])[0] - inherits(old.decl["ret"])[0]))
                added_lines.append(f"- **`{selector(old)}` conforms to {gained or 'more'}.**")
        for old, new in d.renamed_types:
            changed_lines.append(f"- **`{selector(old)}` is `{selector(new)}`.**")
        for kind, old, new, was in sorted(d.pairs, key=lambda p: (p[0], selector(p[1]))):
            if kind == "extended":
                continue
            if kind == "changed" and selector(old) == selector(new):
                what = "declaration" if old.decl["kind"] == "type" else "type"
                changed_lines.append(f"- **`{selector(old)}` changed its {what}.** `{old.text}` is now `{new.text}`.")
            elif kind == "changed":
                changed_lines.append(f"- **`{selector(old)}` is now `{selector(new)}`.**")
            elif kind == "renamed":
                changed_lines.append(f"- **`{selector(old)}` is `{selector(new)}`.**")
            else:
                changed_lines.append(f"- **`{selector(old)}` is `{selector(new)}`.** (a likely pairing; check it)")
        moves = {}
        for entry, protocol in d.moved:
            owner = ".".join(k.split(" ", 1)[1] for k in entry.path)
            moves.setdefault((owner, protocol), []).append(selector(entry, qualify=False))
        for (owner, protocol), names in sorted(moves.items()):
            listed = ", ".join(f"`{n}`" for n in sorted(names))
            changed_lines.append(f"- **`{owner}` takes {listed} from `{protocol}`.**")
        for entry, size, was in d.removed_types:
            changed_lines.append(f"- **`{selector(entry)}` is gone.** ({size} members)")
        for entry in sorted(d.removed + d.finished, key=selector):
            changed_lines.append(f"- **`{selector(entry)}` is gone.**")
        twinned = {id(o) for o, _ in d.twins}
        for old, new in d.twins:
            deprecated_lines.append(f"- **`{selector(old)}` is deprecated; use `{selector(new)}`.**")
        for entry in sorted(d.deprecated, key=selector):
            if id(entry) not in twinned:
                deprecated_lines.append(f"- **`{selector(entry)}` is deprecated.**")
    if added_lines:
        print("### Added\n", file=out)
        print("\n".join(added_lines) + "\n", file=out)
    if changed_lines:
        print("### Changed\n", file=out)
        print("\n".join(changed_lines) + "\n", file=out)
    if deprecated_lines:
        print("### Deprecated\n", file=out)
        print("\n".join(deprecated_lines) + "\n", file=out)
    if not (added_lines or changed_lines or deprecated_lines):
        print("(no public change)", file=out)


# ---------------------------------------------------------------------------
# Self-test: fixtures that exercise every class the reader knows.

OLD_FIXTURE = """// Ollin: the public surface, written by Scripts/api-surface.sh.
// Change the source, then run it with --record; never edit this file by hand.
enum CameraView: String, Sendable
  case isometric
  static var corner: CameraView { get }
open class Sketch
  @available(deprecated) func older()
  func caustic(through: Lens, index: Double, closed: Bool = default) -> [Ray]
  func gone()
  func reload(to: Sketch, keepClock: Bool = default)
  func ring(innerRadius: Double, outerRadius: Double) -> Vector2
  func updateSwarm(_: Swarm)
  var sources: [MIDISource] { get }
struct Dropped
  var x: Int { get }
struct Old: Equatable
  var a: Int { get }
  var b: Int { get }
struct Same: Equatable
  var kept: Int { get }
struct Vec2: Equatable
  func distance(to: Vec2) -> Double
  var length: Double { get }
  var x: Double { get set }
"""

NEW_FIXTURE = """// Ollin: the public surface, written by Scripts/api-surface.sh.
// Change the source, then run it with --record; never edit this file by hand.
enum CameraView: String, Sendable
  @available(deprecated) static var corner: CameraView { get }
  case isometric
final class Crowd
  var count: Int { get }
open class Sketch
  func availableSources() -> [MIDISource]
  func caustic(through: Lens, ior: Double, closed: Bool = default) -> [Ray]
  func fresh()
  func randomVector(innerRadius: Double, outerRadius: Double) -> Vector2
  func reload(to: Sketch, keepClock: Bool = default, keepRun: Bool = default)
  func stepSwarm(_: Swarm)
struct New: Equatable
  var a: Int { get }
  var b: Int { get }
struct Same: Equatable, Sendable
  var kept: Int { get }
protocol Vec: Equatable
  func distance(to: Self) -> Double
  var length: Double { get }
struct Vec2: Equatable, Vec
  var x: Double { get set }
"""

SHIMMED_FIXTURE = """// Ollin: the public surface, written by Scripts/api-surface.sh.
// Change the source, then run it with --record; never edit this file by hand.
enum CameraView: String, Sendable
  case isometric
  static var corner: CameraView { get }
open class Sketch
  @available(deprecated) func caustic(through: Lens, index: Double, closed: Bool = default) -> [Ray]
  func caustic(through: Lens, ior: Double, closed: Bool = default) -> [Ray]
  @available(deprecated) func gone()
  @available(deprecated) func older()
  @available(deprecated) func reload(to: Sketch, keepClock: Bool = default)
  func reload(to: Sketch, keepClock: Bool = default, keepRun: Bool = default)
  @available(deprecated) func ring(innerRadius: Double, outerRadius: Double) -> Vector2
  func randomVector(innerRadius: Double, outerRadius: Double) -> Vector2
  func stepSwarm(_: Swarm)
  @available(deprecated) func updateSwarm(_: Swarm)
  @available(deprecated) var sources: [MIDISource] { get }
  func availableSources() -> [MIDISource]
struct Dropped
  var x: Int { get }
struct Old: Equatable
  var a: Int { get }
  var b: Int { get }
struct Same: Equatable
  var kept: Int { get }
protocol Vec: Equatable
  func distance(to: Self) -> Double
  var length: Double { get }
struct Vec2: Equatable, Vec
  var x: Double { get set }
"""


def selftest():
    failures = []

    def check(condition, what):
        if not condition:
            failures.append(what)

    with tempfile.TemporaryDirectory() as work:
        old_dir, new_dir, shim_dir = (os.path.join(work, n) for n in ("old", "new", "shim"))
        for d in (old_dir, new_dir, shim_dir):
            os.mkdir(d)
        for d, text in ((old_dir, OLD_FIXTURE), (new_dir, NEW_FIXTURE), (shim_dir, SHIMMED_FIXTURE)):
            with open(os.path.join(d, "Ollin.txt"), "w") as handle:
                handle.write(text)
        with open(os.path.join(new_dir, "OllinFresh.txt"), "w") as handle:
            handle.write("// OllinFresh\n// header\nstruct Thing\n  var a: Int { get }\n")

        # The parser reads a signature piece by piece.
        d = describe("@discardableResult static func exportWidget(to: String, from: Foundation.Date = default, of: () -> Sketch) -> [String]")
        check(d["kind"] == "func" and d["name"] == "exportWidget", "func name")
        check(d["labels"] == ("to", "from", "of"), f"labels {d['labels']}")
        check(d["types"] == ("String", "Foundation.Date", "() -> Sketch"), f"types {d['types']}")
        check(d["defaults"] == (False, True, False), f"defaults {d['defaults']}")
        check(d["ret"] == "-> [String]", f"ret {d['ret']}")
        check("static" in d["mods"] and "@discardableResult" in d["mods"], "modifiers")
        d = describe("init?(resource: String, withExtension: String? = default, in: Foundation.Bundle)")
        check(d["kind"] == "init" and d["labels"] == ("resource", "withExtension", "in"), "init labels")
        d = describe("case object([String : JSON])")
        check(d["kind"] == "case" and d["name"] == "object", "case name")
        d = describe("struct Crowd<T>: Equatable where T: Hashable")
        check(d["kind"] == "type" and d["name"] == "Crowd" and d["type_kind"] == "struct", "type head")
        d = describe("subscript(_: Int) -> Double { get set }")
        check(d["kind"] == "subscript" and d["types"] == ("Int",), "subscript")

        # The unshimmed rewrite: every class of change lands where it should.
        diffs = diff_all(old_dir, new_dir)
        by_name = {d.module: d for d in diffs}
        check(by_name["OllinFresh"].is_new_module, "a new module")
        d = by_name["Ollin"]
        pairs = {(k, selector(o), selector(n)) for k, o, n, _ in d.pairs}
        check(("renamed", "updateSwarm(_:)", "stepSwarm(_:)") in pairs, f"rename by shape: {pairs}")
        check(("renamed", "ring(innerRadius:outerRadius:)", "randomVector(innerRadius:outerRadius:)") in pairs, "rename with labels kept")
        check(("changed", "caustic(through:index:closed:)", "caustic(through:ior:closed:)") in pairs, "a label change is a change")
        check(("changed", "reload(to:keepClock:)", "reload(to:keepClock:keepRun:)") in pairs, "a new parameter is a change")
        check(("likely renamed", "sources", "availableSources()") in pairs, f"a cross-kind pairing is likely: {pairs}")
        check(("extended", "Same", "Same") in pairs and ("extended", "Vec2", "Vec2") in pairs, f"a gained conformance extends the type: {pairs}")
        check(head_loses(Entry((), "struct A: Equatable, Sendable", False, 0), Entry((), "struct A: Equatable", False, 0)), "a dropped conformance loses")
        check(head_loses(Entry((), "struct A<T>: Equatable", False, 0), Entry((), "struct A<T, U>: Equatable", False, 0)), "a changed generic signature loses")
        check(not head_loses(Entry((), "enum A: String, Sendable", False, 0), Entry((), "enum A: String, Sendable, CaseIterable", False, 0)), "a gained conformance keeps")
        check([selector(e) for e in d.removed] == ["gone()"], f"removed {[selector(e) for e in d.removed]}")
        check([selector(e) for e in d.finished] == ["older()"], "a deprecated line that went away finished its cycle")
        check([(selector(o), selector(n)) for o, n in d.renamed_types] == [("Old", "New")], "a renamed type")
        check([(selector(e), n) for e, n, _ in d.removed_types] == [("Dropped", 1)], "a removed type folds its members")
        check([selector(e) for e in d.added] == ["fresh()"], f"added {[selector(e) for e in d.added]}")
        check([selector(e) for e in d.deprecated] == ["CameraView.corner"], "a newly deprecated line")
        check(len(d.twins) == 0, "no twin when the replacement already existed")
        moved = sorted((selector(e), p) for e, p in d.moved)
        check(moved == [("Vec2.distance(to:)", "Vec"), ("Vec2.length", "Vec")], f"members moved onto a protocol: {moved}")
        check([(selector(e), n) for e, n in d.added_types] == [("Crowd", 1), ("Vec", 2)], f"added types {[(selector(e), n) for e, n in d.added_types]}")
        members = {e.text for e in read_listing(os.path.join(new_dir, "Ollin.txt"))[0] if e.path == ("struct Same",)}
        check(members == {"var kept: Int { get }"}, "members keyed by the container's kind and name survive a head change")
        violations = [selector(e) for e in d.violations]
        check(sorted(violations) == sorted(["updateSwarm(_:)", "ring(innerRadius:outerRadius:)", "caustic(through:index:closed:)",
                                            "reload(to:keepClock:)", "sources", "gone()", "Dropped", "Old"]),
              f"violations {sorted(violations)}")
        check(bump(diffs, 0) == "minor", "0.x: any change is a minor")
        check(bump(diffs, 1) == "major", "1.x: a removal is a major")

        # The shimmed rewrite: the rule holds, and the bump is a minor from 1.0 on.
        diffs = diff_all(old_dir, shim_dir)
        d = diffs[0]
        check(d.violations == [], f"shimmed: no violations, got {[selector(e) for e in d.violations]}")
        check(d.removals == 0, "shimmed: nothing removed")
        twins = {(selector(o), selector(n)) for o, n in d.twins}
        check(("updateSwarm(_:)", "stepSwarm(_:)") in twins and ("sources", "availableSources()") in twins, f"twins {twins}")
        check(("reload(to:keepClock:)", "reload(to:keepClock:keepRun:)") in twins, "a shim beside a widened signature")
        check(len(d.deprecated) == 6, f"six newly deprecated lines, got {len(d.deprecated)}")
        check(bump(diffs, 1) == "minor", "1.x: a deprecation is a minor")
        check(bump(diffs, 0) == "minor", "0.x: still a minor")

        # No change at all is a patch, and a dropped shim is a major.
        diffs = diff_all(old_dir, old_dir)
        check(all(x.is_empty for x in diffs), "identical listings are empty")
        check(bump(diffs, 1) == "patch" and bump(diffs, 0) == "patch", "no change is a patch")
        after = os.path.join(work, "after")
        os.mkdir(after)
        with open(os.path.join(after, "Ollin.txt"), "w") as handle:
            handle.write(SHIMMED_FIXTURE.replace("  @available(deprecated) func gone()\n", ""))
        diffs = diff_all(shim_dir, after)
        check(diffs[0].violations == [] and diffs[0].removals == 1, "dropping a deprecated line is allowed by the rule")
        check(bump(diffs, 1) == "major", "and still costs a major")

        # The tree rule reads the sources.
        src = os.path.join(work, "Sources")
        os.makedirs(os.path.join(src, "Ollin", "3D"))
        with open(os.path.join(src, "Ollin", "3D", "CameraRig.swift"), "w") as handle:
            handle.write('    @available(*, deprecated, renamed: "isometric")\n    static var corner: CameraView { .isometric }\n')
        with open(os.path.join(src, "Ollin", "Deprecations.swift"), "w") as handle:
            handle.write('    @available(*, deprecated, renamed: "isometric")\n    @available(*, deprecated)\n')
        problems = source_violations(src)
        check(any("CameraRig.swift:1: a shim outside" in p for p in problems), f"a shim outside the file: {problems}")
        check(any("Deprecations.swift:2: a shim with no renamed" in p for p in problems), f"a shim without its fix-it: {problems}")
        check(len(problems) == 2, f"exactly two problems, got {problems}")

    if failures:
        for failure in failures:
            print(f"api-diff selftest: {failure}", file=sys.stderr)
        return 1
    print("api-diff selftest: every class of change lands where it should")
    return 0


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--old")
    parser.add_argument("--new")
    parser.add_argument("--from-label", default="")
    parser.add_argument("--to-label", default="tree")
    parser.add_argument("--from-version", default="0.0.0")
    parser.add_argument("--module")
    parser.add_argument("--sources")
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--warn", action="store_true")
    parser.add_argument("--changelog", action="store_true")
    parser.add_argument("--summary", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        sys.exit(selftest())
    if not (args.old and args.new):
        sys.exit("api-diff.py: --old and --new are required")

    diffs = diff_all(args.old, args.new, args.module)
    from_major = int(args.from_version.split(".")[0])
    mode = "strict" if (args.strict or (from_major >= 1 and not args.warn)) else "warn"
    violations = [e for d in diffs for e in d.violations]
    source_problems = source_violations(args.sources) if args.sources else []

    if args.changelog:
        changelog(diffs, args)
    elif not args.summary:
        report(diffs, args)
    if not args.changelog:
        summary(diffs, args, mode, violations, source_problems)
    failed = source_problems or (mode == "strict" and violations)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
