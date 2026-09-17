#!/bin/zsh
#
# Scripts/check-api-pages.sh: check that every public name has a page.
#
#   Scripts/check-api-pages.sh             # check, exit nonzero on any gap
#   Scripts/check-api-pages.sh --list      # also print every exempt and allowed name
#   Scripts/check-api-pages.sh --owner X   # print the gaps under one type, and stop
#
# Scripts/check-names.sh reads the prose and asks whether every name in it is
# real. This reads the other direction: it takes the public surface written
# down under API/ and asks whether every name in it is written down anywhere
# in the reference. Nothing did that before, and nothing could: every other
# gate starts from the pages. check-links walks the navigation, check-snippets
# compiles the fences, guide-coverage counts the matrix rows, check-names
# reads a backtick back to the tree, api-docs builds the generated reference
# from the doc comments. A public name no page mentions is invisible to all of
# them, which is how `Mesh.klein`, `Material.rimSharpness` and
# `Sketch.previousMouse` shipped with nothing written about them anywhere.
# This is the gate for 1.0's promise that the reference is complete.
#
# What it reads: every declaration under API/*.txt, one line per public
# declaration, written by Scripts/api-surface.sh. What it reads against: the
# code in every page under Docs/ - its code spans, its fenced blocks, its
# headings, and a one-word bold run, which is how a page of settings names its
# fields (`- **roughness** runs from 0 to 1`). Those are the places a page
# spells a name rather than describing it.
#
# What counts as named:
#
#   A type      its name in some page's code. A nested type also counts when
#               the page that spells the outer one spells the inner one, or
#               when the reference names something under it: a page writes
#               `channel: .magnitude` and never spells FourierChannel, which
#               is the reference doing its job rather than a gap.
#   An init     the type written as a call (`Vector2(x:y:)`, and a generic
#               one still names its type), or `init(` on a page that names it.
#   A member    `.name` or `name(` anywhere in the reference, or the bare name
#               on a page that also names its owner, or any of that owner's
#               own owners (a page spells `Light`, not `Light.Kind`). The
#               first two forms let a
#               Sketch method be documented on the page for its subject
#               (`drawTruchet` lives on the Generators page, which has no
#               reason to spell `Sketch`); the third lets a property be named
#               in prose beside its owner. A member of Sketch itself is looked
#               up bare wherever it appears, because that is how it is called:
#               `keyIsPressed` is documented on the Input page, which has no
#               reason to spell Sketch either.
#
# A type with no page swallows its members: the gap is the page, reported once,
# not one line for each of the forty-five members underneath it. A type allowed
# bare swallows them the same way.
#
# Exempt by construction, each class named for the allow list:
#
#   conformance   a member a declared conformance requires (== under Equatable,
#                 description under CustomStringConvertible, rawValue under
#                 RawRepresentable, allCases under CaseIterable, and the rest).
#                 The page documents the type, not the protocol's own names.
#                 Ollin's own public protocols count here too, read from the
#                 listing: `Vector` is documented once, and every conformer's
#                 copy of `component(_:)` is that same name. A protocol no page
#                 names is reported as the type it is, so nothing hides behind
#                 an undocumented one.
#   operator      an operator has no identifier to write in prose; a page says
#                 that vectors add, and cannot spell `+` without spelling
#                 every use of it.
#   subscript     written `thing[i]` at the call, never by its own name, and
#                 callAsFunction the same: a page writes `profile(0.5)`.
#   associated    a typealias or associated type a conformance fixes (Element,
#                 Iterator, RawValue, ArrayLiteralElement).
#   wrapper       wrappedValue and projectedValue on a @propertyWrapper: the
#                 page documents @Param, not the wrapper's plumbing.
#   builder       buildBlock and the rest on a @resultBuilder, which the
#                 compiler calls and nobody writes.
#   override      an @objc override of a platform superclass method, whose
#                 name is AppKit's rather than ours.
#   factory       an initializer of a type the reference hands over another
#                 way: a `makeSwarm(count:)` on Sketch, a `Light.spot(…)`, a
#                 `Mesh.sphere(…)`, or a documented property that already holds
#                 one (`scan.settings`). The page documents the call a sketch
#                 writes, and the type itself is checked either way.
#   deprecated    a shim, which its page replaced by naming the successor.
#
# Anything else deliberately bare is listed in Scripts/check-api-pages-allow.txt
# with its reason, one entry per line as `<class> <what>`, where what is a
# dotted API path (`Owner.member`, `Owner.*` for all of them, `Phone*Sample`
# and other globs), or a source file, in which case every public type declared
# in that file is covered. The file form is the honest one for a whole tier
# that is public for another module rather than for a sketch: a wire protocol
# both sides encode, the host apps' own inspector model. An entry that matches
# nothing fails, so the list cannot outlive what it excuses. A name missing
# because the reference is a page short is never listed: the page is written.
#
# What it cannot see: whether the mention teaches anything. A name that
# appears once inside a fence is named and the gate is satisfied; whether the
# page explains it is a review question, and the Guide's coverage matrix is
# where a capability's teaching is tracked. It also cannot tell two owners'
# members apart when they share a spelling, so a documented `reset()` on one
# type covers an undocumented one on another.
#
# A couple of seconds, so preflight runs it every time: a page deleted or a
# public name recorded stales this whether or not the diff touched either.

cd "$(dirname "$0")/.." || exit 1

list=0
owner=""
want_owner=0
for arg in "$@"; do
    if [[ $want_owner -eq 1 ]]; then
        owner="$arg"
        want_owner=0
        continue
    fi
    case "$arg" in
    --list) list=1 ;;
    --owner) want_owner=1 ;;
    --owner=*) owner="${arg#--owner=}" ;;
    --help | -h)
        sed -n '3,102p' "$0" | sed 's|^# \{0,1\}||'
        exit 0
        ;;
    esac
done

python3 - "$list" "$owner" <<'PY'
import collections
import fnmatch
import pathlib
import re
import sys

list_all = sys.argv[1] == "1"
only_owner = sys.argv[2]

DECL = re.compile(
    r"^(?P<indent>\s*)(?P<attrs>(?:@\w+(?:\([^)]*\))?\s+)*)"
    r"(?P<mods>(?:open |public |final |indirect |static |class |mutating |nonisolated |convenience |override |required |unowned |weak |lazy |optional |dynamic |unsafe |nonmutating |unowned\(unsafe\) )*)"
    r"(?:(?P<kind>func|case|init|subscript|var|let|typealias|associatedtype)[?!]?\s*(?P<name>[A-Za-z_][A-Za-z0-9_]*)?"
    r"|(?P<tkind>struct|class|enum|actor|protocol|extension)\s+(?P<tname>[A-Za-z_][A-Za-z0-9_.]*))"
)
SOURCE_DECL = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:public\s+|open\s+|package\s+|final\s+|indirect\s+|nonisolated\s+)*"
    r"(?:struct|class|enum|actor|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)"
)
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
SPAN = re.compile(r"`([^`\n]+)`")
BOLD = re.compile(r"\*\*([A-Za-z_][A-Za-z0-9_]*)\*\*")   # a settings list names its fields in bold

# A conformance and the members it fixes. The page documents the type; the
# protocol's own names belong to the standard library's reference, not ours.
CONFORMANCE = {
    "Equatable": {"=="},
    "Hashable": {"hash", "hashValue", "=="},
    "Comparable": {"<", "<=", ">", ">="},
    "CustomStringConvertible": {"description"},
    "CustomDebugStringConvertible": {"debugDescription"},
    "Identifiable": {"id", "ID"},
    "RawRepresentable": {"rawValue", "init", "RawValue"},
    "CaseIterable": {"allCases", "AllCases"},
    "Codable": {"init", "encode", "CodingKeys"},
    "Decodable": {"init", "CodingKeys"},
    "Encodable": {"encode", "CodingKeys"},
    "OptionSet": {"rawValue", "init", "RawValue", "Element", "ArrayLiteralElement"},
    "Sequence": {"makeIterator", "next", "Iterator", "Element", "underestimatedCount"},
    "IteratorProtocol": {"next", "Element"},
    "Collection": {"startIndex", "endIndex", "index", "Index", "Indices", "Element", "SubSequence", "count", "isEmpty"},
    "BidirectionalCollection": {"index", "Index", "Indices", "Element", "SubSequence"},
    "RandomAccessCollection": {"index", "Index", "Indices", "Element", "SubSequence"},
    "AdditiveArithmetic": {"zero"},
    "ExpressibleByArrayLiteral": {"init", "ArrayLiteralElement"},
    "ExpressibleByStringLiteral": {"init", "StringLiteralType", "ExtendedGraphemeClusterLiteralType", "UnicodeScalarLiteralType"},
    "ExpressibleByIntegerLiteral": {"init", "IntegerLiteralType"},
    "ExpressibleByFloatLiteral": {"init", "FloatLiteralType"},
    "ExpressibleByDictionaryLiteral": {"init", "Key", "Value"},
    "LocalizedError": {"errorDescription", "failureReason", "recoverySuggestion", "helpAnchor"},
    "RandomNumberGenerator": {"next"},
    "Strideable": {"advanced", "distance", "Stride"},
    "Numeric": {"init", "magnitude", "Magnitude"},
}
CONFORMANCE_TYPEALIAS = {
    "Element", "Iterator", "Index", "Indices", "SubSequence", "RawValue", "AllCases",
    "ArrayLiteralElement", "ID", "Stride", "Magnitude", "Body", "CodingKeys",
    "StringLiteralType", "IntegerLiteralType", "FloatLiteralType",
    "ExtendedGraphemeClusterLiteralType", "UnicodeScalarLiteralType", "Key", "Value",
}

errors, exempted, allowed_hits = [], [], []

# ------------------------------------------------------------------ surface
decls = []
types = {}                                       # dotted path -> the type's decl
for listing in sorted(pathlib.Path("API").glob("*.txt")):
    stack = []                                   # [(indent, path)]
    for n, line in enumerate(listing.read_text().split("\n"), 1):
        if not line.strip() or line.lstrip().startswith("//"):
            continue
        m = DECL.match(line)
        if not m:
            continue
        indent = len(m.group("indent"))
        while stack and stack[-1][0] >= indent:
            stack.pop()
        owner = stack[-1][1] if stack else ""
        if m.group("tname"):
            kind = m.group("tkind")
            if kind == "extension":
                stack.append((indent, m.group("tname").split("<")[0]))
                continue                         # an extension is a place, not a name
            short_name = m.group("tname").split(".")[-1].split("<")[0]
            path = f"{owner}.{short_name}" if owner else short_name
            head = line.split(" -> ")[0]
            conf = {c.strip().split("<")[0].split(".")[-1] for c in head.split(":", 1)[1].split(",")} if ":" in head else set()
            d = dict(file=listing.name, line=n, owner=owner, path=path, kind=kind, name=short_name,
                     is_type=True, text=line.strip(), conf=conf,
                     attrs=m.group("attrs") or "", mods=m.group("mods") or "")
            decls.append(d)
            types[path] = d
            stack.append((indent, path))
        else:
            kind = m.group("kind")
            name = m.group("name")
            if name is None and kind in ("init", "subscript"):
                name = kind                      # `init?(…)` carries its keyword as its name
            decls.append(dict(file=listing.name, line=n, owner=owner, kind=kind, name=name, is_type=False,
                              path=f"{owner}.{name}" if name else f"{owner}.(operator)",
                              text=line.strip(), conf=set(),
                              attrs=m.group("attrs") or "", mods=m.group("mods") or ""))

returns = collections.defaultdict(list)           # type name -> the declarations that hand one back
own = collections.defaultdict(list)               # type path -> its own members
for d in decls:
    if not d["is_type"] and d["owner"]:
        own[d["owner"]].append(d)
    if not d["is_type"] and d["kind"] != "init":
        text = d["text"].replace("{ get set }", "").replace("{ get }", "").strip()
        if " -> " in text:
            handed = text.rsplit(" -> ", 1)[1]
        elif d["kind"] in ("var", "let") and ": " in text:
            handed = text.split(" = ")[0].rsplit(": ", 1)[1]
        else:
            continue
        handed = handed.strip().rstrip("?").split(".")[-1]
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", handed):
            returns[handed].append(d)

# Ollin's own protocols count as conformances too: the page documents `Vector`
# once, and every conformer's copy of `component(_:)` is that same name.
for path, d in types.items():
    if d["kind"] == "protocol":
        CONFORMANCE.setdefault(d["name"], set()).update(
            m["name"] for m in own.get(path, []) if m["name"])

# ------------------------------------------------------------------- oracle
pages = {}
for page in sorted(pathlib.Path("Docs").rglob("*.md")):
    code, fenced = [], False
    for line in page.read_text(errors="ignore").split("\n"):
        if line.startswith("```"):
            fenced = not fenced
            continue
        if fenced:
            code.append(line)
        else:
            code.extend(SPAN.findall(line))
            code.extend(BOLD.findall(line))
            if line.startswith("#"):
                code.append(line.lstrip("#"))
    pages[str(page)] = "\n".join(code)

page_idents = {p: set(IDENT.findall(c)) for p, c in pages.items()}
whole = "\n".join(pages.values())
dotted = set(re.findall(r"\.([A-Za-z_][A-Za-z0-9_]*)", whole))
called = set(re.findall(r"([A-Za-z_][A-Za-z0-9_]*)(?:<[^<>\n]*>)?\s*\(", whole))   # a generic call still names its type
qualified = set(re.findall(r"([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)", whole))
everywhere = set(IDENT.findall(whole))

# Where each public type is declared, for the allow list's file form.
declared_in = collections.defaultdict(set)
for source in pathlib.Path("Sources").rglob("*.swift"):
    path = str(source)
    for line in source.read_text(errors="ignore").split("\n"):
        m = SOURCE_DECL.match(line)
        if m:
            declared_in[m.group(1)].add(path)


def short(path):
    return path.split(".")[-1] if path else ""


def on_a_page_with(name, owner_path):
    """`name` in some page's code, on a page that also spells the owner or one of its ancestors."""
    owners = [part for part in owner_path.split(".") if part]
    for ids in page_idents.values():
        if name in ids and (not owners or any(o in ids for o in owners)):
            return True
    return False


def exempt(d):
    owner = types.get(d["owner"])
    if d["kind"] == "subscript":
        return "subscript"
    if d["name"] is None:
        return "operator"                        # `static func ==`, `static func *`
    if d["name"] == "callAsFunction":
        return "callable"                        # written `profile(0.5)`, never by its name
    if d["name"].startswith("build") and owner and "@resultBuilder" in owner["attrs"]:
        return "builder"                         # buildBlock and the rest: the compiler calls them
    if "deprecated" in d["text"]:
        return "deprecated"
    if "@objc" in d["attrs"] and "override" in d["mods"]:
        return "override"
    if d["name"] in ("wrappedValue", "projectedValue") and owner and "@propertyWrapper" in owner["attrs"]:
        return "wrapper"
    if d["kind"] in ("typealias", "associatedtype") and d["name"] in CONFORMANCE_TYPEALIAS:
        return "associated"
    if d["kind"] == "init" and owner:
        for f in returns.get(owner["name"], ()):
            if f["owner"] != d["owner"] and member_named(f):
                return "factory"                 # the reference documents the call that hands one over
    if owner:
        for c in owner["conf"]:
            if c in CONFORMANCE and d["name"] in CONFORMANCE[c]:
                return f"conformance ({c})"
    return None


def member_named(d):
    owner_name = short(d["owner"])
    if d["kind"] == "init":
        return owner_name in called or on_a_page_with("init", d["owner"])
    if owner_name == "Sketch":
        return d["name"] in everywhere    # the bare API is written with no receiver, which is how it is called
    return d["name"] in dotted or d["name"] in called or on_a_page_with(d["name"], d["owner"])


# ---------------------------------------------------------------- allow list
allow = []                                        # [class, pattern, used]
allow_path = pathlib.Path("Scripts/check-api-pages-allow.txt")
for n, line in enumerate(allow_path.read_text().split("\n"), 1) if allow_path.exists() else []:
    body = line.split("#")[0].strip()
    if not body:
        continue
    parts = body.split()
    if len(parts) != 2:
        errors.append(f"Scripts/check-api-pages-allow.txt:{n}: expected `<class> <what>`, got `{body}`")
        continue
    allow.append([parts[0], parts[1], False])


def allowed(path):
    """The class of the entry covering this dotted path, by name, glob, or declaring file."""
    top = path.split(".")[0]
    for entry in allow:
        cls, pattern = entry[0], entry[1]
        if pattern.endswith(".swift"):
            hit = pattern in declared_in.get(top, ())
        elif pattern.endswith(".*"):
            hit = path == pattern[:-2] or path.startswith(pattern[:-1])
        else:
            hit = fnmatch.fnmatchcase(path, pattern)
        if hit:
            entry[2] = True
            return cls
    return None


# --------------------------------------------------------------------- types
bare_types = set()                                # no page, or allowed bare: both swallow their members
for d in sorted([d for d in decls if d["is_type"]], key=lambda d: (d["file"], d["line"])):
    cls = allowed(d["path"])
    if cls:
        bare_types.add(d["path"])
        allowed_hits.append(f"{d['file']}:{d['line']}  {cls}  {d['path']}")
        continue
    outer = short(d["owner"])
    if outer:
        named = on_a_page_with(d["name"], d["owner"]) or (outer, d["name"]) in qualified
    else:
        named = d["name"] in everywhere
    if not named:
        named = any(member_named(m) for m in own.get(d["path"], []) if not exempt(m))
    if not named:
        bare_types.add(d["path"])
        errors.append(f"{d['file']}:{d['line']}  {d['path']}  no page names this type or anything under it")

# ------------------------------------------------------------------- members
for d in sorted([d for d in decls if not d["is_type"]], key=lambda d: (d["file"], d["line"])):
    if not d["owner"]:
        continue
    if d["owner"] in bare_types or any(d["owner"].startswith(t + ".") for t in bare_types):
        continue                                  # the type is the gap, reported once
    cls = exempt(d)
    if cls:
        exempted.append(f"{d['file']}:{d['line']}  {cls}  {d['path']}")
        continue
    cls = allowed(d["path"])
    if cls:
        allowed_hits.append(f"{d['file']}:{d['line']}  {cls}  {d['path']}")
        continue
    if not member_named(d):
        errors.append(f"{d['file']}:{d['line']}  {d['path']}  no page names this {d['kind']}")

# --------------------------------------------------------------------- stale
for cls, pattern, used in allow:
    if not used:
        errors.append(f"Scripts/check-api-pages-allow.txt: `{cls} {pattern}` matches nothing under API/")

# -------------------------------------------------------------------- report
if only_owner:
    for e in errors:
        name = e.split("  ")[1] if "  " in e else ""
        if name == only_owner or name.startswith(only_owner + "."):
            print(e)
    sys.exit(0)

if list_all:
    for line in exempted:
        print(f"exempt   {line}")
    for line in allowed_hits:
        print(f"allowed  {line}")

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    by_owner = collections.Counter()
    for e in errors:
        parts = e.split("  ")
        if len(parts) > 1 and "." in parts[1]:
            by_owner[parts[1].rsplit(".", 1)[0]] += 1
    print(f"\ncheck-api-pages: {len(errors)} public names have no page", file=sys.stderr)
    for k, v in by_owner.most_common(20):
        print(f"    {v:4d}  {k}", file=sys.stderr)
    sys.exit(1)

print(f"check-api-pages: every public name has a page "
      f"({len(decls)} declarations, {len(exempted)} exempt by construction, {len(allowed_hits)} allowed)")
PY
