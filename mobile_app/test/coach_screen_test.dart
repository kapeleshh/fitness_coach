import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitness_coach/screens/coach_screen.dart';
import 'package:fitness_coach/services/health_api_service.dart';

/// A service whose coach endpoint answers with [respond]; records questions.
HealthApiService _service(
  List<String> asked,
  Future<http.StreamedResponse> Function() respond,
) {
  return HealthApiService(
    client: MockClient.streaming((request, body) async {
      final sent = json.decode(await body.bytesToString()) as Map<String, dynamic>;
      asked.add(sent['question'] as String);
      return respond();
    }),
  );
}

http.StreamedResponse _streamed(List<String> chunks, [int status = 200]) =>
    http.StreamedResponse(Stream.fromIterable(chunks.map(utf8.encode)), status);

Future<void> _pumpCoach(WidgetTester tester, HealthApiService service) async {
  await tester.pumpWidget(MaterialApp(home: CoachScreen(service: service)));
}

void main() {
  testWidgets('streams the reply under the question', (tester) async {
    final asked = <String>[];
    await _pumpCoach(tester, _service(asked, () async => _streamed(['You slept ', 'well.'])));

    await tester.enterText(find.byType(TextField), 'How did I sleep?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(asked, ['How did I sleep?']);
    expect(find.text('How did I sleep?'), findsOneWidget);
    expect(find.text('You slept well.'), findsOneWidget);
    // The composer is cleared for the next question.
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testWidgets('suggestion chips ask their question', (tester) async {
    final asked = <String>[];
    await _pumpCoach(tester, _service(asked, () async => _streamed(['Yes, go hard.'])));

    expect(find.textContaining("aren't shared with the coach"), findsOneWidget);
    await tester.tap(find.text('Should I train hard today?'));
    await tester.pumpAndSettle();

    expect(asked, ['Should I train hard today?']);
    expect(find.text('Yes, go hard.'), findsOneWidget);
  });

  testWidgets('shows the server error when no model is reachable', (tester) async {
    final asked = <String>[];
    await _pumpCoach(
      tester,
      _service(asked, () async => _streamed(
            [json.encode({'error': 'Could not reach the LLM at http://localhost:11434/v1'})],
            503,
          )),
    );

    await tester.enterText(find.byType(TextField), 'Hi');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(find.text('Could not reach the LLM at http://localhost:11434/v1'), findsOneWidget);
  });

  testWidgets('shows a connection error when the backend is down', (tester) async {
    await _pumpCoach(
      tester,
      HealthApiService(
        client: MockClient.streaming((_, __) async => throw http.ClientException('refused')),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Hi');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't reach the coach"), findsOneWidget);
  });

  testWidgets('ignores blank questions', (tester) async {
    final asked = <String>[];
    await _pumpCoach(tester, _service(asked, () async => _streamed(['unused'])));

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(asked, isEmpty);
    expect(find.text('Ask about your recovery, sleep or training.'), findsOneWidget);
  });
}
