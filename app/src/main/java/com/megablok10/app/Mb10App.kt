package com.megablok10.app

import android.app.Activity
import android.app.Application
import android.os.Bundle
import com.megablok10.app.di.AppGraph
import com.megablok10.app.log.DeviceDiagnostics
import com.megablok10.app.log.Mb10Log

/**
 * Точка входа процесса: включает журнал, ловит падения до того, как что-либо ещё успело запуститься, и собирает корень
 * композиции [graph] (di.AppGraph) — все долгоживущие части приложения; Android-компоненты достают его через `context.appGraph`.
 */
class Mb10App : Application() {
    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()
        Mb10Log.init(this)
        Mb10Log.i("App", "=== ЗАПУСК ПРОЦЕССА === ${DeviceDiagnostics.header()} logDir=${Mb10Log.directory?.path}")
        graph = AppGraph(this)
        graph.resumeInterruptedWork()

        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            Mb10Log.e("App", "ПАДЕНИЕ в потоке ${thread.name}: ${error.javaClass.name}: ${error.message}", error)
            Mb10Log.flush()
            previous?.uncaughtException(thread, error)
        }

        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            private var started = 0
            override fun onActivityStarted(activity: Activity) {
                if (started++ == 0) { DeviceDiagnostics.foreground = true; Mb10Log.event("App", "foreground") }
            }
            override fun onActivityStopped(activity: Activity) {
                if (--started == 0) { DeviceDiagnostics.foreground = false; Mb10Log.event("App", "background") }
            }
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityResumed(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        })
    }

    override fun onLowMemory() {
        super.onLowMemory()
        Mb10Log.warnEvent("App", "low_memory")
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        // Уровни «в фоне» (20–40) приходят пачками и ничего не значат; интересны нехватка памяти при работе (5–15) и агрессивная чистка (60+).
        if (level >= 60 || level in 5..15) Mb10Log.warnEvent("App", "trim_memory", "level" to level)
    }
}
