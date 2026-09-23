# B1 exploration prototype sketch

Owner: Luke Broussard (Role B).
Card: https://trello.com/c/HoKeQKvy/11-b1-build-map-rendering-movement-and-collision

Status: proposal for review, not a runtime map or an agreed shared schema.
Luke confirmed 2D top-down exploration on September 22, 2026. Runtime engine
integration and data formats still need coordination with A1/A2.

## Small test area

A 16-column by 12-row room, with zero-based coordinates. `#` is blocked,
`.` is walkable, and `S` marks the proposed initial position at (2, 2).
The spawn tile is also walkable. The perimeter is closed for B1; map exits
belong to B3.

```text
################
#..............#
#.S............#
#......#.......#
#......#.......#
#......#.......#
#......#.......#
#......####....#
#..............#
#..##..........#
#..............#
################
```

The vertical wall supports head-on collision and sliding/passing tests.
The L-shaped corner exercises corner clipping. The small block near the
bottom provides a second obstacle. All walkable tiles connect to the spawn.

## Proposed prototype presentation

Use simple, distinct floor, wall, and player shapes until D supplies art.
Keep the player distinguishable by shape as well as color. Proposed controls:
arrow keys or WASD, plus four labeled on-screen direction buttons. Keep the
buttons outside the map viewport so they cannot obscure the player.

Choose tile size, player footprint, movement speed and camera behavior after
the primary platform and demo resolution are agreed. Rendering should consume
map data separately from movement logic. Use this room with both a viewport
smaller than the map and a viewport larger than the map for camera checks.

Do not register this Markdown sketch as a Flutter asset. A later B1 commit
will add runtime data using the reviewed format. Town, route, dungeon, NPCs,
chests, encounters and story content remain in B2-B5 and D4.
