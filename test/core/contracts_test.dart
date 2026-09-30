import 'package:app_4/core/contracts.dart';
import 'package:app_4/core/fixtures/contract_fixture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('contract fixtures', () {
    test('fresh fixtures are valid and independent', () {
      final first = createContractFixture();
      final second = createContractFixture();
      expect(createFixtureCatalog().validate(first), isEmpty);
      expect(first.party, hasLength(4));
      expect(identical(first, second), isFalse);
      expect(identical(first.party, second.party), isFalse);
    });

    test('snapshot collections reject mutation', () {
      final state = createContractFixture();
      expect(() => state.party.clear(), throwsUnsupportedError);
      expect(
        () => state.inventory.quantities['fixture.item'] = 50,
        throwsUnsupportedError,
      );
      expect(
        () => state.party.first.jobProgress.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => state.party.first.equipment['hand'] = 'fixture.item',
        throwsUnsupportedError,
      );
      expect(() => state.quests.flags.add('finished'), throwsUnsupportedError);
      expect(
        () => state.quests.openedChestIds.add('chest'),
        throwsUnsupportedError,
      );
    });

    test('constructors copy caller-owned collections', () {
      final bag = {'fixture.item': 2};
      final flags = <String>{};
      final inventory = Inventory(bag);
      final quests = QuestFlags(flags: flags, openedChestIds: flags);
      bag['fixture.item'] = 100;
      flags.add('unexpected');
      expect(inventory.quantities['fixture.item'], 2);
      expect(quests.flags, isEmpty);
      expect(quests.openedChestIds, isEmpty);
    });
  });

  group('world boundary', () {
    test('non-finite, negative and missing coordinates/IDs are rejected', () {
      for (final x in [double.nan, double.infinity, -0.1]) {
        expect(
          () => WorldPosition(mapId: 'room', x: x, y: 0),
          throwsArgumentError,
        );
      }
      expect(() => WorldPosition(mapId: ' ', x: 0, y: 0), throwsArgumentError);
      expect(
        () => WorldPosition(mapId: 'room', x: 0, y: -1),
        throwsArgumentError,
      );
    });

    test(
      'map rejects shape mismatches, wrong map and blocked/outside spawns',
      () {
        MapDefinition make(List<bool> blocked, WorldPosition spawn) =>
            MapDefinition(
              id: 'room',
              width: 2,
              height: 2,
              blocked: blocked,
              spawns: {'entry': spawn},
            );
        expect(
          () => make([false], WorldPosition(mapId: 'room', x: 0.5, y: 0.5)),
          throwsArgumentError,
        );
        expect(
          () => make(
            List.filled(4, false),
            WorldPosition(mapId: 'other', x: 0.5, y: 0.5),
          ),
          throwsArgumentError,
        );
        expect(
          () => make(
            List.filled(4, true),
            WorldPosition(mapId: 'room', x: 0.5, y: 0.5),
          ),
          throwsArgumentError,
        );
        expect(
          () => make(
            List.filled(4, false),
            WorldPosition(mapId: 'room', x: 2, y: 0),
          ),
          throwsArgumentError,
        );
      },
    );

    test('catalog reports unknown map, outside position and blocked tile', () {
      final catalog = createFixtureCatalog();
      expect(
        catalog.validate(
          createContractFixture(
            position: WorldPosition(mapId: 'missing', x: 1.5, y: 1.5),
          ),
        ),
        ['Unknown map: missing'],
      );
      expect(
        catalog.validate(
          createContractFixture(
            position: WorldPosition(mapId: 'fixture.room', x: 3, y: 1.5),
          ),
        ),
        ['Position outside map: fixture.room'],
      );
      expect(
        catalog.validate(
          createContractFixture(
            position: WorldPosition(mapId: 'fixture.room', x: 0.5, y: 0.5),
          ),
        ),
        ['Position on blocked tile: fixture.room'],
      );
    });
  });

  group('party and references', () {
    test('invalid counts and blank IDs are rejected', () {
      expect(() => Inventory({'fixture.item': -1}), throwsArgumentError);
      expect(() => Inventory({'': 1}), throwsArgumentError);
      expect(() => ItemDefinition(id: ' item'), throwsArgumentError);
      expect(
        () => SaveData(contentVersion: '', state: createContractFixture()),
        throwsArgumentError,
      );
    });

    test('party enforces unique IDs and exactly four members', () {
      final fixture = createContractFixture();
      GameState make(List<PartyMember> party) => GameState(
        position: fixture.position,
        party: party,
        inventory: fixture.inventory,
        gold: 0,
        quests: fixture.quests,
      );
      expect(() => make(fixture.party.take(3).toList()), throwsArgumentError);
      expect(
        () => make(List.filled(4, fixture.party.first)),
        throwsArgumentError,
      );
    });

    test('HP/MP/XP constraints run in release builds too', () {
      PartyMember make({int hp = 10, int mp = 3, int xp = 0, int level = 1}) =>
          PartyMember(
            id: 'hero',
            jobId: 'job',
            hp: hp,
            maxHp: 10,
            mp: mp,
            maxMp: 3,
            level: level,
            experience: xp,
            jobProgress: {},
            equipment: {},
          );
      expect(() => make(hp: 11), throwsArgumentError);
      expect(() => make(hp: -1), throwsArgumentError);
      expect(() => make(mp: 4), throwsArgumentError);
      expect(() => make(xp: -1), throwsArgumentError);
      expect(() => make(level: 0), throwsArgumentError);
      expect(make(hp: 0).hp, 0);
    });

    test(
      'catalog accumulates unknown active and historical jobs and items',
      () {
        final fixture = createContractFixture();
        final member = PartyMember(
          id: 'replacement',
          jobId: 'missing.job',
          hp: 1,
          maxHp: 1,
          mp: 0,
          maxMp: 0,
          level: 1,
          experience: 0,
          jobProgress: {'missing.old.job': 2},
          equipment: {'hand': 'missing.gear'},
        );
        final state = GameState(
          position: fixture.position,
          party: [member, ...fixture.party.skip(1)],
          inventory: Inventory({'missing.item': 1}),
          gold: 0,
          quests: fixture.quests,
        );
        expect(
          createFixtureCatalog().validate(state),
          unorderedEquals([
            'Unknown job: missing.job',
            'Unknown job: missing.old.job',
            'Unknown equipped item: missing.gear',
            'Unknown inventory item: missing.item',
          ]),
        );
      },
    );

    test('catalog rejects aliases masquerading as definition IDs', () {
      expect(
        () => ContentCatalog(
          maps: {},
          jobs: {},
          items: {'alias': ItemDefinition(id: 'real')},
        ),
        throwsArgumentError,
      );
    });
  });

  group('battle message boundaries', () {
    test(
      'command copies targets and requires definitions only for item/ability',
      () {
        final targets = ['enemy.1'];
        final command = BattleCommand(
          actorId: 'hero',
          action: BattleAction.attack,
          targetIds: targets,
        );
        targets.clear();
        expect(command.targetIds, ['enemy.1']);
        expect(() => command.targetIds.clear(), throwsUnsupportedError);
        expect(
          () => BattleCommand(
            actorId: 'hero',
            action: BattleAction.item,
            targetIds: [],
          ),
          throwsArgumentError,
        );
        expect(
          () => BattleCommand(
            actorId: 'hero',
            action: BattleAction.attack,
            targetIds: [],
            definitionId: 'spell',
          ),
          throwsArgumentError,
        );
        expect(
          BattleCommand(
            actorId: 'hero',
            action: BattleAction.ability,
            targetIds: ['enemy.1'],
            definitionId: 'fixture.spell',
          ).definitionId,
          'fixture.spell',
        );
      },
    );

    test(
      'terminal result preserves correlation and immutable final snapshot',
      () {
        final fixture = createContractFixture();
        final party = fixture.party.toList();
        final result = BattleResult(
          encounterId: 'encounter.1',
          baseRevision: 7,
          outcome: BattleOutcome.victory,
          party: party,
          inventory: fixture.inventory,
          gold: 12,
        );
        party.clear();
        expect(result.party, hasLength(4));
        expect(result.encounterId, 'encounter.1');
        expect(result.baseRevision, 7);
        expect(result.gold, 12);
        expect(() => result.party.clear(), throwsUnsupportedError);
      },
    );

    test('negative revision or gold is not a valid terminal message', () {
      final fixture = createContractFixture();
      BattleResult make({int revision = 0, int gold = 0}) => BattleResult(
        encounterId: 'encounter',
        baseRevision: revision,
        outcome: BattleOutcome.fled,
        party: fixture.party,
        inventory: fixture.inventory,
        gold: gold,
      );
      expect(() => make(revision: -1), throwsArgumentError);
      expect(() => make(gold: -1), throwsArgumentError);
    });
  });
}
