# C1: deterministic battle rules

Card: https://trello.com/c/2m5KFQi7/16-c1-build-the-deterministic-turn-based-battle-rules

This pure Dart engine implements C1's Attack/Defend rounds without UI. It lives
entirely in C's module and starts from main. It does not import the provisional
A1 combat types or replace A's authoritative application state. A1 combat
integration and T0 balance decisions remain open; these are proposed C1 rules
for review by Luke (peer reviewer) and Jordan (integration owner).

## Use

Import `package:app_4/battle/battle.dart` (use a `battle` prefix when also importing
shared contracts, which have similarly named action/outcome types).

1. Create one `BattleEngine` per encounter with four hero roster entries, one or
   more enemies, and an injected `Random(seed)`. Zero-HP heroes remain in the roster.
2. Read `snapshot`. Collect one `HeroCommand.attack(actorId, targetId)` or
   `HeroCommand.defend(actorId)` for each living hero.
3. Call `resolveRound(expectedRound: snapshot.round, commands: commands)` once
   all selections are ready. Retain the round number from when selections began;
   do not relabel delayed commands with the latest round number.
4. Render the returned immutable events and snapshot. Collect the next round
   only if the outcome is `ongoing`. Terminal engines reject further resolution.

Commands are encounter-local: never send queued input from an old engine to a new
one. The caller owns the engine lifetime and pending selections. This engine has
no callbacks or asynchronous work. It resolves the round synchronously and
publishes the complete snapshot after resolution; UI animation consumes events.

## Proposed C1 rules

- Four hero entries, at least one enemy, globally unique nonblank IDs. HP starts
  in `[0, maxHp]`; maxHp is positive; attack, defense and speed are nonnegative.
- Every living actor acts once. Sort by descending speed; equal speed favors
  heroes, then original roster order within the same side. Command-list order
  does not affect action order.
- Damage is `max(1, attack - defense + variance)`, where variance is the next
  `random.nextInt(3) - 1` (uniform -1, 0 or 1). No crits, misses or healing in C1.
  Each resolved attack draws once. Defend, skipped actions and rejected input
  consume no randomness. Inject a dedicated RNG; do not share it with world/UI.
- Defend reduces incoming damage for the entire selected round, including faster
  enemies, to `ceil(damage / 2)`. It expires at round end and does not stack.
- Attack requires a known enemy ID. Unknown or friendly targets reject the entire
  command batch. A known enemy already at zero HP, or defeated earlier this round,
  retargets to the first living enemy in original roster order.
- C1 enemies attack the first living hero in original roster order. Richer enemy
  behavior, items, magic and fleeing belong to C3.
- Actors already knocked out at round start neither select nor enter turn order.
  An actor knocked out before its queued action emits `skippedKnockout` and does
  nothing. HP clamps to zero; event damage reports actual HP lost, not overkill.
- After every attack, stop immediately if one side has no living actors. No later
  action or RNG draw occurs. An initially defeated roster is already terminal;
  if both sides start defeated, defeat takes precedence.
- Validate the full batch before changing state or using RNG: exactly one command
  per living hero, no unknown/duplicate/enemy/knocked-out actors. Invalid batches
  throw `ArgumentError`. Stale round tokens and terminal submissions throw
  `StateError`. Successful ongoing rounds advance the round number; replaying a
  previous token cannot resolve commands twice.
- Snapshots, combatants and event lists are immutable. Previously returned
  snapshots remain unchanged as the engine advances.

Reproducibility is for the same roster order, commands, seed and RNG implementation.
Dart's `Random` algorithm is not a persisted cross-SDK replay format. Pin the SDK
for replay tests or inject a versioned RNG if durable replays are needed later.

## Integration handoff / remaining decisions

A1 PR #3 currently provides provisional BattleInput/BattleCommand/BattleResult
objects. No production adapter is included: it needs agreed sources for speed,
attack/defense and encounter rosters, and agreement on snapshot/reward ownership.
The local snapshot carries only combat state; inventory, jobs, XP, gold, quests
and world position stay outside C1. C4 owns progression. A future adapter must
preserve encounter ID/base revision and party identities, and return the agreed
final snapshot once without applying rewards twice.

Before integration, Jordan/Joseph should confirm the A1 combat boundary and T0
combat choices; Luke should review the proposed turn, damage, Defend and retarget
rules here. Fixture stats in tests are synthetic, not approved game balance or
D's content. Keep C1 awaiting review/integration rather than marking it Done.

## Verification

`test/battle/battle_test.dart` exercises complete UI-free battles, full seeded
transcripts, exact damage, speed/ties, Defend duration, retargeting, knockouts,
initial and resulting terminal outcomes, stale/invalid commands, RNG non-use on
rejection, HP clamping and immutable snapshots.

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
flutter build web --release --no-pub
```

There is no visible app change, so no screenshot is required for C1. The default
entry point remains the existing starter until A2 integration.
