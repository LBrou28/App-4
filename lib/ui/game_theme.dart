import 'package:flutter/material.dart';

ThemeData lanternTheme() => ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  scaffoldBackgroundColor: const Color(0xff101d29),
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xffe7c482),
    brightness: Brightness.dark,
    primary: const Color(0xffe7c482),
    surface: const Color(0xff172936),
  ),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(fontSize: 18, height: 1.45),
    bodyMedium: TextStyle(fontSize: 16, height: 1.4),
    labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  ),
  cardTheme: const CardThemeData(margin: EdgeInsets.zero),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(120, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(100, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  ),
);

class MenuPanel extends StatelessWidget {
  const MenuPanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xff344752)),
    ),
    child: child,
  );
}
