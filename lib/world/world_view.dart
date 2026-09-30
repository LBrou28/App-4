import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app/world_view_builder.dart';
import '../core/contracts.dart';
import 'world_camera.dart';
import 'world_controller.dart';
import 'world_map.dart';

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
  });
  final MapDefinition map;
  final WorldHost host;
  final Listenable changes;

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
      collision: WorldCollision(widget.map),
    );
    _controller.synchronize();
    widget.changes.addListener(_hostChanged);
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
        oldWidget.map != widget.map) {
      oldWidget.changes.removeListener(_hostChanged);
      _resetInput();
      _attach();
    }
  }

  @override
  void dispose() {
    widget.changes.removeListener(_hostChanged);
    _ticker.dispose();
    _lifecycle.dispose();
    _controller.clearInput();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final direction = _keys[event.logicalKey];
    if (direction == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent) _controller.press(event.physicalKey, direction);
    if (event is KeyUpEvent) _controller.release(event.physicalKey);
    return KeyEventResult.handled;
  }

  Widget _directionButton(WalkDirection direction, IconData icon) => Semantics(
    label: 'Move ${direction.name}',
    button: true,
    onTap: () {
      _focus.requestFocus();
      _controller.press('accessible', direction);
      _controller.advance(.1);
      _controller.release('accessible');
    },
    child: Listener(
      key: ValueKey('move-${direction.name}'),
      onPointerDown: (event) {
        if (event.buttons != kPrimaryButton) return;
        _focus.requestFocus();
        _controller.press(event.pointer, direction);
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
                        ),
                      ),
                    ),
                    if (error != null || !widget.host.movementEnabled)
                      ColoredBox(
                        color: const Color(0x990c171c),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              error ?? 'Movement paused',
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

class WorldPainter extends CustomPainter {
  WorldPainter({
    required this.map,
    required this.position,
    this.showPlayer = true,
  });
  final MapDefinition map;
  final WorldPosition position;
  final bool showPlayer;
  static const tileSize = 48.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff0e1d24),
    );
    final offset = worldCameraOffset(
      viewport: size,
      mapSize: Size(map.width * tileSize, map.height * tileSize),
      player: Offset(position.x * tileSize, position.y * tileSize),
    );
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        final blocked = map.blocked[y * map.width + x];
        final rect = Rect.fromLTWH(
          x * tileSize,
          y * tileSize,
          tileSize,
          tileSize,
        );
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
    final spawn = map.spawns.values.first;
    canvas.drawCircle(
      Offset(spawn.x * tileSize, spawn.y * tileSize),
      16,
      Paint()
        ..color = const Color(0xffcfdfb4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (showPlayer) {
      final center = Offset(position.x * tileSize, position.y * tileSize);
      canvas.drawOval(
        Rect.fromCenter(
          center: center + const Offset(0, 10),
          width: 30,
          height: 12,
        ),
        Paint()..color = const Color(0x66304030),
      );
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
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant WorldPainter oldDelegate) =>
      oldDelegate.map != map ||
      oldDelegate.position != position ||
      oldDelegate.showPlayer != showPlayer;
}
