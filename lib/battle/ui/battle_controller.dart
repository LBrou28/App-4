import 'package:flutter/foundation.dart';

import '../../core/contracts.dart' as shared;
import '../battle.dart';
import '../battle_session.dart';

/// Owns presentation/selections, never combat calculations.
final class BattleController extends ChangeNotifier {
  BattleController(
    this.session, {
    this.eventDelay = const Duration(milliseconds: 250),
  }) : _snapshot = session.snapshot;

  final BattleSession session;
  final Duration eventDelay;
  BattleSnapshot _snapshot;
  BattleSnapshot get snapshot => _snapshot;
  final List<HeroCommand> _commands = [];
  List<HeroCommand> get commands => List.unmodifiable(_commands);
  final List<BattleEvent> _events = [];
  List<BattleEvent> get events => List.unmodifiable(_events);
  bool targeting = false;
  bool busy = false;
  bool _disposed = false;
  bool _returned = false;
  String? message;

  List<Combatant> get livingHeroes => snapshot.combatants
      .where((c) => c.side == BattleSide.heroes && c.isAlive)
      .toList();
  Combatant? get active => _commands.length < livingHeroes.length
      ? livingHeroes[_commands.length]
      : null;
  shared.BattleResult? get result => busy ? null : session.result;
  bool get canChoose =>
      !busy && !_returned && session.result == null && !_disposed;
  bool get canSubmit => canChoose && active == null && !targeting;

  void attack() {
    if (!canChoose || active == null) return;
    targeting = true;
    message = null;
    notifyListeners();
  }

  void target(String id) {
    if (!canChoose ||
        !targeting ||
        active == null ||
        !snapshot.combatants.any(
          (c) => c.id == id && c.side == BattleSide.enemies && c.isAlive,
        )) {
      return;
    }
    _commands.add(HeroCommand.attack(active!.id, id));
    targeting = false;
    notifyListeners();
  }

  void defend() {
    if (!canChoose || active == null || targeting) return;
    _commands.add(HeroCommand.defend(active!.id));
    message = null;
    notifyListeners();
  }

  void back() {
    if (!canChoose) return;
    if (targeting) {
      targeting = false;
    } else if (_commands.isNotEmpty) {
      _commands.removeLast();
    }
    notifyListeners();
  }

  void edit(String actorId) {
    if (!canChoose) return;
    final index = _commands.indexWhere((c) => c.actorId == actorId);
    if (index < 0) return;
    _commands.removeRange(index, _commands.length);
    targeting = false;
    notifyListeners();
  }

  Future<void> submit() async {
    if (!canSubmit) return;
    busy = true; // Set before notifying or awaiting; repeated input is a no-op.
    message = 'Resolving round ${snapshot.round}…';
    _events.clear();
    notifyListeners();
    try {
      final resolved = session.resolve(snapshot.round, List.of(_commands));
      for (final event in resolved.events) {
        if (_disposed) return;
        _events.add(event);
        notifyListeners();
        await Future<void>.delayed(eventDelay);
      }
      if (_disposed) return;
      _snapshot = resolved.snapshot;
      _commands.clear();
      targeting = false;
      message = null;
    } catch (_) {
      if (_disposed) return;
      _snapshot = session.snapshot;
      _commands.clear();
      targeting = false;
      message =
          'The round could not be submitted. Please choose commands again.';
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> flee() async {
    if (!canChoose || session.fleePolicy == null) return;
    busy = true;
    message = 'Attempting escape…';
    notifyListeners();
    try {
      final escaped = await session.flee();
      if (!_disposed) {
        message = escaped
            ? null
            : 'Escape failed. Your commands are still selected.';
      }
    } catch (_) {
      if (!_disposed) message = 'Escape could not be checked. Try again.';
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  shared.BattleResult? takeResult() {
    if (_disposed || _returned || result == null) return null;
    _returned = true;
    notifyListeners();
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
