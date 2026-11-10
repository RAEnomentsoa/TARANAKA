package mg.smartsaha.taranaka

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * A FlutterFragmentActivity: required by local_auth (fingerprint unlock).
 *
 * Screenshots and screen recording are allowed: FLAG_SECURE is cleared
 * explicitly so no other code path (or an older build) can leave it set.
 *
 * The app locks when the phone screen turns off (never after a delay of
 * inactivity): ACTION_SCREEN_OFF can only be received by a receiver
 * registered at run time, so it lives here and is sent to Dart on the
 * "taranaka/screen" channel. It is also remembered, so a lock missed while
 * the Dart side was busy is applied when the app comes back.
 *
 * "taranaka/files" saves a small text file (the recovery code) where the user
 * chooses, with the system "Save as" dialog: no storage permission needed.
 *
 * "taranaka/phone" calls the health centre from the red alert, through the
 * phone network (no Internet): a direct call when CALL_PHONE was allowed
 * (asked when the centre is saved), else the dialer with the number typed.
 *
 * "taranaka/reminders" schedules the local reminders (see Reminders.kt) and
 * asks, once, to allow notifications (Android 13+).
 */
class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null
    private var filesChannel: MethodChannel? = null
    private var phoneChannel: MethodChannel? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var remindersChannel: MethodChannel? = null
    private var pendingNotifications: MethodChannel.Result? = null

    private val requestNotifications =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted: Boolean ->
            pendingNotifications?.success(granted)
            pendingNotifications = null
        }

    private fun notificationsAllowed(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun configureReminders(flutterEngine: FlutterEngine) {
        remindersChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "taranaka/reminders").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "schedule" -> {
                        val group = call.argument<String>("group")
                        val items = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
                        if (group == null) {
                            result.success(false)
                        } else {
                            Reminders.schedule(
                                this,
                                group,
                                items,
                                call.argument<String>("channelName") ?: getString(R.string.app_name),
                                call.argument<String>("publicText") ?: "",
                            )
                            result.success(true)
                        }
                    }
                    "cancelGroup" -> {
                        call.argument<String>("group")?.let { g -> Reminders.cancelGroup(this, g) }
                        result.success(true)
                    }
                    "notificationsAllowed" -> result.success(notificationsAllowed())
                    "requestNotifications" -> when {
                        notificationsAllowed() -> result.success(true)
                        pendingNotifications != null -> result.success(false)
                        else -> {
                            pendingNotifications = result
                            requestNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private val requestCallPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted: Boolean ->
            pendingPermission?.success(granted)
            pendingPermission = null
        }

    private fun canCallDirectly(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED

    /** "called", "dialer" or "failed". */
    private fun call(number: String): String {
        val uri = Uri.fromParts("tel", number, null)
        if (canCallDirectly()) {
            try {
                startActivity(Intent(Intent.ACTION_CALL, uri))
                return "called"
            } catch (e: Exception) {
                // No phone app able to call: the dialer below.
            }
        }
        return try {
            startActivity(Intent(Intent.ACTION_DIAL, uri))
            "dialer"
        } catch (e: Exception) {
            "failed"
        }
    }
    private var screenWentOff = false

    private var pendingText: String? = null
    private var pendingResult: MethodChannel.Result? = null

    private val createDocument =
        registerForActivityResult(ActivityResultContracts.CreateDocument("text/plain")) { uri: Uri? ->
            val result = pendingResult
            val text = pendingText
            pendingResult = null
            pendingText = null
            if (result == null) return@registerForActivityResult
            if (uri == null || text == null) {
                result.success(false)
                return@registerForActivityResult
            }
            try {
                contentResolver.openOutputStream(uri)?.use { it.write(text.toByteArray(Charsets.UTF_8)) }
                result.success(true)
            } catch (e: Exception) {
                result.success(false)
            }
        }

    private val screenOffReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != Intent.ACTION_SCREEN_OFF) return
            screenWentOff = true
            channel?.invokeMethod("screenOff", null)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        // A system broadcast: delivered even to a receiver not exported.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenOffReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(screenOffReceiver, filter)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        channel = MethodChannel(messenger, "taranaka/screen").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    // True once after the screen turned off, then reset.
                    "takeScreenOff" -> {
                        result.success(screenWentOff)
                        screenWentOff = false
                    }
                    else -> result.notImplemented()
                }
            }
        }
        configurePhone(flutterEngine)
        configureReminders(flutterEngine)
        filesChannel = MethodChannel(messenger, "taranaka/files").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveText" -> {
                        val name = call.argument<String>("name")
                        val text = call.argument<String>("text")
                        if (name == null || text == null || pendingResult != null) {
                            result.success(false)
                        } else {
                            pendingText = text
                            pendingResult = result
                            createDocument.launch(name)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun configurePhone(flutterEngine: FlutterEngine) {
        phoneChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "taranaka/phone").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "call" -> {
                        val number = call.argument<String>("number")
                        result.success(if (number.isNullOrBlank()) "failed" else call(number))
                    }
                    "canCallDirectly" -> result.success(canCallDirectly())
                    "requestCallPermission" -> when {
                        canCallDirectly() -> result.success(true)
                        pendingPermission != null -> result.success(false)
                        else -> {
                            pendingPermission = result
                            requestCallPermission.launch(Manifest.permission.CALL_PHONE)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        unregisterReceiver(screenOffReceiver)
        channel?.setMethodCallHandler(null)
        filesChannel?.setMethodCallHandler(null)
        phoneChannel?.setMethodCallHandler(null)
        phoneChannel = null
        remindersChannel?.setMethodCallHandler(null)
        remindersChannel = null
        channel = null
        filesChannel = null
        super.onDestroy()
    }
}
