#!/usr/bin/env python3
"""Stage 3: publish live_activity_config to Remote Config, keeping every other parameter.

    python3 publish_config.py --project <id> --config <config.json> [--account <email>] [--key live_activity_config] [--yes]

Downloads the current template, saves a backup, replaces only this one parameter, and shows a
summary. Publishes only with --yes, which the skill passes after the user approved the preview.
Roll back with: firebase remoteconfig:rollback -v <version>
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import time

p = argparse.ArgumentParser()
p.add_argument("--project", required=True)
p.add_argument("--config", required=True)
p.add_argument("--account")
p.add_argument("--key", default="live_activity_config")
p.add_argument("--yes", action="store_true")
a = p.parse_args()

base = ["firebase"] + (["--account", a.account] if a.account else []) + ["--project", a.project]
work = tempfile.mkdtemp(prefix="rc-")
current = os.path.join(work, "current.json")
subprocess.run(base + ["remoteconfig:get", "-o", current], check=True, capture_output=True)
template = json.load(open(current))
# The template file from `remoteconfig:get` has no version; ask for the latest one.
versions = subprocess.run(base + ["remoteconfig:versions:list", "--limit", "1", "--json"], capture_output=True, text=True)
try:
    version = json.loads(versions.stdout)["result"]["versions"][0]["versionNumber"]
except (ValueError, KeyError, IndexError):
    version = "unknown"

backup_dir = os.path.join(os.getcwd(), ".live-activity-backups")
os.makedirs(backup_dir, exist_ok=True)
backup = os.path.join(backup_dir, f"remoteconfig-v{version}-{time.strftime('%Y%m%d-%H%M%S')}.json")
json.dump(template, open(backup, "w"), indent=2, ensure_ascii=False)

new_value = json.load(open(a.config, encoding="utf-8"))
params = template.setdefault("parameters", {})
old = params.get(a.key, {})
old_value = json.loads(old.get("defaultValue", {}).get("value", "{}") or "{}")
params[a.key] = {
    **old,
    "defaultValue": {"value": json.dumps(new_value, ensure_ascii=False, indent=2)},
    "valueType": "JSON",
    "description": old.get("description") or "All content shown in the iOS Live Activity (LiveActivityKit).",
}
cards_before = len(old_value.get("contents", [])) if isinstance(old_value, dict) else 0
print(f"Project {a.project}, current version {version}. Backup: {backup}")
print(f"Parameter {a.key}: {'update' if old else 'create'}; cards {cards_before} -> {len(new_value.get('contents', []))}")
print(f"Other parameters kept: {len(params) - 1}")

if not a.yes:
    print("\nNot published (no --yes). Show the user the previews, then rerun with --yes.")
    sys.exit(0)

out = {k: template[k] for k in ("conditions", "parameters", "parameterGroups") if template.get(k)}
tpl = os.path.join(work, "remoteconfig.template.json")
json.dump(out, open(tpl, "w"), indent=2, ensure_ascii=False)
json.dump({"remoteconfig": {"template": "remoteconfig.template.json"}}, open(os.path.join(work, "firebase.json"), "w"))
r = subprocess.run(base + ["deploy", "--only", "remoteconfig"], cwd=work, capture_output=True, text=True)
print(r.stdout[-400:] if r.returncode == 0 else r.stdout + r.stderr)
sys.exit(r.returncode)
