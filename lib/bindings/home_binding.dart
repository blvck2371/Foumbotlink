import 'package:get/get.dart';

import '../controllers/home_controller.dart';
import '../controllers/status_feed_controller.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(HomeController.new);
    // La barre de statuts a son propre flux temps réel et sa propre liste
    // d'abonnements : elle vit à côté du fil, pas dedans.
    Get.lazyPut(StatusFeedController.new);
  }
}
