import 'dart:math' as math;
import 'dart:ui';

/// Pixel translation. Small maps are centered; large maps never reveal outside space.
Offset worldCameraOffset({
  required Size viewport,
  required Size mapSize,
  required Offset player,
}) {
  double axis(double view, double map, double position) => map <= view
      ? (view - map) / 2
      : (view / 2 - position).clamp(math.min(0, view - map), 0).toDouble();
  return Offset(
    axis(viewport.width, mapSize.width, player.dx),
    axis(viewport.height, mapSize.height, player.dy),
  );
}
