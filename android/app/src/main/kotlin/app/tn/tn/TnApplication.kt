package app.tn.tn

import android.app.Application
import android.os.FileObserver
import java.io.File

/**
 * Watches the Flutter SharedPreferences file and refreshes the home-screen
 * widgets on every write.
 *
 * Notification "Done"/"Postpone" actions run in a headless Flutter engine
 * that has no `tn/widget` channel, so the widget kept the old checkbox until
 * TN was opened. The background engine still writes the same prefs file, so
 * a process-wide file watcher catches it and updates the widgets right away.
 */
class TnApplication : Application() {
    private var observer: FileObserver? = null
    private var lastRefresh = 0L
    private var startedActivities = 0

    override fun onCreate() {
        super.onCreate()
        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            override fun onActivityStarted(activity: android.app.Activity) {
                startedActivities++
            }

            override fun onActivityStopped(activity: android.app.Activity) {
                if (startedActivities > 0) startedActivities--
            }

            override fun onActivityCreated(
                activity: android.app.Activity,
                savedInstanceState: android.os.Bundle?
            ) {
            }

            override fun onActivityResumed(activity: android.app.Activity) {}
            override fun onActivityPaused(activity: android.app.Activity) {}
            override fun onActivitySaveInstanceState(
                activity: android.app.Activity,
                outState: android.os.Bundle
            ) {
            }

            override fun onActivityDestroyed(activity: android.app.Activity) {}
        })
        try {
            val prefsDir = File(applicationInfo.dataDir, "shared_prefs")
            if (!prefsDir.exists()) prefsDir.mkdirs()
            observer = object : FileObserver(
                prefsDir.absolutePath,
                CLOSE_WRITE or MOVED_TO
            ) {
                override fun onEvent(event: Int, path: String?) {
                    if (path != "FlutterSharedPreferences.xml") return
                    // The app refreshes widgets itself while it is on screen;
                    // drafts also rewrite this file on every keystroke.
                    if (startedActivities > 0) return
                    val now = System.currentTimeMillis()
                    if (now - lastRefresh < 400) return
                    lastRefresh = now
                    try {
                        TnDayWidgetProvider.updateAll(this@TnApplication)
                        TnKanbanWidgetProvider.updateAll(this@TnApplication)
                    } catch (_: Exception) {
                    }
                }
            }.also { it.startWatching() }
        } catch (_: Exception) {
        }
    }

    override fun onTerminate() {
        try {
            observer?.stopWatching()
        } catch (_: Exception) {
        }
        observer = null
        super.onTerminate()
    }
}
