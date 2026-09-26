# A1 module contracts — review candidate

Status: **PROPOSED, NOT FROZEN**. These are A-owned proposals for review, not
assumptions about B/C/D implementations. No runtime module should depend on this
branch as an agreed API. Review and merge this separately before dependent work.

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

## World proposal — needs Luke's approval

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
- Proposed A2 Flutter entry point: an injected world-view builder receiving
  `WorldHost` and a read-only state notification. The precise widget signature
  and subscription/disposal API must be agreed with B before A2 implementation.

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

- [ ] Luke: coordinate convention, map metadata/schema, footprint responsibility,
  state revisions, movement gating and A2 world-view lifecycle/signature.
- [ ] Joseph: battle input/result snapshot semantics, legal commands, roster
  identity, job/XP/resource model and PartyRules interface.
- [ ] Trey: item/job/data IDs, menu rejection states, Continue/save errors and
  notification/lifecycle requirements for UI.
- [ ] A incorporates requested changes, reruns tests and records explicit review
  approval and the frozen commit in this document/Trello before dependent work.

Send requested changes or explicit acceptance through Jordan; he will coordinate
with the owners. An unanswered question, a passing test or a merged conceptual
diagram does not count as approval. A2 and A3 wait for this gate. A5 additionally
waits for B3, C2, C4 and D1 and the completed A2/A3 implementations.
