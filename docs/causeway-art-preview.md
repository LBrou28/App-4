# Saltglass Causeway art and collision preview

Map 2 follows Luke's annotated collision review from October 1, 2026.
Red indicates solid terrain and props; green indicates objects to remove.

The cleaned artwork removes the right-hand central bridge lantern/post and
the chained stone pillar above the eastern stairs. The left bridge lantern,
camp, chest, other lanterns, ruined arch, stairs and surrounding scenery remain.
The original artwork is retained; the edited version is a separate asset.

## Run and review

```powershell
flutter run -d chrome -t lib/world/demo/causeway_art_main.dart
```

Use WASD, arrows, or the on-screen direction buttons. Collision boundaries and
Whole map are independent switches. Turn Whole map off for the following
camera view. Jump to area provides six inspection locations; Reset returns
to the harbor entrance. The footer shows the marker's foot coordinates.

Both drawing and movement use the original 1254 × 1254 artwork coordinate
space. Collision checks a small foot footprint, with swept movement to prevent
skipping through walls. Red lines follow land, stair, bridge and cliff edges.
Retained props have separate solid footprints. The top of the ruined arch is
blocked as marked, while its approach remains accessible.

Luke's follow-up expands movement across the grassy ground on all five land
shelves, including flowers and low grass beside the trail. Collision follows
the inside of the cliff rims rather than confining players to the dirt path.
Water, cliff faces, elevation changes, walls and retained props remain solid.
The gate pillars can be walked around on the surrounding level grass, while
different terraces still connect using the stairs. The dead tree has a small
trunk footprint; its upper branches do not block the surrounding ground.

Verified routes cover entrance → bridge → northeast exit in both directions,
the campsite/chest approach, northwest stairs/arch, and right-hand overlook.
Water, cliffs, bridge parapets, camp objects and retained posts stay solid.

This is the same kind of standalone collision review as the harbor preview.
Production map IDs, quest triggers, encounters and sprite integration remain
in their existing code; this preview does not replace them. The yellow marker
is a review aid, not a new character design.

## Art edit provenance

Tool: built-in ImageGen, precise object edit with the clean source and Luke's
annotated image as references. The clean source was
`exec-54b825d3-6dcf-41b2-b2f2-9ce87094e323.png`; output was
`exec-77fd1a48-bd8e-41d2-ad93-6b062aa6f23d.png`.
Both generated originals are retained in the local image archive.

Prompt intent: use the clean source as the target and the annotated image only
as an instruction guide. Remove the entire right-hand bridge wooden lantern
fixture and the freestanding chained stone pillar near the right stairs.
Replace their footprints with matching paving/dirt. Preserve all other lamps,
the chest/campsite, stairs, ruined arch, water, cliffs, palette, framing and
layout. Do not add annotation marks or extra scenery.

Asset: `assets/maps/saltglass_causeway_green_removed.png`.

## Validation

- `flutter analyze --no-pub`: clean.
- Full `flutter test --no-pub`: 197 passed, three existing skips.
- Five map 2 geometry tests verify connected routes, walkable grass and blocked terrain/props.
- Dart formatting of all three new Dart files: clean.
- Release web build of `causeway_art_main.dart`: passed; Wasm dry run passed.
- The production Windows executable was not rebuilt for this standalone preview.
- Grass revision: targeted analysis and both map geometry suites rerun; full
  project suite above describes the preceding preview revision.
