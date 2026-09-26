package com.megablok10.app.session

import com.megablok10.app.identity.Identity
import com.megablok10.app.log.Mb10Log

private const val TAG = "Session"

/** Что запускает [SessionController]. В приложении — MeshSession, SyncEngine, MeshForegroundService (адаптер в AppGraph). */
interface SessionActions {
    fun startMesh(identity: Identity)
    fun stopMesh()
    fun startSync()
    /** false — система не пустила (Android 12+: foreground-сервис из фона). */
    fun startForeground(): Boolean
    fun stopForeground()
}

/**
 * Одно место для фоновой работы (docs/refactor-plan.md, B3). Раньше решение «что запущено» было размазано: процесс
 * (Mb10App → startMeshWhenIdentityAppears, startCollectorSync), экран (onUiStarted → startCollectorSync, ensureForeground), сама
 * сеть (MeshSession.start поднимал foreground-сервис) и сброс сессии (mesh.stop) — и каждый знал свою часть правил Android 12+.
 *
 * Входы: процесс стартовал ([onProcessStarted]), личность появилась/сменилась/пропала ([onIdentity]), экран открыт
 * ([onUiStarted]), сброс сессии ([onSessionReset] — до стирания данных). Правила:
 * - синк с мастером — один раз на процесс, с его старта (без адреса или личности движок просто ждёт);
 * - сеть — на личность (по ключу): правка мастера (позывной, фракция) сеть не перезапускает, другой ключ — перезапускает;
 * - foreground-сервис — вместе с сетью; из фона система может не пустить — тогда его поднимет открытие экрана.
 *
 * Никто, кроме контроллера, не зовёт mesh.start/stop, запуск синка и MeshForegroundService.start — стережёт SessionGuardTest.
 */
class SessionController(private val actions: SessionActions) {
    private var meshKey: String? = null
    private var syncStarted = false
    private var foreground = false

    @Synchronized
    fun onProcessStarted() = startSyncOnce()

    @Synchronized
    fun onIdentity(identity: Identity?) {
        if (identity?.publicKeyB64 == meshKey) return
        stopMesh()
        if (identity == null) return
        Mb10Log.event(TAG, "session.mesh_start", "me" to Mb10Log.short(identity.publicKeyB64))
        actions.startMesh(identity)
        meshKey = identity.publicKeyB64
        foreground = actions.startForeground()
        if (!foreground) Mb10Log.event(TAG, "session.foreground_deferred", "reason" to "запуск из фона")
    }

    @Synchronized
    fun onUiStarted() {
        startSyncOnce()
        if (meshKey != null && !foreground) foreground = actions.startForeground()
    }

    /** До стирания данных: сеть не должна принимать сообщения в базу, которую сейчас очистят. Новая личность запустит её снова. */
    @Synchronized
    fun onSessionReset() = stopMesh()

    private fun startSyncOnce() {
        if (syncStarted) return
        syncStarted = true
        actions.startSync()
    }

    private fun stopMesh() {
        if (meshKey == null) return
        Mb10Log.event(TAG, "session.mesh_stop", "me" to Mb10Log.short(meshKey))
        actions.stopForeground()
        actions.stopMesh()
        meshKey = null
        foreground = false
    }
}
