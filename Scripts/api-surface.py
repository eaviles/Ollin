#!/usr/bin/env python3
"""Flatten a swift-api-digester dump into one line per public declaration.

Called by Scripts/api-surface.sh; not meant to be run by hand. Reads the JSON
`-dump-sdk` writes for one module and prints the listing that lives under
API/<Module>.txt: types with their conformances, then every public member
with its modifiers, labels, types, defaults, and deprecation, nested as the
source nests them and sorted within each level, so a declaration that moves
between files or extensions leaves the listing untouched and only a change
to the surface shows up in a diff.
"""
import json
import re
import sys

DROPPED_CONFORMANCES = {"Copyable", "Escapable", "SendableMetatype"}
CORE = "Ollin"


def main() -> None:
    path, module = sys.argv[1], sys.argv[2]
    with open(path) as handle:
        root = json.load(handle)["ABIRoot"]
    strip = [r"\bSwift\.", rf"\b{re.escape(module)}\."]
    if module != CORE:
        strip.append(rf"\b{CORE}\.")

    def plain(text: str) -> str:
        for pattern in strip:
            text = re.sub(pattern, "", text)
        return text

    lines = [
        f"// {module}: the public surface, written by Scripts/api-surface.sh.",
        "// Change the source, then run it with --record; never edit this file by hand.",
    ]
    lines.extend(render(root, plain, depth=0, parent_open=True))
    print("\n".join(lines))


def visible(node: dict) -> bool:
    if "declKind" not in node:
        return False
    if node.get("implicit") or node.get("isInternal"):
        return False
    if node["declKind"] in ("Import", "Accessor"):
        return False
    return True


def render(container: dict, plain, depth: int, parent_open: bool) -> list:
    """The sorted lines for every visible child of `container`, recursively."""
    blocks = []
    for node in container.get("children") or []:
        if not visible(node):
            continue
        head = line(node, plain, parent_open)
        block = ["  " * depth + head]
        if node["declKind"] in ("Struct", "Class", "Enum", "Protocol"):
            block.extend(render(node, plain, depth + 1, bool(node.get("isOpen"))))
        blocks.append(block)
    blocks.sort(key=lambda block: block[0])
    return [text for block in blocks for text in block]


def line(node: dict, plain, parent_open: bool) -> str:
    kind = node["declKind"]
    attrs = set(node.get("declAttributes") or [])
    children = node.get("children") or []
    words = []
    if node.get("deprecated"):
        words.append("@available(deprecated)")
    for attr, spelled in (
        ("DiscardableResult", "@discardableResult"),
        ("PropertyWrapper", "@propertyWrapper"),
        ("ResultBuilder", "@resultBuilder"),
        ("DynamicMemberLookup", "@dynamicMemberLookup"),
        ("ObjC", "@objc"),
    ):
        if attr in attrs:
            words.append(spelled)
    if "Frozen" in attrs and not node.get("isExternal"):
        words.append("@frozen")
    if node.get("isOpen"):
        words.append("open")
    if "Final" in attrs and (kind == "Class" or parent_open):
        words.append("final")
    if "Nonisolated" in attrs:
        words.append("nonisolated")
    if "Override" in attrs:
        words.append("override")
    if "Required" in attrs:
        words.append("required")
    if node.get("static"):
        words.append("static")
    if node.get("funcSelfKind") == "Mutating":
        words.append("mutating")
    if "Prefix" in attrs:
        words.append("prefix")
    if "Postfix" in attrs:
        words.append("postfix")
    if node.get("init_kind") == "Convenience":
        words.append("convenience")

    name = node["name"]
    if kind in ("Struct", "Class", "Enum", "Protocol"):
        if node.get("isExternal"):
            owner = node.get("moduleName", "")
            shown = name if owner == "Swift" else f"{owner}.{name}"
            return " ".join(words + ["extension", shown])
        head = name + plain(node.get("genericSig") or "") if kind != "Protocol" else name
        inherits = []
        if kind == "Enum" and node.get("enumRawTypeName"):
            inherits.append(plain(node["enumRawTypeName"]))
        if kind == "Class" and node.get("superclassNames"):
            inherits.append(plain(node["superclassNames"][0]))
        inherits.extend(
            plain(c["printedName"]) for c in node.get("conformances") or []
            if c.get("name") not in DROPPED_CONFORMANCES
        )
        text = " ".join(words + [kind.lower(), head])
        if inherits:
            text += ": " + ", ".join(inherits)
        if kind == "Protocol" and node.get("genericSig"):
            text += " where " + plain(node["genericSig"]).strip("<>")
        return text

    if kind == "EnumElement":
        payload = ""
        if children and children[0].get("kind") == "TypeFunc":
            inner = children[0].get("children") or []
            if inner and inner[0].get("kind") == "TypeFunc":
                params = (inner[0].get("children") or [])[1:]
                if params:
                    shown = plain(params[0]["printedName"])
                    payload = shown if params[0].get("name") == "Tuple" else f"({shown})"
        return " ".join(words + ["case", name + payload])

    if kind == "Var":
        declared = plain(children[0]["printedName"]) if children else "?"
        if node.get("isLet"):
            return " ".join(words + ["let", f"{name}: {declared}"])
        accessors = {a.get("accessorKind") for a in node.get("accessors") or []}
        settable = "set" in accessors and "SetterAccess" not in attrs
        access = "{ get set }" if settable else "{ get }"
        return " ".join(words + ["var", f"{name}: {declared}", access])

    if kind in ("Func", "Constructor", "Subscript"):
        labels = re.search(r"\((.*)\)", node["printedName"])
        labels = [l for l in labels.group(1).split(":") if l] if labels else []
        params = []
        for index, child in enumerate(children[1:]):
            label = labels[index] if index < len(labels) else "_"
            text = f"{label}: {plain(child['printedName'])}"
            if child.get("hasDefaultArg"):
                text += " = default"
            params.append(text)
        returned = plain(children[0]["printedName"]) if children else "()"
        suffix = " throws" if node.get("throwing") else ""
        if node.get("isAsync"):
            suffix = " async" + suffix
        if kind == "Constructor":
            failable = "?" if returned.endswith("?") else ""
            return " ".join(words + [f"init{failable}({', '.join(params)}){suffix}"])
        if kind == "Subscript":
            accessors = {a.get("accessorKind") for a in node.get("accessors") or []}
            access = "{ get set }" if "set" in accessors else "{ get }"
            return " ".join(words + [f"subscript({', '.join(params)}) -> {returned} {access}"])
        signature = f"{name}({', '.join(params)}){suffix}"
        if returned not in ("()", "Void"):
            signature += f" -> {returned}"
        return " ".join(words + ["func", signature])

    if kind == "TypeAlias":
        target = plain(children[0]["printedName"]) if children else "?"
        return " ".join(words + ["typealias", f"{name} = {target}"])
    if kind == "AssociatedType":
        return " ".join(words + ["associatedtype", name])
    return " ".join(words + [kind.lower(), node["printedName"]])


if __name__ == "__main__":
    main()
