import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Rest timer state.
///
/// The countdown is derived from wall-clock deadlines rather than a tick
/// counter, so it stays correct when the app is backgrounded, the device
/// sleeps, or the OS throttles timers — the ticker only drives repaints.
@immutable
class RestTimerState {
  const RestTimerState({
    this.isRunning = false,
    this.totalSeconds = 0,
    this.remainingSeconds = 0,
    this.exerciseName,
    this.isPaused = false,
  });

  final bool isRunning;
  final int totalSeconds;
  final int remainingSeconds;
  final String? exerciseName;
  final bool isPaused;

  bool get isActive => isRunning || isPaused;

  bool get isFinished => isActive && remainingSeconds <= 0;

  double get progress => totalSeconds == 0
      ? 0
      : (1 - remainingSeconds / totalSeconds).clamp(0.0, 1.0);

  RestTimerState copyWith({
    bool? isRunning,
    int? totalSeconds,
    int? remainingSeconds,
    String? exerciseName,
    bool? isPaused,
  }) =>
      RestTimerState(
        isRunning: isRunning ?? this.isRunning,
        totalSeconds: totalSeconds ?? this.totalSeconds,
        remainingSeconds: remainingSeconds ?? this.remainingSeconds,
        exerciseName: exerciseName ?? this.exerciseName,
        isPaused: isPaused ?? this.isPaused,
      );
}

class RestTimerController extends StateNotifier<RestTimerState> {
  RestTimerController() : super(const RestTimerState());

  Timer? _ticker;
  DateTime? _endsAt;
  int _pausedRemaining = 0;

  /// Fires once when the countdown reaches zero.
  VoidCallback? onFinished;

  void start(int seconds, {String? exerciseName}) {
    if (seconds <= 0) return;
    _endsAt = DateTime.now().add(Duration(seconds: seconds));
    state = RestTimerState(
      isRunning: true,
      totalSeconds: seconds,
      remainingSeconds: seconds,
      exerciseName: exerciseName,
    );
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final DateTime? endsAt = _endsAt;
    if (endsAt == null) return;

    final int remaining = endsAt.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) {
      _ticker?.cancel();
      state = state.copyWith(remainingSeconds: 0, isRunning: false);
      unawaited(HapticFeedback.mediumImpact());
      onFinished?.call();
      return;
    }
    state = state.copyWith(remainingSeconds: remaining);
  }

  void pause() {
    if (!state.isRunning) return;
    _ticker?.cancel();
    _pausedRemaining = state.remainingSeconds;
    state = state.copyWith(isRunning: false, isPaused: true);
  }

  void resume() {
    if (!state.isPaused) return;
    _endsAt = DateTime.now().add(Duration(seconds: _pausedRemaining));
    state = state.copyWith(isRunning: true, isPaused: false);
    _startTicker();
  }

  void adjust(int deltaSeconds) {
    if (!state.isActive) return;
    if (state.isPaused) {
      _pausedRemaining = (_pausedRemaining + deltaSeconds).clamp(0, 3600);
      state = state.copyWith(
        remainingSeconds: _pausedRemaining,
        totalSeconds: (state.totalSeconds + deltaSeconds).clamp(1, 3600),
      );
      return;
    }
    final DateTime base = _endsAt ?? DateTime.now();
    _endsAt = base.add(Duration(seconds: deltaSeconds));
    final int remaining =
        _endsAt!.difference(DateTime.now()).inSeconds.clamp(0, 3600);
    state = state.copyWith(
      remainingSeconds: remaining,
      totalSeconds: (state.totalSeconds + deltaSeconds).clamp(1, 3600),
    );
  }

  void skip() {
    _ticker?.cancel();
    _endsAt = null;
    state = const RestTimerState();
  }

  /// Recompute after the app returns from the background.
  void resync() {
    if (!state.isRunning) return;
    _tick();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

final StateNotifierProvider<RestTimerController, RestTimerState>
    restTimerProvider =
    StateNotifierProvider<RestTimerController, RestTimerState>(
  (Ref ref) => RestTimerController(),
);
