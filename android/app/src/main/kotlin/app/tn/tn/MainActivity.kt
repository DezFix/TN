package app.tn.tn

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Shared content waiting for the Dart side (share-into-TN feature).
object PendingShare {
    @Volatile
    var data: MutableMap<String, String?>? = null

    @Synchronized
    fun take(): Map<String, String?>? {
        val d = data
        data = null
        return d
    }
}

/// Widget row text-tap: chatId + entryId waiting for the Dart side (прямо к сообщению, как в "Ближайшее будущее").
object PendingOpenChat {
    @Volatile
    var chatId: String? = null
    @Volatile
    var entryId: String? = null

    @Synchronized
    fun take(): Map<String, String?>? {
        val c = chatId
        val e = entryId
        if (c == null) return null
        chatId = null
        entryId = null
        return mapOf("chatId" to c, "entryId" to e)
    }

    @Synchronized
    fun takeLegacy(): String? {
        val v = chatId
        chatId = null
        entryId = null
        return v
    }
}

object PendingShortcut {
    @Volatile
    var action: String? = null

    @Synchronized
    fun take(): String? {
        val v = action
        action = null
        return v
    }
}

// FlutterFragmentActivity (not FlutterActivity) — required by local_auth's
// biometric prompt on Android.
class MainActivity : FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // Edge-to-edge on Android 15: draw behind system bars, Flutter handles insets via WindowInsets.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE or android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
        }
        super.onCreate(savedInstanceState)
        publishShortcuts()
    }

    private fun publishShortcuts() {
        try {
            if (Build.VERSION.SDK_INT < 25) return
            val sm = getSystemService(android.content.pm.ShortcutManager::class.java) ?: return
            if (sm.isRequestPinShortcutSupported) {
                // Static shortcuts already declared in XML, but ensure dynamic for launchers that need it
                val icon = android.graphics.drawable.Icon.createWithResource(this, R.mipmap.ic_launcher)
                val quick = android.content.pm.ShortcutInfo.Builder(this, "quick_note")
                    .setShortLabel(getString(R.string.shortcut_quick_note))
                    .setLongLabel(getString(R.string.shortcut_quick_note_long))
                    .setIcon(icon)
                    .setIntent(Intent("app.tn.tn.SHORTCUT_QUICK_NOTE").setPackage(packageName).setClassName(packageName, "app.tn.tn.MainActivity"))
                    .build()
                val agenda = android.content.pm.ShortcutInfo.Builder(this, "agenda")
                    .setShortLabel(getString(R.string.shortcut_agenda))
                    .setLongLabel(getString(R.string.shortcut_agenda_long))
                    .setIcon(icon)
                    .setIntent(Intent("app.tn.tn.SHORTCUT_AGENDA").setPackage(packageName).setClassName(packageName, "app.tn.tn.MainActivity"))
                    .build()
                sm.dynamicShortcuts = listOf(quick, agenda)
            }
        } catch (_: Exception) {}
    }

    override fun getInitialRoute(): String {
        if (intent?.getBooleanExtra("open_settings", false) == true) return "/widget-settings"
        return super.getInitialRoute() ?: "/"
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("open_settings", false)) {
            flutterEngine?.let { engine ->
                MethodChannel(engine.dartExecutor.binaryMessenger, "tn/widget")
                    .invokeMethod("openSettings", null)
            }
        }
        when (intent.action) {
            "app.tn.tn.SHORTCUT_QUICK_NOTE" -> {
                flutterEngine?.let { engine ->
                    MethodChannel(engine.dartExecutor.binaryMessenger, "tn/widget")
                        .invokeMethod("shortcutQuickNote", null)
                } ?: run { PendingShortcut.action = "quick_note" }
            }
            "app.tn.tn.SHORTCUT_AGENDA" -> {
                flutterEngine?.let { engine ->
                    MethodChannel(engine.dartExecutor.binaryMessenger, "tn/widget")
                        .invokeMethod("shortcutAgenda", null)
                } ?: run { PendingShortcut.action = "agenda" }
            }
        }
        val chatId = intent.getStringExtra("open_chat")
        val entryId = intent.getStringExtra("open_entry")
        if (!chatId.isNullOrEmpty()) {
            flutterEngine?.let { engine ->
                val args: Any = if (!entryId.isNullOrEmpty()) mapOf("chatId" to chatId, "entryId" to entryId) else chatId
                MethodChannel(engine.dartExecutor.binaryMessenger, "tn/widget")
                    .invokeMethod("openChat", args)
            } ?: run {
                PendingOpenChat.chatId = chatId
                PendingOpenChat.entryId = entryId
            }
        }
        handleShareIntent(intent)?.let { share ->
            flutterEngine?.let { engine ->
                MethodChannel(engine.dartExecutor.binaryMessenger, "tn/share")
                    .invokeMethod("onShare", share)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tn/widget")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        TnDayWidgetProvider.updateAll(applicationContext)
                        result.success(null)
                    }
                    "getPendingOpenChat" -> {
                        result.success(PendingOpenChat.take())
                    }
                    "getPendingShortcut" -> {
                        result.success(PendingShortcut.take())
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tn/share")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPending" -> result.success(PendingShare.take())
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tn/install")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.arguments as? String
                        if (path != null) {
                            try {
                                val file = File(path)
                                if (!file.exists() || file.length() < 8L) {
                                    result.error("INSTALL_FAILED", "update file missing or too small", null)
                                    return@setMethodCallHandler
                                }
                                val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                                } else {
                                    Uri.fromFile(file)
                                }
                                // ACTION_INSTALL_PACKAGE is the dedicated
                                // installer action; some OEM shells misreport
                                // plain ACTION_VIEW installs as "package
                                // corrupted". ClipData carries the explicit
                                // read grant — several Android 14 skins need
                                // it on top of FLAG_GRANT_READ_URI_PERMISSION.
                                val action = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
                                    Intent.ACTION_INSTALL_PACKAGE else Intent.ACTION_VIEW
                                val intent = Intent(action).apply {
                                    setDataAndType(uri, "application/vnd.android.package-archive")
                                    clipData = android.content.ClipData.newRawUri("TN_UPDATE", uri)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                        putExtra(Intent.EXTRA_RETURN_RESULT, false)
                                    }
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("INSTALL_FAILED", e.message, null)
                            }
                        } else {
                            result.error("NO_PATH", "No file path provided", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tn/appInfo")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAbi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a")
                    "getSupportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                    "getVersionCode" -> {
                        try {
                            val pInfo = packageManager.getPackageInfo(packageName, 0)
                            val vc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) pInfo.longVersionCode else pInfo.versionCode.toLong()
                            result.success(vc)
                        } catch (_: Exception) { result.success(0L) }
                    }
                    "isUniversal" -> {
                        // Universal APK contains multiple ABIs, split contains single. We approximate via versionCode: universal <2000, splits >=2000
                        try {
                            val pInfo = packageManager.getPackageInfo(packageName, 0)
                            val vc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) pInfo.longVersionCode else pInfo.versionCode.toLong()
                            // base = vc % 1000, universal if vc <1000 or vc==base, split if vc>=2000
                            val isUniversal = vc < 1000 || vc == vc % 1000L
                            // More reliable: check nativeLibraryDir contains multiple ABIs? Fallback to versionCode heuristic.
                            result.success(isUniversal)
                        } catch (_: Exception) { result.success(true) }
                    }
                    else -> result.notImplemented()
                }
            }
        // Cold start via a share action.
        intent?.let { handleShareIntent(it) }?.let { PendingShare.data = it.toMutableMap() }
        // Cold start via widget text tap (прямо к сообщению, как в "Ближайшее будущее").
        val openChatId = intent?.getStringExtra("open_chat")
        val openEntryId = intent?.getStringExtra("open_entry")
        if (!openChatId.isNullOrEmpty()) {
            PendingOpenChat.chatId = openChatId
            PendingOpenChat.entryId = openEntryId
        }
        when (intent?.action) {
            "app.tn.tn.SHORTCUT_QUICK_NOTE" -> PendingShortcut.action = "quick_note"
            "app.tn.tn.SHORTCUT_AGENDA" -> PendingShortcut.action = "agenda"
        }
    }

    /** Extracts shared text/media into a map, copying streams to app storage. */
    private fun handleShareIntent(intent: Intent): Map<String, String?>? {
        if (intent.action != Intent.ACTION_SEND) return null
        val mime = intent.type ?: return null
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (!text.isNullOrBlank()) {
            return mapOf("text" to text, "path" to null as String?, "name" to null as String?, "mime" to mime)
        }
        @Suppress("DEPRECATION")
        val stream = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: return null
        val name = queryName(stream)
        val copied = copyToAppStorage(stream, name) ?: return null
        return mapOf(
            "text" to intent.getStringExtra(Intent.EXTRA_SUBJECT),
            "path" to copied.absolutePath,
            "name" to (name ?: copied.name),
            "mime" to mime,
        )
    }

    private fun queryName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { c ->
                val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && c.moveToFirst()) c.getString(idx) else null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun copyToAppStorage(uri: Uri, originalName: String?): File? {
        return try {
            val dir = File(filesDir, "media").apply { mkdirs() }
            val safeName = (originalName ?: "shared-${System.currentTimeMillis()}")
                .replace(Regex("[^A-Za-z0-9._()-]"), "_")
                .takeLast(80)
            val dst = File(dir, "${System.currentTimeMillis()}-$safeName")
            contentResolver.openInputStream(uri)?.use { input ->
                dst.outputStream().use { input.copyTo(it) }
            } ?: return null
            dst
        } catch (_: Exception) {
            null
        }
    }
}
