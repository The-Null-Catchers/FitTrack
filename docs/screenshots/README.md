# Screenshots

Drop PNGs here and reference them from the root README:

| File | Screen |
| --- | --- |
| `home.png` | Home dashboard |
| `workout.png` | Active workout with the rest timer running |
| `nutrition.png` | Nutrition day with macro rings |
| `progress.png` | Progress charts |
| `coach.png` | FitCoach |
| `admin.png` | Admin dashboard |
| `dark.png` | Any screen in dark mode |
| `arabic.png` | Any screen in Arabic (RTL) |

To capture a populated app:

```bash
docker compose up -d
docker compose run --rm api seed --demo
cd apps/mobile && flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

Sign in as `demo@fittrack.app` / `FitTrack2024!`.
