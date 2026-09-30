# B4 tutorial-island map pass

The playable demo now uses authored geometry for the first island. B4 owns the
tile layout, collision, spawn placement, exits, and visual landmark markers.
It does not create quest flags, story events, battle triggers, or rewards.

## Playable route

`Bellwether Harbor` is a compact harbor square with a west rest house, central
lantern, dockside obstruction, Mara, Orrin, and an east exit to the route.

`Saltglass Causeway` is a wider coastal route. It has a north supply spur,
sheltered bench, central sea-stack obstacle, a return exit south-west, and a
cistern exit to the east.

`Tide Cistern` has a left entrance/rest alcove, a narrow opening through the
dry-well divider, a marked threshold, and a bell chamber to the east. Its west
exit returns to Saltglass.

## Stable integration points

The following identifiers are unchanged from B2/B3:

- Maps: `map.bellwether`, `map.salt_path`, `map.tide_cistern`
- Exits: `exit.harbor_to_causeway`, `exit.causeway_to_harbor`,
  `exit.causeway_to_cistern`, `exit.cistern_to_causeway`
- Interactions: `npc.mara`, `npc.orrin`, `npc.sable`,
  `chest.causeway_supplies`

`WorldLandmark` adds non-interactive, visual-only map markers. A, C, and D may
bind future story or gameplay behavior to their own operations after agreeing
on a contract; B4 intentionally makes no such bindings.
