import '../contracts.dart';

/// Synthetic boundary-test data only. Not D's game content or B's runtime map.
/// No balancing, art, progression or job-selection decisions are implied.
GameState createContractFixture({WorldPosition? position}) => GameState(
  position: position ?? WorldPosition(mapId: 'fixture.room', x: 1.5, y: 1.5),
  party: List.generate(
    4,
    (i) => PartyMember(
      id: 'fixture.hero.$i',
      jobId: 'fixture.job',
      hp: 10,
      maxHp: 10,
      mp: 3,
      maxMp: 3,
      level: 1,
      experience: 0,
      jobProgress: {'fixture.job': 0},
      equipment: {},
    ),
  ),
  inventory: Inventory({'fixture.item': 2}),
  gold: 0,
  quests: QuestFlags(flags: {}, openedChestIds: {}),
);

ContentCatalog createFixtureCatalog() => ContentCatalog(
  maps: {
    'fixture.room': MapDefinition(
      id: 'fixture.room',
      width: 3,
      height: 3,
      blocked: [true, true, true, true, false, true, true, true, true],
      spawns: {'entry': WorldPosition(mapId: 'fixture.room', x: 1.5, y: 1.5)},
    ),
  },
  jobs: {'fixture.job': JobDefinition(id: 'fixture.job', abilityIds: {})},
  items: {'fixture.item': ItemDefinition(id: 'fixture.item')},
);
