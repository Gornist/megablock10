package com.megablok10.app.identity

import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.filterNotNull

/**
 * Запускает сетевую сессию при появлении личности — один раз на персонажа (по ключу), а не на каждую правку мастера
 * (позывной/фракция/RAM меняются часто, ключ — только при сбросе сессии). [AppGraph.startMeshWhenIdentityAppears] держит
 * эту подписку в processScope с момента старта процесса — не в скоупе экрана, как было раньше в SessionViewModel: иначе
 * после перезапуска процесса системой без Activity (см. MeshForegroundService, START_STICKY) сессия не поднималась, пока
 * игрок сам не открывал приложение (см. docs/android-handoff.md, «Сетевая сессия от процесса»).
 */
suspend fun StateFlow<Identity?>.startMeshOncePerCharacter(startMesh: suspend (Identity) -> Unit) {
    filterNotNull().distinctUntilChangedBy { it.publicKeyB64 }.collect { startMesh(it) }
}
