import '../core/contracts.dart';

const double harborSpawnPixelX = 11.5 * 1402 / 25;
const double harborSpawnPixelY = 12.5 * 1122 / 20;
const double artworkPixelsPerTile = 8.0;

WorldPosition harborEntryPosition() => WorldPosition(
  mapId: 'map.bellwether',
  x: harborSpawnPixelX / artworkPixelsPerTile,
  y: harborSpawnPixelY / artworkPixelsPerTile,
);
