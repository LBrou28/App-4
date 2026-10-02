import '../core/contracts.dart';
import '../progression.dart';
import '../ui/content/demo_content.dart';

/// T3's server-only starting snapshot. It stays free of Flutter/UI imports so
/// the local WebSocket server can run under the standalone Dart VM.
GameState createLanternLinkInitialState(
  DemoContent content,
  WorldPosition position, {
  LanternJobRules? progression,
}) {
  final rules = progression ?? LanternJobRules();
  PartyMember member(ContentEntry hero) {
    final jobId = hero.text('jobId');
    final profile = rules.profileFor(
      PartyMember(
        id: hero.id,
        jobId: jobId,
        hp: 1,
        maxHp: 1,
        mp: 0,
        maxMp: 0,
        level: 1,
        experience: 0,
        jobProgress: {jobId: 0},
        equipment: {},
      ),
    );
    return PartyMember(
      id: hero.id,
      jobId: jobId,
      hp: profile.maxHp,
      maxHp: profile.maxHp,
      mp: profile.maxMp,
      maxMp: profile.maxMp,
      level: 1,
      experience: 0,
      jobProgress: {jobId: 0},
      equipment: {},
    );
  }

  return GameState(
    position: position,
    party: content.entries('heroes').map(member).toList(),
    inventory: Inventory({
      'item.salves': 2,
      'item.ether': 1,
      'item.revival': 1,
    }),
    gold: 0,
    quests: QuestFlags(flags: {}, openedChestIds: {}),
  );
}
