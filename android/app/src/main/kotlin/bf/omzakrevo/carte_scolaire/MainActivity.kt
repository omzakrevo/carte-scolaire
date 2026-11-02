package bf.omzakrevo.carte_scolaire

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Envoi de SMS par la puce du téléphone (aucun serveur).
 * Canal « carte_scolaire/sms » : hasPermission, requestPermission, send(to, text).
 */
class MainActivity : FlutterActivity() {
    private val channelName = "carte_scolaire/sms"
    private val permissionCode = 4242
    private var pendingPermission: MethodChannel.Result? = null
    private var counter = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasSmsPermission())
                "requestPermission" -> {
                    if (hasSmsPermission()) {
                        result.success(true)
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        pendingPermission?.success(false)
                        pendingPermission = result
                        requestPermissions(arrayOf(Manifest.permission.SEND_SMS), permissionCode)
                    } else {
                        result.success(true)
                    }
                }
                "send" -> {
                    val to = call.argument<String>("to")
                    val text = call.argument<String>("text")
                    if (to.isNullOrBlank() || text.isNullOrBlank()) {
                        result.error("args", "Numéro ou message manquant", null)
                    } else if (!hasSmsPermission()) {
                        result.error("permission", "Autorisation SMS refusée", null)
                    } else {
                        sendSms(to, text, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasSmsPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionCode) {
            val ok = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermission?.success(ok)
            pendingPermission = null
        }
    }

    @Suppress("DEPRECATION")
    private fun smsManager(): SmsManager =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) getSystemService(SmsManager::class.java)
        else SmsManager.getDefault()

    private fun sendSms(to: String, text: String, result: MethodChannel.Result) {
        val action = "bf.omzakrevo.carte_scolaire.SMS_SENT_${System.currentTimeMillis()}_${counter++}"
        val handler = Handler(Looper.getMainLooper())
        var done = false
        val parts: ArrayList<String>
        val manager: SmsManager
        try {
            manager = smsManager()
            parts = manager.divideMessage(text)
        } catch (e: Exception) {
            result.error("send", e.message ?: "SMS indisponible sur cet appareil", null)
            return
        }
        var remaining = parts.size
        var failure: String? = null

        lateinit var receiver: BroadcastReceiver
        val finish: (String?) -> Unit = { err ->
            if (!done) {
                done = true
                try { unregisterReceiver(receiver) } catch (_: Exception) {}
                if (err == null) result.success(true) else result.error("send", err, null)
            }
        }
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (resultCode != Activity.RESULT_OK && failure == null) {
                    failure = when (resultCode) {
                        SmsManager.RESULT_ERROR_NO_SERVICE -> "Pas de réseau"
                        SmsManager.RESULT_ERROR_RADIO_OFF -> "Mode avion ou réseau coupé"
                        SmsManager.RESULT_ERROR_NULL_PDU -> "Message invalide"
                        else -> "Crédit insuffisant ou réseau indisponible (code $resultCode)"
                    }
                }
                remaining--
                if (remaining <= 0) finish(failure)
            }
        }
        val filter = IntentFilter(action)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
        val flags = PendingIntent.FLAG_ONE_SHOT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        val sentIntents = ArrayList<PendingIntent>()
        for (i in parts.indices) {
            val intent = Intent(action).setPackage(packageName)
            sentIntents.add(PendingIntent.getBroadcast(this, (counter * 100 + i) and 0xFFFFFF, intent, flags))
        }
        try {
            if (parts.size == 1) {
                manager.sendTextMessage(to, null, text, sentIntents[0], null)
            } else {
                manager.sendMultipartTextMessage(to, null, parts, sentIntents, null)
            }
        } catch (e: Exception) {
            finish(e.message ?: "Échec de l'envoi")
            return
        }
        // Sans réponse du réseau après 40 s, on considère le SMS parti (certains appareils ne confirment pas).
        handler.postDelayed({ finish(failure) }, 40000)
    }
}
