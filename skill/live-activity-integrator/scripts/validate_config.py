#!/usr/bin/env python3
"""Stage 3: check a live_activity_config before publishing. Changes nothing.

    python3 validate_config.py <config.json> [--repeat-minutes N] [--skip-images]

1. Schema: runs ajv against schema/live_activity_config.schema.json (needs Node/npx).
2. Every card, fully resolved (top-level defaults + the card's own fields):
   - images load over HTTPS and are real images under 1 MB,
   - banner images for the large style are wide enough (>= 2.4:1, ideally ~3:1),
   - title fits on one line, accent colour is readable on the dark timer pill,
   - layout fields that were inherited (they surprised us once) are listed.
3. REPEAT_EVERY_MINUTES is at least the longest timer, so countdowns can finish.
Exit code 1 if there are errors; warnings don't fail.
"""
import json
import os
import subprocess
import sys
import tempfile
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SCHEMA = os.path.normpath(os.path.join(HERE, "..", "..", "..", "schema", "live_activity_config.schema.json"))
CARD_FIELDS = ["brandName", "title", "subtitle", "imageUrl", "bannerImageUrl", "imageStyle", "symbol",
               "accentColor", "showStages", "titlePosition", "showTimer", "timerMinutes"]
DEFAULTS = {"imageStyle": "small", "titlePosition": "below", "showStages": True, "showTimer": False,
            "timerMinutes": 0, "title": "", "subtitle": "", "brandName": "", "accentColor": "#FF6B35"}

args = [a for a in sys.argv[1:] if not a.startswith("--")]
if not args:
    sys.exit(__doc__)
path = args[0]
repeat = None
if "--repeat-minutes" in sys.argv:
    repeat = int(sys.argv[sys.argv.index("--repeat-minutes") + 1])
skip_images = "--skip-images" in sys.argv

errors, warnings = [], []
config = json.load(open(path, encoding="utf-8"))

# 1. Schema
schema_run = subprocess.run(
    ["npx", "--yes", "ajv-cli@5.0.0", "validate", "--spec=draft2020", "--all-errors", "-s", SCHEMA, "-d", path],
    capture_output=True, text=True)
if schema_run.returncode != 0:
    detail = "\n".join(l.strip() for l in (schema_run.stdout + schema_run.stderr).splitlines()
                       if "instancePath" in l or "message" in l)
    errors.append("Schema check failed:\n" + (detail or schema_run.stdout + schema_run.stderr))


def luminance(hex_color: str) -> float:
    h = hex_color.lstrip("#")[-6:]
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    lin = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def check_image(url: str, label: str, wide: bool):
    if not url:
        return
    if not url.startswith("https://"):
        errors.append(f"{label}: image must use HTTPS: {url}")
        return
    if skip_images:
        return
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "LiveActivityKit-validator"})
        with urllib.request.urlopen(req, timeout=20) as r:
            data = r.read(5_000_001)
            kind = r.headers.get("Content-Type", "")
    except Exception as e:  # noqa: BLE001
        errors.append(f"{label}: image didn't load ({e}): {url}")
        return
    if not kind.startswith("image/"):
        errors.append(f"{label}: not an image (Content-Type {kind or 'missing'}): {url}")
        return
    if len(data) > 1_000_000:
        warnings.append(f"{label}: image is {len(data) // 1024} KB; keep it under 1 MB (the app downscales, but downloads take longer)")
    with tempfile.NamedTemporaryFile(suffix=".img") as f:
        f.write(data)
        f.flush()
        out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", f.name], capture_output=True, text=True).stdout
    try:
        w = int(out.split("pixelWidth:")[1].split()[0])
        h = int(out.split("pixelHeight:")[1].split()[0])
    except (IndexError, ValueError):
        warnings.append(f"{label}: couldn't read image size: {url}")
        return
    if wide and w / h < 2.4:
        warnings.append(f"{label}: banner is {w}x{h} ({w / h:.1f}:1). The large layout is about 3:1, so the top and "
                        "bottom will be cropped. Use a wide crop, e.g. 1100x360.")


cards = config.get("contents") or [{}]
longest_timer = 0
for i, card in enumerate(cards):
    label = f"Card {i + 1}" if config.get("contents") else "Config"
    resolved = {k: card.get(k, config.get(k, DEFAULTS.get(k))) for k in CARD_FIELDS}
    inherited = [k for k in ("titlePosition", "showTimer") if config.get("contents") and k not in card]
    if inherited:
        warnings.append(f"{label}: inherits {', '.join(f'{k}={resolved[k]!r}' for k in inherited)} from the top level. "
                        "Set it on the card if that's not intended.")
    title = (resolved.get("title") or "")
    if len(title) > 32:
        warnings.append(f"{label}: title is {len(title)} characters; about 32 fit on one line.")
    accent = resolved.get("accentColor") or "#FF6B35"
    try:
        if luminance(accent) < 0.05:
            warnings.append(f"{label}: accent {accent} is very dark and hard to see on the dark timer pill.")
    except ValueError:
        pass  # schema reports bad colours
    large = resolved.get("imageStyle") == "large"
    banner = resolved.get("bannerImageUrl") or resolved.get("imageUrl")
    check_image(resolved.get("imageUrl") or "", f"{label} imageUrl", wide=False)
    if large:
        check_image(banner or "", f"{label} bannerImageUrl", wide=True)
        if not banner:
            warnings.append(f"{label}: large style without an image; the card shows a black area.")
    if resolved.get("showTimer") and not resolved.get("showStages"):
        longest_timer = max(longest_timer, int(resolved.get("timerMinutes") or 0))

if repeat is not None and longest_timer > repeat:
    warnings.append(f"REPEAT_EVERY_MINUTES is {repeat} but the longest timer is {longest_timer} minutes, so the card "
                    "is replaced before the countdown ends. Set it to at least the longest timer.")

print(f"Checked {len(cards)} card(s) in {path}")
for e in errors:
    print(f"ERROR   {e}")
for w in warnings:
    print(f"WARNING {w}")
print("OK" if not errors else f"{len(errors)} error(s)")
sys.exit(1 if errors else 0)
