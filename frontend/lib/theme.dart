import 'package:flutter/material.dart';

// LSU brand palette (LSU Brand Guide). Students may use LSU's colors, but
// not its logo, tiger eye, seal or athletics marks, so the app uses none.
const lsuPurple = Color(0xFF461D7C); // Official LSU Purple
const lsuGold = Color(0xFFFDD023); // Official LSU Gold
const corporatePurple = Color(0xFF3C1053);
const lightPurple = Color(0xFFA39AAC);
const corporateGold = Color(0xFFD29F13);
const lightGold = Color(0xFFF1EEDB);
const lightGray = Color(0xFFD0D0CE);
const gray50 = Color(0xFF999999);

/// Background of the bands that head each list section.
const sectionBackground = lightGold;

/// A flat, list-based look: a purple top bar naming the screen, light gold
/// section bands, plain white rows and a purple tab bar.
///
/// Text colors stick to the pairs in the brand guide's "Accessible Color
/// Combinations" chart (p. 49). Gold text on white is not on it, so
/// category colors only tint icons and badges; their labels use LSU Purple.
ThemeData buildTheme() {
  final colorScheme = ColorScheme.fromSeed(seedColor: lsuPurple).copyWith(
    primary: lsuPurple,
    onPrimary: Colors.white,
    primaryContainer: lightPurple,
    onPrimaryContainer: Colors.black,
    secondary: lsuGold,
    onSecondary: lsuPurple,
    secondaryContainer: lightGold,
    onSecondaryContainer: corporatePurple,
    tertiary: corporateGold,
    onTertiary: Colors.black,
    tertiaryContainer: corporateGold,
    onTertiaryContainer: Colors.black,
    surface: Colors.white,
    outline: gray50,
    outlineVariant: lightGray,
  );

  return ThemeData(
    colorScheme: colorScheme,
    // LSU's brand fonts (Forza, Proxima Nova, Sinter) are licensed, so the app
    // bundles Montserrat, a free font close to Proxima Nova.
    fontFamily: 'Montserrat',
    scaffoldBackgroundColor: Colors.white,
    // White on Official LSU Purple is on the guide's accessible list.
    appBarTheme: const AppBarTheme(
      backgroundColor: lsuPurple,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
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
      color: lightGray,
      space: 1,
      thickness: 1,
    ),
    cardTheme: const CardThemeData(elevation: 0.5),
  );
}
