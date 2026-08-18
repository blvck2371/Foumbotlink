import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'firebase_options.dart';
import 'routes/app_pages.dart';
import 'services/auth_service.dart';
import 'services/feed_service.dart';
import 'services/market_service.dart';
import 'services/onboarding_service.dart';
import 'services/user_profile_service.dart';
import 'services/weather_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await Get.putAsync<OnboardingService>(
    () async => OnboardingService().init(),
    permanent: true,
  );
  Get.put<ThemeController>(ThemeController(), permanent: true);
  Get.put<WeatherService>(WeatherService(), permanent: true);
  Get.put<AuthService>(AuthService(), permanent: true);
  Get.put<UserProfileService>(UserProfileService(), permanent: true);
  Get.put(FeedService(), permanent: true);
  Get.put(MarketService(), permanent: true);

  runApp(const FoumbotlikApp());
}

class FoumbotlikApp extends StatelessWidget {
  const FoumbotlikApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();

    return Obx(
      () => GetMaterialApp(
        title: 'Foumbot Link',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeController.themeMode,
        initialRoute: AppPages.initial,
        getPages: AppPages.routes,
        defaultTransition: Transition.fadeIn,
      ),
    );
  }
}
