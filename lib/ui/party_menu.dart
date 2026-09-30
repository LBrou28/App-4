import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/contracts.dart';
import 'content/demo_content.dart';
import 'game_theme.dart';

/// A supplies the current authoritative snapshot and commits C's accepted result
/// before notifying/returning. UI never applies CommandAccepted.state itself.
abstract interface class PartyMenuHost implements Listenable {
  GameState get state;
  Future<CommandResult> submit(MenuCommand command);
}

enum PartyPage { status, inventory, equipment, jobs }

class PartyMenu extends StatefulWidget {
  const PartyMenu({
    super.key,
    required this.host,
    required this.content,
    required this.onBack,
    this.initialPage = PartyPage.status,
  });
  final PartyMenuHost host;
  final DemoContent content;
  final VoidCallback onBack;
  final PartyPage initialPage;
  @override
  State<PartyMenu> createState() => _PartyMenuState();
}

class _PartyMenuState extends State<PartyMenu> {
  late PartyPage _page = widget.initialPage;
  String? _memberId;
  bool _busy = false;
  String? _message;
  bool _rejected = false;
  int _generation = 0;
  final _menuFocus = FocusNode(debugLabel: 'Party menu fallback');
  @override
  void initState() {
    super.initState();
    widget.host.addListener(_changed);
  }

  @override
  void didUpdateWidget(PartyMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.host, oldWidget.host)) {
      oldWidget.host.removeListener(_changed);
      widget.host.addListener(_changed);
      _generation++;
      _busy = false;
      _message = null;
      _memberId = null;
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _generation++;
    widget.host.removeListener(_changed);
    _menuFocus.dispose();
    super.dispose();
  }

  Future<void> _submit(MenuCommand command) async {
    if (_busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.host.submit(command);
      if (!mounted || generation != _generation) return;
      setState(() {
        _rejected = result is CommandRejected;
        _message = switch (result) {
          CommandRejected(:final message) => message,
          CommandAccepted() => 'Party updated.',
        };
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _rejected = true;
          _message = 'The action could not be completed. Please try again.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
        _menuFocus.requestFocus();
      }
    }
  }

  void _back() {
    if (!_busy) widget.onBack();
  }

  void _selectPage(int index) => setState(() {
    _page = PartyPage.values[index];
    _message = null;
  });
  @override
  Widget build(BuildContext context) {
    final state = widget.host.state;
    final member = state.party.firstWhere(
      (p) => p.id == _memberId,
      orElse: () => state.party.first,
    );
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _back},
      child: Focus(
        focusNode: _menuFocus,
        skipTraversal: true,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Back',
              onPressed: _busy ? null : _back,
              icon: const Icon(Icons.arrow_back),
            ),
            title: Text(widget.content.title),
            actions: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('${state.gold} gold'),
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, size) {
              final navigation = _navigation(size.maxWidth >= 900);
              final body = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _titles[_page.index],
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _subtitles[_page.index],
                    style: const TextStyle(color: Color(0xffadc1ca)),
                  ),
                  const SizedBox(height: 24),
                  if (_page != PartyPage.status) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in state.party)
                          ChoiceChip(
                            label: Text(widget.content.label('heroes', p.id)),
                            selected: p.id == member.id,
                            onSelected: _busy
                                ? null
                                : (_) => setState(() {
                                    _memberId = p.id;
                                    _message = null;
                                  }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (_busy) const LinearProgressIndicator(),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _message!,
                          style: TextStyle(
                            color: _rejected
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  switch (_page) {
                    PartyPage.status => _status(state, size.maxWidth),
                    PartyPage.inventory => _inventory(state, member),
                    PartyPage.equipment => _equipment(state, member),
                    PartyPage.jobs => _jobs(member),
                  },
                ],
              );
              final scroll = SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: body,
              );
              return size.maxWidth >= 900
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 220, child: navigation),
                        Expanded(child: scroll),
                      ],
                    )
                  : Column(
                      children: [
                        navigation,
                        Expanded(child: scroll),
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }

  static const _titles = [
    'Your companions',
    'Travel supplies',
    'Equipment',
    'Choose a calling',
  ];
  static const _subtitles = [
    'Four keepers, one journey. Take care of each other.',
    'Select a companion, then choose an item to use.',
    'Prepare each companion for the road ahead.',
    'Every keeper can learn a different craft.',
  ];
  Widget _navigation(bool wide) {
    const icons = [
      Icons.groups_outlined,
      Icons.backpack_outlined,
      Icons.shield_outlined,
      Icons.auto_awesome_outlined,
    ];
    const labels = ['Party', 'Inventory', 'Equipment', 'Jobs'];
    final buttons = List.generate(
      4,
      (i) => Padding(
        padding: const EdgeInsets.all(4),
        child: TextButton.icon(
          autofocus: i == 0,
          style: TextButton.styleFrom(
            minimumSize: const Size(100, 48),
            backgroundColor: _page.index == i ? const Color(0xff30434c) : null,
          ),
          onPressed: _busy ? null : () => _selectPage(i),
          icon: Icon(icons[i]),
          label: Text(labels[i]),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: wide
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'KEEPER’S JOURNAL',
                    style: TextStyle(letterSpacing: 2, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
                ...buttons,
                const Spacer(),
                const Text(
                  'Tab • Select\nEnter • Confirm\nEsc • Back',
                  style: TextStyle(height: 1.8, color: Color(0xff9bb0b9)),
                ),
              ],
            )
          : Wrap(alignment: WrapAlignment.center, children: buttons),
    );
  }

  Widget _status(GameState state, double width) => LayoutBuilder(
    builder: (context, constraints) {
      final cardWidth = constraints.maxWidth >= 620
          ? (constraints.maxWidth - 16) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final p in state.party)
            SizedBox(
              width: cardWidth,
              child: MenuPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          child: Text(
                            widget.content
                                .label('heroes', p.id)
                                .substring(0, 1),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.content.label('heroes', p.id),
                                style: const TextStyle(fontSize: 23),
                              ),
                              Text(
                                '${widget.content.label('jobs', p.jobId)} · Level ${p.level}',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _resource('HP', p.hp, p.maxHp, const Color(0xff83c6b5)),
                    const SizedBox(height: 14),
                    _resource('MP', p.mp, p.maxMp, const Color(0xff8baedb)),
                    const SizedBox(height: 18),
                    Text(
                      'Experience ${p.experience}  ·  Job progress ${p.jobProgress[p.jobId] ?? 0}',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Weapon: ${p.equipment['weapon'] == null ? 'None' : widget.content.label('items', p.equipment['weapon']!)}',
                    ),
                    Text(
                      'Body: ${p.equipment['body'] == null ? 'None' : widget.content.label('items', p.equipment['body']!)}',
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
  Widget _resource(String label, int current, int max, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('$label $current / $max', semanticsLabel: '$label $current of $max'),
      const SizedBox(height: 6),
      LinearProgressIndicator(
        value: max == 0 ? 0 : current / max,
        color: color,
        minHeight: 6,
        borderRadius: BorderRadius.circular(6),
      ),
    ],
  );

  Widget _inventory(GameState state, PartyMember member) {
    final bag = state.inventory.quantities.entries
        .where((e) => e.value > 0)
        .toList();
    if (bag.isEmpty) return const MenuPanel(child: Text('Your bag is empty.'));
    return Column(
      children: [
        for (final entry in bag)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: MenuPanel(
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 24,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 300,
                    child: Text(
                      '${widget.content.label('items', entry.key)} × ${entry.value}',
                      style: const TextStyle(fontSize: 19),
                    ),
                  ),
                  if (widget.content
                      .entries('items')
                      .any(
                        (e) =>
                            e.id == entry.key && e.text('kind') == 'consumable',
                      ))
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _submit(
                              UseItem(itemId: entry.key, memberId: member.id),
                            ),
                      child: Text(
                        'Use on ${widget.content.label('heroes', member.id)}',
                      ),
                    )
                  else
                    const Text('Equip from Equipment'),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _equipment(GameState state, PartyMember member) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final slot in ['weapon', 'body'])
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: MenuPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot == 'weapon' ? 'Weapon' : 'Body',
                  style: const TextStyle(fontSize: 22),
                ),
                const SizedBox(height: 8),
                Text(
                  'Equipped: ${member.equipment[slot] == null ? 'None' : widget.content.label('items', member.equipment[slot]!)}',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item
                        in widget.content
                            .entries('items')
                            .where(
                              (e) =>
                                  e.optionalText('slotId') == slot &&
                                  (state.inventory.quantities[e.id] ?? 0) > 0,
                            ))
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _submit(
                                EquipItem(
                                  memberId: member.id,
                                  slotId: slot,
                                  itemId: item.id,
                                ),
                              ),
                        child: Text('Equip ${item.name}'),
                      ),
                    OutlinedButton(
                      onPressed: _busy || member.equipment[slot] == null
                          ? null
                          : () => _submit(
                              EquipItem(memberId: member.id, slotId: slot),
                            ),
                      child: const Text('Unequip'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );
  Widget _jobs(PartyMember member) => Column(
    children: [
      for (final job in widget.content.entries('jobs'))
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: MenuPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(job.name, style: const TextStyle(fontSize: 22)),
                const SizedBox(height: 8),
                Text(job.description),
                const SizedBox(height: 8),
                Text(
                  'Abilities: ${job.strings('abilityIds').isEmpty ? 'Physical techniques' : job.strings('abilityIds').map((id) => widget.content.label('spells', id)).join(', ')}',
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: _busy || member.jobId == job.id
                        ? null
                        : () => _submit(
                            ChangeJob(memberId: member.id, jobId: job.id),
                          ),
                    child: Text(
                      member.jobId == job.id
                          ? 'Current job'
                          : 'Choose ${job.name}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}
