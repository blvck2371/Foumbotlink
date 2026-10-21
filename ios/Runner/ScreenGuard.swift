import Flutter
import UIKit

/// Surveillance de la capture d'écran, côté iOS.
///
/// iOS n'a pas d'équivalent de `FLAG_SECURE` : le système n'offre aucun
/// moyen d'empêcher une capture. Ce qu'il offre, ce sont deux signaux —
/// et ils n'ont pas la même valeur :
///
///  - `UIScreen.isCaptured` dit qu'un enregistrement d'écran ou une
///    recopie (AirPlay, câble) est **en cours**. Il se lit *avant* que
///    quoi que ce soit soit capté, donc l'app peut masquer le contenu :
///    c'est une vraie protection.
///  - `userDidTakeScreenshotNotification` arrive **après** la capture. On
///    ne peut plus rien empêcher ; tout ce qu'on peut faire, c'est le dire
///    à qui a envoyé le message.
///
/// Le canal est le même que sur Android (`foumbot/screen_guard`) et les
/// méthodes portent les mêmes noms, mais elles ne font pas la même chose :
/// ici `secure` ouvre la surveillance au lieu de verrouiller la fenêtre.
/// Côté Dart, `ScreenGuard` connaît cette différence.
final class ScreenGuard {
  private let channel: FlutterMethodChannel
  private var observers: [NSObjectProtocol] = []
  private var watching = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "foumbot/screen_guard",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "secure":
        self.start()
        result(nil)
      case "unsecure":
        self.stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Vrai si l'écran est enregistré ou recopié ailleurs.
  ///
  /// Lu sur les scènes connectées plutôt que sur `UIScreen.main`, obsolète
  /// depuis iOS 16 : une app peut avoir plusieurs fenêtres, et il suffit
  /// que l'une soit captée.
  private var isCaptured: Bool {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .contains { $0.screen.isCaptured }
  }

  /// La surveillance ne tourne que pendant l'affichage d'un contenu à vue
  /// unique : observer en permanence coûterait pour rien, et enverrait des
  /// événements dont personne n'a que faire.
  private func start() {
    guard !watching else { return }
    watching = true

    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: UIScreen.capturedDidChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.reportCapture()
      }
    )
    observers.append(
      center.addObserver(
        forName: UIApplication.userDidTakeScreenshotNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.channel.invokeMethod("screenshot", arguments: nil)
      }
    )

    // L'état de départ compte autant que ses changements : un
    // enregistrement peut déjà tourner au moment où l'on ouvre.
    reportCapture()
  }

  private func stop() {
    guard watching else { return }
    watching = false

    let center = NotificationCenter.default
    observers.forEach { center.removeObserver($0) }
    observers.removeAll()

    // Plus rien de sensible à l'écran : Dart repart d'un état neutre,
    // sans quoi un masque resterait posé sur la prochaine ouverture.
    channel.invokeMethod("captured", arguments: false)
  }

  private func reportCapture() {
    channel.invokeMethod("captured", arguments: isCaptured)
  }
}
