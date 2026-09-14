import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart';
import 'routes/app_pages.dart';
import 'screens/offline/offline_screen.dart';
import 'services/auth_service.dart';
import 'services/call_service.dart';
import 'services/callkit_helper.dart';
import 'services/feed_service.dart';
import 'services/chat_service.dart';
import 'services/connectivity_service.dart';
import 'services/demarche_service.dart';
import 'services/dossier_service.dart';
import 'services/follow_service.dart';
import 'services/local_notifications_service.dart';
import 'services/market_favorites_service.dart';
import 'services/market_service.dart';
import 'services/saved_search_service.dart';
import 'services/status_service.dart';
import 'services/seller_review_service.dart';
import 'services/moderation_service.dart';
import 'services/notification_service.dart';
import 'services/onboarding_service.dart';
import 'services/presence_service.dart';
import 'services/push_service.dart';
import 'services/user_profile_service.dart';
import 'services/weather_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

/// Réception d'un message FCM quand l'app est en arrière-plan ou tuée.
/// Doit rester une fonction top-level annotée `vm:entry-point` : elle tourne
/// dans un isolate séparé, sans le reste de l'app.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final data = message.data;
  switch (data['type']) {
    case 'incoming_call':
      await showCallkitIncomingFromData(data);
    case 'call_cancelled':
      await dismissCallkit(data['callId'] as String?);
  }
}

/// Action sur l'UI d'appel native pendant que l'app est tuée (« Refuser » /
/// expiration). « Répondre » relance l'app : PushService le récupère alors
/// via `FlutterCallkitIncoming.activeCalls()`.
@pragma('vm:entry-point')
Future<void> callkitBackgroundHandler(CallEvent event) async {
  switch (event) {
    case CallEventActionCallDecline(:final callKitParams):
      await _writeCallStatusFromBackground(callKitParams.id, 'declined');
    case CallEventActionCallTimeout(:final id):
      await _writeCallStatusFromBackground(id, 'missed');
    default:
      break;
  }
}

Future<void> _writeCallStatusFromBackground(
  String callId,
  String status,
) async {
  if (callId.isEmpty) return;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (FirebaseAuth.instance.currentUser == null) return;
    await FirebaseFirestore.instance.collection('calls').doc(callId).update({
      'status': status,
      'endedAt': FieldValue.serverTimestamp(),
    });
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Cache hors-ligne borné à 100 Mo : assez pour garder l'historique récent
  // (conversations, feed) consultable hors connexion, mais avec éviction LRU.
  // `CACHE_SIZE_UNLIMITED` désactivait complètement le garbage-collector du
  // cache local : la base SQLite grossissait sans fin et chaque requête la
  // rescannait entièrement → "Long db operation" à répétition + l'app qui
  // rame même avec du réseau.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 100 * 1024 * 1024,
  );

  // Appels entrants quand l'app n'est pas au premier plan : le message FCM
  // réveille cet isolate, qui lève l'écran d'appel CallKit ; l'action
  // « Refuser » depuis app tuée passe par le handler CallKit.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Android uniquement : `registerBackgroundHandler` n'existe que dans la
  // partie Kotlin de flutter_callkit_incoming — le plugin iOS ne
  // l'implémente pas, et l'appel se soldait par une
  // `MissingPluginException` (« No implementation found for method
  // registerBackgroundHandler on channel flutter_callkit_incoming »), non
  // attendue donc jamais rattrapée, qui remontait au démarrage de chaque
  // session iOS. Côté iOS, un appel reçu app fermée arrive de toute façon
  // par PushKit et est traité nativement par `CallkitIncomingAppDelegate` :
  // il n'y a rien à enregistrer depuis Dart.
  if (defaultTargetPlatform == TargetPlatform.android && !kIsWeb) {
    try {
      await FlutterCallkitIncoming.onBackgroundMessage(
        callkitBackgroundHandler,
      );
    } catch (e) {
      // Un enregistrement raté prive des actions d'appel app tuée, pas de
      // l'application : le démarrage doit continuer.
      debugPrint('CallKit : enregistrement du handler impossible — $e');
    }
  }
  await initializeDateFormatting('fr_FR');

  // Manrope/Space Grotesk sont utilisées sur quasi tous les écrans —
  // laissées en mode par défaut, google_fonts tente de les télécharger
  // depuis Google à chaque premier usage de chaque graisse (poids), ce
  // qui donnait l'impression que toute l'app "rame"/est hors-ligne dès
  // le lancement. Les polices sont maintenant embarquées dans
  // assets/fonts/google_fonts (voir pubspec.yaml) et prioritaires sur le
  // réseau ; on coupe complètement le fetch réseau en secours pour ne
  // plus jamais dépendre de la connectivité pour afficher du texte.
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* {
    for (final path in [
      'assets/fonts/google_fonts/Manrope-OFL.txt',
      'assets/fonts/google_fonts/SpaceGrotesk-OFL.txt',
    ]) {
      final license = await rootBundle.loadString(path);
      yield LicenseEntryWithLineBreaks(['google_fonts'], license);
    }
  });

  await Get.putAsync<OnboardingService>(
    () async => OnboardingService().init(),
    permanent: true,
  );
  Get.put<ThemeController>(ThemeController(), permanent: true);
  // Sonde le réseau en tâche de fond dès le lancement (voir
  // `ConnectivityService.onInit`) : rien à attendre ici, l'app
  // démarre optimiste et la page hors-connexion se lève d'elle-même
  // si la première sonde échoue.
  Get.put<ConnectivityService>(ConnectivityService(), permanent: true);
  Get.put<WeatherService>(WeatherService(), permanent: true);
  Get.put<AuthService>(AuthService(), permanent: true);
  Get.put<PresenceService>(PresenceService(), permanent: true);
  Get.put<UserProfileService>(UserProfileService(), permanent: true);
  Get.put(FeedService(), permanent: true);
  Get.put(MarketService(), permanent: true);
  Get.put(MarketFavoritesService(), permanent: true);
  Get.put(SavedSearchService(), permanent: true);
  Get.put(SellerReviewService(), permanent: true);
  Get.put(FollowService(), permanent: true);
  Get.put(DossierService(), permanent: true);
  Get.put(DemarcheService(), permanent: true);
  Get.put(ModerationService(), permanent: true);
  Get.put(NotificationService(), permanent: true);
  Get.put(StatusService(), permanent: true);
  Get.put(ChatService(), permanent: true);
  Get.put(CallService(), permanent: true);
  await Get.putAsync<LocalNotificationsService>(
    () async => LocalNotificationsService().init(),
    permanent: true,
  );
  Get.put(PushService(), permanent: true);

  runApp(const FoumbotlikApp());
}

class FoumbotlikApp extends StatelessWidget {
  const FoumbotlikApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();

    return Obx(
      () => GetMaterialApp(
        title: 'Foumbot Link',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeController.themeMode,
        initialRoute: AppPages.initial,
        getPages: AppPages.routes,
        defaultTransition: Transition.fadeIn,
        // Page « pas de connexion » posée au-dessus de tous les écrans —
        // voir [ConnectivityGate].
        builder: (context, child) =>
            ConnectivityGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
