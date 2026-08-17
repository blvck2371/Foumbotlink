import 'package:get/get.dart';

import '../routes/app_routes.dart';
import '../services/onboarding_service.dart';

class SplashController extends GetxController {
  @override
  void onReady() {
    super.onReady();
    _redirect();
  }

  Future<void> _redirect() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final onboarding = Get.find<OnboardingService>();
    if (onboarding.isCompleted) {
      Get.offAllNamed(AppRoutes.home);
    } else {
      Get.offAllNamed(AppRoutes.onboarding);
    }
  }
}
