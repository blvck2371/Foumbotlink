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
    // Juste une frame, le temps que le logo soit peint : cette pause
    // était de 350 ms, ajoutées telles quelles à chaque démarrage à froid
    // par-dessus l'écran natif de lancement.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final onboarding = Get.find<OnboardingService>();
    if (onboarding.isCompleted) {
      Get.offAllNamed(AppRoutes.home);
    } else {
      Get.offAllNamed(AppRoutes.onboarding);
    }
  }
}
