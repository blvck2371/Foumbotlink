package com.foumbotlik.foumbotlik

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Protège l'écran pendant l'affichage d'un message à vue unique.
 *
 * Deux verrous, parce que la capture a deux chemins :
 *  - `FLAG_SECURE` noircit la fenêtre pour les captures d'écran, les
 *    enregistrements vidéo et l'aperçu dans la liste des applications
 *    récentes ;
 *  - `setAllowedCapturePolicy(ALLOW_CAPTURE_BY_NONE)` interdit aux autres
 *    applications d'enregistrer le son de celle-ci — sans quoi un
 *    enregistreur d'écran capterait un vocal à vue unique sous une image
 *    noire (Android 10 et au-delà ; en deçà, l'API n'existe pas et le son
 *    reste capturable).
 *
 * Un canal maison plutôt qu'une dépendance : c'est une dizaine de lignes,
 * et les paquets qui font ça sont souvent à l'abandon.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "secure" -> {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        setAudioCapturable(false)
                        result.success(null)
                    }
                    "unsecure" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        setAudioCapturable(true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun setAudioCapturable(capturable: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val audio = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        audio.allowedCapturePolicy = if (capturable) {
            AudioAttributes.ALLOW_CAPTURE_BY_ALL
        } else {
            AudioAttributes.ALLOW_CAPTURE_BY_NONE
        }
    }

    companion object {
        private const val CHANNEL = "foumbot/screen_guard"
    }
}
