import '../localization/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/coach/presentation/coach_screen.dart';
import '../../features/coach/presentation/plan_generator_screen.dart';
import '../../features/exercises/presentation/exercise_detail_screen.dart';
import '../../features/exercises/presentation/exercise_library_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/home/presentation/shell_screen.dart';
import '../../features/nutrition/presentation/food_search_screen.dart';
import '../../features/nutrition/presentation/nutrition_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/profile/presentation/devices_screen.dart';
import '../../features/profile/presentation/notification_settings_screen.dart';
import '../../features/profile/presentation/privacy_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/programs/presentation/program_detail_screen.dart';
import '../../features/programs/presentation/programs_screen.dart';
import '../../features/progress/presentation/measurements_screen.dart';
import '../../features/progress/presentation/photo_compare_screen.dart';
import '../../features/progress/presentation/progress_photos_screen.dart';
import '../../features/progress/presentation/progress_screen.dart';
import '../../features/progress/presentation/records_screen.dart';
import '../../features/progress/presentation/weight_log_screen.dart';
import '../../features/workout/presentation/active_workout_screen.dart';
import '../../features/workout/presentation/workout_history_screen.dart';
import '../../features/workout/presentation/workout_screen.dart';
import '../../features/workout/presentation/workout_summary_screen.dart';

/// Route names, referenced by `context.goNamed(...)` so no path string is
/// duplicated across the app.
class Routes {
  const Routes._();

  static const String welcome = 'welcome';
  static const String login = 'login';
  static const String register = 'register';
  static const String forgotPassword = 'forgot-password';
  static const String onboarding = 'onboarding';

  static const String home = 'home';
  static const String workout = 'workout';
  static const String nutrition = 'nutrition';
  static const String progress = 'progress';
  static const String profile = 'profile';

  static const String activeWorkout = 'active-workout';
  static const String workoutSummary = 'workout-summary';
  static const String workoutHistory = 'workout-history';
  static const String exercises = 'exercises';
  static const String exerciseDetail = 'exercise-detail';
  static const String programs = 'programs';
  static const String programDetail = 'program-detail';
  static const String coach = 'coach';
  static const String planGenerator = 'plan-generator';
  static const String foodSearch = 'food-search';
  static const String weightLog = 'weight-log';
  static const String measurements = 'measurements';
  static const String photos = 'photos';
  static const String photoCompare = 'photo-compare';
  static const String records = 'records';
  static const String devices = 'devices';
  static const String notificationSettings = 'notification-settings';
  static const String privacy = 'privacy';
}

final GlobalKey<NavigatorState> _rootKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellKey = GlobalKey<NavigatorState>();

/// Rebuilds the router's redirect whenever auth state changes.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(this._ref) {
    _ref.listen<AuthState>(authControllerProvider,
        (AuthState? _, AuthState __) {
      notifyListeners();
    });
  }

  final Ref _ref;
}

final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final _AuthRefreshNotifier refresh = _AuthRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (BuildContext context, GoRouterState state) {
      final AuthState auth = ref.read(authControllerProvider);
      final String location = state.matchedLocation;

      const Set<String> publicRoutes = <String>{
        '/welcome',
        '/login',
        '/register',
        '/forgot-password',
      };
      final bool isPublic = publicRoutes.contains(location);

      // Hold on the current screen until the stored session is resolved.
      if (auth.status == AuthStatus.unknown) return null;

      if (!auth.isSignedIn) return isPublic ? null : '/welcome';

      // Signed in but the fitness profile is incomplete: finish onboarding
      // before anything else, since the whole app depends on those answers.
      if (auth.status == AuthStatus.needsOnboarding) {
        return location == '/onboarding' ? null : '/onboarding';
      }

      if (isPublic || location == '/onboarding') return '/home';
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/welcome',
        name: Routes.welcome,
        builder: (_, __) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/login',
        name: Routes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: Routes.register,
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        name: Routes.forgotPassword,
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        name: Routes.onboarding,
        builder: (_, __) => const OnboardingScreen(),
      ),

      // The five tabs live inside a shell so the bottom bar and the
      // minimised-workout banner persist across navigation.
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (BuildContext context, GoRouterState state, Widget child) =>
            ShellScreen(child: child),
        routes: <RouteBase>[
          GoRoute(
            path: '/home',
            name: Routes.home,
            pageBuilder: (_, GoRouterState state) =>
                const NoTransitionPage<void>(child: HomeScreen()),
          ),
          GoRoute(
            path: '/workout',
            name: Routes.workout,
            pageBuilder: (_, GoRouterState state) =>
                const NoTransitionPage<void>(child: WorkoutScreen()),
          ),
          GoRoute(
            path: '/nutrition',
            name: Routes.nutrition,
            pageBuilder: (_, GoRouterState state) =>
                const NoTransitionPage<void>(child: NutritionScreen()),
          ),
          GoRoute(
            path: '/progress',
            name: Routes.progress,
            pageBuilder: (_, GoRouterState state) =>
                const NoTransitionPage<void>(child: ProgressScreen()),
          ),
          GoRoute(
            path: '/profile',
            name: Routes.profile,
            pageBuilder: (_, GoRouterState state) =>
                const NoTransitionPage<void>(child: ProfileScreen()),
          ),
        ],
      ),

      // Full-screen routes, pushed above the shell.
      GoRoute(
        path: '/active-workout',
        name: Routes.activeWorkout,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const ActiveWorkoutScreen(),
      ),
      GoRoute(
        path: '/workout-summary',
        name: Routes.workoutSummary,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const WorkoutSummaryScreen(),
      ),
      GoRoute(
        path: '/workout-history',
        name: Routes.workoutHistory,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const WorkoutHistoryScreen(),
      ),
      GoRoute(
        path: '/exercises',
        name: Routes.exercises,
        parentNavigatorKey: _rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            ExerciseLibraryScreen(
          isPicker: state.uri.queryParameters['picker'] == 'true',
        ),
      ),
      GoRoute(
        path: '/exercises/:id',
        name: Routes.exerciseDetail,
        parentNavigatorKey: _rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            ExerciseDetailScreen(exerciseId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/programs',
        name: Routes.programs,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const ProgramsScreen(),
      ),
      GoRoute(
        path: '/programs/:id',
        name: Routes.programDetail,
        parentNavigatorKey: _rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            ProgramDetailScreen(programId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/coach',
        name: Routes.coach,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const CoachScreen(),
      ),
      GoRoute(
        path: '/coach/plan',
        name: Routes.planGenerator,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const PlanGeneratorScreen(),
      ),
      GoRoute(
        path: '/food-search',
        name: Routes.foodSearch,
        parentNavigatorKey: _rootKey,
        builder: (BuildContext context, GoRouterState state) =>
            FoodSearchScreen(
          mealType: state.uri.queryParameters['meal'] ?? 'snack',
        ),
      ),
      GoRoute(
        path: '/weight-log',
        name: Routes.weightLog,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const WeightLogScreen(),
      ),
      GoRoute(
        path: '/measurements',
        name: Routes.measurements,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const MeasurementsScreen(),
      ),
      GoRoute(
        path: '/photos',
        name: Routes.photos,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const ProgressPhotosScreen(),
      ),
      GoRoute(
        path: '/photos/compare',
        name: Routes.photoCompare,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const PhotoCompareScreen(),
      ),
      GoRoute(
        path: '/records',
        name: Routes.records,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const RecordsScreen(),
      ),
      GoRoute(
        path: '/devices',
        name: Routes.devices,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const DevicesScreen(),
      ),
      GoRoute(
        path: '/notification-settings',
        name: Routes.notificationSettings,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: '/privacy',
        name: Routes.privacy,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const PrivacyScreen(),
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Text(
          context.l10n.t('routeNotFound'),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    ),
  );
});
