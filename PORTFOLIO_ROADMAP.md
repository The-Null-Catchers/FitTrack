# FitTrack portfolio roadmap

Baseline reviewed on November 17, 2026. Repository roadmap published on November 18, 2026.

This roadmap applies to this repository and follows the shared Null Catchers portfolio plan. Verify the documented state against the current code and runs before starting work.

**Estimated initial demo effort** 18–30 hours for a developer familiar with the project. The estimate excludes external reviews, store accounts, target environment setup, and later milestones.

## Project priorities

**Documented state** The app logs workouts locally and uses an idempotent outbox. It includes progress, nutrition, and a coach with provider fallbacks. CI produces bilingual screenshots. A physical device still needs to verify the offline scenario.

**P0 — Demo** Recover a workout started offline and sync it exactly once after reconnection.

**P1 — Validation and depth** Test the timer across background and foreground transitions, Arabic labels and numbers, and suggestions alongside user-selected goals. Verify local and server records after retries or session expiry and preserve the user’s chosen goal.

**P2 — Later** Consider supersets or circuits first if they help the scenario, then barcode or health integrations.

**Acceptance criteria** The workout survives disconnection and syncs once. Evidence identifies the release and labels synthetic fitness data.

**Demo scenario** Workout plan → offline workout → restore the session → sync → review progress. [README](https://github.com/The-Null-Catchers/FitTrack/blob/main/README.md).

## Next milestones

[PR #32](https://github.com/The-Null-Catchers/FitTrack/pull/32) added English and Arabic screenshots of Home, Workout, Nutrition, and Progress. [PR #33](https://github.com/The-Null-Catchers/FitTrack/pull/33) restored demo progress history and corrected the three-month range. [Screenshot instructions](README.md#screenshots).

1. [ ] On Android, start a workout in a test account, disconnect, log a set, and close and reopen the app. Confirm the set, values, and active session are restored.
2. [ ] Reconnect, finish the workout, and retry sync. Confirm that one server record has the expected values and the outbox clears after acknowledgement.
3. [ ] Capture the device walkthrough and Arabic progress screen. Record the device, app version, SHA, and synthetic data source.

## Portfolio acceptance checklist

- [ ] Another person can reproduce the primary workflow from a clean checkout using the README and test credentials or fixtures.
- [ ] The demo tells one complete story with a defined user, problem, and saved result.
- [ ] Tests cover the main flow, an important failure, and access boundaries when multiple accounts are involved.
- [ ] Demo data is labeled synthetic and reproducible. Review screenshots and recordings for secrets and customer data.
- [ ] Include four to six real screenshots where appropriate, a 60–120 second recording, and working links. Identify the revision used for capture.
- [ ] The README describes implemented capabilities, setup, architecture, limits, tests, and the demo.
- [ ] A short case study explains two engineering decisions, a considered alternative, and how the system handles an actual failure.
- [ ] Release evidence records the commit SHA, CI, prerequisites, and limits. Performance data includes workload, hardware, and method.
- [ ] Licensing and contributor attribution are settled before distribution. Choose the license for each repository individually.

A hosted demo is optional. Code execution, server administration, and secret management can be demonstrated through a recording and a reproducible isolated environment. Keep public demo access scoped to the activities it needs.

## Implementation and follow-up

- Break P0 into tasks with expected behavior, acceptance criteria, and a suitable test.
- Verify existing functionality first. Update this plan when evidence tied to a commit or PR closes a milestone.
- Record the fixture source, the revision used for evidence, and the tested limits.
- Review the final diff and verify required checks for its exact SHA before merging. Follow branch protection.
- For documentation-only changes with no applicable workflow, verify content and links and record the checks actually performed.
- Tie performance, security, and readiness claims to supporting evidence.
