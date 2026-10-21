import 'dart:math' as math;

import 'package:coach_engine/src/civil_date.dart';
import 'package:coach_engine/src/py.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// Equal in value, in int-versus-float type, and in the sign of zero.
Matcher _samePython(num expected) => predicate<num>(
      (actual) =>
          actual == expected &&
          (actual is int) == (expected is int) &&
          actual.isNegative == expected.isNegative,
      'equals ${expected is int ? 'int' : 'float'} $expected',
    );

void main() {
  final cases = loadFixture('numerics') as Map<String, dynamic>;

  List<List<dynamic>> casesFor(String name) =>
      (cases[name] as List).cast<List<dynamic>>();

  test('pyRound matches round() in every recorded case', () {
    for (final [x as num, ndigits as int?, expected as num] in casesFor('round')) {
      expect(pyRound(x, ndigits), _samePython(expected), reason: 'round($x, $ndigits)');
    }
  });

  test('pyFixed matches fixed-point format() in every recorded case', () {
    for (final [x as num, spec as String, expected as String] in casesFor('format')) {
      final digits = int.parse(spec.substring(spec.indexOf('.') + 1, spec.length - 1));
      expect(pyFixed(x, digits, sign: spec.startsWith('+')), expected,
          reason: 'format($x, "$spec")');
    }
  });

  test('pySum matches sum() exactly, including compensated float sums', () {
    for (final [values as List, expected as num] in casesFor('sum')) {
      expect(pySum(values.cast<num>()), _samePython(expected), reason: 'sum($values)');
    }
  });

  test('pyRepr matches repr() of floats', () {
    for (final [x as num, expected as String] in casesFor('repr')) {
      expect(pyRepr(x.toDouble()), expected, reason: 'repr($x)');
    }
  });

  test('pyStr shows values the way an f-string does', () {
    expect(pyStr(null), 'None');
    expect(pyStr(71), '71');
    expect(pyStr(71.0), '71.0');
    expect(pyStr(true), 'True');
    expect(pyStr('text'), 'text');
  });

  test('pyMedian matches statistics.median', () {
    for (final [values as List, expected as num] in casesFor('median')) {
      expect(pyMedian(values.cast<num>()), _samePython(expected), reason: 'median($values)');
    }
  });

  test('dart:math log and exp agree with Python to the last bit or close to it', () {
    for (final name in ['log', 'exp']) {
      for (final [x as num, expected as num] in casesFor(name)) {
        final actual = name == 'log' ? math.log(x) : math.exp(x);
        expect(actual, closeTo(expected, expected.abs() * 1e-15), reason: '$name($x)');
      }
    }
  });

  group('CivilDate', () {
    test('parses, prints and compares ISO dates', () {
      final date = CivilDate.parse('2026-07-07');
      expect(date.toString(), '2026-07-07');
      expect(date.addDays(-7).toString(), '2026-06-30');
      expect(date.addDays(1) > date, isTrue);
      expect(CivilDate.parse('2026-12-31').addDays(1), CivilDate(2027, 1, 1));
    });

    test('counts calendar days across a daylight-saving change', () {
      expect(CivilDate.parse('2026-03-30').daysSince(CivilDate.parse('2026-03-28')), 2);
      expect(CivilDate.parse('2026-11-02').daysSince(CivilDate.parse('2026-10-31')), 2);
    });

    test('weekday counts from Monday as 0, like Python', () {
      expect(CivilDate.parse('2026-11-02').weekday, 0); // a Monday
      expect(CivilDate.parse('2026-11-08').weekday, 6);
    });

    test('rejects malformed and impossible dates', () {
      expect(() => CivilDate.parse('2026-02-30'), throwsFormatException);
      expect(() => CivilDate.parse('2026-7-7'), throwsFormatException);
      expect(CivilDate.tryParse(null), isNull);
      expect(CivilDate.tryParse('not a date'), isNull);
    });
  });
}
