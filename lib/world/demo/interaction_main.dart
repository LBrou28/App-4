import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/game_app.dart';
import '../../ui/content/demo_content.dart';
import '../interaction_world.dart';
import '../world_view.dart';

void main() => runApp(buildInteractionDemo());

/// A owns the real coordinator and dialogue route; B supplies geometry and input.
Widget buildInteractionDemo() {
  late InteractionWorld world;
  return GameApp(
    loadWorld: () async {
      world = InteractionWorld(
        DemoContent.decode(
          await rootBundle.loadString('assets/data/lantern_wake.json'),
        ),
      );
      return world.session();
    },
    buildWorld: (map) =>
        (context, host, changes) => WorldView(
          map: map,
          host: host,
          changes: changes,
          interactions: world.targets,
          landmarks: world.landmarks,
          mapName: world.names[map.id],
        ),
  );
}
