import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/calendar_api.dart';
import 'theme.dart';

void main() {
  runApp(LsuCalendarApp(repository: CalendarApi()));
}

class LsuCalendarApp extends StatelessWidget {
  const LsuCalendarApp({super.key, required this.repository, this.clock});

  final CalendarRepository repository;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LSU Calendar',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: HomeScreen(repository: repository, clock: clock),
    );
  }
}
