#!/usr/bin/env python3
"""Stage 3/6: show which devices of an app have saved push tokens. Read-only; prints no tokens.

    python3 check_tokens.py --project <firebase-project-id> --bundle-id <id> [--account <email>]

Uses the Firebase CLI's own sign-in (the account must have access to the project).
"""
import argparse
import json
import os
import urllib.parse
import urllib.request

p = argparse.ArgumentParser()
p.add_argument("--project", required=True)
p.add_argument("--bundle-id", required=True)
p.add_argument("--account")
a = p.parse_args()

# The Firebase CLI stores its sign-in here; its OAuth client ID/secret are public constants of firebase-tools.
store = json.load(open(os.path.expanduser("~/.config/configstore/firebase-tools.json")))
accounts = [store] + store.get("additionalAccounts", [])
account = next((x for x in accounts if not a.account or x.get("user", {}).get("email") == a.account), None)
if not account or "tokens" not in account:
    raise SystemExit("Firebase CLI isn't signed in with that account. Ask the user to run: firebase login:add")
body = urllib.parse.urlencode({
    "grant_type": "refresh_token",
    "refresh_token": account["tokens"]["refresh_token"],
    "client_id": "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com",
    "client_secret": "j9iVZfS8kkCEFUPaAeJV0sAi",
}).encode()
access = json.load(urllib.request.urlopen("https://oauth2.googleapis.com/token", body))["access_token"]

url = f"https://firestore.googleapis.com/v1/projects/{a.project}/databases/(default)/documents/liveActivityDevices?pageSize=300"
docs = json.load(urllib.request.urlopen(urllib.request.Request(url, headers={"Authorization": "Bearer " + access}))).get("documents", [])
mine = [d for d in docs if d["fields"].get("bundleId", {}).get("stringValue") == a.bundle_id]
print(f"{len(mine)} device(s) for {a.bundle_id} (of {len(docs)} in the project)")
for d in sorted(mine, key=lambda d: d["updateTime"], reverse=True):
    f = d["fields"]
    act = f.get("activity", {}).get("mapValue", {}).get("fields", {})
    print(f"  {d['name'].rsplit('/', 1)[-1][:8]}  updated {d['updateTime'][:19]}Z  "
          f"FCM {'yes' if 'fcmToken' in f else 'NO'} | push-to-start {'yes' if 'startToken' in f else 'NO'} | "
          f"activity {act.get('status', {}).get('stringValue', 'none')}"
          f"{' with update token' if 'pushToken' in act else ''}")
if not mine:
    print("No devices yet: open the app once on a device (or simulator) and check again.")
