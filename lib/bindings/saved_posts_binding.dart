import 'package:get/get.dart';

import '../controllers/saved_posts_controller.dart';

class SavedPostsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(SavedPostsController.new);
  }
}
