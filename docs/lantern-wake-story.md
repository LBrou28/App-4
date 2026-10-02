# The Lantern Wake — alpha story

Confirmed with Luke on October 2, 2026. This is the current narrative reference;
older demo handoffs remain historical records.

## Before the game

Lantern Master Alden Vale carried one tide lantern between the island shrines.
Every year, he returned its light to Bellwether's harbor shrine to renew the tide.
He was killed generations ago, and the lantern was corrupted. Its darkness has
spread slowly along his old route, affecting numerous islands. Bellwether's tide
has only now failed, stranding its boats and exposing the harbor shore.

The killer's identity remains a mystery. The Hollow Bell was a guardian of the
beacon; corruption turned it into the lantern's jailer. Defeating it does not
reveal who murdered Alden.

## Playable story

1. Keeper Mara waits beside Bellwether's empty harbor shrine. Her records point
   to the lost lantern in the Tide Cistern. She asks Ada, Ren, Iona and Tavi to
   recover it and bring it home. She does not give the party the lantern.
2. The Saltglass Causeway connects the harbor to the cistern. Sable explains
   that the same corruption has affected other islands. Supplies sit beside the
   western camp, below the ruined arch; the cistern exit is to the northeast.
3. The Tide Cistern was once peaceful. Its ruined paths, dark roots and corrupted
   guardians now make it a dungeon. The northwest valve drains the central
   channel and opens the crossing to the beacon chamber.
4. The Hollow Bell occupies the chamber's middle. Alden's small, portable
   lantern rests at the back. Victory leads to the recovery dialogue; the party
   retrieves the lantern after the fight.
5. The party returns to Mara and places the lantern in the harbor shrine. Its
   warm flame returns and Bellwether's tide begins to recover. The other islands
   still need its light, setting up the next journey and the unresolved murder.

Mara's repeat dialogue speaks about the island shrines and carrying the light
onward. It remains valid after quest acceptance, completion and save/reload.
The harbor bell is scenery; ringing a bell is not the quest objective.

## Implementation boundaries

The player-facing version is alpha, following the submitted demo. The title,
opening, pause lore, NPC dialogue, map objectives and battle heading all use
The Lantern Wake. Title-screen art/layout and Lantern Link stay in place.

This pass changes narrative presentation, not progression, rewards, collision,
encounter placement, artwork or save contracts. Existing authored IDs and save
versions stay stable. In particular, `quest.lantern.bell_awake` is the legacy
internal flag for recovering the lantern after defeating the Hollow Bell;
`quest.lantern.complete` means the lantern was returned to the harbor shrine.
There is no new inventory item or additional playable island in this pass.
