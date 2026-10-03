import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitness_coach/screens/main_navigation.dart';
import 'package:fitness_coach/services/health_api_service.dart';

void main() {
  testWidgets('main navigation renders all five tabs', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MainNavigation()));
    // Give the screens' initState fetches time to fail fast against the
    // test environment's stubbed HTTP client.
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Coach'), findsOneWidget);
    expect(find.text('My Data'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Analyze'), findsOneWidget);
  });

  testWidgets('Analyze opens the analysis screens as pages', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MainNavigation()));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Analyze'));
    await tester.pump();
    expect(find.text('Predictions'), findsOneWidget);
    expect(find.text('AI Lab'), findsOneWidget);

    await tester.tap(find.text('Patterns'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('🔍 Pattern Explorer'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
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

    test('fetchReadiness decodes UTF-8 even without a charset', () async {
      final service = HealthApiService(
        client: MockClient((_) async => http.Response.bytes(
              utf8.encode(json.encode({'briefing': 'GREEN — train as planned'})),
              200,
              headers: {'content-type': 'text/plain'},
            )),
      );

      final readiness = await service.fetchReadiness();

      expect(readiness['briefing'], 'GREEN — train as planned');
    });

    test('API errors carry the server message', () async {
      final service = HealthApiService(
        client: MockClient((_) async => http.Response(
              json.encode({'error': 'Date must be YYYY-MM-DD'}),
              400,
              headers: {'content-type': 'application/json'},
            )),
      );

      expect(
        service.fetchTrainingLoad(),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'Date must be YYYY-MM-DD')),
      );
    });

    test('askCoach sends only the question and streams the reply', () async {
      Object? sent;
      final service = HealthApiService(
        client: MockClient.streaming((request, body) async {
          sent = json.decode(await body.bytesToString());
          return http.StreamedResponse(
            // An em dash split across chunks must still decode.
            Stream.fromIterable([
              utf8.encode('Rest '),
              [0xE2],
              [0x80, 0x94, ...utf8.encode(' then easy.')],
            ]),
            200,
          );
        }),
      );

      final reply = await service.askCoach('Train today?').join();

      expect(reply, 'Rest — then easy.');
      expect(sent, {'question': 'Train today?'});
    });

    test('askCoach surfaces a non-JSON error status', () {
      final service = HealthApiService(
        client: MockClient.streaming((_, __) async => http.StreamedResponse(
              Stream.value(utf8.encode('<html>Bad gateway</html>')),
              502,
            )),
      );

      expect(
        service.askCoach('hi').join(),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'Request failed (HTTP 502)')),
      );
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
