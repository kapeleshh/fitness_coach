import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/main_navigation.dart';

class FitnessCoachApp extends StatelessWidget {
  const FitnessCoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fitness Coach',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: const MainNavigation(),
    );
  }
}
