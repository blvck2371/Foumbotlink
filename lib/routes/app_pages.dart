import 'package:get/get.dart';

import '../bindings/auth_binding.dart';
import '../controllers/live_host_controller.dart';
import '../controllers/live_viewer_controller.dart';
import '../bindings/call_binding.dart';
import '../bindings/chat_binding.dart';
import '../bindings/community_binding.dart';
import '../bindings/directory_binding.dart';
import '../bindings/dossier_binding.dart';
import '../bindings/conversations_binding.dart';
import '../bindings/compose_binding.dart';
import '../bindings/home_binding.dart';
import '../bindings/market_binding.dart';
import '../bindings/market_compose_binding.dart';
import '../bindings/notifications_binding.dart';
import '../bindings/saved_posts_binding.dart';
import '../bindings/onboarding_binding.dart';
import '../bindings/profile_binding.dart';
import '../bindings/edit_profile_binding.dart';
import '../bindings/splash_binding.dart';
import '../screens/auth/auth_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/call/call_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/chat/conversations_screen.dart';
import '../screens/community/contact_suggestions_screen.dart';
import '../screens/community/community_screen.dart';
import '../screens/compose/compose_screen.dart';
import '../screens/feed/feed_post_screen.dart';
import '../screens/feature/feature_placeholder_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/lives/live_host_screen.dart';
import '../screens/lives/live_viewer_screen.dart';
import '../screens/lives/lives_screen.dart';
import '../screens/market/market_compose_screen.dart';
import '../screens/market/market_detail_screen.dart';
import '../screens/market/market_alerts_screen.dart';
import '../screens/market/market_screen.dart';
import '../screens/feed/saved_posts_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/directory/directory_screen.dart';
import '../screens/directory/pro_detail_screen.dart';
import '../screens/directory/pro_edit_screen.dart';
import '../screens/demarches/dossier_detail_screen.dart';
import '../screens/demarches/dossier_tracking_screen.dart';
import '../screens/demarches/structure_demarches_screen.dart';
import '../screens/demarches/structure_desk_screen.dart';
import '../screens/demarches/demarche_detail_screen.dart';
import '../screens/demarches/demarches_screen.dart';
import '../screens/moderation/moderation_screen.dart';
import '../screens/profile/user_profile_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/splash/splash_screen.dart';
import 'app_routes.dart';
import '../screens/search/search_screen.dart';

class AppPages {
  static const initial = AppRoutes.splash;

  static final routes = <GetPage<dynamic>>[
    GetPage(
      name: AppRoutes.splash,
      page: () => const SplashScreen(),
      binding: SplashBinding(),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: AppRoutes.onboarding,
      page: () => const OnboardingScreen(),
      binding: OnboardingBinding(),
      transition: Transition.fadeIn,
      transitionDuration: const Duration(milliseconds: 400),
    ),
    GetPage(
      name: AppRoutes.home,
      page: () => const HomeScreen(),
      binding: HomeBinding(),
      transition: Transition.fadeIn,
      transitionDuration: const Duration(milliseconds: 400),
    ),
    GetPage(
      name: AppRoutes.feature,
      page: () => const FeaturePlaceholderScreen(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.feedPost,
      page: () => const FeedPostScreen(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.search,
      page: () => const SearchScreen(),
      binding: SearchBinding(),
      transition: Transition.fadeIn,
      transitionDuration: const Duration(milliseconds: 200),
    ),
    GetPage(
      name: AppRoutes.savedPosts,
      page: () => const SavedPostsScreen(),
      binding: SavedPostsBinding(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.compose,
      page: () => const ComposeScreen(),
      binding: ComposeBinding(),
      transition: Transition.downToUp,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.auth,
      page: () => const AuthScreen(),
      binding: AuthBinding(),
      transition: Transition.downToUp,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.directory,
      page: () => const DirectoryScreen(),
      binding: DirectoryBinding(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.directoryDetail,
      page: () => const ProDetailScreen(),
      binding: DirectoryBinding(),
      transition: Transition.cupertino,
    ),
    GetPage(
      name: AppRoutes.directoryEdit,
      page: () => const ProEditScreen(),
      binding: DirectoryBinding(),
      transition: Transition.cupertino,
    ),
    GetPage(
      name: AppRoutes.market,
      page: () => const MarketScreen(),
      binding: MarketBinding(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.marketDetail,
      page: () => const MarketDetailScreen(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.marketCompose,
      page: () => const MarketComposeScreen(),
      binding: MarketComposeBinding(),
      transition: Transition.downToUp,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.marketAlerts,
      page: () => const MarketAlertsScreen(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.conversations,
      page: () => const ConversationsScreen(),
      binding: ConversationsBinding(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.chat,
      page: () => const ChatScreen(),
      binding: ChatBinding(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.call,
      page: () => const CallScreen(),
      binding: CallBinding(),
      opaque: true,
      fullscreenDialog: true,
      transition: Transition.downToUp,
      transitionDuration: const Duration(milliseconds: 260),
    ),
    GetPage(
      name: AppRoutes.community,
      page: () => const CommunityScreen(),
      binding: CommunityBinding(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.editProfile,
      page: () => const EditProfileScreen(),
      binding: EditProfileBinding(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.userProfile,
      page: () => const UserProfileScreen(),
      binding: ProfileBinding(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.demarches,
      page: () => const DemarchesScreen(),
      binding: DemarchesBinding(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.demarcheDetail,
      page: () => const DemarcheDetailScreen(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.dossiers,
      page: () => const DossierTrackingScreen(),
      binding: DossierBinding(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),

    GetPage(
      name: AppRoutes.dossierDetail,
      page: () => const DossierDetailScreen(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),

    GetPage(
      name: AppRoutes.structureDemarches,
      page: () => const StructureDemarchesScreen(),
      binding: StructureDemarchesBinding(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.structureDesk,
      page: () => const StructureDeskScreen(),
      binding: StructureDeskBinding(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),

    GetPage(
      name: AppRoutes.settings,
      page: () => const SettingsScreen(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.moderation,
      page: () => const ModerationScreen(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.contactSuggestions,
      page: () => const ContactSuggestionsScreen(),
      binding: ContactsBinding(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),

    GetPage(
      name: AppRoutes.lives,
      page: () => const LivesScreen(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
    GetPage(
      name: AppRoutes.liveHost,
      page: () => const LiveHostScreen(),
      binding: BindingsBuilder(() {
        Get.put(LiveHostController());
      }),
      transition: Transition.downToUp,
      transitionDuration: const Duration(milliseconds: 280),
    ),
    GetPage(
      name: AppRoutes.liveViewer,
      page: () => const LiveViewerScreen(),
      binding: BindingsBuilder(() {
        Get.put(LiveViewerController());
      }),
      transition: Transition.fadeIn,
      transitionDuration: const Duration(milliseconds: 220),
    ),

    GetPage(
      name: AppRoutes.notifications,
      page: () => const NotificationsScreen(),
      binding: NotificationsBinding(),
      transition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 320),
    ),
  ];
}
