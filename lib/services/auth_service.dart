import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

/// Authentification Firebase — email/mot de passe et téléphone/SMS.
/// Retourne `null` en cas de succès, sinon un message d'erreur en
/// français prêt à afficher à l'utilisateur.
class AuthService extends GetxService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final firebaseUser = Rxn<User>();

  bool get isSignedIn => firebaseUser.value != null;
  String get uid => firebaseUser.value!.uid;

  @override
  void onInit() {
    super.onInit();
    firebaseUser.bindStream(_auth.authStateChanges());
  }

  Future<String?> signUpWithEmail(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return null;
    } on FirebaseAuthException catch (e) {
      return _messageFor(e);
    } catch (_) {
      return _genericError;
    }
  }

  Future<String?> signInWithEmail(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return null;
    } on FirebaseAuthException catch (e) {
      return _messageFor(e);
    } catch (_) {
      return _genericError;
    }
  }

  Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return _messageFor(e);
    } catch (_) {
      return _genericError;
    }
  }

  /// Envoie le code SMS. `onCodeSent` reçoit l'id de vérification à
  /// fournir ensuite à [confirmPhoneCode]. Sur Android, la vérification
  /// peut aboutir automatiquement (sans saisie de code) — dans ce cas
  /// [onAutoVerified] est appelé directement.
  Future<void> sendPhoneCode({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String message) onError,
    required void Function() onAutoVerified,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber.trim(),
        verificationCompleted: (credential) async {
          try {
            await _auth.signInWithCredential(credential);
            onAutoVerified();
          } on FirebaseAuthException catch (e) {
            onError(_messageFor(e));
          } catch (_) {
            onError(_genericError);
          }
        },
        verificationFailed: (e) => onError(_messageFor(e)),
        codeSent: (verificationId, _) => onCodeSent(verificationId),
        codeAutoRetrievalTimeout: (_) {},
      );
    } on FirebaseAuthException catch (e) {
      onError(_messageFor(e));
    } catch (_) {
      onError(_genericError);
    }
  }

  Future<String?> confirmPhoneCode(String verificationId, String smsCode) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );
      await _auth.signInWithCredential(credential);
      return null;
    } on FirebaseAuthException catch (e) {
      return _messageFor(e);
    } catch (_) {
      return _genericError;
    }
  }

  Future<void> signOut() => _auth.signOut();

  static const _genericError =
      'Une erreur est survenue. Vérifiez votre connexion et réessayez.';

  String _messageFor(FirebaseAuthException e) => switch (e.code) {
        'invalid-email' => 'Adresse e-mail invalide.',
        'email-already-in-use' => 'Un compte existe déjà avec cet e-mail.',
        'weak-password' => 'Mot de passe trop court (6 caractères minimum).',
        'user-not-found' || 'wrong-password' || 'invalid-credential' =>
          'E-mail ou mot de passe incorrect.',
        'invalid-phone-number' => 'Numéro de téléphone invalide.',
        'invalid-verification-code' => 'Code incorrect.',
        'too-many-requests' => 'Trop de tentatives, réessayez plus tard.',
        'network-request-failed' => 'Pas de connexion internet.',
        _ => e.message ?? _genericError,
      };
}
