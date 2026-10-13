#!/usr/bin/env python3
"""Resume helper: check every stage of an integration and say where to continue. Read-only.

    python3 status.py --app <app folder> [--project <firebase-project-id>] [--account <email>]
                      [--repo <owner>/<app>-live-activity-cron]

Without --project/--repo, only the local stages (1–2) are checked.
"""
import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
p = argparse.ArgumentParser()
p.add_argument("--app", required=True)
p.add_argument("--project")
p.add_argument("--account")
p.add_argument("--repo")
a = p.parse_args()


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


rows = []  # (stage, ok, detail)

# Stage 1
code, out = run(["ruby", os.path.join(HERE, "inspect_app.rb"), a.app])
if code != 0:
    print(out)
    sys.exit("Stage 1 failed: couldn't read the app project.")
info = json.loads(out)
rows.append(("1 Inspect", not info["suspiciousBuildPhases"],
             f"{info['uiStack']} app {info['bundleId']}, iOS {info['deploymentTarget']}"
             + (f"; SUSPICIOUS build phases: {info['suspiciousBuildPhases']}" if info["suspiciousBuildPhases"] else "")))

# Stage 2
pbx = open(os.path.join(info["project"], "project.pbxproj"), encoding="utf-8").read()
has_pkg = "live-activity-kit" in pbx
has_runtime = "LiveActivityKit;" in pbx or "productName = LiveActivityKit;" in pbx
has_widget_lib = "LiveActivityKitWidget" in pbx
started = info["liveActivityKitInstalled"]
problems = [name for ok, name in [(has_pkg, "package"), (has_runtime, "LiveActivityKit in app"),
                                  (has_widget_lib, "LiveActivityKitWidget in a widget extension"),
                                  (started, "LiveActivityKit.start() line")] if not ok]
rows.append(("2 iOS", not problems, "kit package, widget and start line present" if not problems else "missing: " + ", ".join(problems)))

# Stage 3
fb = info["firebase"]
if not fb["plist"]:
    rows.append(("3 Firebase", False, "no GoogleService-Info.plist"))
elif not fb["plistMatchesApp"]:
    rows.append(("3 Firebase", False, f"GoogleService-Info.plist is for {fb['plistBundleId']}, not {info['bundleId']}"))
elif a.project:
    tokens_cmd = ["python3", os.path.join(HERE, "check_tokens.py"), "--project", a.project, "--bundle-id", info["bundleId"]]
    if a.account:
        tokens_cmd += ["--account", a.account]
    code, out = run(tokens_cmd)
    line = out.strip().splitlines()[0] if out.strip() else "token check failed"
    rc_cmd = ["firebase"] + (["--account", a.account] if a.account else []) + ["--project", a.project, "remoteconfig:get", "-o", "/dev/stdout"]
    code_rc, out_rc = run(rc_cmd)
    has_param = '"live_activity_config"' in out_rc
    devices = line.split()[0] if line[:1].isdigit() else "0"
    ok = has_param and devices != "0"
    rows.append(("3 Firebase", ok, f"config file ok; Remote Config live_activity_config {'present' if has_param else 'MISSING'}; {line}"))
else:
    rows.append(("3 Firebase", None, "config file ok (pass --project to check Remote Config and tokens)"))

# Stage 4–5
if a.repo:
    code, _ = run(["gh", "repo", "view", a.repo])
    if code != 0:
        rows.append(("4 GitHub", False, f"repo {a.repo} not found"))
        rows.append(("5 Timer", False, "needs the repo first"))
    else:
        _, secrets = run(["gh", "secret", "list", "-R", a.repo])
        _, variables = run(["gh", "variable", "list", "-R", a.repo])
        need = [v for v in ("REPEAT_EVERY_MINUTES", "ATTRIBUTES_TYPE", "APP_BUNDLE_ID") if v not in variables]
        has_secret = "FIREBASE_SERVICE_ACCOUNT" in secrets
        rows.append(("4 GitHub", has_secret and not need,
                     ("secret set" if has_secret else "secret FIREBASE_SERVICE_ACCOUNT MISSING (user step)")
                     + ("" if not need else "; missing variables: " + ", ".join(need))))
        _, runs = run(["gh", "run", "list", "-R", a.repo, "--limit", "4", "--json", "createdAt,event,conclusion"])
        try:
            recent = json.loads(runs)
        except ValueError:
            recent = []
        dispatch = [r for r in recent if r["event"] == "workflow_dispatch"]
        failed = [r for r in recent if r["conclusion"] == "failure"]
        rows.append(("5 Timer", len(dispatch) >= 2 and not failed,
                     f"{len(dispatch)} of the last {len(recent)} runs were triggered externally; {len(failed)} failed"
                     + ("" if recent else " (no runs yet)")))
else:
    rows.append(("4 GitHub", None, "pass --repo to check"))

print(f"{'Stage':<12} {'State':<9} Detail")
next_stage = None
for stage, ok, detail in rows:
    state = "done" if ok else ("unknown" if ok is None else "TODO")
    print(f"{stage:<12} {state:<9} {detail}")
    if ok is False and next_stage is None:
        next_stage = stage
print()
print(f"Continue at stage {next_stage}." if next_stage else "All checked stages are done.")
