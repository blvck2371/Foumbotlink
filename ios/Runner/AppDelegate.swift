import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Retenu par l'AppDelegate : il porte le gestionnaire du canal et les
  /// observateurs de capture, qui mourraient avec lui.
  private var screenGuard: ScreenGuard?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Requis pour afficher les notifications (appel manqué) au premier plan
    // et laisser firebase_messaging gérer le token APNs. Le câblage PushKit
    // (VoIP) + CallKit pour l'état tué sur iOS est une étape ultérieure,
    // conditionnée par un compte Apple Developer + certificat VoIP.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// App au premier plan : l'alerte « Appel entrant » est masquée, l'écran
  /// d'appel (CallKit) s'affiche déjà. Le reste suit le comportement
  /// normal de firebase_messaging.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if notification.request.content.userInfo["type"] as? String == "incoming_call" {
      completionHandler([])
      return
    }
    super.userNotificationCenter(
      center, willPresent: notification, withCompletionHandler: completionHandler)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    screenGuard = ScreenGuard(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
  }
}
