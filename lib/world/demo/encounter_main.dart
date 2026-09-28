import 'dart:math';

import 'package:flutter/material.dart';

import '../prototype_map.dart';
import '../world_encounters.dart';
import '../world_view.dart';
import 'demo_host.dart';

void main() => runApp(const B3Demo());

class SeededEncounterRandom implements EncounterRandom {
  final _random = Random(42);
  @override
  int nextInt(int max) => _random.nextInt(max);
}

class B3Demo extends StatefulWidget {
  const B3Demo({super.key});
  @override
  State<B3Demo> createState() => _B3DemoState();
}

class _B3DemoState extends State<B3Demo> {
  final _map = createPrototypeMap();
  late final _host = DemoWorldHost(_map, encounterIds: {'demo.patrol'});
  late final _encounters = EncounterStepper(
    zones: [
      EncounterZone(
        mapId: _map.id,
        left: 5,
        top: 1,
        width: 10,
        height: 10,
        definitionId: 'demo.patrol',
        rollDenominator: 3,
        rollThreshold: 1,
      ),
    ],
    random: SeededEncounterRandom(),
  );

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'B3 Encounter Demo\nWalk right: x ≥ 5 is the encounter area. Left side is safe.\nOne roll per tile walked; three safe steps after returning.',
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  WorldView(
                    map: _map,
                    host: _host,
                    changes: _host,
                    encounters: _encounters,
                  ),
                  AnimatedBuilder(
                    animation: _host,
                    builder: (context, child) => _host.activeEncounter == null
                        ? const SizedBox.shrink()
                        : Positioned.fill(
                            child: ColoredBox(
                              color: const Color(0xf0111824),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.shield_outlined, size: 64),
                                    const SizedBox(height: 20),
                                    const Text(
                                      'Encounter!',
                                      style: TextStyle(fontSize: 32),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text(
                                        'Test encounter screen · no combat or rewards',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    FilledButton(
                                      onPressed: _host.finishEncounter,
                                      child: const Text(
                                        'Return to exploration',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: _host,
              builder: (context, child) => Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'x ${_host.state.position.x.toStringAsFixed(2)} · y ${_host.state.position.y.toStringAsFixed(2)} · encounters ${_host.encounterCount}',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
