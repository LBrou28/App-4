import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../core/contracts.dart' as shared;
import '../../ui/game_theme.dart';
import '../../ui/sprite_art.dart';
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
    this.pauseSignal,
  });
  final ValueListenable<bool>? pauseSignal;
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
  String? _effectMenu;
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
      pauseSignal: widget.pauseSignal,
    );
  }

  @override
  void didUpdateWidget(BattleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.session, oldWidget.session) ||
        !identical(widget.pauseSignal, oldWidget.pauseSignal)) {
      _controller.dispose();
      _effectMenu = null;
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
                _controller.targeting &&
                        (_controller.pendingEffect == null ||
                            _controller.pendingEffect!.kind ==
                                EffectKind.damage)
                    ? 'Choose an enemy'
                    : 'Enemy formation',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: _controller.session.isBoss ? 220 : 150,
                child: EncounterArtwork(isBoss: _controller.session.isBoss),
              ),
              const SizedBox(height: 16),
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
                        onPressed: _controller.validTarget(enemy)
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
        SizedBox(height: 150, child: const BattlePartyArtwork()),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'YOUR PARTY',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ],
        ),
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
            'MP ${hero.mp} / ${hero.maxMp}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            !hero.isAlive
                ? 'Knocked out'
                : selection != null
                ? selection.action == BattleAction.defend
                      ? 'Defend'
                      : '${selection.action == BattleAction.attack ? 'Attack' : (widget.session.rules.spells[selection.effectId] ?? widget.session.rules.items[selection.effectId])!.name} → ${_name(selection.targetId!)}'
                : active
                ? 'Choosing command'
                : 'Awaiting command',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_controller.targeting &&
              _controller.pendingEffect != null &&
              _controller.pendingEffect!.kind != EffectKind.damage)
            FilledButton(
              key: ValueKey('target-${hero.id}'),
              onPressed: _controller.validTarget(hero)
                  ? () => _controller.target(hero.id)
                  : null,
              child: Text('Target ${_name(hero.id)}'),
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
              Text(
                _controller.pendingEffect?.kind == EffectKind.revive
                    ? 'Select a knocked-out ally.'
                    : _controller.pendingEffect != null &&
                          _controller.pendingEffect!.kind != EffectKind.damage
                    ? 'Select a living ally.'
                    : 'Select a living enemy in the formation.',
              ),
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
                OutlinedButton(
                  key: const ValueKey('magic'),
                  onPressed:
                      _controller.canChoose &&
                          !_controller.targeting &&
                          (_controller.active?.spellIds.isNotEmpty ?? false)
                      ? () => setState(
                          () => _effectMenu = _effectMenu == 'magic'
                              ? null
                              : 'magic',
                        )
                      : null,
                  child: const Text('Magic'),
                ),
                OutlinedButton(
                  key: const ValueKey('items'),
                  onPressed:
                      _controller.canChoose &&
                          !_controller.targeting &&
                          _controller.active != null &&
                          widget.session.rules.items.isNotEmpty
                      ? () => setState(
                          () => _effectMenu = _effectMenu == 'items'
                              ? null
                              : 'items',
                        )
                      : null,
                  child: const Text('Items'),
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
            if (_effectMenu != null &&
                !_controller.targeting &&
                _controller.active != null)
              Wrap(
                spacing: 8,
                children: [
                  for (final effect
                      in (_effectMenu == 'items'
                          ? widget.session.rules.items.values
                          : widget.session.rules.spells.values.where(
                              (e) =>
                                  _controller.active!.spellIds.contains(e.id),
                            )))
                    TextButton(
                      key: ValueKey('effect-${effect.id}'),
                      onPressed:
                          _controller.canUse(
                            effect,
                            item: _effectMenu == 'items',
                          )
                          ? () {
                              _controller.chooseEffect(
                                effect,
                                item: _effectMenu == 'items',
                              );
                              setState(() => _effectMenu = null);
                            }
                          : null,
                      child: Text(
                        '${effect.name} (${_effectMenu == 'items' ? '${_controller.availableItems(effect.id)} left' : '${effect.mpCost} MP'})',
                      ),
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
              onPressed: _controller.canChoose && widget.session.canFlee
                  ? _controller.flee
                  : null,
              child: const Text('Flee'),
            ),
            if (!widget.session.canFlee)
              Text(
                widget.session.isBoss
                    ? 'Boss encounter: escape is disabled.'
                    : 'Escape is unavailable in this encounter.',
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
                            BattleEventKind.spell || BattleEventKind.item =>
                              '${_name(event.actorId)} uses ${(widget.session.rules.spells[event.effectId] ?? widget.session.rules.items[event.effectId])!.name} → ${_name(event.targetId!)}: ${event.damage > 0 ? '${event.damage} damage' : '${event.restored} restored'}',
                            BattleEventKind.skippedTarget =>
                              '${_name(event.actorId)}: target unavailable; no cost.',
                            BattleEventKind.fled => 'The party escaped.',
                            BattleEventKind.fleeFailed =>
                              'Escape failed. Enemies act.',
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
