import 'package:flutter/material.dart';

const lsuPurple = Color(0xFF461D7C);
const lsuGold = Color(0xFFFDD023);

/// Background of the gray bands that head each list section.
const sectionGray = Color(0xFFEDEBF0);

/// A flat, list-based look: a white top bar, a purple bar naming the screen,
/// gray section bands, plain white rows and a purple tab bar.
ThemeData buildTheme() {
  final colorScheme = ColorScheme.fromSeed(seedColor: lsuPurple).copyWith(
    primary: lsuPurple,
    onPrimary: Colors.white,
    secondary: lsuGold,
    onSecondary: Colors.black,
    surface: Colors.white,
  );

  return ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: lsuPurple,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: lsuPurple,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: lsuPurple,
      surfaceTintColor: Colors.transparent,
      indicatorColor: lsuGold,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? lsuPurple
              : Colors.white,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE0DDE5),
      space: 1,
      thickness: 1,
    ),
    cardTheme: const CardThemeData(elevation: 0.5),
  );
}
