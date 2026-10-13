#!/usr/bin/env bash
# Stage 4–5: create and configure the app's cron repo from the template. Safe to run again.
#
#   cron_repo.sh --repo <owner>/<app>-live-activity-cron --bundle-id <id>
#                [--template iosdeveloper2026/live-activity-cron] [--repeat-minutes 30]
#                [--attributes-type LiveActivityAttributes] [--dry-run]
#
# Prints every gh command before running it. Never touches secrets: the user adds
# FIREBASE_SERVICE_ACCOUNT, and creates the fine-grained token and the cron-job.org job.
set -euo pipefail

repo=""; bundle=""; template="iosdeveloper2026/live-activity-cron"; repeat=30; type="LiveActivityAttributes"; dry=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --bundle-id) bundle="$2"; shift 2 ;;
    --template) template="$2"; shift 2 ;;
    --repeat-minutes) repeat="$2"; shift 2 ;;
    --attributes-type) type="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
[[ -n "$repo" && -n "$bundle" ]] || { echo "need --repo and --bundle-id" >&2; exit 2; }
run() { echo "> $*"; [[ $dry -eq 1 ]] || "$@"; }

gh auth status >/dev/null 2>&1 || { echo "GitHub CLI is not signed in. Ask the user to run: gh auth login"; exit 3; }

if gh repo view "$repo" >/dev/null 2>&1; then
  echo "Repo $repo already exists; updating its settings."
else
  run gh repo create "$repo" --public --template "$template" \
    --description "Scheduled Live Activity pushes through Firebase Cloud Messaging"
  [[ $dry -eq 1 ]] || sleep 5   # the template copy takes a moment
fi

run gh variable set REPEAT_EVERY_MINUTES --body "$repeat" -R "$repo"
run gh variable set ATTRIBUTES_TYPE --body "$type" -R "$repo"
run gh variable set APP_BUNDLE_ID --body "$bundle" -R "$repo"
run gh api -X PATCH "repos/$repo" \
  -f "security_and_analysis[secret_scanning][status]=enabled" \
  -f "security_and_analysis[secret_scanning_push_protection][status]=enabled" --silent
run gh api -X PUT "repos/$repo/actions/permissions/fork-pr-contributor-approval" \
  -f approval_policy=all_external_contributors --silent

has_secret=$(gh secret list -R "$repo" 2>/dev/null | grep -c '^FIREBASE_SERVICE_ACCOUNT' || true)
[[ $dry -eq 1 ]] && echo "
Dry run: nothing was created or changed. The commands above will run without --dry-run."
cat <<EOF

Repo: https://github.com/$repo
Variables: REPEAT_EVERY_MINUTES=$repeat, ATTRIBUTES_TYPE=$type, APP_BUNDLE_ID=$bundle

USER STEPS
$( [[ "$has_secret" == "1" ]] && echo "  [done] FIREBASE_SERVICE_ACCOUNT secret is set" || echo "  1. Firebase console > Project settings > Service accounts > Generate new private key.
     Paste the whole file at https://github.com/$repo/settings/secrets/actions as FIREBASE_SERVICE_ACCOUNT, then delete the file." )
  2. Fine-grained token at https://github.com/settings/personal-access-tokens/new
     Only this repo ($repo), Actions: Read and write, nothing else.
  3. cron-job.org > Create cronjob > IMPORT FROM CURL, paste (with the token), then set
     Content-Type to application/json, schedule every 5 minutes, save responses, TEST RUN (expect 204):

curl -X POST https://api.github.com/repos/$repo/actions/workflows/live-activity.yml/dispatches -H "Authorization: Bearer YOUR_TOKEN_HERE" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" -H "Content-Type: application/json" -d '{"ref":"main"}'
EOF
