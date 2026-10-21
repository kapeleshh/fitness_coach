import 'package:flutter/foundation.dart';

/// A failed request, carrying the server's `error` message.
class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Where the screens get their data.
///
/// [HealthApiService] reads the self-hosted backend over HTTP. The public
/// app adds a source that computes the same JSON bodies on the phone, so the
/// screens work unchanged with either. Failures are reported by throwing
/// [ApiException] with a message the screens can show.
abstract class HealthDataSource extends ChangeNotifier {
  /// Daily wellness records, newest first, in the 0-filled shape of
  /// `/api/health-data`. Filled by [refresh].
  List<Map<String, dynamic>> get healthData;

  /// The `/api/summary` body from the last [refresh], or null.
  Map<String, dynamic>? get summary;

  /// Why the last [refresh] failed, or null.
  String? get error;

  int get totalDays => healthData.length;

  List<Map<String, dynamic>> get last7Days => healthData.take(7).toList();

  /// Reload [healthData] and [summary].
  Future<void> refresh();

  /// The analytics bodies (correlations, anomalies, weekly patterns,
  /// baselines), keyed by name. Throws when any of them fails.
  Future<Map<String, Map<String, dynamic>>> fetchAnalytics();

  /// Today's readiness, including the `training_load` object and the
  /// briefing with the training-load note appended.
  Future<Map<String, dynamic>> fetchReadiness();

  /// Point-in-time readiness for the last [days] scored days, newest first.
  Future<Map<String, dynamic>> fetchReadinessHistory({int days = 14});

  /// Current fitness/fatigue/form, the last 7 days and recent sessions.
  Future<Map<String, dynamic>> fetchTrainingLoad();

  /// Readiness, today's key metrics, rule-based insights, and this week
  /// against last week.
  Future<Map<String, dynamic>> fetchInsights();

  /// The curated correlations, strongest first, plus the number of `days`.
  Future<Map<String, dynamic>> fetchCorrelations();

  /// Correlation between any two daily metrics, [x] on a day against [y]
  /// [lag] days later.
  Future<Map<String, dynamic>> fetchCorrelationPair(String x, String y, {int lag = 0});

  /// Tomorrow's predicted body battery, with the heuristic's measured error.
  Future<Map<String, dynamic>> fetchOutlook();

  /// Stream the coach's reply to [question] as it is generated. Throws
  /// [ApiException] before any text arrives if the request is refused.
  Stream<String> askCoach(String question);
}
