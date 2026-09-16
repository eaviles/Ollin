#!/bin/zsh
#
# Scripts/check-api-names.sh: hold the public surface to the settled naming
# rules.
#
#   Scripts/check-api-names.sh            # check API/*.txt, exit nonzero on any error
#   Scripts/check-api-names.sh --list     # also print every allowed hit
#   Scripts/check-api-names.sh <dir>      # check the listings in another directory
#
# The naming pass settled its rules in CLAUDE.md (Conventions, "The naming
# pass's settled rules"), and every rule there was applied by hand once. What
# nothing did afterwards was read new API against them: a `maximumHandCount`
# shipped a week after the min/max rule, a `seed: UInt64` on a sim written
# after the Int rule, an `extension:` label after `withExtension:` was the
# spelling, a `denoise: Bool` after configuration Booleans became third-person
# assertions. Each of those read fine in review, because a reviewer reads a
# change against its own file and not against a rule written in another one.
# This reads the listings under API/ (one line per public declaration, written
# by Scripts/api-surface.sh) against the rules, so a name outside them fails
# before it is recorded rather than surfacing in the last sweep before 1.0.
#
# The rules, each named for the allow-list:
#
#   limits       A limit is min…/max…, never minimum…/maximum….
#   magnitude    `intensity` is light emission; how much of an effect is
#                `amount`. `intensity` passes on a declaration whose type or
#                name says light (light, illumination, caustic, lumen, IES,
#                spectrum); anything else is listed with its reason.
#   factory      A method that creates a live resource is make…; create…,
#                new…, build… (outside a result builder) and alloc… are not.
#                A dot static on a value type stays bare (`Light.spot`), so a
#                `static func make…` on a struct or enum is flagged.
#   boolean      A scalar Bool property reads as a third-person assertion
#                (keepsHighlights, usesSceneGravity) or as state (is…, has…,
#                wants…, can…, needs…, did…). A bare adjective or an imperative
#                (`settled`, `denoise`) is neither; `should…`/`enable…`/
#                `disable…` are flagged as labels too, as is a label that is a
#                bare order (`invert:`, `flip:`, `mirror:`, `wrap:`, `clamp:`),
#                whose house spelling is the participle or the assertion. A
#                Bool collection keeps its adjective and is not read here.
#   time         Advancing by seconds is advance(by:), to a clock advance(to:);
#                running discrete steps is step(_:). advance() with no label,
#                step(by:), tick(), update(dt:), and any update… verb are the
#                drifts this catches (`update` says less than the call does).
#   resource     A resource loader labels the extension withExtension:, and
#                its `in:` bundle takes no default (a default resolves to the
#                framework's own bundle, not the caller's).
#   seed         A public seed: parameter is Int. A continuous shader-uniform
#                seed on Filter, Generator or Sim stays Double on purpose, and
#                a random number generator's own state word stays UInt64.
#   highlight    A highlight exponent is …Sharpness, never …Power, …Exponent,
#                shininess or glossiness.
#   hook         An input hook on Sketch is past tense (mousePressed), never
#                on… or a bare verb.
#   verb         Geometry-emitting Sketch methods are draw…, never a bare noun
#                (circle, rect, line).
#   stack        The state stack is pushState/popState/withState, never push,
#                pop, isolated, or the Processing pair.
#   knob         The word for a @Param is parameter; `knob` is reserved for
#                the drag handle and hardware, and does not appear here.
#   value        One value vocabulary across inputs: number/int/text/bool,
#                never string, double, float, integer, boolean.
#   destination  A destination a sketch names is a String path; a write/save
#                that takes only a URL is flagged (a URL overload beside the
#                String form is fine).
#   lifecycle    start() reports isRunning, open() reports isOpen, connect()
#                reports isConnected and is undone by disconnect(), publish
#                reports isPublishing; close() tears down a connection and
#                stop() stops something that runs.
#   draining     A poll-and-clear read is a plural noun (messages(), lines());
#                drain…/pending… are not.
#   listing      A listing that goes and asks the outside world is available…()
#                (availableDisplays(), availableSources()). A bare plural reads
#                as the draining accessor or as held state, so a no-argument
#                one returning an array is flagged.
#
# What it cannot see: a rule about meaning rather than spelling (`factor` only
# for a true multiplier, a domain verb for a run-to-completion call), which
# stays a review question. What it reads is only the public surface, so an
# internal name is out of scope by construction.
#
# Exceptions live in Scripts/check-api-names-allow.txt, one per line as
# `<rule> <Owner.member>` with a comment saying why, `*` for every member of
# an owner. An entry that no longer matches anything fails, so the list
# cannot go stale. A name that is Ollin's own drift is never listed: the
# source is renamed instead, pre-1.0 without a shim and named in the
# changelog. Under a second, so preflight runs it every time.

cd "$(dirname "$0")/.." || exit 1

list=0
dir=API
for arg in "$@"; do
    case "$arg" in
    --list) list=1 ;;
    --help | -h)
        sed -n '3,79p' "$0" | sed 's|^# \?||'
        exit 0
        ;;
    *) dir="$arg" ;;
    esac
done

python3 - "$list" "$dir" <<'PY'
import collections
import pathlib
import re
import sys

list_notes = sys.argv[1] == "1"
listing_dir = pathlib.Path(sys.argv[2])

DECL = re.compile(
    r"^(?P<indent>\s*)(?P<attrs>(?:@\w+(?:\([^)]*\))?\s+)*)"
    r"(?P<mods>(?:open |public |final |indirect |static |class |mutating |nonisolated |convenience |override |required |unowned |weak |lazy |optional |dynamic |unsafe |nonmutating |unowned\(unsafe\) )*)"
    r"(?:(?P<kind>func|case|init|subscript|var|let)[?!]?\s*(?P<name>[A-Za-z_][A-Za-z0-9_]*)?"
    r"|(?P<tkind>struct|class|enum|actor|protocol|extension)\s+(?P<tname>[A-Za-z_][A-Za-z0-9_.]*))"
)


def split_params(rest):
    """(label, type, has_default) for each parameter of a `(...)` list at the start of `rest`."""
    if not rest.startswith("("):
        return [], rest
    depth = 0
    end = 0
    for end, ch in enumerate(rest):
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                break
    out = []
    for param in re.split(r",(?![^\[(<]*[\])>])", rest[1:end]):
        param = param.strip()
        if not param:
            continue
        m = re.match(r"([A-Za-z_][A-Za-z0-9_]*|_)\s*:\s*(.*)$", param)
        if not m:
            out.append(("_", param, False))
            continue
        label, typ = m.group(1), m.group(2)
        has_default = "= default" in typ
        typ = typ.split("= default")[0].strip()
        out.append((label, typ, has_default))
    return out, rest[end + 1:]


class Decl:
    def __init__(self, file, line, text, owner, owner_line, kind, name, params, rest, mods, attrs):
        self.file, self.line, self.text = file, line, text
        self.owner, self.owner_line = owner, owner_line      # dotted path, and the owner's own listing line
        self.kind, self.name = kind, name
        self.params, self.rest = params, rest
        self.mods, self.attrs = mods, attrs

    @property
    def where(self):
        return f"{self.file}:{self.line}"

    @property
    def spelled(self):
        if self.kind in ("func", "init", "subscript", "case") and self.params is not None:
            return f"{self.name}({''.join(l + ':' for l, _, _ in self.params)})"
        return self.name

    @property
    def key(self):
        return f"{self.owner}.{self.name}" if self.owner else self.name

    @property
    def owner_short(self):
        return self.owner.split(".")[-1] if self.owner else ""

    @property
    def returns(self):
        return "->" in self.rest


decls = []
members = collections.defaultdict(list)          # owner path -> [Decl]
owner_kind = {}                                  # owner path -> struct/class/enum/...
owner_lines = {}

for listing in sorted(listing_dir.glob("*.txt")):
    stack = []                                   # [(indent, path, line text)]
    for n, line in enumerate(listing.read_text().split("\n"), 1):
        m = DECL.match(line)
        if not m or not line.strip():
            continue
        indent = len(m.group("indent"))
        while stack and stack[-1][0] >= indent:
            stack.pop()
        if m.group("tname"):
            short = m.group("tname").split(".")[-1].split("<")[0]
            kind = m.group("tkind")
            if kind == "extension":
                path = m.group("tname").split("<")[0]
            else:
                path = ".".join([p for _, p, _ in stack] + [short])
            owner_kind.setdefault(path, kind)
            owner_lines.setdefault(path, line.strip())
            stack.append((indent, path, line.strip()))
            continue
        kind, name = m.group("kind"), m.group("name")
        owner = stack[-1][1] if stack else ""
        owner_line = stack[-1][2] if stack else ""
        rest = line[m.end():].lstrip("?!").lstrip()
        params, tail = (None, rest)
        if kind in ("func", "init", "subscript", "case"):
            params, tail = split_params(rest)
            if kind == "case" and params == []:
                params = None
        if kind == "init":
            name = "init"
        if name is None:
            continue
        d = Decl(str(listing), n, line.strip(), owner, owner_line, kind, name, params, tail, m.group("mods"), m.group("attrs"))
        decls.append(d)
        members[owner].append(d)

# ------------------------------------------------------------- allow list
allow = {}                                        # (rule, key) -> reason
allow_used = set()
allow_file = pathlib.Path("Scripts/check-api-names-allow.txt")
if allow_file.exists():
    for raw in allow_file.read_text().split("\n"):
        line = raw.split("#")[0].strip()
        if not line:
            continue
        parts = line.split(None, 1)
        if len(parts) != 2:
            continue
        allow[(parts[0], parts[1].strip())] = raw.split("#", 1)[1].strip() if "#" in raw else ""


def allowed(rule, decl):
    """An entry `rule Owner.member`, `rule Owner.*`, or `rule member` for a top-level declaration."""
    candidates = []
    if decl.owner:
        parts = decl.owner.split(".")
        for i in range(len(parts)):
            suffix = ".".join(parts[i:])
            candidates += [f"{suffix}.{decl.name}", f"{suffix}.*"]
    else:
        candidates.append(decl.name)
    for key in candidates:
        if (rule, key) in allow:
            allow_used.add((rule, key))
            return True
    return False


errors, notes = [], []


def fail(rule, decl, message):
    if allowed(rule, decl):
        notes.append(f"{decl.where}: [{rule}, allowed] {decl.key}: {message}")
        return
    errors.append(f"{decl.where}: [{rule}] {decl.key}: {message}")


def words(name):
    """camelCase split, the first word lowercased."""
    parts = re.findall(r"[A-Z]?[a-z0-9]+|[A-Z]+(?![a-z])", name)
    return [parts[0].lower()] + parts[1:] if parts else [name]


# ---------------------------------------------------------------- rules
LIMIT = re.compile(r"(?:^|[^a-zA-Z])(?:minimum|maximum)[A-Z_]|^(?:minimum|maximum)$|[a-z](?:Minimum|Maximum)(?:[A-Z]|$)")
LIGHT = re.compile(r"light|illuminat|caustic|lumen|IES|spectr", re.I)
STATE_FIRST = {"is", "has", "have", "wants", "can", "needs", "did", "was", "were", "will", "must", "may", "does"}
COMPOUND = re.compile(r"[a-z0-9](?:Is|Are|Was|Were|Has|Have|Can|Does|Did|Will|Collide)(?:[A-Z]|$)")
BAD_BOOL_PREFIX = re.compile(r"^(?:should|enable|disable)(?:[A-Z]|$)")
HIGHLIGHT = re.compile(r"(?:specular|rim|sparkle|highlight|gloss|sheen|phong|fresnel)(?:Exponent|Power)|shininess|glossiness", re.I)
TIME_LABELS = {"dt", "deltaTime", "by", "seconds", "elapsed", "delta"}
NOUNS = {"circle", "rect", "ellipse", "line", "triangle", "quad", "arc", "polygon", "polyline", "square", "bezier", "curve", "star", "ngon", "shape", "point", "text", "image", "ring"}
STACK = {"push", "pop", "isolated", "pushMatrix", "popMatrix", "pushStyle", "popStyle", "resetMatrix"}
VALUE = {"string", "double", "float", "integer", "boolean"}
DESTINATION = re.compile(r"^(?:write|save|export|record|dump)")
# A Bool label is an adjective or a third-person assertion, never a bare order.
ORDERS = {"invert", "flip", "mirror", "wrap", "clamp", "reverse", "show", "hide",
          "enable", "disable", "toggle", "animate", "center", "repeat", "skip",
          "trim", "crop", "tile", "loop", "close", "open", "fill", "stroke"}
# A listing that goes and asks the outside world is available…(), never a bare
# plural, which reads as the draining accessor.
LISTINGS = {"apps", "displays", "windows", "devices", "servers", "sources",
            "destinations", "endpoints"}

for d in decls:
    labels = [l for l, _, _ in d.params] if d.params else []
    names = [d.name] + labels

    # limits
    for n in names:
        if LIMIT.search(n):
            fail("limits", d, f"`{n}` spells a limit with minimum/maximum; limits are min…/max…")
            break

    # magnitude
    for n in names:
        if n == "intensity" or n.endswith("Intensity"):
            if not (LIGHT.search(d.owner) or LIGHT.search(d.name) or LIGHT.search(d.owner_line)):
                fail("magnitude", d, f"`{n}` outside a light: intensity is light emission, how much of an effect is amount")
            break

    # factory
    if d.kind == "func":
        if re.match(r"^(?:create|new|alloc|construct)[A-Z]", d.name):
            fail("factory", d, f"`{d.name}` creates something; a resource-making method is make…")
        elif re.match(r"^build[A-Z]", d.name) and "@resultBuilder" not in d.owner_line:
            fail("factory", d, f"`{d.name}` creates something; a resource-making method is make…")
        elif re.match(r"^make[A-Z]", d.name) and "static" in d.mods and owner_kind.get(d.owner) in ("struct", "enum"):
            fail("factory", d, f"`{d.name}` is a dot static on a value type, which stays bare (`Light.spot`, not `Light.makeSpot`)")

    # boolean
    if d.kind in ("var", "let") and re.match(r"^Bool\??(?:\s|$)", d.rest.lstrip(": ").strip()):
        name = d.name
        first = words(name)[0]
        ok = (first in STATE_FIRST or (len(first) >= 3 and first.endswith("s")) or COMPOUND.search(name)
              or name == "bool")
        if BAD_BOOL_PREFIX.match(name) or not ok:
            fail("boolean", d, f"`{name}: Bool` reads as neither an assertion (keepsX, usesX) nor state (isX, hasX, wantsX)")
    if d.params:
        for label, typ, _ in d.params:
            if re.match(r"^Bool\??$", typ) and BAD_BOOL_PREFIX.match(label):
                fail("boolean", d, f"label `{label}: Bool` is a should/enable/disable spelling; a configuration Boolean is a third-person assertion")
                break
            if re.match(r"^Bool\??$", typ) and label in ORDERS:
                fail("boolean", d, f"label `{label}: Bool` is a bare order; a configuration Boolean is a participle ({label}ed) or an assertion ({label}s)")
                break

    # time
    if d.kind == "func" and d.params is not None:
        first = labels[0] if labels else None
        if d.name == "advance" and first not in ("by", "to", "toward"):
            fail("time", d, f"`{d.spelled}`: advancing by seconds is advance(by:), to a clock advance(to:); a discrete step is step(_:)")
        elif re.match(r"^update(?:[A-Z]|$)", d.name) and "Representable" not in d.owner_line:
            fail("time", d, f"`{d.spelled}`: `update` says less than the call does; a per-frame advance is advance(by:)/advance(to:) and a discrete run is step…")
        elif d.name == "step" and labels and first != "_":
            fail("time", d, f"`{d.spelled}`: running discrete steps is step(_:), never a labeled count")
        elif d.name == "tick":
            fail("time", d, f"`{d.spelled}`: advancing by seconds is advance(by:), a discrete step is step(_:)")
        elif d.name in ("update", "simulate", "integrate", "run") and first in TIME_LABELS:
            fail("time", d, f"`{d.spelled}`: advancing by seconds is advance(by:)")

    # resource
    if d.params and "resource" in labels:
        for label, typ, has_default in d.params:
            if label in ("extension", "ext", "fileExtension", "pathExtension", "ofType", "type"):
                fail("resource", d, f"label `{label}:` on a resource loader; the extension is withExtension:")
            if label == "in" and "Bundle" in typ and has_default:
                fail("resource", d, "`in:` on a resource loader takes a default, which resolves to a bundle that is not the caller's")

    # seed
    seed_types = []
    if d.params:
        seed_types += [typ for label, typ, _ in d.params if label == "seed"]
    if d.kind in ("var", "let") and d.name == "seed":
        seed_types.append(d.rest.lstrip(": ").split("{")[0].strip())
    for typ in seed_types:
        base = typ.rstrip("?")
        if base == "Int":
            continue
        if base == "Double" and d.owner_short in ("Filter", "Generator", "Sim", "Combine", "Shader"):
            continue
        if base == "UInt64" and "RandomNumberGenerator" in d.owner_line:
            continue
        fail("seed", d, f"`seed: {typ}`: a public seed takes Int (a continuous shader seed stays Double, a generator's state word UInt64)")
        break

    # highlight
    for n in names:
        if HIGHLIGHT.search(n):
            fail("highlight", d, f"`{n}`: a highlight exponent is …Sharpness")
            break

    if d.owner_short == "Sketch":
        # hook
        if d.kind == "func" and "open" in d.mods:
            if re.match(r"^on[A-Z]", d.name):
                fail("hook", d, f"`{d.name}`: an input hook is past tense (mousePressed), never on…")
            elif re.match(r"^(?:mouse|key|touch|scroll|drag|click)", d.name) and not d.name.endswith("ed"):
                fail("hook", d, f"`{d.name}`: an input hook is past tense (mousePressed, mouseScrolled)")
        # verb
        if d.kind == "func" and d.name in NOUNS and not d.returns:
            fail("verb", d, f"`{d.name}` emits geometry under a noun; draw verbs carry the draw prefix (draw{d.name[0].upper()}{d.name[1:]})")
        # stack
        if d.kind == "func" and d.name in STACK:
            fail("stack", d, f"`{d.name}`: the state stack is pushState/popState, scoped as withState {{ }}")

    # knob
    for n in names + [d.owner_short]:
        if "knob" in n.lower():
            fail("knob", d, f"`{n}`: the word is parameter; knob is the drag handle or the hardware")
            break

    # value
    if d.kind in ("func", "var") and d.name in VALUE:
        fail("value", d, f"`{d.name}`: the value vocabulary is number / int / text / bool")

    # destination
    if d.kind == "func" and DESTINATION.match(d.name) and d.params:
        for label, typ, _ in d.params:
            if label in ("to", "at", "into") and typ.endswith("URL"):
                sibling = any(
                    o is not d and o.kind == "func" and o.name == d.name and o.params
                    and any(l == label and t == "String" for l, t, _ in o.params)
                    for o in members[d.owner])
                if not sibling:
                    fail("destination", d, f"`{d.spelled}` takes only a URL; a destination a sketch names is a String path")
                break

    # draining
    if d.kind == "func" and re.match(r"^(?:drain|pending)[A-Z]", d.name):
        fail("draining", d, f"`{d.name}`: a poll-and-clear read is a plural noun (messages(), lines())")

    # listing. Only a no-argument read of an array: `endpoints(of:)` answers about
    # something handed to it, and a setting that happens to be plural is not a list.
    if d.name in LISTINGS and not d.params and "[" in d.rest:
        fail("listing", d, f"`{d.name}`: a listing that asks the system is available{d.name[0].upper()}{d.name[1:]}(); a bare plural is held state or a drain")

# lifecycle, per type
for owner, ms in members.items():
    if not owner:
        continue
    funcs = {m.name for m in ms if m.kind == "func"}
    props = {m.name for m in ms if m.kind in ("var", "let")}
    verbs = {v for v in ("start", "open", "connect", "publish") if v in funcs or any(f.startswith(v) for f in funcs if v == "publish")}
    for m in ms:
        if m.kind in ("var", "let") and m.name in ("isStarted", "isOpened", "isStopped"):
            fail("lifecycle", m, f"`{m.name}`: start() reports isRunning, open() reports isOpen, connect() reports isConnected")
        if m.kind in ("var", "let") and m.name in ("isActive", "isOn", "isLive") and verbs:
            wanted = {"start": "isRunning", "open": "isOpen", "connect": "isConnected", "publish": "isPublishing"}
            fail("lifecycle", m, f"`{m.name}` beside {', '.join(sorted(verbs))}(): the state follows the verb ({', '.join(wanted[v] for v in sorted(verbs))})")
        if m.kind == "func" and m.name in ("close", "end", "halt", "shutdown") and "start" in funcs and "open" not in funcs and "connect" not in funcs:
            fail("lifecycle", m, f"`{m.name}()` beside start(): something that runs is stopped by stop()")
        if m.kind == "func" and m.name == "stop" and "connect" in funcs and "disconnect" not in funcs and "start" not in funcs:
            fail("lifecycle", m, "`stop()` beside connect(): a connection is undone by disconnect()")
        if m.kind == "func" and m.name == "stop" and "open" in funcs and "close" not in funcs and "start" not in funcs:
            fail("lifecycle", m, "`stop()` beside open(): a port is closed by close()")

# an allow line that matches nothing is stale
for (rule, key), _ in allow.items():
    if (rule, key) not in allow_used:
        errors.append(f"Scripts/check-api-names-allow.txt: `{rule} {key}` matches nothing under {listing_dir}/; drop it")

errors.sort()
for e in errors:
    print(e)
if list_notes:
    for n in sorted(notes):
        print(n)
print(f"check-api-names: {len(decls)} public declarations read, {len(notes)} allowed by the list, {len(errors)} problem(s)")
if errors:
    print("check-api-names: rename the source (pre-1.0, no shim; name it in CHANGELOG.md), re-record with")
    print("    Scripts/api-surface.sh --record, or list the exception with its reason in Scripts/check-api-names-allow.txt")
sys.exit(1 if errors else 0)
PY
