# B3 encounter movement checkpoint

Run `flutter run -d chrome -t lib/world/demo/encounter_main.dart`.

Walk right from the spawn. The practice room's x >= 5 area rolls a seeded
one-in-three chance after each tile of accepted travel. The left side is safe.
The test encounter screen pauses movement and its return button preserves the
post-movement position. Three further tiles in the encounter zone are protected
before rolls resume. This screen does not implement combat, rewards, or A5.

`WorldView` accepts an optional stable `EncounterStepper`. Movement counts actual
collision-limited distance, one step per tile, independently of frame rate.
Rejected/zero movement does not count. A completed step samples the committed
position's zone. Partial distance is cleared on gate/focus loss; cooldown remains
in the stepper across battle return. The caller must replace/reset the stepper
when starting a new session. The same host remains the sole GameState owner.

Tests exercise 30/60/120 FPS, idle/walls/rejected writes, post-movement revision,
duplicate encounter rejection, return location, cooldown, and the 1280x720 UI
walk/encounter/return flow. Existing B1 tests remain enabled.

This branch is stacked on `codex/b1-exploration`. Map exits still require Jordan's
named-spawn transition contract; this is an encounter checkpoint, not all of B3.
