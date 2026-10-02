import 'package:flutter/material.dart';

import '../core/contracts.dart';
import 'game_theme.dart';

/// A owns availability checks and operations; this screen never reads storage.
/// Null availability means A3 is still checking. A supplies fresh LoadResult.
class TitleScreen extends StatefulWidget {
  const TitleScreen({
    super.key,
    required this.availability,
    required this.hasActiveProgress,
    required this.onNewGame,
    required this.onContinue,
    this.title = 'The Lantern Wake',
  });
  final LoadResult? availability;
  final bool hasActiveProgress;
  final Future<void> Function() onNewGame;
  final Future<void> Function() onContinue;
  final String title;
  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  bool _busy = false;
  bool _confirming = false;
  String? _error;
  Future<void> _newGame() async {
    if (_busy) return;
    setState(() => _busy = true);
    if (widget.hasActiveProgress ||
        widget.availability is SaveLoaded ||
        widget.availability is SaveUnreadable) {
      setState(() => _confirming = true);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Begin a new journey?'),
          content: const Text(
            'This ends the current session. Saving your new journey may replace the existing save.',
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep progress'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Start new game'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() => _confirming = false);
      if (confirmed != true) {
        setState(() => _busy = false);
        return;
      }
    }
    await _perform(widget.onNewGame);
  }

  Future<void> _perform(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Unable to open the journey. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _saveMessage => switch (widget.availability) {
    null => 'Checking for a saved journey…',
    SaveLoaded() => 'A saved journey is ready to continue.',
    SaveMissing() => 'No saved journey yet.',
    SaveUnreadable(reason: SaveReadFailure.corrupt) =>
      'The saved journey could not be read.',
    SaveUnreadable(reason: SaveReadFailure.unsupportedVersion) =>
      'This save belongs to a different game version.',
    SaveUnreadable() => 'Save storage is unavailable.',
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final intro = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BELLWETHER CHRONICLES',
                style: TextStyle(
                  letterSpacing: 4,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 64,
                  height: 1.05,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Four keepers. One lost lantern.\nA sea waiting to wake.',
                style: TextStyle(
                  fontSize: 21,
                  height: 1.6,
                  color: Color(0xffb7cbd0),
                ),
              ),
              const SizedBox(height: 36),
              const Icon(Icons.flare, size: 84, color: Color(0xffe7c482)),
            ],
          );
          final actions = MenuPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Your journey', style: TextStyle(fontSize: 26)),
                const SizedBox(height: 24),
                FilledButton(
                  autofocus: true,
                  onPressed: _busy || widget.availability == null
                      ? null
                      : _newGame,
                  child: const Text('New Game'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: !_busy && widget.availability is SaveLoaded
                      ? () => _perform(widget.onContinue)
                      : null,
                  child: const Text('Continue'),
                ),
                const SizedBox(height: 18),
                Semantics(liveRegion: true, child: Text(_saveMessage)),
                if (_busy && !_confirming)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 28),
                const Text(
                  'Tab to move • Enter to choose',
                  style: TextStyle(color: Color(0xff9bb0b9)),
                ),
              ],
            ),
          );
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: constraints.maxWidth >= 800
                    ? Row(
                        children: [
                          Expanded(child: intro),
                          const SizedBox(width: 60),
                          SizedBox(width: 350, child: actions),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [intro, const SizedBox(height: 32), actions],
                      ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
