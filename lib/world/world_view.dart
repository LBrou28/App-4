import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app/world_view_builder.dart';
import '../core/contracts.dart';
import '../ui/sprite_art.dart';
import 'artwork_world.dart';
import 'cistern_geometry.dart';
import 'world_camera.dart';
import 'world_controller.dart';
import 'world_map.dart';
import 'world_encounters.dart';
import 'world_interactions.dart';

/// Bind the map once; A2 supplies its stable host/notifier through the shared typedef.
WorldViewBuilder worldViewBuilder(MapDefinition map) =>
    (context, host, changes) =>
        WorldView(map: map, host: host, changes: changes);

class WorldView extends StatefulWidget {
  const WorldView({
    super.key,
    required this.map,
    required this.host,
    required this.changes,
    this.encounters,
    this.interactions,
    this.landmarks = const [],
    this.mapName,
    this.artwork,
  });
  final MapDefinition map;
  final WorldHost host;
  final Listenable changes;
  final EncounterStepper? encounters;
  final WorldInteractions? interactions;
  final List<WorldLandmark> landmarks;
  final String? mapName;
  final ArtworkWorld? artwork;

  @override
  State<WorldView> createState() => _WorldViewState();
}

class _WorldViewState extends State<WorldView>
    with SingleTickerProviderStateMixin {
  late WorldController _controller;
  late Ticker _ticker;
  late AppLifecycleListener _lifecycle;
  final _focus = FocusNode(debugLabel: 'B1 world controls');
  Duration? _lastFrame;
  ui.Image? _mapArt;
  ui.Image? _openArt;
  String? _loadedMap;
  int _artGeneration = 0;

  static final _keys = <LogicalKeyboardKey, WalkDirection>{
    LogicalKeyboardKey.arrowUp: WalkDirection.up,
    LogicalKeyboardKey.keyW: WalkDirection.up,
    LogicalKeyboardKey.arrowDown: WalkDirection.down,
    LogicalKeyboardKey.keyS: WalkDirection.down,
    LogicalKeyboardKey.arrowLeft: WalkDirection.left,
    LogicalKeyboardKey.keyA: WalkDirection.left,
    LogicalKeyboardKey.arrowRight: WalkDirection.right,
    LogicalKeyboardKey.keyD: WalkDirection.right,
  };

  @override
  void initState() {
    super.initState();
    _attach();
    _loadMapArt();
    _ticker = createTicker(_tick)..start();
    _lifecycle = AppLifecycleListener(
      onInactive: _resetInput,
      onHide: _resetInput,
      onPause: _resetInput,
      onDetach: _resetInput,
    );
  }

  void _attach() {
    _controller = WorldController(
      host: widget.host,
      collision:
          widget.artwork?.collision(
            widget.map.id,
            flags: () => widget.host.state.quests.flags,
          ) ??
          WorldCollision(widget.map),
      speed: widget.artwork == null ? WorldController.tilesPerSecond : 14,
      encounters: widget.encounters,
      interactions: widget.interactions,
    );
    _controller.synchronize();
    widget.changes.addListener(_hostChanged);
  }

  Future<void> _loadMapArt() async {
    final generation = ++_artGeneration;
    final scene = widget.artwork == null
        ? null
        : ArtworkWorld.scenes[widget.map.id];
    _mapArt?.dispose();
    _openArt?.dispose();
    _mapArt = null;
    _openArt = null;
    _loadedMap = null;
    if (scene == null) return;
    Future<ui.Image> image(String asset) async {
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    }

    ui.Image? base, open;
    try {
      base = await image(scene.asset);
      if (scene.id == ArtworkWorld.dungeon) {
        open = await image('assets/maps/drowned_cistern_open_sluice_v2.png');
      }
      if (!mounted || generation != _artGeneration) {
        base.dispose();
        open?.dispose();
        return;
      }
      setState(() {
        _mapArt = base;
        _openArt = open;
        _loadedMap = scene.id;
      });
    } catch (error, stack) {
      base?.dispose();
      open?.dispose();
      if (mounted && generation == _artGeneration) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'world artwork',
            context: ErrorDescription('loading ${scene.asset}'),
          ),
        );
      }
    }
  }

  void _resetInput() {
    _controller.clearInput();
    _lastFrame = null;
  }

  void _hostChanged() {
    _controller.synchronize();
    if (!widget.host.movementEnabled || _controller.positionError != null) {
      _lastFrame = null;
    }
    if (mounted) setState(() {});
  }

  String get _questObjective {
    final flags = widget.host.state.quests.flags;
    if (!flags.contains('quest.lantern.accepted')) {
      return 'Talk to Keeper Mara beside the empty harbor shrine.';
    }
    if (!flags.contains(ArtworkWorld.sluiceFlag)) {
      return 'Find the lost lantern: reach the Tide Cistern and turn the northwest valve.';
    }
    if (!flags.contains('quest.lantern.bell_awake')) {
      return 'Defeat the Hollow Bell in the beacon chamber and recover Alden\'s lantern.';
    }
    if (!flags.contains('quest.lantern.complete')) {
      return 'Bring the recovered lantern to Mara at the harbor shrine.';
    }
    return 'Bellwether\'s tide is returning. Other islands still need the light.';
  }

  String? get _earlyDepartureHint {
    final flags = widget.host.state.quests.flags;
    return widget.map.id == ArtworkWorld.route &&
            !flags.contains('quest.lantern.accepted')
        ? 'Before you go: Keeper Mara is waiting beside the empty harbor shrine.'
        : null;
  }

  void _tick(Duration now) {
    final previous = _lastFrame;
    _lastFrame = now;
    if (previous != null) {
      _controller.advance((now - previous).inMicroseconds / 1000000);
    }
  }

  @override
  void didUpdateWidget(covariant WorldView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host ||
        oldWidget.changes != widget.changes ||
        oldWidget.map != widget.map ||
        oldWidget.encounters != widget.encounters ||
        oldWidget.interactions != widget.interactions ||
        oldWidget.artwork != widget.artwork) {
      oldWidget.changes.removeListener(_hostChanged);
      _resetInput();
      _attach();
      _loadMapArt();
    }
  }

  @override
  void dispose() {
    widget.changes.removeListener(_hostChanged);
    _ticker.dispose();
    _lifecycle.dispose();
    _artGeneration++;
    _mapArt?.dispose();
    _openArt?.dispose();
    _controller.clearInput();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.keyE &&
        widget.interactions != null) {
      if (event is KeyDownEvent) _interact();
      return KeyEventResult.handled;
    }
    final direction = _keys[event.logicalKey];
    if (direction == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent) _press(event.physicalKey, direction);
    if (event is KeyUpEvent) _controller.release(event.physicalKey);
    return KeyEventResult.handled;
  }

  void _press(Object source, WalkDirection direction) {
    _controller.press(source, direction);
    setState(() {}); // Facing changes even when a solid target blocks movement.
  }

  void _interact() {
    _focus.requestFocus();
    _controller.interact();
    setState(() {});
  }

  Widget _directionButton(WalkDirection direction, IconData icon) => Semantics(
    label: 'Move ${direction.name}',
    button: true,
    onTap: () {
      _focus.requestFocus();
      _press('accessible', direction);
      _controller.advance(.1);
      _controller.release('accessible');
    },
    child: Listener(
      key: ValueKey('move-${direction.name}'),
      onPointerDown: (event) {
        if (event.buttons != kPrimaryButton) return;
        _focus.requestFocus();
        _press(event.pointer, direction);
      },
      onPointerUp: (event) => _controller.release(event.pointer),
      onPointerCancel: (event) => _controller.release(event.pointer),
      child: Container(
        width: 48,
        height: 48,
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xff294048),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xff567078)),
        ),
        child: Icon(icon, color: Colors.white, size: 23),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final position = widget.host.state.position;
    final error = _controller.positionError;
    return Focus(
      autofocus: true,
      focusNode: _focus,
      onKeyEvent: _key,
      onFocusChange: (focused) {
        if (!focused) _resetInput();
      },
      child: Column(
        children: [
          if (widget.interactions != null)
            Container(
              width: double.infinity,
              color: const Color(0xff14272f),
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  Text(
                    '${widget.mapName ?? widget.map.id}  ·  E / Interact to talk or open chests',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'WAKE THE TIDE  ·  $_questObjective',
                    key: const ValueKey('quest-objective'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xffffd36e),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((_controller.interactionMessage ?? _earlyDepartureHint)
                      case final message?) ...[
                    const SizedBox(height: 6),
                    Text(
                      message,
                      key: const ValueKey('world-guidance-message'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xffcde8ef)),
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            child: Listener(
              onPointerDown: (_) => _focus.requestFocus(),
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Semantics(
                      label:
                          'Exploration map. Player at ${position.x.toStringAsFixed(1)}, ${position.y.toStringAsFixed(1)}.',
                      child: CustomPaint(
                        key: const ValueKey('world-canvas'),
                        painter: WorldPainter(
                          map: widget.map,
                          position: position,
                          showPlayer: error == null,
                          drawPlayerBody: false,
                          hideTownNpcs: true,
                          scene: widget.artwork == null
                              ? null
                              : ArtworkWorld.scenes[widget.map.id],
                          background: _loadedMap == widget.map.id
                              ? _mapArt
                              : null,
                          openBackground: _loadedMap == widget.map.id
                              ? _openArt
                              : null,
                          sluiceOpen: widget.host.state.quests.flags.contains(
                            ArtworkWorld.sluiceFlag,
                          ),
                          targets: widget.interactions?.targets ?? const [],
                          landmarks: widget.landmarks,
                          openedChests: widget.host.state.quests.openedChestIds,
                          facing: _controller.facing,
                        ),
                      ),
                    ),
                    if (error == null)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final scene = ArtworkWorld.scenes[widget.map.id];
                          final unit = scene == null
                              ? WorldPainter.tileSize
                              : ArtworkScene.displayTile;
                          final mapSize =
                              scene?.displaySize ??
                              Size(
                                widget.map.width * WorldPainter.tileSize,
                                widget.map.height * WorldPainter.tileSize,
                              );
                          final camera = worldCameraOffset(
                            viewport: constraints.biggest,
                            mapSize: mapSize,
                            player: Offset(
                              position.x * unit,
                              position.y * unit,
                            ),
                          );
                          final townsfolk = widget.map.id == ArtworkWorld.town
                              ? (widget.interactions?.targets ??
                                        const <WorldTarget>[])
                                    .where(
                                      (target) =>
                                          target.mapId == ArtworkWorld.town &&
                                          target.kind == WorldTargetKind.npc,
                                    )
                                    .toList()
                              : const <WorldTarget>[];
                          return SizedBox.expand(
                            child: Stack(
                              children: [
                                for (final npc in townsfolk)
                                  if (npc.id == 'npc.mara' &&
                                      !widget.host.state.quests.flags.contains(
                                        'quest.lantern.accepted',
                                      ))
                                    Positioned(
                                      left:
                                          camera.dx + (npc.x + .5) * unit - 15,
                                      top: camera.dy + (npc.y + .5) * unit - 74,
                                      child: IgnorePointer(
                                        child: Semantics(
                                          label: 'Quest available from Keeper Mara',
                                          child: _QuestMarker(),
                                        ),
                                      ),
                                    ),
                                for (final npc in townsfolk)
                                  Positioned(
                                    left: camera.dx + (npc.x + .5) * unit - 18,
                                    top: camera.dy + (npc.y + .5) * unit - 46,
                                    child: IgnorePointer(
                                      child: BellwetherTownspersonSprite(
                                        variant: npc.id == 'npc.orrin' ? 1 : 0,
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  left: camera.dx + position.x * unit - 24,
                                  top: camera.dy + position.y * unit - 48,
                                  child: IgnorePointer(
                                    child: ExplorationHeroSprite(
                                      directionRow:
                                          switch (_controller.facing) {
                                            WalkDirection.down => 0,
                                            WalkDirection.up => 1,
                                            WalkDirection.left => 2,
                                            WalkDirection.right => 3,
                                          },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    // A Lantern Link guest is intentionally read-only but
                    // must still be able to see the host's exploration.
                    if (error != null)
                      ColoredBox(
                        color: const Color(0x990c171c),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              error,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            color: const Color(0xff14272f),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'EXPLORE\nWASD / arrow keys\nor hold a direction',
                    style: TextStyle(
                      color: Color(0xffd3e6df),
                      height: 1.6,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (widget.interactions != null)
                  Flexible(
                    child: FilledButton(
                      onPressed:
                          widget.host.movementEnabled &&
                              _controller.interactionTarget != null
                          ? _interact
                          : null,
                      child: Text(
                        _controller.interactionTarget?.label ?? 'Interact',
                      ),
                    ),
                  ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _directionButton(WalkDirection.up, Icons.keyboard_arrow_up),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _directionButton(
                          WalkDirection.left,
                          Icons.keyboard_arrow_left,
                        ),
                        _directionButton(
                          WalkDirection.down,
                          Icons.keyboard_arrow_down,
                        ),
                        _directionButton(
                          WalkDirection.right,
                          Icons.keyboard_arrow_right,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestMarker extends StatelessWidget {
  const _QuestMarker();

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('quest-marker-mara'),
    width: 30,
    height: 30,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xffffd36e),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color(0xff14272f), width: 3),
    ),
    child: const Text(
      '!',
      style: TextStyle(
        color: Color(0xff14272f),
        fontSize: 20,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class WorldPainter extends CustomPainter {
  WorldPainter({
    required this.map,
    required this.position,
    this.showPlayer = true,
    this.drawPlayerBody = true,
    this.hideTownNpcs = false,
    this.scene,
    this.openBackground,
    this.sluiceOpen = false,
    this.background,
    this.targets = const [],
    this.landmarks = const [],
    this.openedChests = const {},
    this.facing = WalkDirection.down,
  });
  final MapDefinition map;
  final WorldPosition position;
  final bool showPlayer;
  final bool drawPlayerBody;
  final bool hideTownNpcs;
  final ui.Image? background;
  final ui.Image? openBackground;
  final ArtworkScene? scene;
  final bool sluiceOpen;
  double get unit => scene == null ? tileSize : ArtworkScene.displayTile;
  Size get mapSize =>
      scene?.displaySize ?? Size(map.width * tileSize, map.height * tileSize);
  final List<WorldTarget> targets;
  final List<WorldLandmark> landmarks;
  final Set<String> openedChests;
  final WalkDirection facing;
  static const tileSize = 48.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff0e1d24),
    );
    final offset = worldCameraOffset(
      viewport: size,
      mapSize: mapSize,
      player: Offset(position.x * unit, position.y * unit),
    );
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    if (background != null && scene != null) {
      canvas.drawImageRect(
        background!,
        Rect.fromLTWH(
          0,
          0,
          background!.width.toDouble(),
          background!.height.toDouble(),
        ),
        Offset.zero & mapSize,
        Paint()..filterQuality = FilterQuality.none,
      );
      if (sluiceOpen &&
          openBackground != null &&
          map.id == ArtworkWorld.dungeon) {
        final r = CisternGeometry.openArtRegion;
        canvas.drawImageRect(
          openBackground!,
          r,
          Rect.fromLTWH(
            r.left * ArtworkScene.zoom,
            r.top * ArtworkScene.zoom,
            r.width * ArtworkScene.zoom,
            r.height * ArtworkScene.zoom,
          ),
          Paint()..filterQuality = FilterQuality.none,
        );
      }
    } else if (scene != null) {
      // Loading art must not flash an unrelated synthetic tile map.
    } else {
      for (var y = 0; y < map.height; y++) {
        for (var x = 0; x < map.width; x++) {
          final blocked = map.blocked[y * map.width + x];
          final rect = Rect.fromLTWH(x * unit, y * unit, tileSize, tileSize);
          canvas.drawRect(
            rect,
            Paint()
              ..color = blocked
                  ? const Color(0xff30484b)
                  : ((x + y).isEven
                        ? const Color(0xff80917b)
                        : const Color(0xff7a8b75)),
          );
          if (blocked) {
            canvas.drawRect(
              rect.deflate(3),
              Paint()..color = const Color(0xff4d6360),
            );
            canvas.drawLine(
              rect.topLeft + const Offset(4, 4),
              rect.topRight + const Offset(-4, 4),
              Paint()
                ..color = const Color(0xff708078)
                ..strokeWidth = 2,
            );
          } else {
            canvas.drawCircle(
              rect.topLeft + Offset(10 + (y % 3) * 8, 15 + (x % 3) * 5),
              1.2,
              Paint()..color = const Color(0xff687d66),
            );
          }
        }
      }
    }
    for (final landmark in landmarks.where((l) => l.mapId == map.id)) {
      final center = Offset((landmark.x + .5) * unit, (landmark.y + .5) * unit);
      final (color, marker) = switch (landmark.kind) {
        WorldLandmarkKind.rest => (const Color(0xffefe8c5), 'R'),
        WorldLandmarkKind.lantern => (const Color(0xffffdd70), 'L'),
        WorldLandmarkKind.dock => (const Color(0xffa4d8d8), 'D'),
        WorldLandmarkKind.supplies => (const Color(0xffd5b275), 'S'),
        WorldLandmarkKind.shelter => (const Color(0xffb6d39d), 'H'),
        WorldLandmarkKind.threshold => (const Color(0xffdc8879), '!'),
        WorldLandmarkKind.bell => (const Color(0xffe7bd57), 'B'),
      };
      canvas.drawCircle(center, 14, Paint()..color = const Color(0xff19313a));
      canvas.drawCircle(
        center,
        11,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      final text = TextPainter(
        text: TextSpan(
          text: marker,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'Roboto',
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
    }
    for (final target in targets.where(
      (target) =>
          target.mapId == map.id &&
          !(hideTownNpcs &&
              map.id == 'map.bellwether' &&
              target.kind == WorldTargetKind.npc),
    )) {
      final center = Offset((target.x + .5) * unit, (target.y + .5) * unit);
      final opened = openedChests.contains(target.id);
      final color = switch (target.kind) {
        WorldTargetKind.npc => const Color(0xff6ab9ed),
        WorldTargetKind.quest => const Color(0xffc68bef),
        WorldTargetKind.chest =>
          opened ? const Color(0xff828b87) : const Color(0xffe7ba58),
        WorldTargetKind.exit => const Color(0xff45c4b0),
      };
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: 34, height: 34),
          const Radius.circular(6),
        ),
        Paint()..color = color,
      );
      final text = TextPainter(
        text: TextSpan(
          text: switch (target.kind) {
            WorldTargetKind.npc => 'N',
            WorldTargetKind.quest =>
              target.id == 'quest.cistern.valve'
                  ? 'V'
                  : target.id == 'quest.cistern.bell'
                  ? 'B'
                  : '!',
            WorldTargetKind.chest => opened ? '-' : 'C',
            WorldTargetKind.exit => '>',
          },
          style: const TextStyle(
            color: Color(0xff14272f),
            fontFamily: 'Roboto',
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
    }
    final spawn = map.spawns.values.first;
    canvas.drawCircle(
      Offset(spawn.x * unit, spawn.y * unit),
      16,
      Paint()
        ..color = const Color(0xffcfdfb4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (showPlayer) {
      final center = Offset(position.x * unit, position.y * unit);
      canvas.drawOval(
        Rect.fromCenter(
          center: center + const Offset(0, 10),
          width: 30,
          height: 12,
        ),
        Paint()..color = const Color(0x66304030),
      );
      if (drawPlayerBody) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: 25, height: 25),
            const Radius.circular(5),
          ),
          Paint()..color = const Color(0xfff6cb70),
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: center + const Offset(0, 4),
            width: 25,
            height: 5,
          ),
          Paint()..color = const Color(0xffb56945),
        );
        canvas.drawCircle(
          center + const Offset(-4, -5),
          2,
          Paint()..color = const Color(0xff25353a),
        );
        canvas.drawCircle(
          center + const Offset(4, -5),
          2,
          Paint()..color = const Color(0xff25353a),
        );
      }
      if (targets.isNotEmpty) {
        final direction = switch (facing) {
          WalkDirection.up => const Offset(0, -19),
          WalkDirection.down => const Offset(0, 19),
          WalkDirection.left => const Offset(-19, 0),
          WalkDirection.right => const Offset(19, 0),
        };
        canvas.drawCircle(center + direction, 3, Paint()..color = Colors.white);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant WorldPainter oldDelegate) =>
      oldDelegate.map != map ||
      oldDelegate.position != position ||
      oldDelegate.showPlayer != showPlayer ||
      oldDelegate.drawPlayerBody != drawPlayerBody ||
      oldDelegate.hideTownNpcs != hideTownNpcs ||
      oldDelegate.background != background ||
      oldDelegate.openBackground != openBackground ||
      oldDelegate.scene != scene ||
      oldDelegate.sluiceOpen != sluiceOpen ||
      oldDelegate.targets != targets ||
      oldDelegate.landmarks != landmarks ||
      oldDelegate.openedChests != openedChests ||
      oldDelegate.facing != facing;
}
