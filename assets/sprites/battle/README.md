# Transparent battle enemy sprites

These sibling PNGs were extracted from the approved concept sheets using the
built-in image_gen tool on October 2, 2026. Original concept assets are preserved.
They contain both small exploration and large battle depictions; EncounterArtwork
samples only one large depiction per stable enemy ID. Canvas sizes and source
regions are declared in lib/ui/sprite_art.dart. Alpha is preserved; no Python
image edits or re-encoding were used.

## Sources and outputs

- concepts/regular-enemy-concepts.png -> battle/regular-enemies-transparent.png
  (1983 x 793 RGBA): Brine Mite, Wick Moth and Silt Guard.
- concepts/lantern-warden-boss-concept.png -> battle/hollow-bell-transparent.png
  (1536 x 1024 RGBA): The Hollow Bell.

## Final prompt set (built-in mode; transparent_background=true)

### Regular enemies

Use case: background-extraction. Edit target: attached existing enemy sprite
concept sheet. Remove ONLY the dark blue background, gradient, ground shadows,
and ground texture, replacing all surrounding space with actual transparent
alpha. Keep all six original enemy depictions exactly as they are: small crab,
large crab, small moth, large moth, small armored guardian, large armored
guardian, in the same positions and relative sizes. Preserve canvas aspect ratio
and composition and generous separation. Preserve the existing pixel art shapes,
palette, details, faces and silhouettes unchanged; do not redraw, enhance, add
detail, add text, add frames, or add other objects. This will be sampled as
individual game sprites. Each sprite and its intrinsic magical glow must remain
fully visible without cropping.

### Hollow Bell

Use case: background-extraction. Edit target: attached existing Hollow Bell boss
sprite concept sheet. Remove ONLY the dark blue background and ground shadows,
replacing the surrounding space with actual transparent alpha. Keep BOTH
existing boss depictions, the small exploration boss on the left and larger
battle boss on the right, at the same positions and relative sizes. Preserve
the original canvas aspect ratio. Preserve all original pixel art shapes,
colors, bell armor, seaweed, lantern and intrinsic teal magical effects
unchanged. Do not redesign or add detail. No text, frames, scenery or new
objects. Preserve generous empty transparent space separating the two
depictions and keep their complete silhouettes visible.

These are generated background extractions, not guaranteed pixel-identical
masks. Review visible edges at the in-game display size before approving.
