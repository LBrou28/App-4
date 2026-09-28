import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'app/game_app.dart';
import 'core/fixtures/contract_fixture.dart';
import 'world/prototype_map.dart';
import 'world/world_map.dart';
import 'world/world_view.dart';

void main() => runApp(
  GameApp(
    loadWorld: () async {
      final map = createPrototypeMap();
      return WorldSession(
        map: map,
        initialState: createContractFixture(position: map.spawns['entry']!),
        isClear: WorldCollision(map).isClear,
      );
    },
    buildWorld: worldViewBuilder,
  ),
);
