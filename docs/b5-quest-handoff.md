# B5 quest-completion handoff

B5 turns the authored `quest.lantern` rows into world operations without
changing the content IDs or the save schema. `QuestPlacement` binds each step
to a B interaction target, while the controller remains the only writer of
`GameState.quests.flags`.

## Demo flow

1. Finish Keeper Mara's `dialogue.call` to set
   `quest.lantern.accepted`. Closing it does not set the flag.
2. Sable and the Cistern threshold become available after acceptance. They are
   guidance-only dialogues and do not grant a flag.
3. Interact with the purple `!` beside the Hollow Bell. The accepted quest
   launches the registered `enemy.hollow_bell` battle. Victory commits
   `quest.lantern.bell_awake` with the combat rewards, then opens Iona's
   `dialogue.bell`. Closing the followup preserves that victory; the boss
   cannot be challenged or rewarded again. Defeat and fleeing do not set it.
4. Finish Mara's `dialogue.ending` after the bell-awake flag is present to set
   `quest.lantern.complete`.

Each accepted operation publishes one coherent revision. Ordinary quest
dialogue remains completion-only; its cancellation cannot grant a flag.
Encounter-backed flags commit with the first matching victory, including
Lantern Link's authoritative result. Duplicate snapshots do not replay the
followup. Flags persist through the existing save codec with no schema change.

## A3 integration

Register C5's `LanternBalance().createSession` under the authored encounter
IDs once A3 supplies the production party state. B5 already requests the
stable `enemy.hollow_bell` ID and accepts C's terminal result exactly once; it
does not duplicate C5's XP, job progress or gold rewards. The final A3
round-trip test should finish this sequence, save, reload, and confirm all
three flags remain set.
