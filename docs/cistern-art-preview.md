# B4 Drowned Cistern artwork / collision preview

Status: Luke approved the playable preview and authorized its commit and push. Production world integration remains pending.
Branch: `codex/b4-harbor-art-collision`, based on map 2 commit `ff4654e`.

## Luke's instructions

- Red marks describe solid ruins, cliff faces, water, gates, columns and retained props.
- Green means remove the marked item; no explicit green removal marks were found on this map 3 guide.
- Both yellow-marked obstructions are replaced with regular continuous ground: the lower-left entrance connector and the eastern corridor corner.
- Grass and moss on flat ground remain walkable, as in map 2. Different heights connect through stairs and bridges.
- Luke confirmed that operating the northwest valve opens the central sluice route to the beacon chamber.
- Keep the small lantern at the back and the center of the boss room clear.

## Assets and rendering

- `assets/maps/drowned_cistern_paths_v2.png`: cleaned, closed-sluice map.
- `assets/maps/drowned_cistern_open_sluice_v2.png`: source artwork for the open center passage.
- Both are 1254 × 1254. The generated originals remain preserved.
- The closed map is always the base image. When open, only the rectangle x578–676, y385–582 is composited from the open source, avoiding whole-map changes between states.
- Built-in ImageGen was used for both raster edits. These are versioned new files.

## Try it

```powershell
flutter run -d chrome -t lib/world/demo/cistern_art_main.dart
```

Current local release preview: http://127.0.0.1:8920/

WASD / arrow keys or touch arrows move the neutral test marker. Collision uses a 6px foot footprint and swept steps up to 2px. Toggle collision boundaries or whole-map view. The camera follows the marker when whole-map view is off.

Walk the western detour to the northwest valve and press E, or use **Turn valve (E)** when nearby. Activation drains the central waterfall and exposes the stone passage. Other waterways remain blocked. **Reset run** returns to the entrance and closes the sluice.

**Jump to area** is a review shortcut. The beacon chamber shortcut becomes available only after activation.

The valve is local preview state; production quest flags, host operations, combat, chest rewards and save migration are not changed by this test.

## Validation

- Geometry routes: entrance ↔ main junction, western detour ↔ valve, eastern connector ↔ chest, closed/open center passage ↔ beacon chamber.
- Solid props, cliff rims and unaffected water remain blocked; flat courtyard grass is clear.
- Widget test: remote E cannot open the sluice, nearby E opens it once, reset closes it and restores the entrance.
- Widened-art revision full suite: 208 passed, 3 skipped.
- Final three collision-only corrections: all 11 targeted geometry/UI tests passed; analyzer clean. The full suite was not repeated for this final small geometry adjustment.
- Static analysis: no issues.
- New files pass formatting. The full-repository format check flags five untouched existing files: `lib/app/game_app.dart`, `lib/battle/demo/c5.dart`, `test/battle/c5_balance_test.dart`, `test/world/tutorial_island_map_test.dart`, and `test/world/world_encounters_test.dart`. No unrelated formatting changes were made.
- Release web build of this preview passed.
- Browser at 1280 × 720: assets render, E activates the valve, the center overlay and boundaries update, keyboard movement works, and reset restores the closed state.
- This web-only preview introduces no Windows-specific code; Windows build was not run for this local review.

Review screenshots: `docs/cistern-open-preview-v2.png` and `docs/cistern-closed-preview-v2.png`.

## Widened route revision

Luke requested wider routes and corrected two cropped areas. The lower-left connection is solid ground; the western crossing joins a broad, pillar-free central landing. Western stairs and the valve approach are wider. The central valve-opened passage also has more steering room.

Tests walk multiple parallel lines across the lower connection, western crossing, valve stairs and open passage. Collision follows the revised ground edges; water below the central landing remains blocked. Original v1 assets are retained locally as prior versions; the approved v2 assets are included in this commit.

Final collision-only follow-up smooths the eastern bend and western crossing and removes the small wall sliver at the western upper connection. No further artwork changes were made.

## Exact image edit prompts

### Yellow path edits
Use case: precise-object-edit.
Asset type: existing 1254x1254 top-down pixel RPG dungeon exploration map.
Input images: Image 1 is the clean EDIT TARGET. Image 2 is ONLY the user's annotated instruction guide; never copy its colored marks.
Primary request: make ONLY the two yellow-marked passages visibly continuous and traversable, removing the interfering stone pillar/wall pieces and replacing their footprints with matching worn cobblestone/dirt paths. (1) Lower-left connector near the entry gate, bounded approximately x302-411,y943-1061 in Image 1: remove the tall mossy stone column and short obstructing wall pieces in this yellow region. Make a clearly continuous 50-65px-wide horizontal stone/dirt path from the existing entrance landing around x275,y1030 to the existing central-island connector around x465,y1035. Keep the flanking gate pillars, fence, water, and outer cliffs. (2) Eastern lower connector, around x925-1015,y630-725 in Image 1: remove the stone column/wall return obstructing the regular land path at this yellow mark. Replace it with a clean, gently bending cobbled route at least 50px wide joining the main east-west corridor around x850,y755 to the eastern stair landing around x990,y660. Do not turn water channels into new ground; clear only the obstructing column/wall on existing land. Preserve the actual staircase.
Constraints: preserve the exact rest of the layout, all rooms, stairs, paths, stone bridges, wooden sluice gates and posts, valve at top left, chest at upper right, small lantern at the back of the boss room, ruins, grass/moss, dark water, waterfalls, palette, pixel scale, framing and perspective. The boss room center stays empty. Do not move or enlarge other features. No colored annotations, no text/UI, no characters or new scenery. Return the clean edited map at the same framing and proportions.

### Open center sluice
Use case: precise-object-edit. Asset: open-sluice state for the same top-down pixel RPG dungeon. Image 1 is the edit target, the cleaned map with the two yellow-marked paths already opened. Change ONLY the NARROW VERTICAL CENTRAL SLUICE CHANNEL between the boss-room entrance stairs at x595-665,y340-410 and the lower approach stairs at x598-660,y525-581, using the 1254x1254 image coordinates. The northwest valve has been activated: lift/retract ONLY the central blocking wooden gate crossbars, drain the bright blue waterfall from this central passage, and expose a continuous 45-55px-wide worn stone causeway/stepped floor centered around x625 that joins the lower stairs to the upper stairs. Water remains on both sides; keep both sets of wooden/stone side posts and flanking cliffs. The walkable stone surface must visibly connect without gaps from y392 to y557. Use the existing pixel scale, gray worn wet cobbles, moss and lighting. Preserve every other pixel as closely as possible: both yellow-cleared paths, ALL OTHER waterways and sluices, side paths, ruins, valve at top left, chest on right, small lantern at back of boss room, empty center for boss, palette and framing. No new characters, annotations, labels or UI. Do not change other parts of the map; this is a localized open-gate overlay source.



### Widening edit
Use case: precise-object-edit.
Asset: 1254x1254 top-down pixel RPG dungeon map, closed center sluice state.
Input images: Image 1 is the clean EDIT TARGET. Images 2 and 3 are cropped screenshots identifying troublesome paths; their red collision outlines are annotations only, never render those red lines.
Primary request: widen the playable routes moderately and repair the two screenshot areas. KEEP the same map, original pixel art style, palette, perspective, boss room, small lantern, chest, northwest valve and closed central waterfall/gate.
1. Screenshot 2 / Image 3 is the WEST BRIDGE meeting the CENTRAL STAIR JUNCTION, corresponding to x425-675,y700-880 in Image 1. Replace the tiny narrow wooden bridge with a substantial continuous worn stone bridge, a 60-75px-deep walkable deck centered near y746, crossing from the west courtyard at x420 to the central ground at x590. Remove the large broken stone column and pipe clutter immediately below its eastern end around x530-585,y790-850. Rebuild that jagged notch as one simple wide stone landing, joining the bridge horizontally to the central north/south stairs, with smooth straight cliff edges and a clearly readable route. Existing water beyond the widened bridge and landing stays water. No narrow U-shaped detour around a pillar.
2. Screenshot 1 / Image 2 is the LOWER-LEFT ENTRANCE CONNECTION, around x300-500,y980-1090 in Image 1. Replace this pinched connector with an uninterrupted 65-80px-wide horizontal stone/dirt causeway, joining the entrance landing near x275,y1040 to the central lower landing near x500,y1040. Clear the fence/wall/post pieces intruding into this connector's walkable band. Keep the west entrance gate, exterior cliffs and the main lower central stairs. This is ordinary solid ground, no gate or gap in this connector.
3. Widen the NORTHWEST VALVE APPROACH and west route stairs: provide a clear 65-75px-wide stone staircase/walking surface on the existing west corridor around x245-300,y210-385, and around x240-308,y495-575. Enlarge the floor directly in front of the valve at x220-318,y183-235. Shift the side stone railings/cliff rims outward only as needed. Keep the valve exactly where it is at x265,y150; allow approaching it from the stairs. Also widen the other obviously tight horizontal stone bridge/path surfaces slightly to roughly 55-65px where possible while retaining the intended layout and water separations.
Constraints: changes are localized to these traversal improvements. No new routes across other water channels, no moved rooms, no added props, no changed storyline, no new characters/text/UI/annotations. Center sluice stays CLOSED with waterfall and wooden gate intact. Preserve the boss arena, chest, northwestern valve and all unaffected ruins and scenery; same 1254x1254 framing, same pixel size and style.

### Landing/post correction
Use case: precise-object-edit. Image 1 is the revised clean 1254x1254 dungeon map EDIT TARGET.
Make TWO small corrections only. (1) Remove the broken, squat mossy ROUND STONE COLUMN at approximately x518-577,y785-882, immediately LEFT of the central vertical stairway in the lower-middle of the image. Its cap is around x545,y810 and its mossy round base is around x550,y872. This is NOT any column in the western courtyard and NOT the tall columns surrounding the upper boss room. Remove the entire specified column and any small pipe/clutter attached to that footprint. Replace its footprint with matching flat worn cobblestone floor joined to the existing central landing and WEST stone bridge. Extend that landing smoothly west to x490, north to y746, and south to y874, with a simple straight stone cliff retaining edge at x490. The player should be able to walk STRAIGHT across the western stone bridge at y746 to the main stairs without a notch, narrow detour or pillar in the ground, and walk comfortably on the side of the central stairs. (2) Remove ONLY the intruding southeast post of the lower-left iron entrance gate around x335-364,y994-1048, where it projects into the newly widened horizontal path around y1035. Replace its footprint in that path with ordinary cobblestone. Preserve the rest of the entrance gate.
All other pixels stay as close as possible to Image 1. Preserve the new wide western stairs and valve approach, the widened lower-left connection, all other water gaps and walls, the closed center sluice/waterfall, boss arena, lantern and chest. Preserve exact framing, scale, palette and pixel style. No new routes elsewhere or changed scenery. No UI, labels, red marks or characters.

### Wider opened sluice
Use case: precise-object-edit. Image 1 is the revised clean dungeon map EDIT TARGET, 1254x1254.
Create its northwest-valve-activated state by editing ONLY the center sluice passage at x578-676,y385-582. Retract the wooden crossbar gate and drain the bright central waterfall; expose a continuous worn stone walkway centered on x627 from the upper boss entrance stairs (y392) to the lower approach stairs (y566). Make the visible walkable floor about 65-70px wide, approximately x593-662. Move the INNER edges of the passage's side posts/rails just outward enough for that clear floor, retaining those posts and water on both sides. Join it seamlessly to the existing upper and lower stairs with no waterfall gaps. Preserve exact pixel scale, wet gray stones, palette and lighting.
Every other pixel stays as close as possible to Image 1. In particular preserve the now-wide western stairs, the solid lower-left path, the broad western stone bridge and pillar-free central landing, the valve, chest, boss room and small lantern. Do not change any other waterway or sluice. No new characters, props, text or UI. This will be rendered as a localized center-passage overlay, so exact alignment and preserved framing matter.
