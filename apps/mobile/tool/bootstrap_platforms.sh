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

  # `flutter create` fills in any file that is missing, which includes the
  # counter-app scaffold test. This project has its own suite under test/ and
  # no widget_test.dart, so the scaffold is generated every time and then fails
  # to analyse (it references `MyApp`, which does not exist here). Drop it.
  if [[ -f test/widget_test.dart ]] && grep -q 'MyApp' test/widget_test.dart; then
    echo "Removing the generated scaffold test…"
    rm test/widget_test.dart
  fi
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

WRAPPER="android/gradle/wrapper/gradle-wrapper.properties"
if [[ -f "$WRAPPER" ]] && grep -q 'gradle-8\.3-all\.zip' "$WRAPPER"; then
  echo "Bumping the Gradle wrapper to 8.7…"
  # `flutter create` scaffolds Gradle 8.3, which predates Java 21 support.
  # Java 21 is the default JDK on current runners and dev machines, and Flutter
  # itself reports the compatible range here as 8.4-8.7, so the scaffolded
  # version fails the build before it starts. 8.7 is the top of that range.
  sed -i 's|gradle-8\.3-all\.zip|gradle-8.7-all.zip|' "$WRAPPER"
fi

SETTINGS="android/settings.gradle"
if [[ -f "$SETTINGS" ]] && grep -q 'com.android.application" version "8\.1\.0"' "$SETTINGS"; then
  echo "Bumping the Android Gradle Plugin to 8.6.0…"
  # AGP below 8.2.1 cannot build against Java 21: jlink fails transforming
  # core-for-system-modules.jar whenever sourceCompatibility is set, which
  # every Flutter plugin does. See https://issuetracker.google.com/issues/294137077.
  # Kotlin moves with it — 1.8.22 predates the AGP 8.6 metadata format.
  sed -i 's|com.android.application" version "8\.1\.0"|com.android.application" version "8.6.0"|' "$SETTINGS"
  sed -i 's|org.jetbrains.kotlin.android" version "1\.8\.22"|org.jetbrains.kotlin.android" version "1.9.24"|' "$SETTINGS"
fi

APP_GRADLE="android/app/build.gradle"
if [[ -f "$APP_GRADLE" ]] && ! grep -q 'coreLibraryDesugaringEnabled' "$APP_GRADLE"; then
  echo "Enabling core library desugaring…"
  # flutter_local_notifications schedules with java.time, so it requires core
  # library desugaring; without it the build stops at checkDebugAarMetadata.
  python3 - "$APP_GRADLE" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()

text = text.replace(
    "    compileOptions {\n",
    "    compileOptions {\n        coreLibraryDesugaringEnabled = true\n",
    1,
)

# The Flutter template ends with the `flutter { source = "../.." }` block; the
# desugaring artifact has to land in a top-level dependencies block after it.
text = text.rstrip() + (
    "\n\ndependencies {\n"
    '    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.4"\n'
    "}\n"
)
path.write_text(text)
PY
fi

echo "Done. Next: flutter pub get && flutter run"
