# D1 / D4: The Lantern Wake

Cards: [D1 menus](https://trello.com/c/A8XvNVzh) ·
[D4 story/data](https://trello.com/c/Qon6F4VP)

Status: **presentation and content draft ready for review; not integrated or Done.**
Branch `codex/d1-d4-menus-content` is stacked on A2's existing
`codex/a2-world-shell` at `760861d`. It reuses A1's DTOs without changing
`lib/core/`, `lib/app/`, `lib/world/`, `lib/battle/` or `lib/main.dart`.
The only shared-file edit is registering one JSON asset in `pubspec.yaml`.
No new dependency, storage implementation, battle formula or map renderer is added.

## Run the review preview

```sh
flutter pub get --enforce-lockfile
flutter run -d chrome -t lib/ui/demo/main.dart
```

Use New Game → Open party journal. Party, Inventory, Equipment and Jobs are
available with keyboard or touch. Escape returns from the journal. The preview's
conversation buttons show all six dialogues; Enter advances, Previous goes back,
and Escape/Close cancels. Returning to title and starting again asks before ending
the current session. Continue is disabled because the preview has no persistent save.

The preview deliberately rejects party commands with an explanatory message.
It does not pretend to implement C4 or persist anything. Successful commands and
live host updates are exercised by the tests. Preview HP/MP/XP/gold are synthetic
presentation fixtures in `lib/ui/demo/main.dart`, **not proposed game balance**.
The default app entry point still launches A2's exploration shell; CI's default
artifacts will not show this separate UI preview.

## D1 integration surface

### TitleScreen (A2/A3)

Pass the latest `LoadResult?` from A3 as `availability`; null means loading.
Only `SaveLoaded` enables Continue. Missing, corrupt, unsupported-version and
unavailable states each have distinct explanatory text. `onContinue` is the
application callback: A revalidates the save, commits it and changes application
mode. D never reads storage or commits `SaveLoaded.data`. Failed callbacks keep
the screen available for retry. `hasActiveProgress` ensures a current session
cannot be silently replaced. New Game also confirms when a saved or unreadable
slot exists; the application owns the eventual replacement policy.

### PartyMenu (A2/C4)

Implement `PartyMenuHost` with A's authoritative `GameState` and `Listenable`.
`submit(MenuCommand)` receives the existing A1 `UseItem`, `EquipItem` (null item
means unequip) or `ChangeJob`. A serializes mutations, calls C's rules, validates
and commits an accepted result, then notifies before returning it. The menu
renders only `host.state`; it never installs `CommandAccepted.state` itself.
Rejected messages appear verbatim and exceptions show a retryable generic error.
Menu navigation/commands are disabled while a command is pending. Disposal or
host replacement prevents stale completions from changing the new screen.

UI selection only filters bag equipment by display slot. C remains responsible
for legality, ownership, job restrictions, KO/resource rules, stat adjustments,
inventory counts and progression. Equipment and spell hints in the D4 data are
authoring proposals, not an authoritative eligibility check.

### Dialogue (A2/B2)

`showGameDialogue(context, DialogueRequest(...))` returns a single
`DialogueDismissal.completed` or `.cancelled`. Back/Escape is cancellation;
only Finish reports completion. The modal restores focus to its opener.
This is a **D-owned presentation adapter proposal**, not an approved expansion
of `WorldHost`. A/B must disable world input and clear held controls before
opening it, await the result, then perform any authorized quest transaction and
restore the proper mode. D does not set quest flags or award items. NPC proximity,
trigger repeat rules, movement gates and save semantics remain with A/B.

## D4 story and map handoff (B)

Premise: Bellwether's tide has stopped. Ada, Ren, Iona and Tavi carry a living
lantern to the Tide Cistern to wake a protective construct that has mistaken
stillness for safety. The ending returns the tide and the fishing fleet to the
harbor. All names and dialogue are original; no FF dialogue or assets are copied.

| Sequence | Location and layout intent | Trigger / payload |
| --- | --- | --- |
| 1. Accept | `map.bellwether`: keeper in dock square; west rest house; east exit | `npc.mara` → `dialogue.call`; set `quest.lantern.accepted` after completion |
| 2. Prepare | `map.salt_path`: loop with north supply spur, sheltered advice bench, east dungeon entrance | `npc.sable` → `dialogue.jobs`; optional `chest.causeway_supplies` grants 2 × `item.salves` once |
| 3. Enter | `map.tide_cistern`: entrance landing, rest alcove, marked boss threshold | `dialogue.threshold`; retain accessible return route |
| 4. Wake | Bell chamber beyond threshold | Win against `enemy.hollow_bell`, then `dialogue.bell`; set `quest.lantern.bell_awake` only after successful completion |
| 5. Return | Back through route to harbor | `dialogue.ending`; requires bell-awake flag, sets `quest.lantern.complete` |

Paper topology (not collision coordinates or a runtime map format):

```text
Bellwether                     Saltglass Causeway                 Tide Cistern
[rest house]                   [supply chest: optional spur]      [entrance landing]
     |                                    |                             |
[keeper / lantern] -- east -- [advice bench / path loop] -- east -- [rest alcove]
                                                                        |
                                                             [marked boss threshold]
                                                                        |
                                                                 [bell chamber]
```

Both exits are bidirectional. No random encounters in town. Route enemies are
brine mites and wick moths; cistern enemies are silt guards plus the explicit
boss. The boss should not be selected as an ordinary random encounter. Rest
points are `rest.harbor` and `rest.cistern`; recovery semantics belong to A/C.
Chest opened-state and reward application must be one atomic transaction, never
awarded from dialogue text. Repeated conversations must not duplicate rewards.
Leaving/cancelling dialogue must not satisfy its completion condition.

The target remains a short demo; encounter frequency and actual duration need
playtesting after B/C integration. This content draft does not claim a tested
15–20 minute playthrough.

## D4 content tables (C)

| Job ID | Display / intended role | Proposed abilities | Proposed equipment |
| --- | --- | --- | --- |
| `job.warrior` | Breakwater / front line | `spell.anchor` | Harbor Blade, Keeper Coat |
| `job.monk` | Tide Striker / physical momentum | `spell.current` | Rope Wraps, Keeper Coat |
| `job.white_mage` | Lantern Keeper / recovery | `spell.mend`, `spell.glow` | Shell Staff, Linen Robe |
| `job.black_mage` | Stormcaller / elemental attacks | `spell.ember`, `spell.rill`, `spell.charged` | Shell Staff, Linen Robe |

| Spell ID | Target | Narrative effect |
| --- | --- | --- |
| `spell.mend` | Ally | Restore HP; C chooses amount, cost and KO legality |
| `spell.anchor` | Ally | Defense creates a short damage reduction effect |
| `spell.current` | Enemy | Consecutive attacks build a short momentum combo |
| `spell.glow` | Ally | Healing can leave a shield or regeneration effect |
| `spell.ember` | Enemy | Fire damage; C chooses amount, cost and resistances |
| `spell.rill` | Enemy | Water damage; C chooses amount, cost and resistances |
| `spell.charged` | Enemy | Lightning/water magic primes the next spell |

| Enemy ID | Role | Encounter intent |
| --- | --- | --- |
| `enemy.brine_mite` | Regular / route | Gentle physical introduction |
| `enemy.wick_moth` | Regular / route | Fire user; water-magic teaching opportunity |
| `enemy.silt_guard` | Regular / dungeon | Durable shell; reason to vary physical and magic jobs |
| `enemy.hollow_bell` | Boss / dungeon | Pressure/recovery windows; mixed roles help without mandating a single composition |

Items include Harbor Salve and Dew Phial, three weapons and two armor pieces.
JSON descriptions carry their intended effects. Costs, power, HP/MP, damage,
resistance coefficients, XP, loot, prices and job-transition adjustments await C.
Job advice and a free rest before the boss encourage experimentation without
introducing D-owned combat or progression formulas.

## Authoring schema and validation

Source of truth: `assets/data/lantern_wake.json`.
Parser: `lib/ui/content/demo_content.dart`.

`schemaVersion: 1` is D's local authoring schema. `contentVersion` identifies
the draft. Neither is a finalized shared save schema. IDs use lowercase dotted
namespaces and underscores, and must remain stable when names/text change.

Every object has exact fields; unknown fields, missing fields, wrong types,
empty text, duplicate IDs, invalid enums and nonpositive reward counts fail
with `FormatException`. References cover hero jobs, job spells/equipment,
enemy spells, map exits/enemies/dialogues, NPC map/dialogue, dialogue speakers,
chests/items, rest maps and quest flags/maps/dialogues/enemies. Return exits,
reachable quest locations and flags produced before use are checked. Loaded
collections are immutable. Parsing never supplies default IDs for bad input.

`sharedJobs` and `sharedItems` produce A1 `JobDefinition` and `ItemDefinition`.
Names, equipment hints, spell/enemy definitions, map outlines, dialogue and quest
steps stay in D's metadata until A/B/C agree the remaining shared schemas.
The loader validates authorship structure, not collision, combat balance,
save migrations or gameplay execution. A1's existing `ContentCatalog` is
also tested against a synthetic map and the preview state.

## Remaining integration / review gates

- **A1 (Jordan + consumers):** approve stable IDs, slot IDs and final schemas
  for spell/enemy/dialogue/quest registries. Existing menu/save contracts are
  explicitly provisional in `docs/contracts.md`.
- **A2/A3 (Jordan):** mount menus in the game shell, implement save availability
  and Continue, and serialize menu commands through the state coordinator.
- **C4 (Joseph):** supply `PartyRules` implementation and confirm job/equipment/
  resource rules. Review D's presentation and content tables.
- **B2/B4/B5 (Luke + Jordan):** implement actual maps, dialogue gates, atomic
  chest rewards, boss progression and ending triggers using agreed boundaries.
- **Review:** teammate approval and integration on main are required by the
  board's definition of Done. Leave both cards in Review / Testing, not Done.

## Validation

Run locked dependencies, formatting, analysis, full tests, and both app/preview
web release builds. `test/ui/content_test.dart` exercises malformed content and
shared adapters. `test/ui/menus_test.dart` exercises display, exact command IDs,
rejections, success, async failures, duplicate dispatch, listener replacement,
save states, New Game confirmation, keyboard dialogue/focus and layouts at
1280×720, 480×640 and 360×640. Production rules/storage and integrated quest
playthrough are outside these tests. Windows native builds need the missing
local Visual Studio C++ toolchain; CI can validate the existing Windows target.
