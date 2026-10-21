import 'package:coach_engine/coach_engine.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'support/json_diff.dart';

void main() {
  final wellness = (loadFixture('wellness') as List).cast<Json>();
  final activities = (loadFixture('activities') as List).cast<Json>();
  final api = loadFixture('api') as Json;

  final builders = <String, Object? Function()>{
    '/api/summary': () => summaryBody(wellness),
    '/api/health-data': () => healthDataBody(wellness),
    '/api/readiness': () => readinessBody(wellness, activities),
    '/api/readiness/history?days=14': () => readinessHistoryBody(wellness, days: 14),
    '/api/training-load': () => trainingLoadBody(wellness, activities),
    '/api/insights': () => insightsBody(wellness),
    '/api/correlations': () => correlationsBody(wellness),
    '/api/correlations/pair?x=sleep_score&y=hrv&lag=0': () =>
        correlationPairBody(wellness, 'sleep_score', 'hrv'),
    '/api/correlations/pair?x=avg_stress&y=sleep_score&lag=1': () =>
        correlationPairBody(wellness, 'avg_stress', 'sleep_score', lag: 1),
    '/api/outlook': () => outlookBody(wellness),
  };

  test('every request the app makes has a builder', () {
    expect(builders.keys.toSet(), api.keys.toSet());
  });

  test('summary of no data is the error body', () {
    expect(summaryBody([]), {'error': 'No data available'});
  });

  for (final MapEntry(key: path, value: build) in builders.entries) {
    test('$path matches the API body', () => expect(build(), sameJson(api[path])));
  }
}
