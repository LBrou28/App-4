import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/contracts.dart';
import '../battle/ui/battle_screen.dart';
import '../multiplayer/lantern_link.dart';
import '../multiplayer/lantern_link_client.dart';
import '../ui/dialogue_panel.dart';
import '../ui/lantern_link_dialog.dart';
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
  late final LanternLinkClient _lanternLink;
  late final AppLifecycleListener _lifecycle;
  final _navigator = GlobalKey<NavigatorState>();
  DialogRoute<DialogueDismissal>? _dialogueRoute;
  DialogRoute<void>? _remoteDialogueRoute;
  int? _shownDialogue;
  String? _shownRemoteDialogue;
  bool _dialogueSyncPending = false;
  MapDefinition? _viewMap;
  Widget? _world;
  final _worldFocus = FocusScopeNode(debugLabel: 'A2 world focus');
  LoadResult? _availability;
  bool _saveBusy = false;
  String? _saveMessage;
  bool _remoteSyncPending = false;
  int? _appliedRemoteRevision;
  bool _sharedBattleActive = false;
  bool _sharedBattleStartPending = false;

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

  void _togglePause() {
    if (_controller.remoteReadOnly) return;
    if (_controller.mode != AppMode.exploration &&
        _controller.mode != AppMode.battle) {
      return;
    }
    _controller.setPaused(!_controller.paused);
    if (!_controller.paused) _worldFocus.requestFocus();
  }

  Future<void> _showHelp() => showDialog<void>(
    context: _navigator.currentContext!,
    builder: (context) => AlertDialog(
      title: const Text('How to play'),
      content: const SizedBox(
        width: 480,
        child: Text(
          'Explore: Arrow keys, WASD, or the direction buttons.\n\n'
          'Pause: P or Escape, then choose Resume.\n\n'
          'Use Tab and Enter to move through every menu.',
          style: TextStyle(height: 1.55),
        ),
      ),
      actions: [
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    ),
  );

  Future<void> _showSettings() => showDialog<void>(
    context: _navigator.currentContext!,
    builder: (context) => AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => AlertDialog(
        title: const Text('Settings'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Music'),
                value: _controller.musicEnabled,
                onChanged: _controller.setMusicEnabled,
              ),
              SwitchListTile(
                title: const Text('Sound effects'),
                value: _controller.effectsEnabled,
                onChanged: _controller.setEffectsEnabled,
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );

  Future<void> _startNewGame() async {
    await _controller.newGame();
    if (!mounted || _controller.mode != AppMode.exploration) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.movementEnabled) _worldFocus.requestFocus();
    });
  }

  Future<void> _showLanternLink() => showDialog<void>(
    context: _navigator.currentContext!,
    builder: (_) => LanternLinkDialog(client: _lanternLink),
  );

  void _syncLanternLink() {
    final active = _controller.activeDialogue?.dialogue;
    final snapshot = _lanternLink.snapshot;
    final localBattle = _controller.activeBattle;
    if (localBattle != null &&
        _lanternLink.isHost &&
        snapshot?.phase == 'exploration' &&
        !_sharedBattleStartPending) {
      _sharedBattleStartPending = true;
      _lanternLink.startEncounter(
        definitionId: localBattle.input.request.definitionId,
        seed: localBattle.input.seed,
      );
      return;
    }
    if (!_controller.paused &&
        (_controller.mode == AppMode.exploration || active != null)) {
      _lanternLink.publishExploration(
        _controller.state,
        dialogue: active == null
            ? null
            : LanternLinkDialogue(
                id: active.id,
                speaker: active.speaker,
                lines: active.lines,
              ),
      );
    }
  }

  void _onLanternLinkChanged() {
    final snapshot = _lanternLink.snapshot;
    if (snapshot?.phase == 'battle') {
      _sharedBattleActive = true;
      if (_sharedBattleStartPending) {
        _sharedBattleStartPending = false;
        _controller.handoffBattleToLanternLink();
      }
    }
    _syncRemoteLanternLink();
    _syncRemoteDialogue();
    if (mounted) setState(() {});
  }

  void _syncRemoteDialogue() {
    final snapshot = _lanternLink.snapshot;
    final dialogue = _lanternLink.isHost ? null : snapshot?.dialogue;
    final key = dialogue == null
        ? null
        : '${snapshot!.revision}:${dialogue.id}';
    if (key == _shownRemoteDialogue) return;
    final navigator = _navigator.currentState;
    if (navigator == null) return;
    final previous = _remoteDialogueRoute;
    _remoteDialogueRoute = null;
    _shownRemoteDialogue = key;
    if (previous != null && previous.isActive) navigator.removeRoute(previous);
    if (dialogue == null) return;
    final route = DialogRoute<void>(
      context: navigator.context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Text(dialogue.speaker),
        content: SizedBox(width: 480, child: Text(dialogue.lines.join('\n\n'))),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    _remoteDialogueRoute = route;
    navigator.push(route).then((_) {
      if (mounted && _remoteDialogueRoute == route) {
        _remoteDialogueRoute = null;
      }
    });
  }

  void _syncRemoteLanternLink() {
    final snapshot = _lanternLink.snapshot;
    final shouldApplyHostResult = _lanternLink.isHost && _sharedBattleActive;
    if (snapshot == null ||
        (_lanternLink.isHost && !shouldApplyHostResult) ||
        snapshot.phase != 'exploration' ||
        _remoteSyncPending ||
        (_appliedRemoteRevision == snapshot.revision &&
            !shouldApplyHostResult)) {
      return;
    }
    _applyRemoteSnapshot(snapshot);
  }

  Future<void> _applyRemoteSnapshot(LanternLinkClientSnapshot snapshot) async {
    _remoteSyncPending = true;
    try {
      await _controller.applyRemoteExplorationState(
        snapshot.gameState,
        readOnly: !_lanternLink.isHost,
      );
      _appliedRemoteRevision = snapshot.revision;
      _sharedBattleActive = false;
    } finally {
      _remoteSyncPending = false;
      if (mounted) _syncRemoteLanternLink();
    }
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
    _lanternLink = LanternLinkClient();
    _controller.addListener(_scheduleDialogue);
    _controller.addListener(_syncLanternLink);
    _lanternLink.addListener(_onLanternLinkChanged);
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
    _controller.removeListener(_syncLanternLink);
    _lanternLink.removeListener(_onLanternLinkChanged);
    _controller.dispose();
    _lanternLink.dispose();
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
    home: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyP): _togglePause,
        const SingleActivator(LogicalKeyboardKey.escape): _togglePause,
      },
      child: Focus(
        autofocus: true,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final map = _controller.map;
            if (map != null && !identical(map, _viewMap)) {
              _viewMap = map;
              _world = widget.buildWorld(map)(
                context,
                _controller,
                _controller,
              );
            }
            final exploring = _controller.mode == AppMode.exploration;
            final battling = _controller.mode == AppMode.battle;
            final sharedBattle = _lanternLink.snapshot?.phase == 'battle';
            return Scaffold(
              appBar: AppBar(
                title: Text(widget.title),
                actions: [
                  IconButton(
                    tooltip: 'Lantern Link multiplayer',
                    onPressed: _showLanternLink,
                    icon: const Icon(Icons.group_outlined),
                  ),
                  IconButton(
                    tooltip: 'Help and controls',
                    onPressed: _showHelp,
                    icon: const Icon(Icons.help_outline),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: _showSettings,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                  if (exploring &&
                      !_controller.paused &&
                      !_controller.remoteReadOnly &&
                      widget.trainingEncounterId != null)
                    TextButton(
                      onPressed: () => _controller.requestEncounter(
                        EncounterRequest(
                          definitionId: widget.trainingEncounterId!,
                        ),
                        expectedRevision: _controller.revision,
                      ),
                      child: const Text('Training battle'),
                    ),
                  if ((exploring || battling) && !_controller.remoteReadOnly)
                    TextButton(
                      onPressed: _togglePause,
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
                      child: _panel(
                        'A new adventure begins',
                        widget.introduction,
                        [
                          FilledButton(
                            onPressed: _startNewGame,
                            child: const Text('New Game'),
                          ),
                          OutlinedButton(
                            onPressed: _showLanternLink,
                            child: const Text('Lantern Link'),
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
                        key: ValueKey(
                          _controller.activeBattle!.input.encounterId,
                        ),
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
                  if (sharedBattle)
                    Positioned.fill(
                      child: _LanternLinkBattleOverlay(
                        client: _lanternLink,
                        names: widget.battleNames,
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
                                child: Text(
                                  _saveBusy ? 'Saving…' : 'Save game',
                                ),
                              ),
                            if (_saveMessage != null) Text(_saveMessage!),
                            FilledButton(
                              onPressed: _saveBusy ? null : _resume,
                              child: Text(
                                battling
                                    ? 'Continue battle'
                                    : 'Continue exploring',
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
      ),
    ),
  );
}

class _LanternLinkBattleOverlay extends StatelessWidget {
  const _LanternLinkBattleOverlay({required this.client, required this.names});
  final LanternLinkClient client;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final snapshot = client.snapshot!;
    final battle = snapshot.battle!;
    final combatants = [
      for (final raw in battle['combatants'] as List)
        Map<String, dynamic>.from(raw as Map),
    ];
    final enemies = combatants
        .where(
          (value) => value['side'] == 'enemies' && (value['hp'] as int) > 0,
        )
        .toList();
    final owned = (snapshot.assignments[client.playerId] ?? const <String>[])
        .toSet();
    return Material(
      color: const Color(0xff102027),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Shared battle • Round ${battle['round']}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView(
                  children: [
                    for (final value in combatants)
                      ListTile(
                        title: Text(
                          names[value['id']] ?? value['id'] as String,
                        ),
                        subtitle: Text(
                          '${value['side']} • HP ${value['hp']} / ${value['maxHp']}',
                        ),
                      ),
                  ],
                ),
              ),
              for (final hero in combatants.where(
                (value) =>
                    value['side'] == 'heroes' &&
                    owned.contains(value['id']) &&
                    (value['hp'] as int) > 0,
              ))
                Row(
                  children: [
                    Expanded(
                      child: Text(names[hero['id']] ?? hero['id'] as String),
                    ),
                    OutlinedButton(
                      onPressed: () => client.defend(hero['id'] as String),
                      child: const Text('Defend'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: enemies.isEmpty
                          ? null
                          : () => client.attack(
                              hero['id'] as String,
                              enemies.first['id'] as String,
                            ),
                      child: const Text('Attack'),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              const Text(
                'Choose actions only for your assigned heroes. The server resolves the round for everyone.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
