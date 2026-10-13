#!/usr/bin/env python3
"""Stage 2: add `LiveActivityKit.start()` to the app's launch code. Prints the diff.

    python3 insert_start_line.py <launch file.swift> [--firebase-configured] [--dry-run]

SwiftUI: adds it to the `App` struct's `init()` (creating `init()` if there is none).
UIKit:   adds it at the top of `application(_:didFinishLaunchingWithOptions:)`.
Adds `FirebaseApp.configure()` too, unless `--firebase-configured` says the app already does it.
Safe to run again: does nothing if `LiveActivityKit.start()` is already there.
"""
import difflib
import re
import sys

args = [a for a in sys.argv[1:] if not a.startswith("--")]
if not args:
    sys.exit(__doc__)
path = args[0]
dry_run = "--dry-run" in sys.argv
firebase_configured = "--firebase-configured" in sys.argv

source = open(path, encoding="utf-8").read()
if "LiveActivityKit.start(" in source:
    print(f"Nothing to do: {path} already starts LiveActivityKit.")
    sys.exit(0)

lines_to_add = ([] if firebase_configured or "FirebaseApp.configure()" in source else ["FirebaseApp.configure()"]) + [
    "LiveActivityKit.start()"
]


def indent_of(line: str) -> str:
    return line[: len(line) - len(line.lstrip())]


def add_imports(text: str) -> str:
    needed = ["LiveActivityKit"] + (["FirebaseCore"] if "FirebaseApp.configure()" in lines_to_add else [])
    for module in needed:
        if re.search(rf"^import {module}\b", text, re.M):
            continue
        imports = list(re.finditer(r"^import \w+.*$", text, re.M))
        at = imports[-1].end() if imports else 0
        text = text[:at] + ("\n" if imports else "") + f"import {module}" + ("" if imports else "\n") + text[at:]
    return text


def insert_in_body(text: str, body_start: int, indent: str) -> str:
    """Insert the lines at the start of a function body, or right after the app's own
    FirebaseApp.configure() if the body has one (the kit must start after Firebase is configured)."""
    configure = re.compile(r"^[ \t]*FirebaseApp\.configure\([^\n]*$", re.M).search(text, body_start)
    body_end = text.find("\n" + indent[:-4] + "}", body_start)
    at = configure.end() if configure and (body_end == -1 or configure.start() < body_end) else body_start
    return text[:at] + "".join(f"\n{indent}{l}" for l in lines_to_add) + text[at:]


updated = None
swiftui = re.search(r"@main\s*\n?\s*struct\s+\w+\s*:\s*App\s*\{", source)
uikit = re.search(r"didFinishLaunchingWithOptions[^{]*\{", source)

if swiftui:
    struct_end = swiftui.end()
    init = re.compile(r"\binit\s*\(\s*\)\s*\{").search(source, struct_end)
    if init:
        line_start = source.rfind("\n", 0, init.start()) + 1
        body_indent = indent_of(source[line_start:init.start()]) + "    "
        updated = insert_in_body(source, init.end(), body_indent)
    else:
        body_indent = "    "
        block = "\n" + f"{body_indent}init() {{\n" + "".join(f"{body_indent}    {l}\n" for l in lines_to_add) + f"{body_indent}}}\n"
        updated = source[:struct_end] + block + source[struct_end:]
elif uikit:
    line_start = source.rfind("\n", 0, uikit.start()) + 1
    body_indent = indent_of(source[line_start:uikit.start()]) + "    "
    updated = insert_in_body(source, uikit.end(), body_indent)
else:
    sys.exit(f"Couldn't find a SwiftUI `@main ... : App` or UIKit didFinishLaunching in {path}. Add the line by hand.")

updated = add_imports(updated)
diff = difflib.unified_diff(source.splitlines(), updated.splitlines(), path, path, lineterm="", n=2)
print("\n".join(diff))
if dry_run:
    print("\nDry run: nothing written.")
else:
    open(path, "w", encoding="utf-8").write(updated)
    print(f"\nUpdated {path}.")
