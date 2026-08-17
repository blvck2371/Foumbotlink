import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/main.dart';
import 'package:foumbotlik/services/onboarding_service.dart';
import 'package:foumbotlik/services/weather_service.dart';
import 'package:foumbotlik/theme/theme_controller.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Get.reset();
    await Get.putAsync<OnboardingService>(
      () async => OnboardingService().init(),
      permanent: true,
    );
    Get.put<ThemeController>(ThemeController(), permanent: true);
    Get.put<WeatherService>(WeatherService(), permanent: true);
  });

  tearDown(Get.reset);

  testWidgets('Affiche le splash carte puis l’onboarding', (tester) async {
    await tester.pumpWidget(const FoumbotlikApp());
    await tester.pump();

    expect(find.byType(Image), findsWidgets);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Foumbot'), findsOneWidget);
    expect(find.text('Bienvenue à Foumbot'), findsOneWidget);
    expect(find.text('Continuer'), findsOneWidget);
  });
}
