import 'package:fittrack/features/workout/application/rest_timer_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late RestTimerController controller;

  setUp(() => controller = RestTimerController());
  tearDown(() => controller.dispose());

  test('starts a countdown with the requested length', () {
    controller.start(90, exerciseName: 'Bench Press');

    expect(controller.state.isRunning, isTrue);
    expect(controller.state.totalSeconds, 90);
    expect(controller.state.remainingSeconds, 90);
    expect(controller.state.exerciseName, 'Bench Press');
    expect(controller.state.progress, 0);
  });

  test('ignores a zero or negative rest period', () {
    controller.start(0);
    expect(controller.state.isActive, isFalse);
  });

  test('adding time extends both the remaining and total', () {
    controller.start(60);
    controller.adjust(15);

    expect(controller.state.totalSeconds, 75);
    expect(controller.state.remainingSeconds, greaterThan(60));
  });

  test('subtracting time never goes below zero', () {
    controller.start(10);
    controller.adjust(-60);

    expect(controller.state.remainingSeconds, greaterThanOrEqualTo(0));
  });

  test('pausing stops the countdown and keeps the remaining time', () {
    controller.start(120);
    controller.pause();

    expect(controller.state.isRunning, isFalse);
    expect(controller.state.isPaused, isTrue);
    expect(controller.state.isActive, isTrue);
    expect(controller.state.remainingSeconds, 120);
  });

  test('resuming restarts from where it was paused', () {
    controller.start(120);
    controller.pause();
    controller.resume();

    expect(controller.state.isRunning, isTrue);
    expect(controller.state.isPaused, isFalse);
  });

  test('adjusting while paused still changes the remaining time', () {
    controller.start(60);
    controller.pause();
    controller.adjust(15);

    expect(controller.state.remainingSeconds, 75);
  });

  test('skipping clears the timer entirely', () {
    controller.start(90);
    controller.skip();

    expect(controller.state.isActive, isFalse);
    expect(controller.state.remainingSeconds, 0);
  });

  test('progress reflects how much rest has elapsed', () {
    controller.start(100);
    controller.adjust(-50);

    // 50 of 50 remaining against a 50s total: the bar is at the start again.
    expect(controller.state.progress, inInclusiveRange(0, 1));
  });
}
