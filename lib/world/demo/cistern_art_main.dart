import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../world_camera.dart';
import 'cistern_geometry.dart';

void main() => runApp(
  const MaterialApp(debugShowCheckedModeBanner: false, home: CisternArtDemo()),
);

/// Visual prototype; the production maps and coordinator are unaffected.
class CisternArtDemo extends StatefulWidget {
  const CisternArtDemo({super.key});
  @override
  State<CisternArtDemo> createState() => _CisternArtDemoState();
}

class _CisternArtDemoState extends State<CisternArtDemo>
    with SingleTickerProviderStateMixin {
  var _geometry = CisternGeometry();
  final _focus = FocusNode();
  final _held = <Object, Offset>{};
  late final Ticker _ticker;
  late final AppLifecycleListener _lifecycle;
  late final Future<_CisternArt> _art = _loadArt();
  Offset _feet = CisternGeometry.spawn;
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

  void _operateValve() {
    if (!_geometry.canOperateValve(_feet)) return;
    _clear();
    setState(() => _geometry = CisternGeometry(sluiceOpen: true));
    _focus.requestFocus();
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
    if (event.logicalKey == LogicalKeyboardKey.keyE) {
      if (event is KeyDownEvent) _operateValve();
      return KeyEventResult.handled;
    }
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
                  'DROWNED CISTERN · COLLISION REVIEW',
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
                    onPressed: _geometry.canOperateValve(_feet)
                        ? _operateValve
                        : null,
                    child: Text(
                      _geometry.sluiceOpen
                          ? 'Valve activated'
                          : 'Turn valve (E)',
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _clear();
                      setState(() {
                        _feet = CisternGeometry.spawn;
                        _geometry = CisternGeometry();
                      });
                      _focus.requestFocus();
                    },
                    child: const Text('Reset run'),
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
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: CisternGeometry.spawn,
                        child: Text('Entrance'),
                      ),
                      const PopupMenuItem(
                        value: Offset(400, 1035),
                        child: Text('Lower-left connection'),
                      ),
                      const PopupMenuItem(
                        value: Offset(192, 650),
                        child: Text('West courtyard'),
                      ),
                      const PopupMenuItem(
                        value: CisternGeometry.valveApproach,
                        child: Text('Northwest valve'),
                      ),
                      const PopupMenuItem(
                        value: Offset(622, 770),
                        child: Text('Main junction'),
                      ),
                      const PopupMenuItem(
                        value: Offset(1080, 445),
                        child: Text('Right chest'),
                      ),
                      const PopupMenuItem(
                        value: Offset(966, 694),
                        child: Text('Right connection'),
                      ),
                      const PopupMenuItem(
                        value: Offset(627, 563),
                        child: Text('Sluice approach'),
                      ),
                      if (_geometry.sluiceOpen)
                        const PopupMenuItem(
                          value: Offset(625, 250),
                          child: Text('Beacon chamber'),
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
                    child: FutureBuilder<_CisternArt>(
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
                          painter: _CisternPainter(
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
                      'WASD / arrows to walk · E at the northwest valve\n'
                      'Feet: ${_feet.dx.round()}, ${_feet.dy.round()} · '
                      'Sluice: ${_geometry.sluiceOpen ? 'open' : 'closed'}.',
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

class _CisternPainter extends CustomPainter {
  _CisternPainter(
    this.art,
    this.geometry,
    this.feet,
    this.overlay,
    this.overview,
  );
  final _CisternArt art;
  final CisternGeometry geometry;
  final Offset feet;
  final bool overlay;
  final bool overview;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = overview
        ? math.min(
            size.width / CisternGeometry.size.width,
            size.height / CisternGeometry.size.height,
          )
        : 1.0;
    final mapSize = CisternGeometry.size * scale;
    final offset = worldCameraOffset(
      viewport: size,
      mapSize: mapSize,
      player: feet * scale,
    );
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    canvas.drawImageRect(
      art.closed,
      Rect.fromLTWH(
        0,
        0,
        art.closed.width.toDouble(),
        art.closed.height.toDouble(),
      ),
      Offset.zero & CisternGeometry.size,
      Paint()..filterQuality = FilterQuality.none,
    );
    if (geometry.sluiceOpen) {
      final region = CisternGeometry.openArtRegion;
      canvas.drawImageRect(
        art.opened,
        Rect.fromLTRB(
          region.left * art.opened.width / 1254,
          region.top * art.opened.height / 1254,
          region.right * art.opened.width / 1254,
          region.bottom * art.opened.height / 1254,
        ),
        region,
        Paint()..filterQuality = FilterQuality.none,
      );
    }
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
      CisternGeometry.footRadius,
      Paint()
        ..color = const Color(0xff80e9e3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CisternPainter old) =>
      old.feet != feet ||
      old.overlay != overlay ||
      old.overview != overview ||
      old.art != art ||
      old.geometry.sluiceOpen != geometry.sluiceOpen;
}

class _CisternArt {
  const _CisternArt(this.closed, this.opened);
  final ui.Image closed;
  final ui.Image opened;
}

Future<_CisternArt> _loadArt() async {
  final images = await Future.wait([
    _loadImage('assets/maps/drowned_cistern_paths_v2.png'),
    _loadImage('assets/maps/drowned_cistern_open_sluice_v2.png'),
  ]);
  return _CisternArt(images[0], images[1]);
}

Future<ui.Image> _loadImage(String path) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}
