> September 29: [A5 handoff](a5-handoff.md) supersedes this checkpoint: registered training battles and B prototype placements are now connected on A5. Production combat mappings and saves remain pending.

# A handoff for B2/B3

Implemented in the combined A2 + D1 + D4 PR #6, under Jordan's instruction to
unblock B. This is an additive capability: `WorldHost` and the existing
`WorldViewBuilder` stay compatible. B may test `host is WorldInteractionHost`.
The interface lives in `lib/core/contracts/ports.dart`; application registration
lives in `lib/app/world_operations.dart` and `content_operations.dart`.

## Calls from B

After any accepted movement, synchronously re-read `host.revision` and call:

```dart
host.useMapExit(exitId, expectedRevision: host.revision);
host.openDialogue(npcId, expectedRevision: host.revision);
host.openChest(chestId, expectedRevision: host.revision);
```

These methods belong to `WorldInteractionHost`. Do not batch calls using one
revision, await between reading and requesting, or submit rewards/positions.
All calls require unpaused exploration, a current revision, a registered ID,
a matching source map, and B's reachable-site predicate. Rejections leave
state, revision, mode and notifications unchanged. Acceptance publishes one
coherent state and newer revision synchronously before returning. Listener
writes and writes inside geometry callbacks are rejected. Throwing geometry
callbacks fail closed. Keep predicates synchronous and side-effect free.

## B's registration handoff

Supply preloaded `WorldArea(map: ..., isClear: WorldCollision(map).isClear)`
for additional maps. The initial `WorldSession.map/isClear` remains authoritative
for the initial map (including returns to it). Supply `MapExit` records with a
stable exit ID, `InteractionSite` source map and reach predicate, destination
map ID and named spawn ID. The destination map must be registered and its spawn
must pass full-footprint collision. Missing map/spawn and blocked destinations
reject. Accepted exits preserve party, inventory, gold and quest/chest flags.
A publishes the new map and position together; GameApp updates B's view.

For NPCs/chests, supply a map of authored NPC/chest IDs to `InteractionSite`
placements. A's `contentOperations(content: content, sites: sites, areas: areas,
exits: exits)` builds `WorldOperations` from Trey's `DemoContent`. Pass that in
`WorldSession(operations: operations, ...)`. Empty placements enable nothing.
Unknown placement IDs and map/content mismatches fail registration. The adapter
uses D's NPC-linked dialogue speaker/lines and chest item/quantity. It does not
translate `b1.practice` into an authored map or fabricate trigger coordinates.
B owns trigger proximity, exits, geometry and full collision checks; A owns
committing state. Tests use synthetic maps; Luke still needs to supply actual
map assets, exit/spawn bindings and NPC/chest reach predicates.

## Dialogue lifecycle

`openDialogue` gates movement immediately and creates a monotonically increasing
session token. GameApp presents Trey's existing `DialoguePanel` once, after the
current frame (never during synchronous host notification). A handles completion
or cancellation through `closeDialogue(token, expectedRevision: revision)`.
The adapter reads the current revision at dismissal; the token rejects an old
route even after restart or a newer conversation. Duplicate opens/closes reject.
Both Finish and Close release dialogue without quest flags or rewards. Losing
app focus during dialogue records pause; dismissing cannot bypass that pause.
The world stays mounted; its ticker is gated and held controls are cleared.
B should request dialogue only, not also open a second UI route.

## Chest atomicity and persistence boundary

`openChest` adds the registered positive item quantity and the chest ID to
`state.quests.openedChestIds` in one publication. Already-open IDs reject even
with a fresh revision, and reentrant requests cannot double-grant. Existing
inventory counts, party, gold, position and quest flags are preserved. The
registry validates reward item IDs. There is no implicit gold, experience or
quest progression. This operation is exactly once within the authoritative
GameState; A3 must persist inventory and opened IDs together for cross-reload
protection. New Game intentionally creates a fresh state. No storage guarantee
or save implementation is claimed here.

## Remaining dependencies

- Luke: wire these calls and register actual maps, exits and interaction sites;
  retain B's encounter policy as provisional until group tuning.
- Joseph: C1 is a standalone battle engine, not an A battle adapter. Provide the
  shared-state/stat mapping, encounter definitions and launch/result boundary;
  coordinate C2 battle presentation. A still rejects encounter requests, so the
  B3 test battle must not be described as integrated production combat.
- Trey: D dialogue and content are consumed without editing D-owned files.
  Party menu commands still require C rules; title Continue requires A3 storage.
  No branch cleanup is required to proceed with the combined PR.

Do not merge this stacked PR into B1. Land dependencies, retarget main and obtain
review for the combined scope. A2 remains partial, not Done.
