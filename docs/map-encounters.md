# B3 follow-up: walking encounters

Card: https://trello.com/c/FLT8q1mo

The alpha now connects its artwork maps to the existing movement-based encounter
policy and production C3/C5 sessions. Bellwether is safe. Saltglass uses the
content-authored Brine Mite and Wick Moth; the Tide Cistern uses Silt Guard.
The Hollow Bell is excluded from the random pool and remains the quest encounter
in the beacon chamber, gated by the northwest valve.

## Pacing and safe areas

A check occurs after 64 artwork pixels of committed travel (8 world units),
with a 1-in-5 chance. New Game, Continue and entering a different map provide
three checks of grace (192 pixels of danger-area travel). Every accepted fight
adds six checks of cooldown (384 pixels minimum), including a successful flee.
Cooldown is runtime pacing, not a new save field. Saving/reloading does not
launch a battle or reapply rewards; Continue starts fresh entry grace.

All terrain already approved as walkable, including grass, is eligible. Entrances
have an 80-pixel safe radius. Interaction reach plus a 24-pixel buffer (minimum
64 pixels), camp/supplies/rest landmarks (80 pixels), and the beacon chamber
are excluded. Safe areas do not consume encounter cooldown. Pushing a wall,
idling, pause/dialogue/loading/battle/game-over and the Lantern Link guest gate
cannot roll. Accepted exits are handled before encounter checks. Battle return
clears held movement and preserves the exact captured position.

The policy lives once per loaded session and survives map changes and ordinary
widget rebuilds. Only AppController requests/accepts battles, and LanternBalance
supplies combat, XP, job progress and gold. No combat formulas, quest flags,
collision polygons, save schema or character designs were changed.

## Enemy presentation

Battle cards use the individual enemy ID to select a region from the transparent
battle sprite assets, not the entire concept sheet. Each card shows only its
battle-sized creature. The boss shows only the large Hollow Bell depiction.
Unknown practice/fixture IDs have an icon rather than misleading campaign art.
Ren and the party/exploration rendering remain as before.

See assets/sprites/battle/README.md for the source art and extraction prompts.

## Review

Review pacing on the trip to the northwest valve, particularly after several
fights without returning to the harbor. Combat numbers remain C5's existing
balance. A/Jordan should review session lifecycle, save/reload and Lantern Link
host/guest behavior; C/Joseph should review pacing and rewards; D/Trey should
review enemy cutout edges and sizing. B5's valve animation/restored-harbor visual
feedback remains its separate follow-up.
