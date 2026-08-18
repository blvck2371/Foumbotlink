import 'package:get/get.dart';

import '../controllers/compose_controller.dart';

class ComposeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(ComposeController.new);
  }
}
