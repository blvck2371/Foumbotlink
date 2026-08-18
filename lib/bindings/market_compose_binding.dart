import 'package:get/get.dart';

import '../controllers/market_compose_controller.dart';

class MarketComposeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<MarketComposeController>(() => MarketComposeController());
  }
}
