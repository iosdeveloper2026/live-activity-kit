#!/usr/bin/env bash
# Sets up the live-activity-integrator skill for Claude Code on this Mac.
#
#   ./skill/install.sh
#
# Checks the tools and sign-ins the skill needs, prints how to fix anything missing, and links
# the skill into ~/.claude/skills (the skill stays in this clone; `git pull` updates it).
# Changes nothing else and installs nothing for you.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
skill="$here/live-activity-integrator"
ok=0; missing=0
pass() { printf "  ✓ %s\n" "$1"; ok=$((ok + 1)); }
fail() { printf "  ✗ %s\n      → %s\n" "$1" "$2"; missing=$((missing + 1)); }

echo "Tools"
if xcodebuild -version >/dev/null 2>&1; then
  ver=$(xcodebuild -version | head -1 | awk '{print $2}')
  [[ ${ver%%.*} -ge 16 ]] && pass "Xcode $ver" || fail "Xcode $ver is too old" "Install Xcode 16 or later from the App Store"
else
  fail "Xcode" "Install Xcode from the App Store, then: sudo xcode-select -s /Applications/Xcode.app"
fi
command -v python3 >/dev/null && pass "python3" || fail "python3" "xcode-select --install"
if command -v ruby >/dev/null && ruby -e 'require "xcodeproj"' 2>/dev/null; then
  pass "Ruby xcodeproj $(ruby -e 'require "xcodeproj"; print Xcodeproj::VERSION')"
else
  fail "Ruby xcodeproj (edits Xcode projects)" "gem install --user-install xcodeproj   (or: brew install cocoapods)"
fi
command -v npx >/dev/null && pass "Node / npx $(node -v 2>/dev/null)" || fail "Node / npx (config schema check)" "brew install node"
command -v firebase >/dev/null && pass "Firebase CLI $(firebase --version 2>/dev/null)" || fail "Firebase CLI" "npm install -g firebase-tools"
command -v gh >/dev/null && pass "GitHub CLI $(gh --version | head -1 | awk '{print $3}')" || fail "GitHub CLI" "brew install gh"

echo "Sign-ins"
if command -v firebase >/dev/null; then
  accounts=$(firebase login:list 2>/dev/null | grep -oE '[[:alnum:]._%+-]+@[[:alnum:].-]+' | sort -u | tr '\n' ' ')
  [[ -n "$accounts" ]] && pass "Firebase CLI: $accounts" || fail "Firebase CLI not signed in" "firebase login   (use the account with access to your Firebase project)"
fi
if command -v gh >/dev/null; then
  user=$(gh api user --jq .login 2>/dev/null)
  [[ -n "$user" ]] && pass "GitHub CLI: $user" || fail "GitHub CLI not signed in" "gh auth login"
fi
if [[ -d "$HOME/Library/Developer/Xcode/UserData" ]] && defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier >/dev/null 2>&1; then
  pass "Xcode has an Apple account"
else
  fail "Xcode may not be signed in to an Apple account" "Xcode → Settings → Accounts → + → Apple ID (needed to sign for a device)"
fi

echo "Claude Code skill"
mkdir -p "$HOME/.claude/skills"
ln -sfn "$skill" "$HOME/.claude/skills/live-activity-integrator"
chmod +x "$skill"/scripts/*.sh "$skill"/scripts/*.py "$skill"/scripts/*.rb 2>/dev/null
pass "Linked ~/.claude/skills/live-activity-integrator → $skill"

echo
if [[ $missing -eq 0 ]]; then
  echo "Ready. In Claude Code, open your app's folder and say: \"add the Live Activity kit to this app\"."
else
  echo "$missing item(s) to fix above. The skill is installed; fix these before running it."
fi
