#!/usr/bin/env bash
# Stage 3: find the app's Firebase iOS app and add its GoogleService-Info.plist.
#
#   firebase_app.sh --project <firebase-project-id> --bundle-id <id> --out <App>/GoogleService-Info.plist
#                   [--account <email>] [--create "Display Name"]
#
# Looks for an existing iOS app with this bundle ID first. Creates one ONLY when --create is
# given, which the skill passes only after the user has approved creating it.
set -euo pipefail

account=""; project=""; bundle=""; out=""; create=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --account) account="--account $2"; shift 2 ;;
    --project) project="$2"; shift 2 ;;
    --bundle-id) bundle="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --create) create="$2"; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
[[ -n "$project" && -n "$bundle" && -n "$out" ]] || { echo "need --project, --bundle-id and --out" >&2; exit 2; }
fb() { firebase $account --project "$project" "$@"; }

echo "> firebase apps:list IOS (looking for $bundle)"
app_id=$(fb apps:list IOS --json 2>/dev/null | python3 -c "
import json, sys
apps = json.load(sys.stdin).get('result', [])
match = [a['appId'] for a in apps if a.get('bundleId') == '$bundle']
print(match[0] if match else '')")

if [[ -z "$app_id" ]]; then
  if [[ -z "$create" ]]; then
    echo "NOT FOUND: no Firebase iOS app with bundle ID $bundle in project $project."
    echo "Ask the user before creating one, then rerun with --create \"<display name>\"."
    exit 3
  fi
  echo "> firebase apps:create IOS \"$create\" --bundle-id $bundle   (approved by the user)"
  app_id=$(fb apps:create IOS "$create" --bundle-id "$bundle" 2>&1 | grep -oE '1:[0-9]+:ios:[a-f0-9]+' | head -1)
  [[ -n "$app_id" ]] || { echo "Creating the app failed." >&2; exit 1; }
else
  echo "Found existing app: $app_id"
fi

# A new app's config can take a few seconds to become available.
rm -f "$out"
for _ in 1 2 3 4 5 6; do
  if fb apps:sdkconfig IOS "$app_id" -o "$out" >/dev/null 2>&1; then break; fi
  rm -f "$out"; sleep 5
done
rm -f firebase-debug.log
[[ -f "$out" ]] || { echo "Couldn't download the config file." >&2; exit 1; }
got=$(/usr/libexec/PlistBuddy -c "Print BUNDLE_ID" "$out")
[[ "$got" == "$bundle" ]] || { echo "Config file is for $got, expected $bundle." >&2; exit 1; }
echo "Wrote $out (app $app_id)"
