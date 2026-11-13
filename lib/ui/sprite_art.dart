import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Approved artwork and extracted battle sprites used by the alpha.
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
  static const battleEnemies =
      'assets/sprites/battle/regular-enemies-transparent.png';
  static const battleBoss = 'assets/sprites/battle/hollow-bell-transparent.png';
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
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: cellWidth * 2,
          maxWidth: cellWidth * 2,
          minHeight: height * 2,
          maxHeight: height * 2,
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

/// Select one battle-sized creature, never the full exploration/concept sheet.
class EncounterArtwork extends StatelessWidget {
  const EncounterArtwork({super.key, required this.enemyId});
  final String enemyId;

  static const regions = <String, Rect>{
    'enemy.brine_mite': Rect.fromLTRB(210, 288, 640, 612),
    'enemy.wick_moth': Rect.fromLTRB(890, 170, 1260, 594),
    'enemy.silt_guard': Rect.fromLTRB(1494, 170, 1956, 638),
    'enemy.hollow_bell': Rect.fromLTRB(540, 0, 1536, 1024),
  };

  @override
  Widget build(BuildContext context) {
    final region = regions[enemyId];
    // Practice/test rosters have no approved art; do not impersonate a campaign
    // enemy or display every creature just because their IDs are unknown.
    if (region == null) return const Icon(Icons.pest_control, size: 48);
    final boss = enemyId == 'enemy.hollow_bell';
    final sheet = boss ? const Size(1536, 1024) : const Size(1983, 793);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(
          constraints.maxWidth / region.width,
          constraints.maxHeight / region.height,
        );
        return Center(
          child: SizedBox(
            width: region.width * scale,
            height: region.height * scale,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: sheet.width * scale,
                maxWidth: sheet.width * scale,
                minHeight: sheet.height * scale,
                maxHeight: sheet.height * scale,
                child: Transform.translate(
                  offset: Offset(-region.left * scale, -region.top * scale),
                  child: Image.asset(
                    boss ? SpriteAssets.battleBoss : SpriteAssets.battleEnemies,
                    width: sheet.width * scale,
                    height: sheet.height * scale,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.none,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
