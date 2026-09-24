# Release signing — generate and hold your own key

The signing key is what lets a new APK **update** an installed one. Android
refuses an update signed by a different key, and the only way through is an
uninstall, which erases the user's data. So this key is not a build detail:
lose it and every existing install becomes a dead end.

Generate it on your own computer. It never goes into this repository, is never
sent through chat, and is never printed by the build.

## 1. Generate the key

`keytool` ships with any JDK.

```bash
keytool -genkeypair -v \
  -keystore fittrack-release.jks \
  -storetype JKS \
  -keyalg RSA -keysize 4096 \
  -validity 10000 \
  -alias fittrack
```

It asks for a **keystore password**, then your name and organisation (any
values; they appear in the certificate), then a **key password** — press Enter
to reuse the keystore password, which keeps things simpler.

`-validity 10000` is about 27 years. An expired key cannot sign updates, so do
not shorten it.

Record the fingerprint now, so you can always tell whether a build used the
right key:

```bash
keytool -list -v -keystore fittrack-release.jks -alias fittrack \
  | grep -E 'SHA256:|Valid'
```

## 2. Back it up

Losing this file ends the update path for every install. Keep **at least two
copies in different places**, for example a password manager attachment and an
encrypted drive. Store the two passwords with them — a keystore without its
password is as lost as no keystore.

Do not put it in the repository, a shared drive folder that syncs publicly, or
a chat message.

## 3. Add the GitHub Actions secrets

The keystore is binary, so it travels as base64.

```bash
base64 -w0 fittrack-release.jks > keystore.b64   # macOS: base64 -i fittrack-release.jks -o keystore.b64
```

Then in the repository: **Settings → Secrets and variables → Actions → New
repository secret**. Add four:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the entire contents of `keystore.b64`, one line |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
| `ANDROID_KEY_ALIAS` | `fittrack` |
| `ANDROID_KEY_PASSWORD` | the key password (same as the store password if you pressed Enter) |

Then delete the intermediate file — it is your key in plain text:

```bash
shred -u keystore.b64 2>/dev/null || rm -P keystore.b64
```

Paste secrets into the GitHub web form directly. Avoid `gh secret set` from a
shell where the value would land in your shell history.

## 4. Run the build

**Actions → Release Android → Run workflow.** Inputs: `build_aab` (off by
default) and an optional `version_name`.

The run fails immediately with a clear message if any of the four secrets is
missing, rather than quietly falling back to a debug key and producing an APK
that cannot update anything.

Artefacts: `fittrack-release` contains the APK, optionally the AAB, and
`SHA256SUMS.txt`. The run summary prints the certificate DN and SHA-256 digest
— **check the digest matches the fingerprint you recorded in step 1.** If it
ever differs, the key changed and updates will be refused.

## How the secrets are protected

- The keystore is decoded into `RUNNER_TEMP`, **outside the workspace**, so it
  cannot be swept into an artifact upload or a `git add`.
- It is written with mode 600 and shredded in an `always()` step, so it goes
  even if the build fails.
- No step echoes a password or the base64 blob. The only things printed are the
  keystore's **size in bytes** and the certificate **fingerprint** — the
  fingerprint is public, it is in every copy of the APK.
- GitHub masks registered secret values in logs, but this workflow does not
  rely on that: it never passes them to a command that would print them.
- `workflow_dispatch` only, so a pull request from a fork can never run it.
  Fork PRs cannot read repository secrets in any case.

## versionCode

Android will not install an APK whose `versionCode` is lower than the installed
one. The workflow sets it to the greater of pubspec's build number and the
GitHub run number, so every run produces a value that increases, and updates
install cleanly over the previous build.

`versionName` (`1.0.0`) is the human-facing string and can be set per run.

## If you ever lose the key

There is no recovery. Existing users must uninstall and reinstall, losing local
data unless they exported it first (**Profile → Export my data**). This is why
step 2 matters more than the rest of this document.
