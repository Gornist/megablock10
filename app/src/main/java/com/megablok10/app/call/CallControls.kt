package com.megablok10.app.call

import com.megablok10.app.data.CallLogEntity
import com.megablok10.app.identity.Identity
import com.megablok10.kit.mesh.PeerInfo
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow

/** Звонки глазами интерфейса: текущий звонок, журнал и действия. Реализация — [CallManager] (WebRTC); в тестах — фейк. */
interface CallControls {
    val state: StateFlow<CallUiState>

    fun observeLog(): Flow<List<CallLogEntity>>

    fun startOutgoingCall(identity: Identity, peer: PeerInfo)

    fun accept(identity: Identity)

    fun endCall(identity: Identity)
}
