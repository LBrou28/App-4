import 'package:flutter/material.dart';

import '../../core/contracts.dart' as shared;
import '../../ui/game_theme.dart';
import '../battle.dart';
import '../battle_session.dart';
import 'battle_controller.dart';

/// Mount one screen per encounter; replacing session resets all pending input.
class BattleScreen extends StatefulWidget {
  const BattleScreen({
    super.key,
    required this.session,
    required this.onCompleted,
    this.names = const {},
    this.title = 'Battle',
    this.eventDelay = const Duration(milliseconds: 250),
  });
  final BattleSession session;
  final ValueChanged<shared.BattleResult> onCompleted;
  final Map<String, String> names;
  final String title;
  final Duration eventDelay;

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen> {
  late BattleController _controller;
  String _name(String id) => widget.names[id] ?? id;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _controller = BattleController(
      widget.session,
      eventDelay: widget.eventDelay,
    );
  }

  @override
  void didUpdateWidget(BattleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.session, oldWidget.session)) {
      _controller.dispose();
      _attach();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1000;
              final arena = _arena(context);
              final controls = _controls(context);
              return SingleChildScrollView(
                padding: EdgeInsets.all(wide ? 24 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'LANTERN TRAIL',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    letterSpacing: 3,
                                  ),
                            ),
                            Text(
                              widget.title,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                          ],
                        ),
                        Chip(
                          label: Text('Round ${_controller.snapshot.round}'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: arena),
                          const SizedBox(width: 20),
                          SizedBox(width: 340, child: controls),
                        ],
                      )
                    else ...[
                      arena,
                      const SizedBox(height: 16),
                      controls,
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _arena(BuildContext context) {
    final enemies = _controller.snapshot.combatants.where(
      (c) => c.side == BattleSide.enemies,
    );
    final heroes = _controller.snapshot.combatants.where(
      (c) => c.side == BattleSide.heroes,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MenuPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _controller.targeting ? 'Choose an enemy' : 'Enemy formation',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final enemy in enemies)
                    SizedBox(
                      width: 180,
                      child: OutlinedButton(
                        key: ValueKey('target-${enemy.id}'),
                        onPressed:
                            _controller.canChoose &&
                                _controller.targeting &&
                                enemy.isAlive
                            ? () => _controller.target(enemy.id)
                            : null,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          disabledForegroundColor: enemy.isAlive
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        child: Semantics(
                          label:
                              '${_name(enemy.id)}, ${enemy.isAlive ? '${enemy.hp} of ${enemy.maxHp} HP' : 'Defeated'}',
                          excludeSemantics: true,
                          child: Column(
                            children: [
                              Icon(
                                enemy.isAlive
                                    ? Icons.pest_control
                                    : Icons.close,
                                size: 52,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _name(enemy.id),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              _hpBar(enemy),
                              const SizedBox(height: 8),
                              Text(
                                enemy.isAlive
                                    ? '${enemy.hp} / ${enemy.maxHp} HP'
                                    : 'Defeated',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('YOUR PARTY', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 680
                ? 4
                : constraints.maxWidth >= 340
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final hero in heroes)
                  SizedBox(width: width, child: _heroCard(context, hero)),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Select each hero’s action, then resolve the round. Edit a hero to change their command.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _hpBar(Combatant actor) => Semantics(
    label: '${_name(actor.id)} HP ${actor.hp} of ${actor.maxHp}',
    child: LinearProgressIndicator(
      value: actor.hp / actor.maxHp,
      minHeight: 6,
      borderRadius: BorderRadius.circular(3),
    ),
  );

  Widget _heroCard(BuildContext context, Combatant hero) {
    final member = widget.session.input.state.party.firstWhere(
      (p) => p.id == hero.id,
    );
    final selection = _controller.commands
        .where((c) => c.actorId == hero.id)
        .firstOrNull;
    final active = _controller.canChoose && _controller.active?.id == hero.id;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          width: active ? 2 : 1,
          color: active
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            hero.isAlive ? Icons.shield_outlined : Icons.heart_broken_outlined,
            color: active ? Theme.of(context).colorScheme.primary : null,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(_name(hero.id), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _hpBar(hero),
          const SizedBox(height: 8),
          Text('HP ${hero.hp} / ${hero.maxHp}'),
          Text(
            'MP ${member.mp} / ${member.maxMp}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            !hero.isAlive
                ? 'Knocked out'
                : selection != null
                ? selection.action == BattleAction.defend
                      ? 'Defend'
                      : 'Attack → ${_name(selection.targetId!)}'
                : active
                ? 'Choosing command'
                : 'Awaiting command',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          TextButton(
            key: ValueKey('edit-${hero.id}'),
            onPressed: _controller.canChoose && selection != null
                ? () => _controller.edit(hero.id)
                : null,
            child: const Text('Edit command'),
          ),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context) {
    final result = _controller.result;
    final outcome = switch (result?.outcome) {
      shared.BattleOutcome.victory => 'Victory',
      shared.BattleOutcome.defeat => 'Defeat',
      shared.BattleOutcome.fled => 'Escaped',
      null => null,
    };
    return MenuPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              outcome ??
                  (_controller.busy
                      ? 'Resolving actions'
                      : _controller.active == null
                      ? 'Ready to resolve'
                      : '${_name(_controller.active!.id)}’s turn'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            result != null
                ? 'The battle is over.'
                : '${_controller.commands.length} / ${_controller.livingHeroes.length} commands selected',
          ),
          const SizedBox(height: 16),
          if (result != null)
            FilledButton(
              key: const ValueKey('return-result'),
              onPressed: () {
                final completed = _controller.takeResult();
                if (completed != null) widget.onCompleted(completed);
              },
              child: const Text('Continue'),
            )
          else ...[
            if (_controller.targeting)
              const Text('Select a living enemy in the formation.'),
            if (_controller.busy) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const ValueKey('attack'),
                  onPressed:
                      _controller.canChoose &&
                          _controller.active != null &&
                          !_controller.targeting
                      ? _controller.attack
                      : null,
                  child: const Text('Attack'),
                ),
                OutlinedButton(
                  key: const ValueKey('defend'),
                  onPressed:
                      _controller.canChoose &&
                          _controller.active != null &&
                          !_controller.targeting
                      ? _controller.defend
                      : null,
                  child: const Text('Defend'),
                ),
                TextButton(
                  key: const ValueKey('back'),
                  onPressed:
                      _controller.canChoose &&
                          (_controller.targeting ||
                              _controller.commands.isNotEmpty)
                      ? _controller.back
                      : null,
                  child: Text(_controller.targeting ? 'Cancel target' : 'Back'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('submit-round'),
              onPressed: _controller.canSubmit ? _controller.submit : null,
              child: const Text('Resolve round'),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('flee'),
              onPressed:
                  _controller.canChoose && widget.session.fleePolicy != null
                  ? _controller.flee
                  : null,
              child: const Text('Flee'),
            ),
            if (widget.session.fleePolicy == null)
              Text(
                'Escape is unavailable in this encounter.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
          if (_controller.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(_controller.message!),
              ),
            ),
          const Divider(height: 28),
          Text('Action log', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: _controller.events.isEmpty
                ? const Text('Choose commands to begin.')
                : ListView(
                    children: [
                      for (final event in _controller.events.reversed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(switch (event.kind) {
                            BattleEventKind.attack =>
                              '${_name(event.actorId)} → ${_name(event.targetId!)}: ${event.damage} damage',
                            BattleEventKind.defend =>
                              '${_name(event.actorId)} defends.',
                            BattleEventKind.skippedKnockout =>
                              '${_name(event.actorId)} is knocked out; action skipped.',
                          }),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
