import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:app_4/app/app_controller.dart';
import 'package:app_4/core/contracts.dart';
import 'package:app_4/core/fixtures/contract_fixture.dart';
import 'package:app_4/world/prototype_map.dart';
import 'package:app_4/world/world_map.dart';

WorldSession session() {
  final map = createPrototypeMap();
  return WorldSession(
    map: map,
    initialState: createContractFixture(position: map.spawns['entry']!),
    isClear: WorldCollision(map).isClear,
  );
}

void main() {
  test('publishes coherent movement synchronously; stale and reentrant writes do nothing', () async {
    final c = AppController(loadWorld: () async => session());
    addTearDown(c.dispose);
    await c.newGame();
    final revision = c.revision;
    final target = WorldPosition(mapId: c.map!.id, x: 3.5, y: 2.5);
    var notices = 0;
    c.addListener(() {
      notices++;
      expect(c.state.position, same(target));
      expect(c.revision, greaterThan(revision));
      expect(c.updatePosition(target, expectedRevision: c.revision), isFalse);
      expect(c.setPaused(true), isFalse);
    });
    expect(c.updatePosition(target, expectedRevision: revision), isTrue);
    expect(notices, 1);
    final accepted = c.state;
    expect(c.updatePosition(target, expectedRevision: revision), isFalse);
    expect(c.state, same(accepted));
    expect(notices, 1);
  });
  test('pause and resume invalidate old work without moving; walls and maps reject', () async {
    final c = AppController(loadWorld: () async => session());
    addTearDown(c.dispose);
    await c.newGame();
    final oldRevision = c.revision;
    final oldState = c.state;
    final seen = <bool>[];
    c.addListener(() => seen.add(c.movementEnabled));
    expect(c.setPaused(true), isTrue);
    expect(
      c.updatePosition(c.state.position, expectedRevision: c.revision),
      isFalse,
    );
    expect(c.setPaused(false), isTrue);
    expect(seen, [false, true]);
    expect(c.state, same(oldState));
    expect(
      c.updatePosition(c.state.position, expectedRevision: oldRevision),
      isFalse,
    );
    expect(
      c.updatePosition(
        WorldPosition(mapId: c.map!.id, x: .5, y: .5),
        expectedRevision: c.revision,
      ),
      isFalse,
    );
    expect(
      c.updatePosition(
        WorldPosition(mapId: 'other', x: 2.5, y: 2.5),
        expectedRevision: c.revision,
      ),
      isFalse,
    );
    expect(seen.length, 2);
  });
  test(
    'cancelled load cannot overwrite a newer session and revisions never reset',
    () async {
      final first = Completer<WorldSession>();
      var loads = 0;
      final c = AppController(
        loadWorld: () => ++loads == 1 ? first.future : Future.value(session()),
      );
      addTearDown(c.dispose);
      final pending = c.newGame();
      final loadingRevision = c.revision;
      await c.newGame(); // duplicate load is ignored
      expect(loads, 1);
      c.returnToTitle();
      await c.newGame();
      final latest = c.state;
      final revision = c.revision;
      first.complete(session());
      await pending;
      expect(c.state, same(latest));
      expect(c.revision, revision);
      expect(revision, greaterThan(loadingRevision));
      expect(
        c.updatePosition(c.state.position, expectedRevision: loadingRevision),
        isFalse,
      );
    },
  );
  test(
    'load failure and invalid spawn are recoverable without enabling movement',
    () async {
      var attempts = 0;
      final c = AppController(
        loadWorld: () async {
          if (++attempts == 1) throw StateError('asset failed');
          return session();
        },
      );
      addTearDown(c.dispose);
      await c.newGame();
      expect(c.mode, AppMode.error);
      expect(c.movementEnabled, isFalse);
      final failedRevision = c.revision;
      await c.newGame();
      expect(c.mode, AppMode.exploration);
      expect(c.error, isNull);
      expect(c.revision, greaterThan(failedRevision));
      final invalid = AppController(
        loadWorld: () async {
          final s = session();
          return WorldSession(
            map: s.map,
            initialState: createContractFixture(
              position: WorldPosition(mapId: s.map.id, x: .5, y: .5),
            ),
            isClear: s.isClear,
          );
        },
      );
      addTearDown(invalid.dispose);
      await invalid.newGame();
      expect(invalid.mode, AppMode.error);
    },
  );
  test(
    'unsupported encounters reject without any notification or mutation',
    () async {
      final c = AppController(loadWorld: () async => session());
      addTearDown(c.dispose);
      await c.newGame();
      final state = c.state;
      final revision = c.revision;
      var notifications = 0;
      c.addListener(() => notifications++);
      for (final r in [revision - 1, revision]) {
        expect(
          c.requestEncounter(
            EncounterRequest(definitionId: 'unknown'),
            expectedRevision: r,
          ),
          isFalse,
        );
      }
      expect(c.state, same(state));
      expect(c.revision, revision);
      expect(notifications, 0);
    },
  );
  test('disposed host rejects writes and late load completion', () async {
    final pending = Completer<WorldSession>();
    final c = AppController(loadWorld: () => pending.future);
    final load = c.newGame();
    final revision = c.revision;
    c.dispose();
    pending.complete(session());
    await load;
    expect(c.revision, revision);
    expect(c.movementEnabled, isFalse);
    expect(
      c.updatePosition(c.state.position, expectedRevision: revision),
      isFalse,
    );
    expect(c.setPaused(true), isFalse);
  });
}
