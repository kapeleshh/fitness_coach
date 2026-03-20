import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'services/mock_data_service.dart';
import 'services/insight_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MockDataService()..initialize()),
        ChangeNotifierProxyProvider<MockDataService, InsightService>(
          create: (_) => InsightService(),
          update: (_, mockDataService, insightService) =>
              insightService!..updateWithData(mockDataService),
        ),
      ],
      child: const FitnessCoachApp(),
    ),
  );
}
