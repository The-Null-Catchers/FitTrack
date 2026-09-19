# FitTrack — mobile app

The Flutter client. Architecture, offline behaviour and the design system are
documented in [`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md).

## First run

```bash
./tool/bootstrap_platforms.sh          # generates android/ and ios/
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` is the Android emulator's route to the host machine, which is where
`docker compose up` puts the API. On a physical device, use your machine's LAN
address. On the iOS simulator, `http://localhost:8000` works.

The platform folders are generated rather than committed because they contain a
binary Gradle wrapper; everything that makes the app *this* app lives in `lib/`,
`test/` and `pubspec.yaml`.

## Layout

```
lib/
  core/            cross-cutting: theme, router, network, database, widgets
  features/<name>/
    domain/        models — plain Dart, hand-written fromJson/toJson
    data/          repositories — the only place that talks to the API or SQLite
    application/   Riverpod controllers and providers
    presentation/  screens and widgets
  l10n/            app_en.arb, app_ar.arb (loaded at runtime, no codegen)
```

## Commands

```bash
flutter analyze
flutter test
flutter test --coverage
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com
flutter build appbundle --release
```

## Notes

* **No code generation.** Models, JSON and localisation are hand-written, so
  `flutter pub get && flutter test` is the whole setup — there is no
  `build_runner` step to fall out of sync.
* **Metric storage.** Weights and lengths are stored in kilograms and
  centimetres everywhere; imperial is a display conversion at the edge.
* **Offline first.** A workout in progress lives in SQLite and is written on
  every set. Changes made offline queue in an outbox keyed by a client-generated
  id, which the server treats as an idempotency key.
