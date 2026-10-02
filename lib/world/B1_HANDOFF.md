# B1 implementation handoff

Owner: Luke Broussard (Role B).
Card: https://trello.com/c/HoKeQKvy/11-b1-build-map-rendering-movement-and-collision

## Current state

Luke confirmed 2D top-down exploration on September 22, 2026.
At main commit `2548bd9`, the repository contains the Flutter starter and build
CI, but no shared models, contracts document, app state flow, or Flame dependency.
A1 is still in To Do. B1 explicitly allows fixture-based prototyping only after
A1. This PR prepares the map and checks; it does not complete B1.

## Coordination needed from A

Agree these in A1's reviewed contracts and example fixtures:

- WorldPosition: coordinate units, map/spawn IDs, player footprint and ownership
  of updates. Specify where the authoritative position is held and how world
  movement updates it without creating a second GameState.
- Movement gating: how the world reads exploration, pause, dialogue and battle
  state, and how it is notified when these change.
- Map data: dimensions, tile collision representation, validation rules and
  coordinate origin. Runtime map files should remain in B's assets/maps area.
- Lifecycle: the A2 entry point that hosts the exploration view, including
  restoring the world position and disposing input listeners.
- Dependencies/assets: A owns pubspec and app wiring. Coordinate the Flame
  dependency and asset registration through A instead of editing them silently.

Confirm the primary demo platform and resolution for camera/control acceptance.
The existing Windows/web CI targets are available build targets, not proof of
the team's chosen demo platform.

## Planned small implementation commits after A1

1. Map loading/validation and deterministic movement/collision, with rule tests.
2. Tile/player rendering and bounded camera, with focused view tests.
3. Keyboard and on-screen controls, lifecycle cleanup, and shared-state gating.
4. Integration evidence and handoff documentation after A2 is available.

Keep this work in lib/world/, assets/maps/ and corresponding world tests.
Use A1 fixtures until A2 is ready. B2-B5 stay separate; do not add NPC, encounter,
reward or quest rules to the B1 controller.

## Acceptance checks to implement

| Card requirement | Evidence |
| --- | --- |
| Four-direction movement | Test each direction and release; agree a deterministic policy for simultaneous/opposing inputs without faster diagonal movement. |
| Walls and bounds | Test every map edge, head-on walls, corners and invalid spawn positions using the prototype map. Large frame deltas must not tunnel through a wall. |
| Frame-rate independence | Compare distance after equal elapsed time at 30, 60 and 120 updates/second; test a long-frame policy explicitly. |
| Camera bounds | Check all corners in smaller-than-map and larger-than-map viewports; the latter should center the map without invalid camera ranges. |
| Usable controls | Exercise keyboard and touch independently, pointer cancellation, focus loss, resize and view disposal; no stuck movement after release. |
| Movement suppression | Pause, dialogue and battle each stop position changes, even while input is held; verify the agreed behavior when exploration resumes. |

Run relevant tests and flutter analyze after implementation. Capture a screenshot
or short clip at the selected demo resolution for the PR. A teammate reviews
before merging; move B1 to Done only after acceptance and integration on main.

## Reviewable preparation

The map sketch is in `assets/maps/B1_PROTOTYPE.md`. Its dimensions, closed
perimeter, single spawn and connectivity can be checked independently of the
pending runtime schema. It intentionally uses placeholder geometry, not final art.
