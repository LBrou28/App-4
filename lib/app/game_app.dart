import 'package:flutter/material.dart';

import '../core/contracts.dart';
import '../battle/ui/battle_screen.dart';
import '../ui/dialogue_panel.dart';
import 'app_controller.dart';
import 'world_view_builder.dart';

class GameApp extends StatefulWidget {
  const GameApp({
    super.key,
    required this.loadWorld,
    required this.buildWorld,
    this.battles = const {},
    this.saves,
    this.trainingEncounterId,
    this.battleNames = const {},
    this.battleTitle = 'Battle',
    this.title = 'App-4 • Practice world',
    this.introduction = 'Explore the practice grounds with arrow keys, WASD or the on-screen controls.\n\nThis early build supports exploration. Battles and saving are coming later.',
  });
  final Map<String, BattleFactory> battles;
  final SaveRepository? saves;
  final String? trainingEncounterId;
  final Map<String, String> battleNames;
  final String battleTitle;
  final String title;
  final String introduction;
  final WorldLoader loadWorld;
  final WorldViewBuilder Function(MapDefinition map) buildWorld;
  @override
  State<GameApp> createState() => _GameAppState();
}

class _GameAppState extends State<GameApp> {
  late final AppController _controller;
  late final AppLifecycleListener _lifecycle;
  final _navigator = GlobalKey<NavigatorState>();
  DialogRoute<DialogueDismissal>? _dialogueRoute;
  int? _shownDialogue;
  bool _dialogueSyncPending = false;
  MapDefinition? _viewMap;
  Widget? _world;
  final _worldFocus = FocusScopeNode(debugLabel: 'A2 world focus');
  LoadResult? _availability;
  bool _saveBusy = false;
  String? _saveMessage;

  Future<void> _refreshSave() async {
    final result = await _controller.readSave();
    if (mounted) setState(() => _availability = result);
  }

  Future<void> _saveGame() async {
    if (_saveBusy) return;
    setState(() {
      _saveBusy = true;
      _saveMessage = null;
    });
    final result = await _controller.saveCurrent();
    if (!mounted) return;
    setState(() {
      _saveBusy = false;
      _saveMessage = result is SaveWritten
          ? 'Journey saved.'
          : (result as SaveWriteFailed).message;
    });
    await _refreshSave();
  }

  Future<void> _continueGame() async {
    final result = await _controller.continueGame();
    if (!mounted) return;
    setState(() {
      _availability = result;
      _saveMessage = result is SaveLoaded
          ? null
          : 'This save could not be continued.';
    });
    if (_controller.movementEnabled) _worldFocus.requestFocus();
  }

  void _returnToTitle() {
    _controller.returnToTitle();
    _saveMessage = null;
    _refreshSave();
  }

  void _scheduleDialogue() {
    if (_dialogueSyncPending) return;
    _dialogueSyncPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dialogueSyncPending = false;
      if (!mounted) return;
      final active = _controller.activeDialogue;
      if (active?.token == _shownDialogue) return;
      final navigator = _navigator.currentState!;
      final previous = _dialogueRoute;
      _dialogueRoute = null;
      _shownDialogue = active?.token;
      if (previous != null && previous.isActive) {
        navigator.removeRoute(previous);
      }
      if (active == null) return;
      final definition = active.dialogue;
      final route = DialogRoute<DialogueDismissal>(
        context: navigator.context,
        barrierDismissible: false,
        builder: (_) => DialoguePanel(
          request: DialogueRequest(
            id: definition.id,
            speaker: definition.speaker,
            lines: definition.lines,
          ),
        ),
      );
      _dialogueRoute = route;
      navigator.push(route).then((dismissal) {
        if (!mounted || _shownDialogue != active.token) return;
        _dialogueRoute = null;
        _shownDialogue = null;
        if (dismissal == DialogueDismissal.completed) {
          _controller.completeDialogue(
            active.token,
            expectedRevision: _controller.revision,
          );
        } else {
          _controller.closeDialogue(
            active.token,
            expectedRevision: _controller.revision,
          );
        }
        if (_controller.movementEnabled) _worldFocus.requestFocus();
      });
    });
  }

  void _resume() {
    _controller.setPaused(false);
    if (_controller.movementEnabled) _worldFocus.requestFocus();
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
    _controller = AppController(
      loadWorld: widget.loadWorld,
      battles: widget.battles,
      saves: widget.saves,
    );
    _refreshSave();
    _controller.addListener(_scheduleDialogue);
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
    _controller.removeListener(_scheduleDialogue);
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
    navigatorKey: _navigator,
    title: widget.title,
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
        final battling = _controller.mode == AppMode.battle;
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.title),
            actions: [
              if (exploring &&
                  !_controller.paused &&
                  widget.trainingEncounterId != null)
                TextButton(
                  onPressed: () => _controller.requestEncounter(
                    EncounterRequest(definitionId: widget.trainingEncounterId!),
                    expectedRevision: _controller.revision,
                  ),
                  child: const Text('Training battle'),
                ),
              if (exploring || battling)
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
                    offstage:
                        !exploring && _controller.mode != AppMode.dialogue,
                    child: TickerMode(
                      enabled: exploring && !_controller.paused,
                      child: FocusScope(node: _worldFocus, child: _world!),
                    ),
                  ),
                ),
              if (_controller.mode == AppMode.title)
                Positioned.fill(
                  child: _panel('A new adventure begins', widget.introduction, [
                    FilledButton(
                      onPressed: _startNewGame,
                      child: const Text('New Game'),
                    ),
                    if (_availability is SaveLoaded)
                      OutlinedButton(
                        onPressed: _continueGame,
                        child: const Text('Continue'),
                      ),
                    if (_availability is SaveUnreadable)
                      const Text(
                        'The saved journey cannot be read on this version.',
                      ),
                  ]),
                ),
              if (_controller.mode == AppMode.loading)
                Positioned.fill(
                  child: _panel(
                    'Loading world',
                    'Preparing your starting point…',
                    [
                      const CircularProgressIndicator(),
                      TextButton(
                        onPressed: _returnToTitle,
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
                      onPressed: _returnToTitle,
                      child: const Text('Back to title'),
                    ),
                  ]),
                ),
              if (battling)
                Positioned.fill(
                  child: BattleScreen(
                    key: ValueKey(_controller.activeBattle!.input.encounterId),
                    session: _controller.activeBattle!,
                    pauseSignal: _controller,
                    title: widget.battleTitle,
                    names: widget.battleNames,
                    onCompleted: (result) {
                      if (_controller.acceptBattleResult(result) &&
                          _controller.movementEnabled) {
                        _worldFocus.requestFocus();
                      }
                    },
                  ),
                ),
              if (_controller.mode == AppMode.gameOver)
                Positioned.fill(
                  child: _panel(
                    'Party defeated',
                    'Your journey has ended. Start a new game or return to the title to continue your last save.',
                    [
                      FilledButton(
                        onPressed: _startNewGame,
                        child: const Text('New Game'),
                      ),
                      TextButton(
                        onPressed: _returnToTitle,
                        child: const Text('Back to title'),
                      ),
                    ],
                  ),
                ),
              if ((exploring || battling) && _controller.paused)
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0xff102027),
                    child: _panel(
                      'Paused',
                      'Your position is kept while paused. Save here to continue this journey after closing the game.',
                      [
                        if (exploring && widget.saves != null)
                          FilledButton.tonal(
                            onPressed: _saveBusy ? null : _saveGame,
                            child: Text(_saveBusy ? 'Saving…' : 'Save game'),
                          ),
                        if (_saveMessage != null) Text(_saveMessage!),
                        FilledButton(
                          onPressed: _saveBusy ? null : _resume,
                          child: Text(
                            battling ? 'Continue battle' : 'Continue exploring',
                          ),
                        ),
                        TextButton(
                          onPressed: _saveBusy ? null : _returnToTitle,
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
