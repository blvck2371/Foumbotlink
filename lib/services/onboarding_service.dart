import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService extends GetxService {
  static const _key = 'foumbotlik_onboarding_done';

  late SharedPreferences _prefs;
  final completed = false.obs;

  Future<OnboardingService> init() async {
    _prefs = await SharedPreferences.getInstance();
    completed.value = _prefs.getBool(_key) ?? false;
    return this;
  }

  Future<void> complete() async {
    completed.value = true;
    await _prefs.setBool(_key, true);
  }

  Future<void> reset() async {
    completed.value = false;
    await _prefs.remove(_key);
  }

  bool get isCompleted => completed.value;
}
