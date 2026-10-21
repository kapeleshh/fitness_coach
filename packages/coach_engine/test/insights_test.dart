import 'package:coach_engine/coach_engine.dart';
import 'package:coach_engine/src/py.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'support/json_diff.dart';

final _end = CivilDate(2026, 7, 7);

/// A record [offset] days before 2026-07-07 (newest = 0), as `_day` in
/// backend/tests/test_insights.py. Unset metrics are absent, i.e. null.
Json _day(int offset, [Json fields = const {}]) =>
    {'date': _end.addDays(-offset).toString(), ...fields};

List<Json> _days(int n, [Json fields = const {}]) => [for (var i = 0; i < n; i++) _day(i, fields)];

void main() {
  final wellness = (loadFixture('wellness') as List).cast<Json>();
  final api = loadFixture('api') as Json;

  group('parity with insights_engine.py and api_server.py', () {
    test('/api/insights', () => expect(insightsBody(wellness), sameJson(api['/api/insights'])));

    test('/api/correlations',
        () => expect(correlationsBody(wellness), sameJson(api['/api/correlations'])));

    test('/api/correlations/pair, same day and lagged', () {
      expect(correlationPairBody(wellness, 'sleep_score', 'hrv'),
          sameJson(api['/api/correlations/pair?x=sleep_score&y=hrv&lag=0']));
      expect(correlationPairBody(wellness, 'avg_stress', 'sleep_score', lag: 1),
          sameJson(api['/api/correlations/pair?x=avg_stress&y=sleep_score&lag=1']));
    });

    test('/api/outlook', () => expect(outlookBody(wellness), sameJson(api['/api/outlook'])));

    test('the pair body refuses unknown metrics and lags out of range', () {
      expect(() => correlationPairBody(wellness, 'sleep_score', 'nope'), throwsArgumentError);
      expect(() => correlationPairBody(wellness, null, 'hrv'), throwsArgumentError);
      expect(() => correlationPairBody(wellness, 'sleep_score', 'hrv', lag: 8), throwsArgumentError);
    });
  });

  // Ported from backend/tests/test_insights.py.
  group('lagged pairs', () {
    test('use calendar days and keep real zeros', () {
      final records = [
        _day(0, {'active_minutes': 0, 'deep_sleep_minutes': 95}),
        _day(1, {'active_minutes': 40, 'deep_sleep_minutes': 80}),
        // no record for 07-05
        _day(3, {'active_minutes': 10, 'deep_sleep_minutes': 70}),
        _day(4, {'active_minutes': 25, 'deep_sleep_minutes': 60}),
      ];
      final (xs, ys) = laggedPairs(records, 'active_minutes', 'deep_sleep_minutes', 1);
      expect(xs, [40.0, 25.0]);
      expect(ys, [95.0, 70.0]);
      final (sameDay, _) = laggedPairs(records, 'active_minutes', 'deep_sleep_minutes', 0);
      expect(sameDay, contains(0.0)); // a rest day is a real zero
    });
  });

  group('weeklySummary', () {
    test('averages, change and trends', () {
      final records = [
        for (var i = 0; i < 7; i++) _day(i, {'sleep_score': 82, 'avg_stress': 30, 'steps': 9000}),
        for (var i = 7; i < 14; i++) _day(i, {'sleep_score': 75, 'avg_stress': 36, 'steps': 8800}),
      ];
      final week = weeklySummary(records);
      expect(week['date'], '2026-07-07');
      expect((week['this_week'] as Json)['sleep'], 82.0);
      expect((week['last_week'] as Json)['sleep'], 75.0);
      expect((week['change'] as Json)['sleep'], 7.0);
      final trends = week['trends'] as Json;
      expect(trends['sleep'], 'improving');
      expect(trends['stress'], 'improving'); // lower is better
      expect(trends['steps'], 'stable'); // +200 steps is under 500
      expect(trends['hrv'], 'unknown'); // never measured
    });

    test('a change needs enough days in both weeks', () {
      final week = weeklySummary([
        ..._days(7, {'sleep_score': 80}),
        _day(8, {'sleep_score': 60}),
        _day(9, {'sleep_score': 60}),
      ]);
      expect((week['last_week'] as Json)['sleep'], 60.0);
      expect((week['change'] as Json)['sleep'], isNull);
      expect((week['trends'] as Json)['sleep'], 'unknown');
    });

    test('empty input', () {
      final week = weeklySummary([]);
      expect(week['date'], isNull);
      expect((week['this_week'] as Json)['sleep'], isNull);
    });
  });

  group('insights', () {
    test('missing metrics trigger nothing', () {
      final records = [
        _day(0, {'steps': 4000}),
        ..._days(13, {'sleep_score': 75, 'body_battery_start': 60}).skip(1),
      ];
      final titles = [for (final i in insights(records)) i['title']];
      expect(titles, isNot(contains('Poor Sleep Quality')));
      expect(titles, isNot(contains('Low Energy Reserves')));
    });

    test('rules fire with this week as the benchmark', () {
      final records = [
        _day(0, {'sleep_score': 45, 'hrv': 40.0, 'body_battery_start': 90, 'avg_stress': 55, 'steps': 12000}),
        for (var i = 1; i < 7; i++)
          _day(i, {'sleep_score': 80, 'hrv': 60.0, 'body_battery_start': 70, 'avg_stress': 30, 'steps': 8000}),
      ];
      final byTitle = {for (final i in insights(records)) i['title']: i};
      expect(byTitle.keys.toSet(), {
        'Poor Sleep Quality', 'Lower HRV Today', 'Fully Charged!',
        'Elevated Stress', 'Step Goal Achieved!',
      });
      expect(byTitle['Poor Sleep Quality']!['benchmark'], pyRound((45 + 6 * 80) / 7));
      expect(byTitle['Step Goal Achieved!']!['benchmark'], pyRound((12000 + 6 * 8000) / 7));
      expect(byTitle['Lower HRV Today']!['icon'], '\u{2764}\u{FE0F}');
    });

    test('the sleep-trend callout has no made-up average', () {
      final records = [
        ..._days(7, {'sleep_score': 70}),
        for (var i = 7; i < 14; i++) _day(i, {'sleep_score': 60}),
      ];
      final [trend] = [for (final i in insights(records)) if (i['metric'] == 'sleep_trend') i];
      expect(trend['value'], 10.0);
      expect(trend['benchmark'], isNull);
    });
  });

  group('correlation', () {
    test('perfect and lagged', () {
      final records = [for (var i = 0; i < 10; i++) _day(i, {'sleep_score': 60 + i, 'hrv': 30.0 + 2 * i})];
      final same = correlation(records, 'sleep_score', 'hrv');
      expect(same['correlation'], 1.0);
      expect(same['strength'], 'strong');
      expect(same['sample_size'], 10);
      expect(same['metric1_avg'], 64.5);
      expect(correlation(records, 'sleep_score', 'hrv', 1)['sample_size'], 9);
    });

    test('too few pairs or a constant metric is insufficient data', () {
      expect(correlation(_days(4, {'sleep_score': 1, 'hrv': 2.0}), 'sleep_score', 'hrv'),
          {'correlation': null, 'strength': 'insufficient_data', 'sample_size': 4});
      final flat = correlation(_days(10, {'sleep_score': 80, 'hrv': 50.0}), 'sleep_score', 'hrv');
      expect(flat['correlation'], isNull);
      expect(flat['strength'], 'insufficient_data');
    });

    test('discovery filters weak pairs and sorts strongest first', () {
      final records = [
        for (var i = 0; i < 20; i++)
          _day(i, {
            'sleep_score': 60 + i, 'body_battery_start': 40 + 3 * i,
            'avg_stress': 30 + (i * 7) % 5, 'hrv': 50.0 + (i * 3) % 4,
          }),
      ];
      final found = discoverCorrelations(records);
      final strengths = [for (final c in found) (c['correlation'] as num).abs()];
      expect(strengths, orderedEquals([...strengths]..sort((a, b) => b.compareTo(a))));
      expect(found.every((c) => c['strength'] != 'minimal' && c['strength'] != 'insufficient_data'), isTrue);
      expect([for (final c in found) c['label']], contains('Sleep → Body Battery'));
      expect(found.any((c) => c['lagged'] == true), isTrue);
    });
  });

  group('outlook', () {
    test('matches the hand-computed prediction', () {
      final records = [
        _day(0, {'body_battery_start': 60, 'body_battery_end': 30, 'avg_stress': 20, 'sleep_score': 75, 'hrv': 55.0}),
        ..._days(8, {'body_battery_start': 60}).skip(1),
      ];
      final out = outlook(records);
      // 0.6 x 60 (this week's mornings) + 0.4 x 30 (this evening) = 48
      expect(out['available'], isTrue);
      expect(out['predicted_body_battery'], 48);
      expect(out['recommended_intensity'], 'low');
      final impacts = {for (final f in (out['factors'] as List).cast<Json>()) f['name']: f['impact']};
      expect(impacts, {
        'Recent Sleep': 'positive', 'Current Stress': 'positive', 'HRV Status': 'unknown',
      });
    });

    test('high stress scales the prediction down', () {
      final records = [_day(0, {'body_battery_start': 60, 'body_battery_end': 30, 'avg_stress': 60})];
      expect(outlook(records)['predicted_body_battery'], pyRound(48 * 0.9));
    });

    test('the backtest is measured', () {
      // Every day predicts 0.6 x 60 + 0.4 x 30 = 48 for a next morning of 60.
      final records = _days(20, {'body_battery_start': 60, 'body_battery_end': 30, 'avg_stress': 20});
      expect(outlook(records)['backtest'], {'mean_abs_error': 12.0, 'days': 19});
      final short = _days(5, {'body_battery_start': 60, 'body_battery_end': 30});
      expect(outlook(short)['backtest'], isNull); // under backtestMinPairs
    });

    test("is unavailable without tonight's battery", () {
      final out = outlook([
        _day(0, {'body_battery_start': 60}),
        ..._days(8, {'body_battery_start': 60}).skip(1),
      ]);
      expect(out['available'], isFalse);
      expect(out.containsKey('message'), isTrue);
      expect(out.containsKey('predicted_body_battery'), isFalse);
    });
  });
}
