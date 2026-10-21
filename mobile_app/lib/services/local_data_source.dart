import 'dart:convert';

import 'package:coach_engine/coach_engine.dart';
import 'package:coach_store/coach_store.dart';
import 'package:flutter/foundation.dart';

import 'health_data_source.dart';

/// The [HealthDataSource] of the public app: every body is computed on the
/// phone by the engines in coach_engine from the encrypted on-device store,
/// exactly as the backend would compute it.
///
/// Bodies go through a JSON round trip, so the screens receive the same
/// runtime types as from [HealthApiService]. There is no coach and no AI Lab
/// here yet, so [hasCoach] and [hasAnalytics] are false.
class LocalDataSource extends HealthDataSource {
  /// [openStore] opens the store on first use, e.g. `openLocalStore`.
  LocalDataSource({required Future<CoachStore> Function() openStore}) : _openStore = openStore;

  final Future<CoachStore> Function() _openStore;
  Future<CoachStore>? _store;

  List<Map<String, dynamic>> _healthData = [];
  Map<String, dynamic>? _summary;
  String? _error;

  @override
  List<Map<String, dynamic>> get healthData => _healthData;
  @override
  Map<String, dynamic>? get summary => _summary;
  @override
  String? get error => _error;
  @override
  bool get hasCoach => false;
  @override
  bool get hasAnalytics => false;

  /// Runs [body] on the open store and returns its result as decoded JSON.
  /// Every failure becomes an [ApiException] the screens can show.
  Future<dynamic> _read(Object? Function(CoachStore store) body) async {
    final CoachStore store;
    try {
      store = await (_store ??= _openStore());
    } catch (e) {
      _store = null; // try again next time
      debugPrint('Opening the on-device store failed: $e');
      throw ApiException("Couldn't open the data on this phone.");
    }
    try {
      return jsonDecode(jsonEncode(body(store)));
    } on ArgumentError catch (e) {
      throw ApiException('${e.message}');
    }
  }

  Future<Map<String, dynamic>> _readBody(Object? Function(CoachStore store) body) async =>
      await _read(body) as Map<String, dynamic>;

  @override
  Future<void> refresh() async {
    try {
      final bodies = await _read((s) {
        final days = s.allDays();
        return {'health_data': healthDataBody(days), 'summary': summaryBody(days)};
      }) as Map<String, dynamic>;
      _healthData = (bodies['health_data'] as List).cast<Map<String, dynamic>>();
      _summary = bodies['summary'] as Map<String, dynamic>;
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    }
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> fetchReadiness() => _readBody((s) => readinessBody(
      s.allDays(), s.activities(includeDuplicates: true), settings: s.allSettings()));

  @override
  Future<Map<String, dynamic>> fetchReadinessHistory({int days = 14}) =>
      _readBody((s) => readinessHistoryBody(s.allDays(), days: days));

  @override
  Future<Map<String, dynamic>> fetchTrainingLoad() => _readBody((s) => trainingLoadBody(
      s.allDays(), s.activities(includeDuplicates: true), settings: s.allSettings()));

  @override
  Future<Map<String, dynamic>> fetchInsights() => _readBody((s) => insightsBody(s.allDays()));

  @override
  Future<Map<String, dynamic>> fetchCorrelations() =>
      _readBody((s) => correlationsBody(s.allDays()));

  @override
  Future<Map<String, dynamic>> fetchCorrelationPair(String x, String y, {int lag = 0}) =>
      _readBody((s) => correlationPairBody(s.allDays(), x, y, lag: lag));

  @override
  Future<Map<String, dynamic>> fetchOutlook() => _readBody((s) => outlookBody(s.allDays()));

  @override
  Future<Map<String, Map<String, dynamic>>> fetchAnalytics() async =>
      throw ApiException("AI Lab isn't part of this version of the app.");

  @override
  Stream<String> askCoach(String question) async* {
    throw ApiException("The coach isn't part of this version of the app yet.");
  }
}
