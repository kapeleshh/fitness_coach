import 'package:fitness_coach/app.dart';
import 'package:fitness_coach/storage/local_store.dart';
import 'package:fitness_coach/storage/sample_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// On a device: writes the synthetic sample into the app's encrypted store
/// and checks that the app computes and shows readiness with no backend.
/// Run with
///   flutter test integration_test/on_device_data_test.dart -d <device>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the app shows readiness computed on the phone', (tester) async {
    final store = await openLocalStore();
    seedSampleDataIfEmpty(store);
    store.close();

    await tester.pumpWidget(const FitnessCoachApp());
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Connection Error'), findsNothing);
    expect(find.textContaining('/100'), findsWidgets); // the readiness briefing
    expect(find.text('Coach'), findsNothing);
  });
}
