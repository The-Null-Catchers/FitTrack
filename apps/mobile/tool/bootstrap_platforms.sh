#!/usr/bin/env bash
# Generate the Android and iOS platform folders for this project.
#
# The Dart sources, assets and pubspec are the project; the platform folders
# are generated scaffolding (they include a binary Gradle wrapper, so they are
# produced by the Flutter SDK rather than committed by hand). Run this once
# after cloning, and again whenever you bump the Flutter version.
#
#   ./tool/bootstrap_platforms.sh
#
# `flutter create` only fills in files that are missing, so it is safe to
# re-run: nothing under lib/ or test/ is touched.
set -euo pipefail

cd "$(dirname "$0")/.."

ORG="app.fittrack"
PROJECT="fittrack"

if [[ ! -d android || ! -d ios ]]; then
  echo "Generating platform folders…"
  flutter create \
    --project-name "$PROJECT" \
    --org "$ORG" \
    --platforms=android,ios \
    --no-overwrite \
    .
else
  echo "Platform folders already present; leaving them alone."
fi

MANIFEST="android/app/src/main/AndroidManifest.xml"
if [[ -f "$MANIFEST" ]] && ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
  echo "Adding the release INTERNET permission…"
  # Flutter only adds INTERNET to the debug and profile manifests; a release
  # build needs it declared in the main one.
  python3 - "$MANIFEST" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
permissions = (
    '    <uses-permission android:name="android.permission.INTERNET"/>\n'
    '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n'
    '    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>\n'
    '    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n'
)
marker = '<application'
index = text.index(marker)
path.write_text(text[:index] + permissions + '\n    ' + text[index:])
PY
fi

PLIST="ios/Runner/Info.plist"
if [[ -f "$PLIST" ]] && ! grep -q 'NSCameraUsageDescription' "$PLIST"; then
  echo "Adding the iOS camera and photo-library usage descriptions…"
  python3 - "$PLIST" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
entries = (
    '\t<key>NSCameraUsageDescription</key>\n'
    '\t<string>FitTrack uses the camera so you can take progress photos. '
    'Photos stay private to your account.</string>\n'
    '\t<key>NSPhotoLibraryUsageDescription</key>\n'
    '\t<string>FitTrack needs access to your photos so you can add an existing '
    'picture as a progress photo.</string>\n'
)
marker = '</dict>\n</plist>'
path.write_text(text.replace(marker, entries + marker))
PY
fi

echo "Done. Next: flutter pub get && flutter run"
