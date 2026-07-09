import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_coach/screens/main_navigation.dart';
import 'package:fitness_coach/services/health_api_service.dart';

void main() {
  testWidgets('main navigation renders all five tabs', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MainNavigation()));
    // Give the screens' initState fetches time to fail fast against the
    // test environment's stubbed HTTP client.
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('My Data'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Patterns'), findsOneWidget);
    expect(find.text('Predict'), findsOneWidget);
    expect(find.text('AI Lab'), findsOneWidget);
  });

  group('HealthApiService', () {
    test('calculateCorrelation finds a perfect positive correlation', () {
      final service = HealthApiService();
      service.setHealthDataForTest(List.generate(
        10,
        (i) => {
          'date': '2026-01-${(i + 1).toString().padLeft(2, '0')}',
          'sleep_score': 50 + i,
          'hrv': 40 + i * 2,
        },
      ));

      final result = service.calculateCorrelation('sleep_score', 'hrv');

      expect(result['strength'], 'strong');
      expect(result['correlation'], closeTo(1.0, 1e-9));
      expect(result['sampleSize'], 10);
    });

    test('calculateCorrelation reports insufficient data on empty set', () {
      final service = HealthApiService();
      service.setHealthDataForTest([]);

      final result = service.calculateCorrelation('sleep_score', 'hrv');

      expect(result['strength'], 'insufficient_data');
      expect(result['correlation'], 0.0);
    });

    test('calculateHealthScore combines weighted metrics into 0-100', () {
      final service = HealthApiService();

      final score = service.calculateHealthScore({
        'sleep_score': 80,
        'hrv': 60,
        'body_battery_start': 70,
        'avg_stress': 30,
        'steps': 8000,
      });

      // 80*0.25 + 60*0.20 + 70*0.20 + (100-30)*0.20 + 80*0.15 = 72
      expect(score, 72);
    });

    test('getWeeklyAverages ignores missing (zero) values', () {
      final service = HealthApiService();
      service.setHealthDataForTest([
        {'date': '2026-01-02', 'sleep_score': 80},
        {'date': '2026-01-01', 'sleep_score': 0}, // missing day
      ]);

      expect(service.getWeeklyAverages()['sleep'], 80.0);
    });
  });
}
