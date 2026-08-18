import 'package:get/get.dart';

import '../bindings/auth_binding.dart';
import '../bindings/compose_binding.dart';
import '../bindings/home_binding.dart';
import '../bindings/market_binding.dart';
import '../bindings/market_compose_binding.dart';
import '../bindings/onboarding_binding.dart';
import '../bindings/splash_binding.dart';
import '../screens/auth/auth_screen.dart';
import '../screens/compose/compose_screen.dart';
import '../screens/feed/feed_post_screen.dart';
import '../screens/feature/feature_placeholder_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/market/market_compose_screen.dart';
import '../screens/market/market_detail_screen.dart';
import '../screens/market/market_screen.dart';
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
    GetPage(
      name: AppRoutes.compose,
      page: () => const ComposeScreen(),
      binding: ComposeBinding(),
      transition: Transition.downToUp,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.auth,
      page: () => const AuthScreen(),
      binding: AuthBinding(),
      transition: Transition.downToUp,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.market,
      page: () => const MarketScreen(),
      binding: MarketBinding(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.marketDetail,
      page: () => const MarketDetailScreen(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.marketCompose,
      page: () => const MarketComposeScreen(),
      binding: MarketComposeBinding(),
      transition: Transition.downToUp,
      transitionDuration: const Duration(milliseconds: 320),
    ),
  ];
}
