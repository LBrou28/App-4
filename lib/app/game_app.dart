import 'package:flutter/material.dart';

import '../core/contracts.dart';
import 'app_controller.dart';
import 'world_view_builder.dart';

class GameApp extends StatefulWidget {
  const GameApp({super.key, required this.loadWorld, required this.buildWorld});
  final WorldLoader loadWorld;
  final WorldViewBuilder Function(MapDefinition map) buildWorld;
  @override
  State<GameApp> createState() => _GameAppState();
}

class _GameAppState extends State<GameApp> {
  late final AppController _controller;
  late final AppLifecycleListener _lifecycle;
  MapDefinition? _viewMap;
  Widget? _world;
  final _worldFocus = FocusScopeNode(debugLabel: 'A2 world focus');

  void _resume() {
    _controller.setPaused(false);
    _worldFocus.requestFocus();
  }

  Future<void> _startNewGame() async {
    await _controller.newGame();
    if (!mounted || _controller.mode != AppMode.exploration) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.movementEnabled) _worldFocus.requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = AppController(loadWorld: widget.loadWorld);
    _lifecycle = AppLifecycleListener(
      onInactive: () => _controller.setPaused(true),
      onHide: () => _controller.setPaused(true),
      onPause: () => _controller.setPaused(true),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _worldFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  Widget _panel(String title, String message, List<Widget> actions) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'App-4 • Practice world',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xffd4bb7b),
      useMaterial3: true,
    ),
    home: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final map = _controller.map;
        if (map != null && !identical(map, _viewMap)) {
          _viewMap = map;
          _world = widget.buildWorld(map)(context, _controller, _controller);
        }
        final exploring = _controller.mode == AppMode.exploration;
        return Scaffold(
          appBar: AppBar(
            title: const Text('App-4 • Practice world'),
            actions: [
              if (exploring)
                TextButton(
                  onPressed: () {
                    if (_controller.paused) {
                      _resume();
                    } else {
                      _controller.setPaused(true);
                    }
                  },
                  child: Text(_controller.paused ? 'Resume' : 'Pause'),
                ),
            ],
          ),
          body: Stack(
            children: [
              if (_world != null)
                Positioned.fill(
                  child: Offstage(
                    offstage: !exploring,
                    child: TickerMode(
                      enabled: exploring && !_controller.paused,
                      child: FocusScope(node: _worldFocus, child: _world!),
                    ),
                  ),
                ),
              if (_controller.mode == AppMode.title)
                Positioned.fill(
                  child: _panel(
                    'A new adventure begins',
                    'Explore the practice grounds with arrow keys, WASD or the on-screen controls.\n\nThis early build supports exploration. Battles and saving are coming later.',
                    [
                      FilledButton(
                        onPressed: _startNewGame,
                        child: const Text('New Game'),
                      ),
                    ],
                  ),
                ),
              if (_controller.mode == AppMode.loading)
                Positioned.fill(
                  child: _panel(
                    'Loading world',
                    'Preparing your starting point…',
                    [
                      const CircularProgressIndicator(),
                      TextButton(
                        onPressed: _controller.returnToTitle,
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              if (_controller.mode == AppMode.error)
                Positioned.fill(
                  child: _panel('Unable to start', _controller.error!, [
                    FilledButton(
                      onPressed: _startNewGame,
                      child: const Text('Try again'),
                    ),
                    TextButton(
                      onPressed: _controller.returnToTitle,
                      child: const Text('Back to title'),
                    ),
                  ]),
                ),
              if (exploring && _controller.paused)
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0xff102027),
                    child: _panel(
                      'Paused',
                      'Your position is kept while paused. Returning to the title ends this practice session; progress is not saved.',
                      [
                        FilledButton(
                          onPressed: _resume,
                          child: const Text('Continue exploring'),
                        ),
                        TextButton(
                          onPressed: _controller.returnToTitle,
                          child: const Text('End session'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
