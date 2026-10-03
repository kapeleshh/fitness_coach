import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitness_coach/screens/today_screen.dart';
import 'package:fitness_coach/services/health_api_service.dart';

// Shaped like the backend's responses; values are synthetic.
const _readiness = {
  'date': '2026-07-07',
  'score': 79,
  'band': 'green',
  'label': 'Train as planned',
  'confidence': 'high',
  'flags': ['illness_watch', 'body_battery_capped'],
  'briefing': 'GREEN — readiness 79/100 (high confidence). Training load: '
      'carrying productive training fatigue (form -29% — fitness 51, fatigue 66).',
};

final _history = {
  'days': 14,
  'series': [
    for (var day = 7; day >= 1; day--)
      {'date': '2026-07-0$day', 'score': 60 + day * 3, 'band': 'amber'},
  ],
};

const _trainingLoad = {
  'date': '2026-07-07',
  'ctl': 50.9,
  'atl': 65.7,
  'tsb': -14.8,
  'form_pct': -29.1,
  'form_band': 'building',
  'acwr': 1.62,
  'confidence': 'high',
  'flags': ['load_spike'],
  'summary': 'Training load: carrying productive training fatigue.',
  'last_7_days': {'sessions': 2, 'load': 112.0, 'minutes': 85},
  'recent_sessions': [
    {
      'local_date': '2026-07-07', 'sport_family': 'run', 'minutes': 40.0,
      'load': 58.0, 'method': 'garmin_load', 'sources': ['garmin', 'strava'],
    },
    {
      'local_date': '2026-07-05', 'sport_family': 'ride', 'minutes': 45.0,
      'load': 54.0, 'method': 'duration_estimate', 'sources': ['strava'],
    },
  ],
};

http.Response _json(Object body, [int status = 200]) => http.Response(
      json.encode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

HealthApiService _service({bool trainingLoadFails = false}) {
  return HealthApiService(
    client: MockClient((request) async => switch (request.url.path) {
          '/api/readiness' => _json(_readiness),
          '/api/readiness/history' => _json(_history),
          '/api/training-load' => trainingLoadFails
              ? _json({'error': 'database is locked'}, 500)
              : _json(_trainingLoad),
          _ => _json({'error': 'Not found'}, 404),
        }),
  );
}

Future<void> _pumpToday(WidgetTester tester, HealthApiService service) async {
  // Tall enough that the whole list is laid out (ListView builds lazily).
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: TodayScreen(service: service)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows readiness, training load and recent sessions', (tester) async {
    await _pumpToday(tester, _service());

    // Readiness: score, label, briefing with the training-load note.
    expect(find.text('79'), findsOneWidget);
    expect(find.text('Train as planned'), findsOneWidget);
    expect(find.textContaining('carrying productive training fatigue (form'), findsOneWidget);
    // Only user-facing flags become chips.
    expect(find.text('Possible illness or overreaching'), findsOneWidget);
    expect(find.textContaining('body_battery'), findsNothing);
    expect(find.text('Readiness, last 14 days'), findsOneWidget);

    // Training load.
    expect(find.text('Building'), findsOneWidget);
    expect(find.text('51'), findsOneWidget);
    expect(find.text('66'), findsOneWidget);
    expect(find.text('-15'), findsOneWidget);
    expect(find.text('Form (-29%)'), findsOneWidget);
    expect(find.text('Load spike: acute:chronic 1.62'), findsOneWidget);

    // Sessions, with where each came from and how its load was measured.
    expect(find.text('Run · 40 min'), findsOneWidget);
    expect(find.text('Tue 7 Jul · Garmin + Strava'), findsOneWidget);
    expect(find.text('Garmin load'), findsOneWidget);
    expect(find.text('Estimated'), findsOneWidget);
  });

  testWidgets('one failing endpoint leaves the rest of the screen', (tester) async {
    await _pumpToday(tester, _service(trainingLoadFails: true));

    expect(find.text('Train as planned'), findsOneWidget);
    expect(find.text("Training load isn't available: database is locked"), findsOneWidget);
    expect(find.text('Recent sessions'), findsNothing);
  });

  testWidgets('no backend shows a retryable connection error', (tester) async {
    var calls = 0;
    final service = HealthApiService(
      client: MockClient((_) async {
        calls++;
        throw http.ClientException('Connection refused');
      }),
    );
    await _pumpToday(tester, service);

    expect(find.text('Connection Error'), findsOneWidget);
    expect(calls, 3);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 6);
  });
}
