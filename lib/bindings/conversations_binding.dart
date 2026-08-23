import 'package:get/get.dart';

import '../controllers/conversations_controller.dart';

class ConversationsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(ConversationsController.new);
  }
}
