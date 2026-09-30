import 'package:app_4/core/contracts.dart';
import 'package:app_4/progression.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rules = LanternJobRules();

  test('every hero can switch among the four unlocked starter jobs', () {
    var state = fixtureState();
    for (final hero in state.party) {
      for (final jobId in rules.starterJobIds.where((id) => id != hero.jobId)) {
        final result = rules.apply(
          state,
          ChangeJob(memberId: hero.id, jobId: jobId),
        );
        expect(result, isA<CommandAccepted>());
        state = (result as CommandAccepted).state;
        final changed = state.party.firstWhere(
          (member) => member.id == hero.id,
        );
        expect(changed.jobId, jobId);
      }
    }
  });

  test('job changes never restore HP or MP and transfer gear once', () {
    var state = fixtureState(
      jobs: ['job.white_mage', 'job.monk', 'job.white_mage', 'job.black_mage'],
      hp: 5,
      mp: 1,
      equipment: {'weapon': 'item.shell_staff', 'body': 'item.linen_robe'},
    );
    final toWarrior = accepted(
      rules.apply(state, ChangeJob(memberId: 'hero.ada', jobId: 'job.warrior')),
    );
    state = toWarrior;
    final warrior = state.party.first;
    expect(warrior.hp, 5);
    expect(warrior.mp, 0);
    expect(warrior.equipment, isEmpty);
    expect(state.inventory.quantities['item.shell_staff'], 1);
    expect(state.inventory.quantities['item.linen_robe'], 1);

    final toBlackMage = accepted(
      rules.apply(
        state,
        ChangeJob(memberId: 'hero.ada', jobId: 'job.black_mage'),
      ),
    );
    final blackMage = toBlackMage.party.first;
    expect(blackMage.hp, 5);
    expect(blackMage.mp, 0);

    final equipped = accepted(
      rules.apply(
        toBlackMage,
        EquipItem(
          memberId: 'hero.ada',
          slotId: 'weapon',
          itemId: 'item.shell_staff',
        ),
      ),
    );
    expect(equipped.party.first.equipment['weapon'], 'item.shell_staff');
    expect(
      equipped.inventory.quantities.containsKey('item.shell_staff'),
      isFalse,
    );
  });

  test('permanent XP levels at the boundary and job progress persists', () {
    var state = fixtureState(experience: 99, jobProgress: {'job.warrior': 7});
    state = rules.grantExperience(state, amount: 1, memberIds: ['hero.ada']);
    var ada = state.party.first;
    expect(ada.experience, 100);
    expect(ada.level, 2);
    expect(ada.jobProgress['job.warrior'], 8);
    expect(ada.maxHp, 44);

    state = accepted(
      rules.apply(state, ChangeJob(memberId: 'hero.ada', jobId: 'job.monk')),
    );
    state = rules.grantExperience(state, amount: 150, memberIds: ['hero.ada']);
    ada = state.party.first;
    expect(ada.experience, 250);
    expect(ada.level, 3);
    expect(ada.jobProgress['job.warrior'], 8);
    expect(ada.jobProgress['job.monk'], 150);

    state = accepted(
      rules.apply(state, ChangeJob(memberId: 'hero.ada', jobId: 'job.warrior')),
    );
    expect(state.party.first.jobProgress['job.warrior'], 8);
  });

  test('XP is authoritative when a legacy party member has a stale level', () {
    var state = fixtureState(level: 3, experience: 120);
    expect(rules.profileFor(state.party.first).maxHp, 44);

    state = accepted(
      rules.apply(state, ChangeJob(memberId: 'hero.ada', jobId: 'job.monk')),
    );
    final ada = state.party.first;
    expect(ada.level, 2);
    expect(ada.maxHp, 39);

    state = rules.grantExperience(state, amount: 1, memberIds: ['hero.ada']);
    expect(state.party.first.level, 2);
    expect(state.party.first.maxHp, 39);
  });

  test('equipment rejects restrictions and preserves state on rejection', () {
    final state = fixtureState(
      inventory: {'item.shell_staff': 1, 'item.rope_wraps': 1},
    );
    final blackMageOnly = rules.apply(
      state,
      EquipItem(
        memberId: 'hero.ada',
        slotId: 'weapon',
        itemId: 'item.shell_staff',
      ),
    );
    expect(blackMageOnly, isA<CommandRejected>());
    expect((blackMageOnly as CommandRejected).code, 'job_cannot_equip');
    expect(state.inventory.quantities['item.shell_staff'], 1);
    expect(state.party.first.equipment['weapon'], 'item.harbor_blade');

    final wrongSlot = rules.apply(
      state,
      EquipItem(
        memberId: 'hero.ada',
        slotId: 'body',
        itemId: 'item.rope_wraps',
      ),
    );
    expect((wrongSlot as CommandRejected).code, 'wrong_equipment_slot');
    expect(state.inventory.quantities['item.rope_wraps'], 1);
    expect(state.party.first.equipment['weapon'], 'item.harbor_blade');
  });
}

GameState fixtureState({
  List<String>? jobs,
  int hp = 20,
  int mp = 0,
  int level = 1,
  int experience = 0,
  Map<String, int>? jobProgress,
  Map<String, String>? equipment,
  Map<String, int>? inventory,
}) => GameState(
  position: WorldPosition(mapId: 'map.test', x: .5, y: .5),
  party: [
    for (final (index, id) in const [
      'hero.ada',
      'hero.ren',
      'hero.iona',
      'hero.tavi',
    ].indexed)
      PartyMember(
        id: id,
        jobId:
            jobs?[index] ??
            const [
              'job.warrior',
              'job.monk',
              'job.white_mage',
              'job.black_mage',
            ][index],
        hp: hp,
        maxHp: 50,
        mp: mp,
        maxMp: 40,
        level: level,
        experience: experience,
        jobProgress: jobProgress ?? {},
        equipment: index == 0
            ? (equipment ?? const {'weapon': 'item.harbor_blade'})
            : const {},
      ),
  ],
  inventory: Inventory(inventory ?? const {}),
  gold: 0,
  quests: QuestFlags(flags: const {}, openedChestIds: const {}),
);

GameState accepted(CommandResult result) => (result as CommandAccepted).state;
