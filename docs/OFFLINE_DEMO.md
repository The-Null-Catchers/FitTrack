# FitTrack offline demo

A build that runs entirely on the phone: no account, no network, no API key, no
backend. It is the real app — same screens, same repositories, same controllers
— with the network transport swapped underneath.

## How it works

`apiClientProvider` normally builds Dio on a real socket. In demo mode it
builds Dio on `DemoApiAdapter`, which answers the same requests from bundled
data. Nothing above that line changes, so the demo exercises the actual app
rather than a parallel mock, and the online stack is untouched.

`assets/demo/seed.json` is a capture of real responses from the FitTrack API,
so every payload has exactly the shape the server produces: 80 exercises,
60 foods, 6 program templates, 41 workouts across 12 weeks, 47 personal
records, 60 weight entries, 42 measurements, 4 habits, 4 goals.

Entry point: **Explore the demo** on the welcome screen. It sets a persisted
preference and signs in through the ordinary auth flow — the adapter ignores
the credentials, so no password is checked and nothing leaves the device.

## Durability

| What | Where | Survives |
|---|---|---|
| Workouts, plans, goals, measurements, meals, habits, profile | `fittrack_demo_state.json` in the app documents directory | app restart, phone restart, app update |
| Progress photos | `photos/` in the app documents directory, referenced by `file://` | app restart, phone restart, app update |

The documents directory is app-private and is **not** cleared by an update. It
*is* removed on uninstall — use **Export my data** first if you care about it.

Photo bytes are copied out of the picker's cache on upload, because that cache
can be cleared by the OS at any time.

## Controls (Profile screen, demo mode only)

- **Export my data** — writes a JSON document containing every local change
  plus photos as base64, then hands it to the system share sheet. This is the
  only thing that survives an uninstall.
- **Restore from a backup** — reads an exported file back. Photo paths are
  rewritten, because the documents directory differs between installs. A file
  that is not a FitTrack export is refused without touching existing data.
- **Reset demo data** — back to the bundled dataset; deletes stored photos too.
- **Leave demo mode** — returns to the sign-in screen.

## What reflects local changes

Everything on screen is recomputed from what is stored on the device. The
bundled capture seeds the starting state; no figure is ever read back out of it
as a pre-computed total. `DemoAnalytics` (`lib/core/demo/demo_analytics.dart`)
does the deriving, and the adapter calls it on every request:

- Workout history, set count and total volume per session
- Every dashboard tile — calorie, protein and water rings, this week's
  workouts, current and longest streak, today's habits, active goals,
  unacknowledged records, latest weight and 30-day change
- Body-weight, training-volume, nutrition and body-measurement charts
- `/progress/overview`, including volume split by muscle group
- Per-exercise progress, derived from the sets stored for that exercise
- Nutrition, stored per day, so logging lunch today leaves yesterday alone
- Habit streaks, recomputed on each check-in
- Personal records, goals, measurements, photos

Delete a workout and the volume comes back off the chart; log a meal and the
rings move. Nothing keeps showing the seed after you change the data.

## Simulated or unavailable

| Feature | Status |
|---|---|
| FitCoach replies | **Canned text**, keyword-selected. Every reply ends "Demo mode — this is a stored sample reply, not a live AI response." |
| FitCoach injury safety | **Real logic**, not canned: injury, pain and medical wording is redirected to a professional and never gets training advice. "Muscle soreness" is deliberately allowed through. |
| Generated workout plans | Built deterministically from the bundled exercise library. Not AI. |
| Barcode scanning | **Unavailable** — returns a clean 404 rather than hanging. |
| Sign up / sign in | **Unavailable in demo mode** by design; they point at a placeholder host. Demo mode is the only working entry. |
| Password change / reset, resend verification | **Refused** with a 503 and a clear message. These need an account server, and reporting success would tell the user their password changed when nothing happened. |
| Push notifications, email | Not delivered. |
| Server sync | **Refused** with a 503. Demo changes are already durable on the device, so there is nothing to push — and claiming a successful sync would tell the user their data is backed up somewhere it is not. The sync row in Settings is disabled in demo mode and reads "saved on this device only". |
| Daily workout reminder | **Real**, delivered by the phone. The switch only turns on once the OS accepts the schedule, and says so when it refuses. |

## Building

```bash
cd apps/mobile
./tool/bootstrap_platforms.sh
flutter build apk --release --dart-define=API_BASE_URL=https://unused.invalid
```

`API_BASE_URL` is irrelevant in demo mode; it is only used if someone leaves
demo mode and tries to sign in for real.

### Which APK to hand out

Ship the **universal** `app-release.apk`. It carries all four ABIs
(arm64-v8a, armeabi-v7a, x86, x86_64) and `versionCode 1`.

Do **not** mix it with `--split-per-abi` output. Flutter offsets split
versionCodes (armeabi-v7a → 1001, arm64-v8a → 2001), so installing a split and
then the universal is a **downgrade** and Android refuses it. Pick one variant
and stay on it.

### Verified properties of the shipped APK

| Property | Value |
|---|---|
| `minSdkVersion` | 21 (Android 5.0) |
| `targetSdkVersion` | 35 |
| ABIs | arm64-v8a, armeabi-v7a, x86, x86_64 |
| Signing | v1 (JAR) + v2 |
| zipalign | 4-byte and 16 KB page aligned |
| ELF `p_align` | 64 KB / 16 KB — safe on 16 KB-page Android 15+ devices |
| Package | `app.fittrack.fittrack` |

The APK is **debug-key signed**: fine for sideloading, not fit for any store,
and it cannot upgrade an install signed with a different key.

## If it will not install

The build above was verified by inspection only. **No device or emulator test
was performed** — the build container has no `/dev/kvm` and no nested
virtualisation, so no emulator can run. Installation is therefore unverified.

Collect these, in order — they distinguish the likely causes:

1. **The exact on-screen error.** "App not installed as package appears to be
   invalid" points at a corrupted download; "Blocked by Play Protect" or
   "Restricted setting" points at device policy. Quote it verbatim.

2. **Samsung Auto Blocker.** On One UI 6.1 and later this is *on by default*
   and silently blocks all sideloading. Settings → Security and privacy →
   Auto Blocker → turn off. This is the single most common cause on a Samsung.

3. **Verify the download.** A truncated transfer is the other common cause:
   ```
   sha256sum app-release.apk
   ```
   Compare against the checksum published with the build, and check the byte
   size matches exactly.

4. **Install over adb, which prints the real reason** where the UI does not:
   ```
   adb install -r app-release.apk
   ```
   `INSTALL_FAILED_UPDATE_INCOMPATIBLE` means an existing `app.fittrack.fittrack`
   is signed with a different key — uninstall it first.
   `INSTALL_FAILED_NO_MATCHING_ABIS` means a split for the wrong architecture.
   `INSTALL_PARSE_FAILED_NO_CERTIFICATES` means the file is damaged.

5. **If adb is unavailable**, the device log still has it:
   ```
   adb logcat -d | grep -iE 'PackageManager|installd|INSTALL_FAILED'
   ```

6. **Check for an existing install:** Settings → Apps → search "FitTrack".
   Uninstall any previous copy before retrying.
