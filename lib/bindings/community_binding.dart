import 'package:get/get.dart';

import '../controllers/community_controller.dart';
import '../controllers/contacts_controller.dart';

class CommunityBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(CommunityController.new);
  }
}

/// Numéro du compte et contacts retrouvés dans le répertoire.
class ContactsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(ContactsController.new);
  }
}
