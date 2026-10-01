import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../world_camera.dart';
import 'causeway_geometry.dart';

void main() => runApp(
  const MaterialApp(debugShowCheckedModeBanner: false, home: CausewayArtDemo()),
);

/// Visual prototype; the production maps and coordinator are unaffected.
class CausewayArtDemo extends StatefulWidget {
  const CausewayArtDemo({super.key});
  @override
  State<CausewayArtDemo> createState() => _CausewayArtDemoState();
}

class _CausewayArtDemoState extends State<CausewayArtDemo>
    with SingleTickerProviderStateMixin {
  final _geometry = CausewayGeometry();
  final _focus = FocusNode();
  final _held = <Object, Offset>{};
  late final Ticker _ticker;
  late final AppLifecycleListener _lifecycle;
  late final Future<ui.Image> _art = _loadArt();
  Offset _feet = CausewayGeometry.spawn;
  Duration? _last;
  bool _overlay = true;
  bool _overview = true;

  static final _keys = {
    LogicalKeyboardKey.arrowUp: Offset(0, -1),
    LogicalKeyboardKey.keyW: Offset(0, -1),
    LogicalKeyboardKey.arrowDown: Offset(0, 1),
    LogicalKeyboardKey.keyS: Offset(0, 1),
    LogicalKeyboardKey.arrowLeft: Offset(-1, 0),
    LogicalKeyboardKey.keyA: Offset(-1, 0),
    LogicalKeyboardKey.arrowRight: Offset(1, 0),
    LogicalKeyboardKey.keyD: Offset(1, 0),
  };

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    _lifecycle = AppLifecycleListener(onInactive: _clear, onHide: _clear);
  }

  void _clear() {
    _held.clear();
    _last = null;
  }

  void _tick(Duration now) {
    final last = _last;
    _last = now;
    if (last == null || _held.isEmpty) return;
    final seconds = math.min((now - last).inMicroseconds / 1000000, .05);
    final direction = _held.values.fold(Offset.zero, (a, b) => a + b);
    if (direction == Offset.zero) return;
    final next = _geometry.move(
      _feet,
      direction / direction.distance * 150 * seconds,
    );
    if (next != _feet && mounted) setState(() => _feet = next);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final direction = _keys[event.logicalKey];
    if (direction == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent) _held[event.physicalKey] = direction;
    if (event is KeyUpEvent) _held.remove(event.physicalKey);
    return KeyEventResult.handled;
  }

  Widget _button(String label, IconData icon, Offset direction) => Semantics(
    label: label,
    button: true,
    child: Listener(
      onPointerDown: (event) {
        _focus.requestFocus();
        _held[event.pointer] = direction;
      },
      onPointerUp: (event) => _held.remove(event.pointer),
      onPointerCancel: (event) => _held.remove(event.pointer),
      child: Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: const Color(0xff294048),
          border: Border.all(color: const Color(0xff567078)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    ),
  );

  @override
  void dispose() {
    _ticker.dispose();
    _lifecycle.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff091b27),
    body: SafeArea(
      child: Focus(
        autofocus: true,
        focusNode: _focus,
        onKeyEvent: _key,
        onFocusChange: (focused) {
          if (!focused) _clear();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'SALTGLASS CAUSEWAY · COLLISION REVIEW',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: _overlay,
                        onChanged: (v) => setState(() => _overlay = v),
                      ),
                      const Text(
                        'Collision boundaries',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: _overview,
                        onChanged: (v) => setState(() => _overview = v),
                      ),
                      const Text(
                        'Whole map',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () {
                      _clear();
                      setState(() => _feet = CausewayGeometry.spawn);
                      _focus.requestFocus();
                    },
                    child: const Text('Reset to harbor entrance'),
                  ),
                  PopupMenuButton<Offset>(
                    tooltip: 'Jump to an area for collision review',
                    onSelected: (feet) {
                      _clear();
                      setState(() {
                        _feet = feet;
                        _overview = false;
                      });
                      _focus.requestFocus();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: CausewayGeometry.spawn,
                        child: Text('Harbor entrance'),
                      ),
                      PopupMenuItem(
                        value: Offset(441, 733),
                        child: Text('Chest approach'),
                      ),
                      PopupMenuItem(
                        value: Offset(650, 402),
                        child: Text('Central bridge'),
                      ),
                      PopupMenuItem(
                        value: Offset(236, 178),
                        child: Text('Ruined arch'),
                      ),
                      PopupMenuItem(
                        value: Offset(993, 610),
                        child: Text('Right overlook'),
                      ),
                      PopupMenuItem(
                        value: Offset(1050, 175),
                        child: Text('Northeast path'),
                      ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Jump to area',
                        style: TextStyle(color: Color(0xffd7c5ff)),
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: ClipRect(
                  child: Listener(
                    onPointerDown: (_) => _focus.requestFocus(),
                    child: FutureBuilder<ui.Image>(
                      future: _art,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) return Text('${snapshot.error}');
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return CustomPaint(
                          size: Size.infinite,
                          painter: _CausewayPainter(
                            snapshot.data!,
                            _geometry,
                            _feet,
                            _overlay,
                            _overview,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'WASD / arrows to walk\n'
                      'Feet: ${_feet.dx.round()}, ${_feet.dy.round()} · '
                      'Red outlines mark solid boundaries.',
                      style: const TextStyle(color: Color(0xffc7d6d1)),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _button(
                        'Move up',
                        Icons.keyboard_arrow_up,
                        const Offset(0, -1),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _button(
                            'Move left',
                            Icons.keyboard_arrow_left,
                            const Offset(-1, 0),
                          ),
                          _button(
                            'Move down',
                            Icons.keyboard_arrow_down,
                            const Offset(0, 1),
                          ),
                          _button(
                            'Move right',
                            Icons.keyboard_arrow_right,
                            const Offset(1, 0),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CausewayPainter extends CustomPainter {
  _CausewayPainter(
    this.art,
    this.geometry,
    this.feet,
    this.overlay,
    this.overview,
  );
  final ui.Image art;
  final CausewayGeometry geometry;
  final Offset feet;
  final bool overlay;
  final bool overview;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = overview
        ? math.min(
            size.width / CausewayGeometry.size.width,
            size.height / CausewayGeometry.size.height,
          )
        : 1.0;
    final mapSize = CausewayGeometry.size * scale;
    final offset = worldCameraOffset(
      viewport: size,
      mapSize: mapSize,
      player: feet * scale,
    );
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    canvas.drawImageRect(
      art,
      Rect.fromLTWH(0, 0, art.width.toDouble(), art.height.toDouble()),
      Offset.zero & CausewayGeometry.size,
      Paint()..filterQuality = FilterQuality.none,
    );
    if (overlay) {
      canvas.drawPath(
        geometry.blocked,
        Paint()..color = const Color(0x36ed4b48),
      );
      canvas.drawPath(
        geometry.blocked,
        Paint()
          ..color = const Color(0xffff5555)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / scale,
      );
    }
    // A neutral test marker: collision follows its feet, not the upper body.
    canvas.drawOval(
      Rect.fromCenter(center: feet, width: 20, height: 9),
      Paint()..color = const Color(0xaa051018),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(feet.dx - 10, feet.dy - 25, 20, 24),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xffffd165),
    );
    canvas.drawCircle(
      feet + const Offset(-4, -18),
      1.6,
      Paint()..color = Colors.black,
    );
    canvas.drawCircle(
      feet + const Offset(4, -18),
      1.6,
      Paint()..color = Colors.black,
    );
    canvas.drawCircle(
      feet,
      CausewayGeometry.footRadius,
      Paint()
        ..color = const Color(0xff80e9e3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CausewayPainter old) =>
      old.feet != feet ||
      old.overlay != overlay ||
      old.overview != overview ||
      old.art != art;
}

Future<ui.Image> _loadArt() async {
  final data = await rootBundle.load(
    'assets/maps/saltglass_causeway_green_removed.png',
  );
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}
