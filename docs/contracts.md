# A1 module contracts — review candidate

Status: **B1-v1 world boundary approved by Jordan; other contracts provisional.**
Jordan explicitly approved decisions 1–5 in the project conversation after
Luke's PR review and Joseph's relayed review: freshness guards, monotonic
revisions, notifications/lifecycle, one encounter and narrowly scoped B1.
This is Jordan's decision, not a claim of blanket approval by Luke, Joseph or Trey.
B1 may use this PR's tested handoff commit with a fake host/notifier before A2
exists. Do not wait for provisional battle/menu/save rules to start B1.
The full A1 PR remains draft; merging/freezing all contracts is a separate gate.

The code under `lib/core/contracts/` is framework-independent Dart. It defines
immutable boundary objects, structural validation, and interface signatures;
it does not implement exploration, combat rules, menus, saves or game content.
Use `package:app_4/core/contracts.dart` to import the candidate API.

## Confirmed context

Browser-first; minimum 1280 x 720; Windows is secondary. See
[game-design.md](game-design.md). The existing Flutter app remains a counter
starter. Luke's diagram and B1 draft identify the boundaries this proposal fills.

## Ownership

| Owner | Files / responsibility |
| --- | --- |
| A / Jordan | `lib/core/`, `lib/app/`, `lib/save/`, `lib/main.dart`, dependency/asset registration, CI, shared state and serialization |
| B / Luke | `lib/world/`, `assets/maps/`, world rendering, collision, map events and encounter requests |
| C / Joseph | `lib/battle/`, `lib/progression/`, battle UI/rules, item/equipment/job rules and progression |
| D / Trey | `lib/ui/`, `assets/data/`, art/audio, menu presentation, content definitions and dialogue |

Each owner maintains corresponding tests. Agree shared-file changes with A.
Do not silently modify another owner's interfaces or manufacture their module.

## B1-v1 world contract — approved for B1

- `WorldPosition`: map ID plus continuous **tile-space center** `(x, y)`, origin
  at top left. Tile `(column, row)` has center `(column + .5, row + .5)`.
  Pixel scale stays in B's renderer. This differs from using integer spawn
  coordinates in B's sketch: its `(2,2)` tile becomes center `(2.5,2.5)`.
- `MapDefinition`: positive dimensions, row-major blocked booleans, named
  spawns. Constructor validates shape, map association, bounds and blocked
  spawn tiles. B owns the eventual file loader and collision/footprint rules.
  No runtime asset file format or player footprint is finalized here.
- A's coordinator is the authoritative position owner. B reads a snapshot
  and revision through `WorldHost`, computes collision-checked movement, and
  calls `updatePosition(..., expectedRevision: ...)`. A rejects stale/wrong-mode
  writes. B re-reads state after acceptance/rejection; it must not keep a second
  authoritative `GameState`.
- `movementEnabled` is true only in exploration with no pause, dialogue,
  battle or loading gate. Losing input focus clears held controls. B disposes
  listeners; A2 owns the stable game instance and lifecycle.
- Flutter entry point is the exported `WorldViewBuilder` typedef in
  `lib/app/world_view_builder.dart`:
  `Widget Function(BuildContext context, WorldHost host, Listenable changes)`.
  Flutter types stay outside `lib/core/`. A owns host/notifier lifetime and keeps
  the mounted world view and its game instance stable across ordinary rebuilds
  and notifications. B subscribes on attachment and removes listeners on disposal;
  if dependencies are replaced, detach from the old notifier before attaching
  to the new one. A disposes its notifier after consumers detach.

### Revision and notification rules

- Read `state`, `revision` and `movementEnabled` together synchronously without
  an await. Both host commands are synchronous, atomic transactions.
- Revisions strictly increase throughout a host's lifetime; never reset or wrap.
  Every accepted movement advances the revision (even equal coordinates).
  Each committed game-state or movement-gate change also advances it: pause and
  resume, dialogue enter/exit, loading enter/exit (including failure recovery),
  battle enter/exit, New Game, accepted save load and map transitions. One atomic
  commit changing several fields needs one increment. Read-only operations and
  saving an unchanged snapshot do not advance it.
- Revisions are runtime freshness tokens, never restored from SaveData. New Game
  and load retain the host and advance its counter. Replacing/disposal of a host
  invalidates the old host: it must reject subsequent calls. Never reconnect
  queued commands from an old host to a new one.
- `updatePosition` rejects stale revisions, gated movement, a different map or
  invalid positions. B checks full player-footprint clearance, including spawns
  and restored positions; center-tile validation alone is not collision handling.
  Success publishes all fields and the newer revision before notifying/returning.
  Failure changes no state, revision or gate and emits no change notification.
  Rejected movement must not advance encounter step counters.
- `changes` notifies synchronously after each committed state OR gate change,
  after all getters expose the coherent new values and before the command returns.
  Listeners read only; they must not synchronously call mutating host commands.
  Any later command must re-read a fresh revision. This prevents reentrant writes
  from changing the meaning of the in-progress transaction.
- On gate disable or focus loss, B clears held controls and accumulated movement.
  Focus loss is a local input reset even if the host gate does not change.
  Resume never replays movement. A2 implements these host obligations; B1 uses
  a fake host/notifier that follows the same contract.

### Encounter acceptance

`requestEncounter(request, expectedRevision: revision)` requires a fresh revision,
ungated exploration and no active encounter. After movement succeeds, B re-reads
the accepted state/revision before requesting an encounter. Acceptance atomically
captures the current (post-movement) position and snapshot, allocates the encounter,
advances revision and disables movement/further encounters before notification or
return. Stale/invalid/gated requests return false without any changes or notification.
There is no await between freshness validation and commit. The combat result
protocol below remains provisional; B1 need not implement encounters or combat.

### B1 scope and handoff

B1 is walking, collision and input/lifecycle behavior using the approved boundary,
its own map and a fake host/notifier. Use `WorldPosition`, `MapDefinition`,
`WorldHost`, the existing synthetic state fixture and `WorldViewBuilder`; fixture
party values are scaffolding, not an approval of C/D gameplay rules. A2 integration
can follow later. B must not replace main.dart or add shared dependencies without
coordinating with A. Use the exact tested commit linked in the PR/Trello handoff
as the B1 branch base (or merge that branch into existing B1 work); it is not yet on main.

Deferred to separate A/B/D contracts: dialogue requests, atomic one-time chest
rewards, quest-flag changes and named-spawn map transitions (B2–B5). WorldHost does
not currently expose those operations. Battle rules, menu commands and persistence
remain provisional and are not B1 prerequisites. Changes to B1-v1 must be explicitly
coordinated with Jordan and Luke and recorded with a new tested handoff.

## Combat/progression proposal — needs Joseph's approval

1. B sends `EncounterRequest(definitionId)`. A accepts at most one while exploring,
   allocates a unique encounter ID, captures the state/revision and return point,
   and creates `BattleInput` with a reproducible seed.
2. C owns all combat, targets, costs, enemy AI, job progression and rewards.
   `BattleCommand` names actor, action, targets and an optional ability/item ID.
   The DTO validates shape, not whether an action is legal in battle.
3. C returns `BattleResult` once with matching encounter ID/base revision and
   final party, inventory and gold **including all costs and earned rewards**.
   A must not add rewards again. This snapshot approach is a proposal requiring
   C approval; if C prefers deltas, revise the contract before runtime work.
4. A validates correlation, unchanged party identities, catalog references and
   allowed mode, commits the entire result once, closes the active encounter,
   and restores the captured world position. Duplicate/stale results are rejected.
   World quest flags/map position cannot be overwritten by a battle result.
5. Victory returns to exploration; flee retains spent resources but gives no
   victory rewards; defeat enters game over. C must confirm XP/job progression,
   equipment restrictions and loss/flee behavior. None are implemented by A1.

`PartyMember` separates character XP from per-job progress. `Inventory` is
proposed to count bag items only, with equipped instances excluded. C must
confirm item stacking, slots, duplicate equipment and HP/MP adjustment rules.
`PartyRules.apply` proposes a new immutable state or a typed rejection; A
serializes/validates the commit, while D only sends commands and displays errors.

## Menus, data and saves — needs Trey's and the other owners' approval

- D uses `UseItem`, `EquipItem` (null item means unequip), and `ChangeJob`.
  Pause/resume, New Game and Continue go to A2, not to `PartyRules`.
- Proposed save statuses: loaded, missing, corrupt, unsupported version,
  unavailable; write returns success/failure. A3 will implement a browser
  storage adapter after A1/A2. No codec/storage behavior is supplied yet.
- `SaveData` proposes a schema version plus content version and `GameState`.
  Save outside battle only. Persist position, party, inventory, gold, quest
  flags and opened chests; do not serialize listeners/widgets or in-flight input.
- Stable IDs must outlive display-name changes. D/B need to provide registries
  for encounters, abilities, dialogue, quests and chests before cross-reference
  validation for those namespaces can be finalized.
- Current `ContentCatalog.validate` checks map bounds/blocked tile, current and
  historical jobs, equipped items and inventory items. It explicitly does not
  certify game rules, quest/chest/ability IDs or a player's collision footprint.

## Fixtures and verification

`createContractFixture()` and `createFixtureCatalog()` contain synthetic IDs
prefixed `fixture.`. They are boundary-test data, not D's content or B's map.
They intentionally do not copy Luke's unmerged runtime proposal or assign real
job stats. `test/core/contracts_test.dart` exercises independent snapshots,
immutable collections, malformed positions/maps/party/resources, unknown
references, command shapes and battle-message correlation fields.

These tests do not prove exactly-once rewards, movement gating, save recovery
or UI behavior; those require A2/A3 and the real modules. Run:

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
flutter build web --release --no-pub
```

## Required review / stop conditions

- [x] Jordan approved the B1-v1 decisions above after Luke's conditional review
  and Joseph's matching feedback. B1 can proceed from the tested handoff commit.
- [ ] Joseph/Jordan: battle input/result snapshot semantics, legal commands,
  roster identity, job/XP/resource model and PartyRules interface.
- [ ] Trey/Jordan: item/job/data IDs, menu rejection states and Continue/save errors.
- [ ] A incorporates remaining decisions, tests and records the full frozen A1
  commit before dependent combat/menu/save implementation and full PR merge.

B1 readiness is narrower than A1 completion. A2's complete battle/menu flow and
A3 still need the relevant provisional decisions resolved. A5 additionally waits
for B3, C2, C4, D1 and completed A2/A3. Passing tests do not imply runtime gameplay
is implemented. Jordan will relay the B1 handoff to Luke.
