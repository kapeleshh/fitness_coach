/// Statistics shared by the engines, with the same arithmetic and the same
/// "can't tell" answers as their Python counterparts.
library;

import 'dart:math' as math;

import 'py.dart';

/// The mean of [values], as `sum(xs) / len(xs)`. Throws on an empty list,
/// as Python would.
double mean(List<num> values) {
  if (values.isEmpty) throw StateError('mean of empty data');
  return pySum(values) / values.length;
}

/// [mean], or null when there are no values.
double? meanOrNull(List<num> values) => values.isEmpty ? null : mean(values);

/// Sample standard deviation (n - 1), or 0.0 with fewer than two values, as
/// `readiness_engine._sample_sd`.
double sampleSd(List<num> values) {
  if (values.length < 2) return 0.0;
  final m = mean(values);
  return math.sqrt(pySum(values.map((x) => (x - m) * (x - m))) / (values.length - 1));
}

/// Pearson r over the positions where both values are present, as
/// `analytics_engine.pearson_correlation`. Null with fewer than 3 such pairs
/// or when either side is constant: "can't tell" must not read as "no
/// relationship" (0).
double? pearson(List<num?> x, List<num?> y) {
  final xs = <double>[];
  final ys = <double>[];
  for (var i = 0; i < math.min(x.length, y.length); i++) {
    final a = x[i];
    final b = y[i];
    if (a == null || b == null) continue;
    xs.add(a.toDouble());
    ys.add(b.toDouble());
  }
  final n = xs.length;
  if (n < 3) return null;
  final meanX = pySum(xs) / n;
  final meanY = pySum(ys) / n;
  final numerator = pySum([for (var i = 0; i < n; i++) (xs[i] - meanX) * (ys[i] - meanY)]);
  final denomX = math.sqrt(pySum(xs.map((v) => (v - meanX) * (v - meanX))));
  final denomY = math.sqrt(pySum(ys.map((v) => (v - meanY) * (v - meanY))));
  if (denomX * denomY == 0) return null;
  return numerator / (denomX * denomY);
}

/// The strength label for a correlation, as
/// `analytics_engine.categorize_strength`.
String categorizeStrength(double r) {
  final magnitude = r.abs();
  if (magnitude > 0.6) return 'strong';
  if (magnitude > 0.4) return 'moderate';
  if (magnitude > 0.2) return 'weak';
  return 'minimal';
}
