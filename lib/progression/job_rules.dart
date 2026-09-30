import '../core/contracts.dart';

/// Values exposed to battle and menu adapters for a member's current job.
final class JobProfile {
  const JobProfile({
    required this.jobId,
    required this.maxHp,
    required this.maxMp,
    required this.attack,
    required this.defense,
    required this.speed,
    required this.commandIds,
    required this.equipmentIds,
  });

  final String jobId;
  final int maxHp;
  final int maxMp;
  final int attack;
  final int defense;
  final int speed;
  final Set<String> commandIds;
  final Set<String> equipmentIds;
}

/// C4's intentionally small, data-independent job table.
///
/// The IDs and command/equipment lists mirror D4's current content. Keep this
/// table in sync with that content until the shared catalog exposes those fields
/// to rule modules.
final class JobSpec {
  const JobSpec({
    required this.id,
    required this.baseHp,
    required this.hpPerLevel,
    required this.baseMp,
    required this.mpPerLevel,
    required this.attack,
    required this.defense,
    required this.speed,
    required this.commandIds,
    required this.equipmentIds,
  });

  final String id;
  final int baseHp;
  final int hpPerLevel;
  final int baseMp;
  final int mpPerLevel;
  final int attack;
  final int defense;
  final int speed;
  final Set<String> commandIds;
  final Set<String> equipmentIds;

  JobProfile profileAt(int level) => JobProfile(
    jobId: id,
    maxHp: baseHp + (level - 1) * hpPerLevel,
    maxMp: baseMp + (level - 1) * mpPerLevel,
    attack: attack,
    defense: defense,
    speed: speed,
    commandIds: Set.unmodifiable(commandIds),
    equipmentIds: Set.unmodifiable(equipmentIds),
  );
}

final class EquipmentSpec {
  const EquipmentSpec({required this.id, required this.slotId});

  final String id;
  final String slotId;
}

/// Implements the C4 job and equipment commands.
///
/// A calls [apply] only while the party menu is open outside battle, then commits
/// an accepted snapshot once. [grantExperience] is intended for C's battle
/// reward adapter, which similarly returns the complete resulting snapshot.
final class LanternJobRules implements PartyRules {
  LanternJobRules({
    Map<String, JobSpec>? jobs,
    Map<String, EquipmentSpec>? items,
  }) : _jobs = Map.unmodifiable(jobs ?? _starterJobs),
       _items = Map.unmodifiable(items ?? _equipment) {
    if (_jobs.keys.toSet().length != _jobs.length ||
        !_starterJobIds.every(_jobs.containsKey)) {
      throw ArgumentError('C4 requires the four starter job definitions.');
    }
  }

  static const _starterJobIds = {
    'job.warrior',
    'job.monk',
    'job.white_mage',
    'job.black_mage',
  };

  static const _starterJobs = {
    'job.warrior': JobSpec(
      id: 'job.warrior',
      baseHp: 38,
      hpPerLevel: 6,
      baseMp: 0,
      mpPerLevel: 0,
      attack: 12,
      defense: 10,
      speed: 6,
      commandIds: {},
      equipmentIds: {'item.harbor_blade', 'item.keeper_coat'},
    ),
    'job.monk': JobSpec(
      id: 'job.monk',
      baseHp: 34,
      hpPerLevel: 5,
      baseMp: 0,
      mpPerLevel: 0,
      attack: 11,
      defense: 7,
      speed: 11,
      commandIds: {},
      equipmentIds: {'item.rope_wraps', 'item.keeper_coat'},
    ),
    'job.white_mage': JobSpec(
      id: 'job.white_mage',
      baseHp: 26,
      hpPerLevel: 3,
      baseMp: 10,
      mpPerLevel: 3,
      attack: 5,
      defense: 5,
      speed: 7,
      commandIds: {'spell.mend'},
      equipmentIds: {'item.shell_staff', 'item.linen_robe'},
    ),
    'job.black_mage': JobSpec(
      id: 'job.black_mage',
      baseHp: 24,
      hpPerLevel: 2,
      baseMp: 12,
      mpPerLevel: 4,
      attack: 6,
      defense: 4,
      speed: 8,
      commandIds: {'spell.ember', 'spell.rill'},
      equipmentIds: {'item.shell_staff', 'item.linen_robe'},
    ),
  };

  static const _equipment = {
    'item.harbor_blade': EquipmentSpec(
      id: 'item.harbor_blade',
      slotId: 'weapon',
    ),
    'item.rope_wraps': EquipmentSpec(id: 'item.rope_wraps', slotId: 'weapon'),
    'item.shell_staff': EquipmentSpec(id: 'item.shell_staff', slotId: 'weapon'),
    'item.keeper_coat': EquipmentSpec(id: 'item.keeper_coat', slotId: 'body'),
    'item.linen_robe': EquipmentSpec(id: 'item.linen_robe', slotId: 'body'),
  };

  final Map<String, JobSpec> _jobs;
  final Map<String, EquipmentSpec> _items;

  Set<String> get starterJobIds => Set.unmodifiable(_starterJobIds);

  JobProfile profileFor(PartyMember member) {
    final job = _jobs[member.jobId];
    if (job == null) throw ArgumentError.value(member.jobId, 'member.jobId');
    // Save data carries a display level, but XP is the progression source.
    return job.profileAt(levelForExperience(member.experience));
  }

  /// Each whole 100 character XP earns one character level. Job progress uses
  /// the same reward amount, but only for the job currently equipped.
  int levelForExperience(int experience) {
    if (experience < 0) throw ArgumentError.value(experience, 'experience');
    return experience ~/ 100 + 1;
  }

  /// Gives [amount] permanent character XP to each selected hero.
  ///
  /// Use the default recipient list for a victory party reward. Permanent XP
  /// derives the character level; only the active job's progress increases.
  GameState grantExperience(
    GameState current, {
    required int amount,
    Iterable<String>? memberIds,
  }) {
    if (amount < 0) throw ArgumentError.value(amount, 'amount');
    final recipients = (memberIds ?? current.party.map((member) => member.id))
        .toSet();
    if (!recipients.every(
      (id) => current.party.any((member) => member.id == id),
    )) {
      throw ArgumentError('Experience recipient is not in the party.');
    }
    return _copyState(
      current,
      party: [
        for (final member in current.party)
          recipients.contains(member.id)
              ? _withExperience(member, amount)
              : member,
      ],
    );
  }

  @override
  CommandResult apply(GameState current, MenuCommand command) =>
      switch (command) {
        ChangeJob() => _changeJob(current, command),
        EquipItem() => _equipItem(current, command),
        _ => CommandRejected(
          code: 'unsupported_command',
          message: 'That command is not handled by job rules.',
        ),
      };

  CommandResult _changeJob(GameState current, ChangeJob command) {
    final member = _member(current, command.memberId);
    if (member == null) return _unknownMember(command.memberId);
    final nextJob = _jobs[command.jobId];
    if (nextJob == null || !_starterJobIds.contains(command.jobId)) {
      return CommandRejected(
        code: 'job_unavailable',
        message: 'That job is not unlocked for this demo.',
      );
    }
    if (!_jobs.containsKey(member.jobId)) {
      return CommandRejected(
        code: 'invalid_current_job',
        message: 'This companion has an unknown current job.',
      );
    }
    if (member.jobId == command.jobId) {
      return CommandRejected(
        code: 'job_already_selected',
        message: 'This companion already has that job.',
      );
    }

    final bag = {...current.inventory.quantities};
    final equipment = {...member.equipment};
    for (final entry in member.equipment.entries) {
      if (!nextJob.equipmentIds.contains(entry.value)) {
        equipment.remove(entry.key);
        _addToBag(bag, entry.value);
      }
    }
    final progress = {...member.jobProgress};
    progress.putIfAbsent(command.jobId, () => 0);
    final level = levelForExperience(member.experience);
    final profile = nextJob.profileAt(level);
    final updated = _copyMember(
      member,
      jobId: command.jobId,
      level: level,
      hp: _clampResource(member.hp, profile.maxHp),
      maxHp: profile.maxHp,
      mp: _clampResource(member.mp, profile.maxMp),
      maxMp: profile.maxMp,
      jobProgress: progress,
      equipment: equipment,
    );
    return CommandAccepted(
      _copyState(
        current,
        party: _replaceMember(current.party, updated),
        inventory: Inventory(bag),
      ),
    );
  }

  CommandResult _equipItem(GameState current, EquipItem command) {
    final member = _member(current, command.memberId);
    if (member == null) return _unknownMember(command.memberId);
    final job = _jobs[member.jobId];
    if (job == null) {
      return CommandRejected(
        code: 'invalid_current_job',
        message: 'This companion has an unknown current job.',
      );
    }
    final equipped = member.equipment[command.slotId];
    if (command.itemId == null) {
      if (equipped == null) {
        return CommandRejected(
          code: 'nothing_equipped',
          message: 'There is no item equipped in that slot.',
        );
      }
      final bag = {...current.inventory.quantities};
      _addToBag(bag, equipped);
      final equipment = {...member.equipment}..remove(command.slotId);
      return CommandAccepted(
        _copyState(
          current,
          party: _replaceMember(
            current.party,
            _copyMember(member, equipment: equipment),
          ),
          inventory: Inventory(bag),
        ),
      );
    }

    final item = _items[command.itemId];
    if (item == null) {
      return CommandRejected(
        code: 'unknown_equipment',
        message: 'That item cannot be equipped.',
      );
    }
    if (item.slotId != command.slotId) {
      return CommandRejected(
        code: 'wrong_equipment_slot',
        message: 'That item does not fit this equipment slot.',
      );
    }
    if (!job.equipmentIds.contains(item.id)) {
      return CommandRejected(
        code: 'job_cannot_equip',
        message: 'This job cannot equip that item.',
      );
    }
    if ((current.inventory.quantities[item.id] ?? 0) <= 0) {
      return CommandRejected(
        code: 'item_not_in_bag',
        message: 'That item is not available in the bag.',
      );
    }
    if (equipped == item.id) {
      return CommandRejected(
        code: 'item_already_equipped',
        message: 'That item is already equipped.',
      );
    }
    final bag = {...current.inventory.quantities};
    _removeFromBag(bag, item.id);
    if (equipped != null) _addToBag(bag, equipped);
    final equipment = {...member.equipment}..[command.slotId] = item.id;
    return CommandAccepted(
      _copyState(
        current,
        party: _replaceMember(
          current.party,
          _copyMember(member, equipment: equipment),
        ),
        inventory: Inventory(bag),
      ),
    );
  }

  PartyMember _withExperience(PartyMember member, int amount) {
    final experience = member.experience + amount;
    final level = levelForExperience(experience);
    final progress = {...member.jobProgress};
    progress[member.jobId] = (progress[member.jobId] ?? 0) + amount;
    final profile = _jobs[member.jobId]!.profileAt(level);
    return _copyMember(
      member,
      level: level,
      experience: experience,
      hp: _clampResource(member.hp, profile.maxHp),
      maxHp: profile.maxHp,
      mp: _clampResource(member.mp, profile.maxMp),
      maxMp: profile.maxMp,
      jobProgress: progress,
    );
  }

  static PartyMember? _member(GameState state, String id) {
    for (final member in state.party) {
      if (member.id == id) return member;
    }
    return null;
  }

  static CommandRejected _unknownMember(String id) => CommandRejected(
    code: 'unknown_member',
    message: 'No companion named $id is in this party.',
  );

  static void _addToBag(Map<String, int> bag, String itemId) {
    bag[itemId] = (bag[itemId] ?? 0) + 1;
  }

  static void _removeFromBag(Map<String, int> bag, String itemId) {
    final remaining = bag[itemId]! - 1;
    if (remaining == 0) {
      bag.remove(itemId);
    } else {
      bag[itemId] = remaining;
    }
  }

  static int _clampResource(int value, int maximum) =>
      value < 0 ? 0 : (value > maximum ? maximum : value);

  static List<PartyMember> _replaceMember(
    List<PartyMember> party,
    PartyMember replacement,
  ) => [
    for (final member in party)
      member.id == replacement.id ? replacement : member,
  ];

  static GameState _copyState(
    GameState state, {
    List<PartyMember>? party,
    Inventory? inventory,
  }) => GameState(
    position: state.position,
    party: party ?? state.party,
    inventory: inventory ?? state.inventory,
    gold: state.gold,
    quests: state.quests,
  );

  static PartyMember _copyMember(
    PartyMember member, {
    String? jobId,
    int? hp,
    int? maxHp,
    int? mp,
    int? maxMp,
    int? level,
    int? experience,
    Map<String, int>? jobProgress,
    Map<String, String>? equipment,
  }) => PartyMember(
    id: member.id,
    jobId: jobId ?? member.jobId,
    hp: hp ?? member.hp,
    maxHp: maxHp ?? member.maxHp,
    mp: mp ?? member.mp,
    maxMp: maxMp ?? member.maxMp,
    level: level ?? member.level,
    experience: experience ?? member.experience,
    jobProgress: jobProgress ?? member.jobProgress,
    equipment: equipment ?? member.equipment,
  );
}
