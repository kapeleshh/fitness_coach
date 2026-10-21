import 'dart:convert';
import 'dart:io';

import 'package:coach_engine/coach_engine.dart';
import 'package:coach_store/coach_store.dart';
import 'package:fitness_coach/screens/main_navigation.dart';
import 'package:fitness_coach/screens/today_screen.dart';
import 'package:fitness_coach/services/health_data_source.dart';
import 'package:fitness_coach/services/local_data_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The parity fixtures the Python engines wrote, shared with coach_engine.
Object? _fixture(String name) => jsonDecode(
    File('../packages/coach_engine/test/fixtures/$name.json').readAsStringSync());

/// An in-memory store holding the synthetic dataset the fixtures came from.
CoachStore _seededStore() => CoachStore.inMemory()
  ..upsertDays((_fixture('wellness') as List).cast<Json>(), origin: 'garmin')
  ..ingestActivities((_fixture('activities_raw') as List).cast<Json>());

void main() {
  final api = _fixture('api') as Map<String, dynamic>;

  group('LocalDataSource', () {
    late CoachStore store;
    late LocalDataSource source;
    setUp(() {
      store = _seededStore();
      source = LocalDataSource(openStore: () async => store);
    });
    tearDown(() => store.close());

    test('returns the body the backend returns for every request', () async {
      final requests = <String, Future<Object?> Function()>{
        '/api/readiness': source.fetchReadiness,
        '/api/readiness/history?days=14': () => source.fetchReadinessHistory(days: 14),
        '/api/training-load': source.fetchTrainingLoad,
        '/api/insights': source.fetchInsights,
        '/api/correlations': source.fetchCorrelations,
        '/api/correlations/pair?x=sleep_score&y=hrv&lag=0': () =>
            source.fetchCorrelationPair('sleep_score', 'hrv'),
        '/api/correlations/pair?x=avg_stress&y=sleep_score&lag=1': () =>
            source.fetchCorrelationPair('avg_stress', 'sleep_score', lag: 1),
        '/api/outlook': source.fetchOutlook,
      };
      for (final MapEntry(key: path, value: request) in requests.entries) {
        expect(await request(), api[path], reason: path);
      }
    });

    test('refresh loads the health data and summary', () async {
      await source.refresh();
      expect(source.error, isNull);
      expect(source.healthData, api['/api/health-data']);
      expect(source.summary, api['/api/summary']);
      expect(source.totalDays, 90);
    });

    test('has no coach and no AI Lab', () async {
      expect(source.hasCoach, isFalse);
      expect(source.hasAnalytics, isFalse);
      expect(source.askCoach('hi').toList(), throwsA(isA<ApiException>()));
      expect(source.fetchAnalytics(), throwsA(isA<ApiException>()));
    });

    test('reports a bad request as an ApiException with the server message', () {
      expect(
        source.fetchCorrelationPair('sleep_score', 'nope'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', "Unknown or missing metric: 'nope'")),
      );
    });

    test('a store that will not open is an error the screens can show, then retried', () async {
      var attempts = 0;
      final failing = LocalDataSource(openStore: () async {
        attempts++;
        throw StoreException('The key does not open this database');
      });
      await expectLater(failing.fetchReadiness(), throwsA(isA<ApiException>()));
      await failing.refresh();
      expect(failing.error, "Couldn't open the data on this phone.");
      expect(attempts, 2);
    });

    test('an empty store gives the empty bodies, not errors', () async {
      final empty = CoachStore.inMemory();
      addTearDown(empty.close);
      final fresh = LocalDataSource(openStore: () async => empty);
      expect((await fresh.fetchReadiness())['band'], 'unknown');
      expect((await fresh.fetchTrainingLoad())['confidence'], 'none');
      await fresh.refresh();
      expect(fresh.summary, {'error': 'No data available'});
      expect(fresh.healthData, isEmpty);
    });
  });

  group('the app on the on-device source', () {
    late CoachStore store;
    late LocalDataSource source;
    setUp(() {
      store = _seededStore();
      source = LocalDataSource(openStore: () async => store);
    });
    tearDown(() => store.close());

    testWidgets('Today shows the readiness score computed on the phone', (tester) async {
      await tester.pumpWidget(MaterialApp(home: TodayScreen(service: source)));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      final score = (api['/api/readiness'] as Map)['score'];
      expect(find.text('$score'), findsWidgets);
    });

    testWidgets('the navigation hides Coach and AI Lab', (tester) async {
      await tester.pumpWidget(MaterialApp(home: MainNavigation(service: source)));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();

      // "Today" is also the Today screen's own title once it has data.
      expect(find.text('Today'), findsWidgets);
      for (final label in ['My Data', 'Insights', 'Analyze']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Coach'), findsNothing);

      await tester.tap(find.text('Analyze'));
      await tester.pump();
      expect(find.text('Patterns'), findsOneWidget);
      expect(find.text('Predictions'), findsOneWidget);
      expect(find.text('AI Lab'), findsNothing);
    });
  });
}
