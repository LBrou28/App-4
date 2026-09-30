# D3 asset manifest — The Lantern Wake

All currently shipped visual placeholders are programmatic Flutter artwork,
created in this repository. They are original and require no attribution.

## Shared visual contract

| Asset group | Dimensions | Naming / frame contract |
| --- | --- | --- |
| World tiles | 48 × 48 logical pixels | `tile_<terrain>_<frame>`; animate compatible tiles at 333 ms. |
| Hero sprites | 32 × 32 logical pixels | `hero_<job>_<direction>_<frame>`; idle plus 2–4 walking frames. |
| Enemy sprites | 48 × 48 logical pixels | `enemy_<id>_<frame>`; idle, lunge, hit and defeat states. |
| UI icons | 24 × 24 logical pixels | Material icons until the final original pixel set is delivered. |
| Effects | 48 × 48 logical pixels | `fx_<effect>_<frame>`; keep collision independent of a frame. |

Palette: deep sea `#101D29`, panel `#172936`, muted teal `#344752`,
lantern gold `#E7C482`, readable text `#D3E6DF`. Do not use color as the
only status signal; retain labels and icons.

## Audio event IDs

The controls are registered now; final original/licensed `.ogg` files will be
bound to these IDs without changing game code:

`music.exploration`, `music.battle`, `ui.select`, `world.step`,
`world.interact`, `world.chest`, `battle.attack`, `battle.hit`,
`battle.spell`, `battle.victory`.

Music and effects have separate, pause-safe toggles in Settings. Audio must
respect these toggles and never restart a paused action. Any third-party asset
added later must list source URL, license and author in this document.

## Water animation direction

Use seamless `tile_water_0`, `tile_water_1`, and `tile_water_2` frames at
250–400 ms. Shorelines, docks and rocks stay static; foam-edge tiles are
separate. Collision must not change between animation frames.
