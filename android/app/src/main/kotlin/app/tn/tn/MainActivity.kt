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

// FlutterFragmentActivity (not FlutterActivity) — required by local_auth's
// biometric prompt on Android.
class MainActivity : FlutterFragmentActivity() {

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
        // Cold start via a share action.
        intent?.let { handleShareIntent(it) }?.let { PendingShare.data = it.toMutableMap() }
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
