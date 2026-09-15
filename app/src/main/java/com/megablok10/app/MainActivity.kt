package com.megablok10.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.megablok10.app.breach.BreachScreen
import com.megablok10.app.call.CallManager
import com.megablok10.app.call.CallPhase
import com.megablok10.app.chat.ChatStore
import com.megablok10.app.identity.IdentityManager
import com.megablok10.app.presence.PeerInfo
import com.megablok10.app.ui.nav.AppTab
import com.megablok10.app.ui.nav.MainScaffold
import com.megablok10.app.ui.screens.CallOverlay
import com.megablok10.app.ui.screens.ChatScreen
import com.megablok10.app.ui.screens.MasterToolScreen
import com.megablok10.app.ui.screens.SettingsScreen
import com.megablok10.app.ui.screens.ShardsScreen
import com.megablok10.app.ui.screens.StatusScreen
import com.megablok10.app.ui.screens.WalletScreen
import com.megablok10.app.ui.theme.MB10Colors

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme(
                colorScheme = darkColorScheme(
                    primary = MB10Colors.yellow,
                    background = MB10Colors.bg0,
                    surface = MB10Colors.bg1,
                    onPrimary = androidx.compose.ui.graphics.Color.Black,
                    onBackground = MB10Colors.ink0,
                    onSurface = MB10Colors.ink0
                )
            ) {
                Surface(color = MaterialTheme.colorScheme.background) {
                    AppRoot()
                }
            }
        }
    }
}

@Composable
fun AppRoot() {
    val context = LocalContext.current
    var identity by remember { mutableStateOf(IdentityManager.current(context)) }
    var tab by remember { mutableStateOf(AppTab.Chat) }
    var chatContact by remember { mutableStateOf<String?>(null) }
    var showMasterTool by remember { mutableStateOf(false) }

    // WebRTC не откроет микрофон без RECORD_AUDIO — звонок (свой исходящий
    // или принятие входящего) — единственное место в приложении, где он
    // реально нужен, поэтому запрашиваем не заранее, а прямо в момент звонка.
    var pendingMicAction by remember { mutableStateOf<(() -> Unit)?>(null) }
    val micPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) pendingMicAction?.invoke()
        pendingMicAction = null
    }
    fun withMicPermission(action: () -> Unit) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            action()
        } else {
            pendingMicAction = action
            micPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    val currentIdentity = identity
    if (currentIdentity != null) {
        LaunchedEffect(currentIdentity.publicKeyB64) {
            ChatStore.start(context, currentIdentity)
        }
    }

    if (currentIdentity == null) {
        SetupScreen(onCreated = { callsign, faction ->
            identity = IdentityManager.getOrCreate(context, callsign, faction)
        })
    } else if (showMasterTool) {
        MasterToolScreen(onClose = { showMasterTool = false })
    } else {
        val callState by CallManager.state.collectAsState()
        Box(Modifier.fillMaxSize()) {
            MainScaffold(identity = currentIdentity, selectedTab = tab, onSelectTab = { tab = it }) { activeTab ->
                when (activeTab) {
                    AppTab.Chat -> ChatScreen(identity = currentIdentity, openedWithContactKey = chatContact, onContactConsumed = { chatContact = null })
                    AppTab.Hack -> BreachScreen()
                    AppTab.Wallet -> WalletScreen(currentIdentity)
                    AppTab.Shards -> ShardsScreen(onOpenHack = { tab = AppTab.Hack })
                    AppTab.Profile -> StatusScreen(
                        currentIdentity,
                        onMessageContact = { pubKeyB64 ->
                            chatContact = pubKeyB64
                            tab = AppTab.Chat
                        },
                        onCallContact = { peer: PeerInfo ->
                            withMicPermission { CallManager.startOutgoingCall(context, currentIdentity, peer) }
                        }
                    )
                    AppTab.Settings -> SettingsScreen(
                        onResetIdentity = {
                            ChatStore.stop()
                            IdentityManager.clear(context)
                            identity = null
                            tab = AppTab.Chat
                        },
                        onOpenMasterTool = { showMasterTool = true }
                    )
                }
            }
            if (callState.phase != CallPhase.IDLE) {
                CallOverlay(
                    state = callState,
                    identity = currentIdentity,
                    onAccept = { withMicPermission { CallManager.accept(context, currentIdentity) } },
                    onEnd = { CallManager.endCall(currentIdentity) }
                )
            }
        }
    }
}

@Composable
fun SetupScreen(onCreated: (String, String) -> Unit) {
    var callsign by remember { mutableStateOf("") }
    var faction by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center
    ) {
        Text("Создание личности", style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.height(24.dp))
        OutlinedTextField(
            value = callsign,
            onValueChange = { callsign = it },
            label = { Text("Позывной") },
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(
            value = faction,
            onValueChange = { faction = it },
            label = { Text("Фракция") },
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(24.dp))
        Button(
            onClick = { if (callsign.isNotBlank()) onCreated(callsign, faction) },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Сгенерировать ключ и QR")
        }
        Spacer(Modifier.height(8.dp))
        Text(
            "Ключевая пара генерируется один раз на этом устройстве и " +
                "остаётся идентификатором персонажа на всю игру.",
            style = MaterialTheme.typography.bodySmall
        )
    }
}
