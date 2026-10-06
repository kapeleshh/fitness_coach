import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitness_coach/screens/correlation_explorer_screen.dart';
import 'package:fitness_coach/screens/insights_feed_screen.dart';
import 'package:fitness_coach/screens/predictions_center_screen.dart';
import 'package:fitness_coach/services/health_api_service.dart';

// Shaped like the backend's responses; values are synthetic. Missing
// metrics are null, as the backend now sends them.

const _insights = {
  'date': '2026-07-07',
  'readiness': {'score': 74, 'band': 'green', 'label': 'Train as planned'},
  'today': {'sleep_score': null, 'hrv': 52.4, 'avg_stress': 31},
  'insights': [
    {
      'type': 'warning', 'category': 'Stress', 'title': 'Elevated Stress',
      'description': 'Average stress of 55 is higher than ideal.', 'icon': '😰',
      'metric': 'avg_stress', 'value': 55, 'benchmark': 33,
    },
    {
      'type': 'positive', 'category': 'Trend', 'title': 'Sleep Improving',
      'description': 'Your sleep score is up 6 points from last week!', 'icon': '📈',
      'metric': 'sleep_trend', 'value': 6.0, 'benchmark': null,
    },
  ],
  'weekly': {
    'date': '2026-07-07',
    'this_week': {'sleep': 78.4, 'hrv': null, 'stress': 31.0, 'steps': 8423.0},
    'last_week': {'sleep': 72.0, 'hrv': null, 'stress': 32.0, 'steps': 9000.0},
    'change': {'sleep': 6.4, 'hrv': null, 'stress': -1.0, 'steps': -577.0},
    'trends': {'sleep': 'improving', 'hrv': 'unknown', 'stress': 'stable', 'steps': 'declining'},
  },
};

const _correlations = {
  'days': 90,
  'correlations': [
    {
      'metric1': 'sleep_score', 'metric2': 'body_battery_start',
      'label': 'Sleep → Body Battery', 'lagged': false, 'correlation': 0.62,
      'strength': 'strong', 'sample_size': 88, 'metric1_avg': 74.1, 'metric2_avg': 66.0,
    },
  ],
};

const _outlook = {
  'date': '2026-07-07',
  'available': true,
  'predicted_body_battery': 48,
  'backtest': {'mean_abs_error': 11.6, 'days': 59},
  'recommended_intensity': 'low',
  'recommendation': 'Lower energy predicted. Consider light activity or rest.',
  'factors': [
    {'name': 'Recent Sleep', 'value': 75, 'impact': 'positive'},
    {'name': 'HRV Status', 'value': null, 'impact': 'unknown'},
  ],
  'today': {'sleep_score': 75, 'body_battery_end': 30, 'avg_stress': null, 'hrv': null},
  'weekly': {'sleep': 76.0, 'hrv': null, 'stress': 30.0, 'steps': 9100.0},
  'trends': {'sleep': 'stable', 'hrv': 'unknown', 'stress': 'improving', 'steps': 'declining'},
};

http.Response _json(Object body, [int status = 200]) => http.Response(
      json.encode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

/// A service answering [routes] by path; anything else is a 404.
HealthApiService _service(Map<String, http.Response Function(http.Request)> routes) {
  return HealthApiService(
    client: MockClient((request) async =>
        routes[request.url.path]?.call(request) ?? _json({'error': 'Not found'}, 404)),
  );
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  // Tall enough that every section is laid out.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

void main() {
  group('Insights', () {
    testWidgets('shows readiness, insights and weekly averages from the backend',
        (tester) async {
      await _pump(tester, InsightsFeedScreen(
        service: _service({'/api/insights': (_) => _json(_insights)}),
      ));

      expect(find.text('Readiness'), findsOneWidget);
      expect(find.text('74'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Elevated Stress'), findsOneWidget);
      expect(find.text('Avg: 33'), findsOneWidget);
      // No benchmark for the trend callout, so no value/average row.
      expect(find.text('Your value: 6.0'), findsNothing);
      expect(find.text('78'), findsOneWidget);       // this week's sleep
      expect(find.text('8.4k'), findsOneWidget);     // this week's steps
      // Missing metrics read "—", never 0.
      expect(find.text('—'), findsNWidgets(2));       // today's sleep, the week's HRV
      expect(find.text('0'), findsNothing);
    });

    testWidgets('shows the server error with a retry', (tester) async {
      await _pump(tester, InsightsFeedScreen(
        service: _service({'/api/insights': (_) => _json({'error': 'database is locked'}, 500)}),
      ));

      expect(find.text('database is locked'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('Patterns', () {
    final rawDays = [
      // Legacy 0-filled raw days: today's sleep wasn't recorded.
      {'date': '2026-07-07', 'sleep_score': 0, 'body_battery_start': 70, 'hrv': 51.0, 'avg_stress': 30},
      {'date': '2026-07-06', 'sleep_score': 77, 'body_battery_start': 65, 'hrv': 49.0, 'avg_stress': 33},
    ];

    HealthApiService patterns(Map<String, dynamic> pair) => _service({
          '/api/correlations': (_) => _json(_correlations),
          '/api/correlations/pair': (_) => _json(pair),
          '/api/summary': (_) => _json({'total_days': 2}),
          '/api/health-data': (_) => _json(rawDays),
        });

    testWidgets('lists the backend correlations', (tester) async {
      await _pump(tester, CorrelationExplorerScreen(
        service: patterns({'strength': 'insufficient_data', 'correlation': null, 'sample_size': 0}),
      ));

      expect(find.text('Based on 90 days of data'), findsOneWidget);
      expect(find.text('Sleep → Body Battery'), findsOneWidget);
      expect(find.text('62%'), findsOneWidget);
      expect(find.text('88'), findsOneWidget);
      // The 7-day chart shows today's unrecorded sleep as "—", not 0.
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('a pair without enough data shows a message, not a crash', (tester) async {
      await _pump(tester, CorrelationExplorerScreen(
        service: patterns({'strength': 'insufficient_data', 'correlation': null, 'sample_size': 3}),
      ));

      await tester.tap(find.text('Analyze Correlation'));
      await tester.pumpAndSettle();

      expect(find.text('Not enough days with both metrics to calculate a correlation'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a pair result shows its strength and sample', (tester) async {
      await _pump(tester, CorrelationExplorerScreen(
        service: patterns({
          'metric1': 'sleep_score', 'metric2': 'body_battery_start', 'lag_days': 0,
          'correlation': 0.45, 'strength': 'moderate', 'sample_size': 60,
          'metric1_avg': 74.0, 'metric2_avg': 66.0,
        }),
      ));

      await tester.tap(find.text('Analyze Correlation'));
      await tester.pumpAndSettle();

      expect(find.text('45%'), findsOneWidget);
      expect(find.text('MODERATE POSITIVE correlation'), findsOneWidget);
      expect(find.text('Based on 60 days with both metrics'), findsOneWidget);
    });
  });

  group('Predictions', () {
    testWidgets('shows the prediction with its measured error', (tester) async {
      await _pump(tester, PredictionsCenterScreen(
        service: _service({'/api/outlook': (_) => _json(_outlook)}),
      ));

      expect(find.text('48'), findsOneWidget);
      expect(find.text('LOW INTENSITY'), findsOneWidget);
      expect(find.text('Usually off by ~12 (tested on 59 days)'), findsOneWidget);
      expect(find.textContaining('Confidence'), findsNothing);
      // An unmeasured factor is "unknown", shown as N/A.
      expect(find.text('UNKNOWN'), findsOneWidget);
      expect(find.text('Value: N/A'), findsOneWidget);
      expect(find.text('9.1k'), findsOneWidget);
      expect(find.text('Not enough data yet'), findsOneWidget);   // HRV trend
      // The hard-coded "Optimal Times" card is gone.
      expect(find.textContaining('Optimal'), findsNothing);
    });

    testWidgets('explains when no prediction is possible', (tester) async {
      await _pump(tester, PredictionsCenterScreen(
        service: _service({
          '/api/outlook': (_) => _json({
                'available': false,
                'message': "Need a week of body battery data, including today's, for a prediction.",
                'today': {'sleep_score': null, 'body_battery_end': null, 'avg_stress': null, 'hrv': null},
                'weekly': {'sleep': null, 'hrv': null, 'stress': null, 'steps': null},
                'trends': {'sleep': 'unknown', 'hrv': 'unknown', 'stress': 'unknown', 'steps': 'unknown'},
              }),
        }),
      ));

      expect(find.textContaining('Need a week of body battery data'), findsOneWidget);
      expect(find.text('📈 Weekly Outlook'), findsNothing);
    });
  });
}
