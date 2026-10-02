# Approved exploration maps in the main game

The production integration now loads the reviewed harbor, causeway, and cistern artwork with their matching collision polygons. Previously, the harbor image was stretched across the older tile map and the other areas still used the tile renderer. All scene rendering, movement, camera coordinates, markers, exits, and saved positions now share an 8-pixel coordinate grid. `ArtworkWorld` owns the production scene configuration; `InteractionWorld(useArtwork: true)` selects it. The default text-map harness remains available for existing isolated demos.

The causeway grass is walkable within the approved island boundary. NPCs, chest, rest points, exits, the northwest valve, and the boss approach have positions on the artwork. The player uses a neutral placeholder body and interactions use letter markers. Character and enemy concept assets remain in the repository for later art work; active exploration, introduction, and battle sprite overlays have been removed.

Completing the northwest valve dialogue sets `quest.cistern.sluice_open`. Cancelling the dialogue leaves the route closed. Opening the valve reveals only the reviewed central stone crossing and changes that crossing's collision. Other water boundaries remain blocked. The quest flag survives save/reload, and the beacon boss requires it. Existing chest, combat, reward, and story identifiers are retained.

Content version `lantern-wake.maps.2` prevents loading old saves with incompatible map coordinates. Start a new game after this update. Unsupported saves are rejected through the existing save validation; their files are not deleted.

## Validation

- Locked dependency resolution and static analysis passed.
- Full Flutter suite: 199 passed, 3 skipped.
- Web release build passed.
- Geometry tests check reachable interactions and exits, closed/open sluice connectivity, movement sweeps, dialogue cancellation, and save/reload.
- The production story-flow test checks quest completion, chest rewards, boss rewards, and save/reload using the artwork world.
- Widget verification checks all three scene dimensions, placeholder presentation, the localized sluice overlay, and a smaller viewport.
- Local Windows build could not run because the Visual Studio toolchain is absent; verify the GitHub Windows job before merging.
- Changed Dart files are formatted. The repository-wide format check reports four pre-existing untouched files: `lib/battle/demo/c5.dart`, `test/battle/c5_balance_test.dart`, `test/world/tutorial_island_map_test.dart`, and `test/world/world_encounters_test.dart`.

Screenshots at 1280 by 720 are in `docs/evidence/maps-main-harbor.png`, `maps-main-causeway.png`, `maps-main-cistern-closed.png`, and `maps-main-cistern-open.png`. They show the actual production app view. The browser preview runs the normal entry point, not the isolated map-review page.

Luke requested integration into main and removal of active sprite overlays. Shared app/content changes provide the required coordinate and quest-aware save validation; battle UI changes only remove concept art. No new battle formulas or loot were introduced.
