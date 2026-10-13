# Steps only the user can do

Give these instructions word for word when a stage reaches them. Never do them yourself and never
ask for the key or token contents.

## Sign Xcode in (once per Mac)
Xcode → Settings (⌘,) → Accounts → **+** → Apple ID → sign in with the account for the team.

## Sign the GitHub CLI in (once per Mac)
Run `gh auth login`, choose GitHub.com, HTTPS, "Login with a web browser", and enter the one-time
code at https://github.com/login/device. If the Mac's keychain has another GitHub account, set the
repo to use gh: `git config --local credential.helper '!gh auth git-credential'`.

## APNs key (.p8) into Firebase
1. developer.apple.com → Certificates, Identifiers & Profiles → **Keys** → **+**.
2. Name with letters, numbers and spaces only. Tick **Apple Push Notifications service (APNs)**,
   Edit → Environment **Sandbox & Production**, Key Restriction **Team Scoped (All Topics)**.
3. Continue → Register → **Download** (only possible once). Note the **Key ID**.
4. Firebase console → Project settings → **Cloud Messaging** → Apple app configuration → the app →
   APNs Authentication Key → **Upload** in **both** rows (development and production) with the Key ID
   and Team ID.
A team can reuse one APNs key for all its apps; upload it once per Firebase iOS app.

## Firebase service-account secret
Firebase console → Project settings → **Service accounts** → **Generate new private key**. Paste the
whole JSON at `https://github.com/<repo>/settings/secrets/actions` → New repository secret →
`FIREBASE_SERVICE_ACCOUNT`. Delete the downloaded file.

## Fine-grained GitHub token
https://github.com/settings/personal-access-tokens/new → Repository access **Only select
repositories** → the cron repo → Permissions → **Actions: Read and write** (Metadata read-only is
added automatically) → Generate. Copy it straight into cron-job.org.

## cron-job.org job
Sign up free → Cronjobs → Create cronjob → **IMPORT FROM CURL** → paste the command the agent
printed, with the token in place of `YOUR_TOKEN_HERE` → check:
- COMMON: every 5 minutes, Enable job on, Save responses in job history on
- ADVANCED: method POST, headers Authorization / Accept / X-GitHub-Api-Version, and
  **Content-Type `application/json`** (the import sets a form type; change it), body `{"ref":"main"}`
→ **TEST RUN** must show **204 No Content** → **CREATE**.

## Physical iPhone
Connect by **cable**, unlock, tap **Trust**, keep it unlocked; Developer Mode on (Settings → Privacy
& Security). The first Live Activity asks "Allow Live Activities?" — tap Allow. Dismissing a card
ends it; that's not a bug.
