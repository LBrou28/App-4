import 'package:flutter/material.dart';

/// Approved concept artwork used by the playable demo.
abstract final class SpriteAssets {
  static const explorationParty =
      'assets/sprites/concepts/exploration-party-approved.png';
  static const renDirections =
      'assets/sprites/concepts/ren-four-direction-prototype.png';
  static const battleParty = 'assets/sprites/concepts/battle-party-concept.png';
  static const regularEnemies =
      'assets/sprites/concepts/regular-enemy-concepts.png';
  static const lanternWarden =
      'assets/sprites/concepts/lantern-warden-boss-concept.png';
  static const bellwetherTownsfolk =
      'assets/sprites/townsfolk/bellwether-townsfolk-v2.png';
}

/// A single frame from Ren's four-by-four exploration sheet.
class ExplorationHeroSprite extends StatelessWidget {
  const ExplorationHeroSprite({super.key, required this.directionRow});

  final int directionRow;

  @override
  Widget build(BuildContext context) {
    const frameSize = 48.0;
    const sheetSize = frameSize * 4;
    return SizedBox(
      width: frameSize,
      height: frameSize,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: sheetSize,
          maxWidth: sheetSize,
          minHeight: sheetSize,
          maxHeight: sheetSize,
          child: Transform.translate(
            offset: Offset(
              -frameSize,
              -frameSize * directionRow.clamp(0, 3).toDouble(),
            ),
            child: Image.asset(
              SpriteAssets.renDirections,
              width: sheetSize,
              height: sheetSize,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.none,
            ),
          ),
        ),
      ),
    );
  }
}

class ExplorationPartyArtwork extends StatelessWidget {
  const ExplorationPartyArtwork({super.key});

  @override
  Widget build(BuildContext context) => Image.asset(
    SpriteAssets.explorationParty,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.none,
    semanticLabel: 'The four Bellwether keepers',
  );
}

/// One resident from the two-by-two Bellwether townsfolk sheet.
class BellwetherTownspersonSprite extends StatelessWidget {
  const BellwetherTownspersonSprite({super.key, required this.variant});

  final int variant;

  @override
  Widget build(BuildContext context) {
    final row = variant.clamp(0, 3) ~/ 2;
    final column = variant.clamp(0, 3) % 2;
    const height = 52.0;
    const cellWidth = 78.0;
    const cropWidth = 44.0;
    const horizontalInset = (cellWidth - cropWidth) / 2;
    return SizedBox(
      width: cropWidth,
      height: height,
      child: ClipRect(
        child: Align(
          alignment: Alignment.topLeft,
          child: Transform.translate(
            offset: Offset(
              -(column * cellWidth + horizontalInset),
              -row * height,
            ),
            child: Image.asset(
              SpriteAssets.bellwetherTownsfolk,
              width: cellWidth * 2,
              height: height * 2,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.none,
            ),
          ),
        ),
      ),
    );
  }
}

class BattlePartyArtwork extends StatelessWidget {
  const BattlePartyArtwork({super.key});

  @override
  Widget build(BuildContext context) => Image.asset(
    SpriteAssets.battleParty,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.none,
    semanticLabel: 'The party prepares for battle',
  );
}

class EncounterArtwork extends StatelessWidget {
  const EncounterArtwork({super.key, required this.isBoss});

  final bool isBoss;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.asset(
      isBoss ? SpriteAssets.lanternWarden : SpriteAssets.regularEnemies,
      fit: BoxFit.cover,
      alignment: isBoss ? Alignment.center : Alignment.center,
      filterQuality: FilterQuality.none,
      semanticLabel: isBoss
          ? 'The Hollow Bell, lantern warden boss'
          : 'Creatures of the Lantern Trail',
    ),
  );
}
