import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// D-owned presentation request; B/A must gate movement before opening it.
/// Dismissal is reported exactly once by the returned Future, never by state writes.
final class DialogueRequest {
  DialogueRequest({
    required this.id,
    required this.speaker,
    required List<String> lines,
  }) : lines = List.unmodifiable(lines) {
    if (id.trim().isEmpty ||
        speaker.trim().isEmpty ||
        lines.isEmpty ||
        lines.any((s) => s.trim().isEmpty)) {
      throw ArgumentError('Dialogue needs an ID, speaker and nonempty lines');
    }
  }
  final String id;
  final String speaker;
  final List<String> lines;
}

enum DialogueDismissal { completed, cancelled }

Future<DialogueDismissal> showGameDialogue(
  BuildContext context,
  DialogueRequest request,
) async =>
    await showDialog<DialogueDismissal>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DialoguePanel(request: request),
    ) ??
    DialogueDismissal.cancelled;

class DialoguePanel extends StatefulWidget {
  const DialoguePanel({super.key, required this.request});
  final DialogueRequest request;
  @override
  State<DialoguePanel> createState() => _DialoguePanelState();
}

class _DialoguePanelState extends State<DialoguePanel> {
  int _line = 0;
  @override
  void didUpdateWidget(DialoguePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.request, widget.request)) _line = 0;
  }

  void _advance() {
    if (_line + 1 == widget.request.lines.length) {
      Navigator.pop(context, DialogueDismissal.completed);
    } else {
      setState(() => _line++);
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.pop(context, DialogueDismissal.cancelled),
    },
    child: AlertDialog(
      title: Text(widget.request.speaker),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  widget.request.lines[_line],
                  style: const TextStyle(fontSize: 21, height: 1.6),
                ),
              ),
              const SizedBox(height: 24),
              Text('${_line + 1} / ${widget.request.lines.length}'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, DialogueDismissal.cancelled),
          child: const Text('Close'),
        ),
        if (_line > 0)
          TextButton(
            onPressed: () => setState(() => _line--),
            child: const Text('Previous'),
          ),
        FilledButton(
          autofocus: true,
          onPressed: _advance,
          child: Text(
            _line + 1 == widget.request.lines.length ? 'Finish' : 'Next',
          ),
        ),
      ],
    ),
  );
}
