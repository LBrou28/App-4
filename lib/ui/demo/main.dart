import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/contracts.dart';
import '../../progression.dart';
import '../content/demo_content.dart';
import '../dialogue_panel.dart';
import '../game_theme.dart';
import '../party_menu.dart';
import '../title_screen.dart';

void main() => runApp(
  MaterialApp(
    theme: lanternTheme(),
    debugShowCheckedModeBanner: false,
    title: 'The Lantern Wake · UI preview',
    home: const MenuPreview(),
  ),
);

/// A small C4 integration host for the D party-menu preview.
class PreviewHost extends ChangeNotifier implements PartyMenuHost {
  PreviewHost(DemoContent content) : _state = previewState(content);
  final PartyRules _rules = LanternJobRules();
  GameState _state;
  @override
  GameState get state => _state;
  @override
  Future<CommandResult> submit(MenuCommand command) async {
    final result = _rules.apply(state, command);
    if (result case CommandAccepted(:final state)) {
      _state = state;
      notifyListeners();
    }
    return result;
  }
}

GameState previewState(DemoContent content) => GameState(
  position: WorldPosition(mapId: 'map.bellwether', x: 1.5, y: 1.5),
  party: [
    for (final (i, hero) in content.entries('heroes').indexed)
      PartyMember(
        id: hero.id,
        jobId: hero.text('jobId'),
        hp: [84, 68, 45, 52][i],
        maxHp: [100, 90, 70, 75][i],
        mp: [0, 0, 18, 14][i],
        maxMp: [0, 0, 24, 28][i],
        level: 2,
        experience: 120,
        jobProgress: {hero.text('jobId'): 2},
        equipment: {
          'weapon': [
            'item.harbor_blade',
            'item.rope_wraps',
            'item.shell_staff',
            'item.shell_staff',
          ][i],
          'body': i < 2 ? 'item.keeper_coat' : 'item.linen_robe',
        },
      ),
  ],
  inventory: Inventory({
    'item.salves': 3,
    'item.ether': 1,
    'item.shell_staff': 1,
    'item.keeper_coat': 1,
  }),
  gold: 140,
  quests: QuestFlags(flags: {}, openedChestIds: {}),
);

class MenuPreview extends StatefulWidget {
  const MenuPreview({super.key});
  @override
  State<MenuPreview> createState() => _MenuPreviewState();
}

class _MenuPreviewState extends State<MenuPreview> {
  late final Future<DemoContent> _content = rootBundle
      .loadString('assets/data/lantern_wake.json')
      .then(DemoContent.decode);
  PreviewHost? _host;
  String _screen = 'title';
  bool _hasProgress = false;
  @override
  void dispose() {
    _host?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<DemoContent>(
    future: _content,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Scaffold(
          body: Center(child: Text('The preview content could not be loaded.')),
        );
      }
      final content = snapshot.data;
      if (content == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      _host ??= PreviewHost(content);
      if (_screen == 'title') {
        return TitleScreen(
          title: content.title,
          availability: SaveMissing(),
          hasActiveProgress: _hasProgress,
          onNewGame: () async {
            setState(() {
              _hasProgress = true;
              _screen = 'journal';
            });
          },
          onContinue: () async {},
        );
      }
      if (_screen == 'party') {
        return PartyMenu(
          host: _host!,
          content: content,
          onBack: () => setState(() => _screen = 'journal'),
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: const Text('The Lantern Wake · Presentation preview'),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(content.questName, style: const TextStyle(fontSize: 42)),
                  const SizedBox(height: 20),
                  Text(
                    content.premise,
                    style: const TextStyle(fontSize: 20, height: 1.6),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: () => setState(() => _screen = 'party'),
                    child: const Text('Open party journal'),
                  ),
                  const SizedBox(height: 24),
                  const Text('Conversations', style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final dialogue in content.entries('dialogues'))
                        OutlinedButton(
                          onPressed: () => showGameDialogue(
                            context,
                            DialogueRequest(
                              id: dialogue.id,
                              speaker: content.label(
                                dialogue.text('speakerId').startsWith('hero.')
                                    ? 'heroes'
                                    : 'npcs',
                                dialogue.text('speakerId'),
                              ),
                              lines: dialogue.strings('lines'),
                            ),
                          ),
                          child: Text(dialogue.id.split('.').last),
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'The party menu applies C4 job and equipment rules. Saving and map events remain preview-only.',
                    style: TextStyle(color: Color(0xffadc1ca)),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => setState(() => _screen = 'title'),
                    child: const Text('Return to title'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
