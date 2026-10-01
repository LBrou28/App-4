import 'package:flutter/material.dart';

import '../multiplayer/lantern_link_client.dart';

/// Small, keyboard-friendly lobby that works on the browser target. The host
/// address is intentionally entered by the player because browsers cannot host
/// the local Dart service themselves.
class LanternLinkDialog extends StatefulWidget {
  const LanternLinkDialog({super.key, required this.client});
  final LanternLinkClient client;

  @override
  State<LanternLinkDialog> createState() => _LanternLinkDialogState();
}

class _LanternLinkDialogState extends State<LanternLinkDialog> {
  final _address = TextEditingController(
    text: 'ws://localhost:8088/lantern-link',
  );
  final _name = TextEditingController();
  int _players = 2;
  bool _busy = false;

  @override
  void dispose() {
    _address.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      await widget.client.connect(
        endpoint: _address.text,
        playerId: _name.text,
      );
    } catch (_) {
      // The client exposes the readable error in its status panel.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Lantern Link'),
    content: SizedBox(
      width: 520,
      child: AnimatedBuilder(
        animation: widget.client,
        builder: (context, _) {
          final client = widget.client;
          final snapshot = client.snapshot;
          if (snapshot == null) return _joinForm(client);
          return _lobby(client, snapshot);
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          widget.client.disconnect();
          Navigator.pop(context);
        },
        child: const Text('Leave room'),
      ),
      FilledButton(
        autofocus: true,
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );

  Widget _joinForm(LanternLinkClient client) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Start the Dart server on one computer, then enter its local-network WebSocket address.',
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _address,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: 'Server address',
          hintText: 'ws://192.168.1.42:8088/lantern-link',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Your player name'),
        onSubmitted: (_) => _busy ? null : _connect(),
      ),
      if (client.error != null) ...[
        const SizedBox(height: 12),
        Text(
          client.error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const SizedBox(height: 18),
      FilledButton(
        onPressed: _busy ? null : _connect,
        child: Text(
          _busy || client.connecting ? 'Connecting…' : 'Join Lantern Link',
        ),
      ),
    ],
  );

  Widget _lobby(LanternLinkClient client, LanternLinkClientSnapshot snapshot) {
    final ownerHeroes =
        snapshot.assignments[client.playerId] ?? const <String>[];
    final battle = snapshot.battle;
    final enemies = battle == null
        ? const <String>[]
        : [
            for (final value in battle['combatants'] as List)
              if (Map<String, dynamic>.from(value as Map)['side'] ==
                      'enemies' &&
                  (Map<String, dynamic>.from(value)['hp'] as int) > 0)
                Map<String, dynamic>.from(value)['id'] as String,
          ];
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Room: ${snapshot.room}  •  ${snapshot.phase}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('Host: ${snapshot.hostId ?? 'waiting'}'),
          const SizedBox(height: 12),
          Text(
            'Players (${snapshot.players.length}): ${snapshot.players.join(', ')}',
          ),
          if (client.isHost && snapshot.phase == 'lobby') ...[
            const SizedBox(height: 16),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 2, label: Text('2 players')),
                ButtonSegment(value: 4, label: Text('4 players')),
              ],
              selected: {_players},
              onSelectionChanged: (value) {
                setState(() => _players = value.first);
                client.configurePlayers(value.first);
              },
            ),
            const SizedBox(height: 10),
            FilledButton.tonal(
              onPressed: snapshot.players.length == _players
                  ? client.assignEvenly
                  : null,
              child: const Text('Assign heroes and begin exploration'),
            ),
          ],
          if (snapshot.assignments.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Hero assignments',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final entry in snapshot.assignments.entries)
              Text('${entry.key}: ${entry.value.join(', ')}'),
          ],
          if (snapshot.phase == 'exploration' && client.isHost) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: client.startEncounter,
              child: const Text('Start shared training battle'),
            ),
          ],
          if (battle != null) ...[
            const SizedBox(height: 16),
            Text(
              'Shared battle • Round ${battle['round']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final hero in ownerHeroes)
              Row(
                children: [
                  Expanded(child: Text(hero)),
                  OutlinedButton(
                    onPressed: () => client.defend(hero),
                    child: const Text('Defend'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: enemies.isEmpty
                        ? null
                        : () => client.attack(hero, enemies.first),
                    child: const Text('Attack'),
                  ),
                ],
              ),
          ],
          if (client.error != null) ...[
            const SizedBox(height: 12),
            Text(
              client.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
