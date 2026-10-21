import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

/// A non-200 response from the API, carrying the server's `error` message.
class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Centralized API service for fetching real Garmin health data.
/// The single data-access layer for all screens.
class HealthApiService extends ChangeNotifier {
  /// [client] is injectable for tests (package:http/testing.dart MockClient).
  HealthApiService({http.Client? client}) : _client = client ?? http.Client();

  static const Duration _requestTimeout = Duration(seconds: 10);

  /// The coach answers only after the model produces its first token, and a
  /// local model can take a while to load on first use.
  static const Duration _coachTimeout = Duration(seconds: 90);

  final http.Client _client;

  List<Map<String, dynamic>> _healthData = [];
  Map<String, dynamic>? _summary;
  bool _isLoading = false;
  String? _error;
  DateTime? _lastSync;
  
  // Getters
  List<Map<String, dynamic>> get healthData => _healthData;
  Map<String, dynamic>? get summary => _summary;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime? get lastSync => _lastSync;
  int get totalDays => _healthData.length;
  
  /// Get today's data
  Map<String, dynamic>? get today => 
      _healthData.isNotEmpty ? _healthData.first : null;
  
  /// Get yesterday's data
  Map<String, dynamic>? get yesterday => 
      _healthData.length > 1 ? _healthData[1] : null;
  
  /// Get last 7 days
  List<Map<String, dynamic>> get last7Days => 
      _healthData.take(7).toList();
  
  /// Get last 30 days
  List<Map<String, dynamic>> get last30Days => 
      _healthData.take(30).toList();
  
  /// Initialize the service by fetching data from the API.
  Future<void> initialize() async {
    await refresh();
  }

  /// Force refresh data from API
  Future<void> refresh() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Fetch summary
      final summaryRes = await _client.get(
        Uri.parse('$apiBaseUrl/api/summary'),
      ).timeout(_requestTimeout);

      if (summaryRes.statusCode == 200) {
        _summary = json.decode(summaryRes.body);
      }

      // Fetch all health data
      final dataRes = await _client.get(
        Uri.parse('$apiBaseUrl/api/health-data'),
      ).timeout(_requestTimeout);

      if (dataRes.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(dataRes.body);
        _healthData = jsonList.cast<Map<String, dynamic>>();
        _lastSync = DateTime.now();
      }

      _isLoading = false;
    } catch (e) {
      _error = 'Unable to connect to the health data API at $apiBaseUrl. '
          'Make sure the backend server is running.';
      _isLoading = false;
      debugPrint('API Error: $e');
    }

    notifyListeners();
  }

  /// Fetch the backend analytics endpoints (correlations, anomalies,
  /// weekly patterns, baselines). Returns a map keyed by endpoint name.
  /// Throws on connection failure so callers can render an error state.
  Future<Map<String, Map<String, dynamic>>> fetchAnalytics() async {
    const endpoints = ['correlations', 'anomalies', 'weekly', 'baselines'];
    final responses = await Future.wait(endpoints.map(
      (e) => _client
          .get(Uri.parse('$apiBaseUrl/api/analytics/$e'))
          .timeout(_requestTimeout),
    ));

    final result = <String, Map<String, dynamic>>{};
    for (var i = 0; i < endpoints.length; i++) {
      final res = responses[i];
      if (res.statusCode != 200) {
        // Surface a clear error instead of letting json.decode throw on a
        // non-JSON error body, so callers can render an error state.
        throw Exception(
          'Analytics endpoint /${endpoints[i]} returned ${res.statusCode}',
        );
      }
      result[endpoints[i]] = json.decode(res.body) as Map<String, dynamic>;
    }
    return result;
  }

  // ============= READINESS, TRAINING LOAD, COACH =============

  /// Today's readiness, including the `training_load` object and the
  /// briefing with the training-load note appended.
  Future<Map<String, dynamic>> fetchReadiness() => _getJson('/api/readiness');

  /// Point-in-time readiness for the last [days] scored days, newest first.
  Future<Map<String, dynamic>> fetchReadinessHistory({int days = 14}) =>
      _getJson('/api/readiness/history?days=$days');

  /// Current fitness/fatigue/form, the last 7 days and recent sessions.
  Future<Map<String, dynamic>> fetchTrainingLoad() =>
      _getJson('/api/training-load');

  // Insights, Patterns and Predictions used to compute their numbers on the
  // device from 0-filled data; the backend now does it, with missing = null.

  /// Readiness, today's key metrics, rule-based insights, and this week
  /// against last week.
  Future<Map<String, dynamic>> fetchInsights() => _getJson('/api/insights');

  /// The curated correlations, strongest first, plus the number of `days`.
  Future<Map<String, dynamic>> fetchCorrelations() =>
      _getJson('/api/correlations');

  /// Correlation between any two daily metrics, [x] on a day against [y]
  /// [lag] days later.
  Future<Map<String, dynamic>> fetchCorrelationPair(String x, String y, {int lag = 0}) {
    final query = Uri(queryParameters: {'x': x, 'y': y, 'lag': '$lag'}).query;
    return _getJson('/api/correlations/pair?$query');
  }

  /// Tomorrow's predicted body battery, with the heuristic's measured error.
  Future<Map<String, dynamic>> fetchOutlook() => _getJson('/api/outlook');

  /// Stream the coach's reply to [question] as it is generated.
  ///
  /// The server builds all grounding context itself, so only the question is
  /// sent, and each question is answered independently. Throws
  /// [ApiException] with the server's message before any text arrives if the
  /// request is refused (e.g. 503 when no language model is reachable).
  Stream<String> askCoach(String question) async* {
    final request = http.Request('POST', Uri.parse('$apiBaseUrl/api/coach/chat'))
      ..headers['Content-Type'] = 'application/json'
      ..body = json.encode({'question': question});
    final response = await _client.send(request).timeout(_coachTimeout);
    if (response.statusCode != 200) {
      throw ApiException(
        _errorMessage(await response.stream.bytesToString(), response.statusCode),
      );
    }
    yield* response.stream.transform(utf8.decoder);
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final res = await _client
        .get(Uri.parse('$apiBaseUrl$path'))
        .timeout(_requestTimeout);
    // Decode the bytes as UTF-8 explicitly: FastAPI sends application/json
    // without a charset, and briefings contain non-ASCII punctuation.
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) {
      throw ApiException(_errorMessage(body, res.statusCode));
    }
    return json.decode(body) as Map<String, dynamic>;
  }

  static String _errorMessage(String body, int statusCode) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } on FormatException {
      // Not JSON: fall through to the generic message.
    }
    return 'Request failed (HTTP $statusCode)';
  }

  /// Get data for specific date range
  List<Map<String, dynamic>> getDateRange(DateTime start, DateTime end) {
    return _healthData.where((d) {
      final date = DateTime.parse(d['date']);
      return date.isAfter(start.subtract(const Duration(days: 1))) && 
             date.isBefore(end.add(const Duration(days: 1)));
    }).toList();
  }
  
  /// Get data for specific date
  Map<String, dynamic>? getDate(String dateStr) {
    try {
      return _healthData.firstWhere((d) => d['date'] == dateStr);
    } catch (e) {
      return null;
    }
  }
  
  // ============= DATA EXPORT =============
  
  /// Export data as CSV string
  String exportToCsv() {
    if (_healthData.isEmpty) return '';
    
    // Header
    var headers = [
      'date', 'sleep_score', 'deep_sleep_min', 'light_sleep_min', 'rem_sleep_min',
      'body_battery_start', 'body_battery_end', 'hrv', 'avg_stress',
      'steps', 'calories', 'resting_hr'
    ];
    
    var lines = [headers.join(',')];
    
    for (var day in _healthData) {
      var row = [
        day['date'],
        day['sleep_score'],
        day['deep_sleep_minutes'],
        day['light_sleep_minutes'],
        day['rem_sleep_minutes'],
        day['body_battery_start'],
        day['body_battery_end'],
        day['hrv'],
        day['avg_stress'],
        day['steps'],
        day['total_calories'],
        day['resting_hr'],
      ];
      lines.add(row.join(','));
    }
    
    return lines.join('\n');
  }
}

// Singleton instance
final healthApiService = HealthApiService();
