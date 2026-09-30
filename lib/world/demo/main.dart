import 'package:flutter/material.dart';

import '../prototype_map.dart';
import '../world_view.dart';
import 'demo_host.dart';

void main() => runApp(const B1Demo());

/// Separate launch target so B1 never replaces A's main.dart or app flow.
class B1Demo extends StatefulWidget {
  const B1Demo({super.key});
  @override
  State<B1Demo> createState() => _B1DemoState();
}

class _B1DemoState extends State<B1Demo> {
  final _map = createPrototypeMap();
  late final _host = DemoWorldHost(_map);
  late final _builder = worldViewBuilder(_map);

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorSchemeSeed: const Color(0xffd3b276),
    ),
    home: Scaffold(
      backgroundColor: const Color(0xff0d1b22),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Icons.explore_outlined, color: Color(0xfff6cb70)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'APP–4  /  EXPLORATION',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'B1 practice room · Walk around the walls and test the corners.',
                  style: TextStyle(color: Color(0xffb5c4bd)),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _builder(context, _host, _host),
                ),
              ),
              const SizedBox(height: 8),
              AnimatedBuilder(
                animation: _host,
                builder: (context, child) => Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'TEST HOST',
                      style: TextStyle(fontSize: 11, color: Color(0xffa9bdb8)),
                    ),
                    for (final gate in DemoGate.values)
                      ChoiceChip(
                        label: Text(gate.name),
                        selected: _host.gate == gate,
                        onSelected: (_) => _host.setGate(gate),
                      ),
                    TextButton(
                      onPressed: _host.reset,
                      child: const Text('Reset position'),
                    ),
                    Text(
                      'x ${_host.state.position.x.toStringAsFixed(2)}   y ${_host.state.position.y.toStringAsFixed(2)}',
                      key: const ValueKey('position-readout'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
