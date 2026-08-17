import 'package:get/get.dart';

import '../bindings/home_binding.dart';
import '../bindings/onboarding_binding.dart';
import '../bindings/splash_binding.dart';
import '../screens/feed/feed_post_screen.dart';
import '../screens/feature/feature_placeholder_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/splash/splash_screen.dart';
import 'app_routes.dart';

class AppPages {
  static const initial = AppRoutes.splash;

  static final routes = <GetPage<dynamic>>[
    GetPage(
      name: AppRoutes.splash,
      page: () => const SplashScreen(),
      binding: SplashBinding(),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: AppRoutes.onboarding,
      page: () => const OnboardingScreen(),
      binding: OnboardingBinding(),
      transition: Transition.fadeIn,
      transitionDuration: const Duration(milliseconds: 400),
    ),
    GetPage(
      name: AppRoutes.home,
      page: () => const HomeScreen(),
      binding: HomeBinding(),
      transition: Transition.fadeIn,
      transitionDuration: const Duration(milliseconds: 400),
    ),
    GetPage(
      name: AppRoutes.feature,
      page: () => const FeaturePlaceholderScreen(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.feedPost,
      page: () => const FeedPostScreen(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
  ];
}
