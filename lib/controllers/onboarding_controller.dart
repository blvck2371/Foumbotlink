import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../routes/app_routes.dart';
import '../services/onboarding_service.dart';

enum OnboardingVisual { map, city, civic }

class OnboardingPageData {
  const OnboardingPageData({
    required this.visual,
    required this.scene,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.highlights = const [],
  });

  final OnboardingVisual visual;
  final String scene;
  final String eyebrow;
  final String title;
  final String subtitle;
  final List<OnboardingHighlight> highlights;
}

class OnboardingHighlight {
  const OnboardingHighlight({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}

class OnboardingController extends GetxController {
  static const pages = <OnboardingPageData>[
    OnboardingPageData(
      visual: OnboardingVisual.map,
      scene: 'welcome',
      eyebrow: 'Ouest Cameroun · Noun',
      title: 'Bienvenue à Foumbot',
      subtitle:
          'Voici le territoire de votre commune. Une carte vivante pour comprendre Foumbot, ses routes, ses quartiers et son rythme.',
    ),
    OnboardingPageData(
      visual: OnboardingVisual.city,
      scene: 'welcome',
      eyebrow: 'La ville',
      title: 'Au service de tous',
      subtitle:
          'Infos, démarches, annonces et échanges entre habitants.',
    ),
    OnboardingPageData(
      visual: OnboardingVisual.civic,
      scene: 'welcome',
      eyebrow: 'Ensemble',
      title: 'Une commune plus proche',
      subtitle:
          'Annonces, idées et dialogue avec la mairie — simplement.',
    ),
  ];

  final pageController = PageController();
  final index = 0.obs;

  OnboardingPageData get currentPage => pages[index.value];
  bool get isLast => index.value >= pages.length - 1;
  String get currentScene => currentPage.scene;

  void onPageChanged(int value) => index.value = value;

  void next() {
    if (isLast) {
      finish();
      return;
    }
    final goingTo = index.value + 1;
    pageController.nextPage(
      duration: Duration(milliseconds: goingTo >= 2 ? 640 : 480),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> finish() async {
    await Get.find<OnboardingService>().complete();
    Get.offAllNamed(AppRoutes.home);
  }

  @override
  void onClose() {
    pageController.dispose();
    super.onClose();
  }
}
