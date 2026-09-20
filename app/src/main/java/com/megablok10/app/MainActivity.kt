package com.megablok10.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.megablok10.app.announce.AnnouncementStore
import com.megablok10.app.call.CallManager
import com.megablok10.app.call.CallPhase
import com.megablok10.app.chat.ChatStore
import com.megablok10.app.collector.ChangeField
import com.megablok10.app.collector.ChangeReason
import com.megablok10.app.collector.ChangeRecordStore
import com.megablok10.app.identity.IdentityManager
import com.megablok10.app.presence.PeerInfo
import com.megablok10.app.ui.nav.AppTab
import com.megablok10.app.ui.nav.MainScaffold
import com.megablok10.app.ui.screens.AnnouncementDialogHost
import com.megablok10.app.ui.screens.CallOverlay
import com.megablok10.app.ui.screens.CallsScreen
import com.megablok10.app.ui.screens.ChatScreen
import com.megablok10.app.ui.screens.CyberdeckScreen
import com.megablok10.app.ui.screens.ProfileScreen
import com.megablok10.app.ui.screens.WalletScreen
import com.megablok10.app.ui.theme.AppButton
import com.megablok10.app.ui.theme.AppTextField
import com.megablok10.app.ui.theme.ButtonVariant
import com.megablok10.app.ui.theme.HexBullet
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.Jura
import com.megablok10.app.ui.theme.MB10Colors
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme(
                colorScheme = darkColorScheme(
                    primary = MB10Colors.accentAction,
                    background = MB10Colors.surfaceBase,
                    surface = MB10Colors.surfaceRaised,
                    onPrimary = androidx.compose.ui.graphics.Color.Black,
                    onBackground = MB10Colors.inkPrimary,
                    onSurface = MB10Colors.inkPrimary
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
    var showProfile by remember { mutableStateOf(false) }
    var chatThreadOpen by remember { mutableStateOf(false) }
    var shardDetailOpen by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    // Фоновая отправка ChangeRecord мастерскому коллектору — не зависит от
    // наличия личности (очередь может копиться и отправляться, даже пока
    // экран настройки ещё не пройден, хотя на практике enqueue() без
    // личности просто ничего не пишет).
    LaunchedEffect(Unit) {
        AnnouncementStore.load(context)
        ChangeRecordStore.start(context)
    }

    // WebRTC не откроет микрофон без RECORD_AUDIO — звонок (свой исходящий
    // или принятие входящего) — единственное место в приложении, где он
    // реально нужен, поэтому запрашиваем не заранее, а прямо в момент звонка.
    // POST_NOTIFICATIONS просим тут же за компанию (нужен для видимой
    // CallStyle-плашки на Android 13+), но не блокируем на нём звонок —
    // без неё сервис всё равно поднимется и звонок пройдёт, просто плашки
    // не будет видно.
    var pendingMicAction by remember { mutableStateOf<(() -> Unit)?>(null) }
    val callPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { results ->
        if (results[Manifest.permission.RECORD_AUDIO] == true) pendingMicAction?.invoke()
        pendingMicAction = null
    }
    fun withMicPermission(action: () -> Unit) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            action()
        } else {
            pendingMicAction = action
            val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                arrayOf(Manifest.permission.RECORD_AUDIO, Manifest.permission.POST_NOTIFICATIONS)
            } else {
                arrayOf(Manifest.permission.RECORD_AUDIO)
            }
            callPermissionLauncher.launch(permissions)
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
            val isNewIdentity = !IdentityManager.hasIdentity(context)
            val created = IdentityManager.getOrCreate(context, callsign, faction)
            identity = created
            if (isNewIdentity) {
                scope.launch {
                    ChangeRecordStore.enqueue(context, ChangeField.CALLSIGN, null, created.callsign, ChangeReason.CHARACTER_CREATED)
                    ChangeRecordStore.enqueue(context, ChangeField.FACTION, null, created.faction, ChangeReason.CHARACTER_CREATED)
                }
            }
        })
    } else if (showProfile) {
        ProfileScreen(
            identity = currentIdentity,
            onMessageContact = { pubKeyB64 ->
                chatContact = pubKeyB64
                tab = AppTab.Chat
                showProfile = false
            },
            onCallContact = { peer: PeerInfo ->
                withMicPermission { CallManager.startOutgoingCall(context, currentIdentity, peer) }
            },
            onResetIdentity = {
                // Зеркало пары enqueue при CHARACTER_CREATED (см. SetupScreen выше) —
                // иначе сброс персонажа молча выпадает из истории дашборда: до сих пор
                // мастер видел там появление позывного/фракции, но не их исчезновение.
                // Enqueue обязан пройти ДО IdentityManager.clear — подписывать запись
                // уже будет нечем, ключ сотрётся вместе с остальными SharedPreferences.
                scope.launch {
                    ChangeRecordStore.enqueue(context, ChangeField.CALLSIGN, currentIdentity.callsign, "", ChangeReason.CHARACTER_RESET)
                    ChangeRecordStore.enqueue(context, ChangeField.FACTION, currentIdentity.faction, "", ChangeReason.CHARACTER_RESET)
                    ChatStore.stop()
                    IdentityManager.clear(context)
                    identity = null
                    tab = AppTab.Chat
                    showProfile = false
                }
            },
            onBack = { showProfile = false }
        )
    } else {
        val callState by CallManager.state.collectAsState()
        // Только активный таб решает, вложен ли он сейчас — chrome прячется по его флагу,
        // не по обоим сразу (состояние неактивного таба не влияет, пока на него не переключились).
        val hideChrome = when (tab) {
            AppTab.Chat -> chatThreadOpen
            AppTab.Hack -> shardDetailOpen
            else -> false
        }
        Box(Modifier.fillMaxSize()) {
            MainScaffold(
                identity = currentIdentity,
                selectedTab = tab,
                onSelectTab = { tab = it },
                onOpenProfile = { showProfile = true },
                hideChrome = hideChrome
            ) { activeTab ->
                when (activeTab) {
                    AppTab.Chat -> ChatScreen(
                        identity = currentIdentity,
                        openedWithContactKey = chatContact,
                        onContactConsumed = { chatContact = null },
                        onNestedChange = { chatThreadOpen = it }
                    )
                    AppTab.Calls -> CallsScreen(onCallPeer = { peer: PeerInfo ->
                        withMicPermission { CallManager.startOutgoingCall(context, currentIdentity, peer) }
                    })
                    AppTab.Hack -> CyberdeckScreen(identity = currentIdentity, onNestedChange = { shardDetailOpen = it })
                    AppTab.Wallet -> WalletScreen(currentIdentity)
                }
            }
            AnnouncementDialogHost()
            if (callState.phase != CallPhase.IDLE) {
                CallOverlay(
                    state = callState,
                    identity = currentIdentity,
                    onAccept = { withMicPermission { CallManager.accept(context, currentIdentity) } },
                    onEnd = { CallManager.endCall(context, currentIdentity) }
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
            .background(MB10Colors.surfaceBase)
            .padding(24.dp),
        verticalArrangement = Arrangement.Center
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            HexBullet(MB10Colors.accentAction, size = 10.dp)
            Spacer(Modifier.width(8.dp))
            Text("МЕГАБЛОК №10", color = MB10Colors.inkPrimary, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 20.sp)
        }
        Spacer(Modifier.height(4.dp))
        Text("Создание личности", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp)
        Spacer(Modifier.height(28.dp))

        Text("Позывной", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.sp)
        Spacer(Modifier.height(6.dp))
        AppTextField(value = callsign, onValueChange = { callsign = it }, placeholder = "RAZOR", modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(16.dp))
        Text("Фракция", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.sp)
        Spacer(Modifier.height(6.dp))
        AppTextField(value = faction, onValueChange = { faction = it }, placeholder = "Малстром", modifier = Modifier.fillMaxWidth())

        Spacer(Modifier.height(28.dp))
        AppButton(
            "Сгенерировать ключ и QR",
            variant = ButtonVariant.Primary,
            enabled = callsign.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
            onClick = { if (callsign.isNotBlank()) onCreated(callsign, faction) }
        )
        Spacer(Modifier.height(10.dp))
        Text(
            "Ключевая пара генерируется один раз на этом устройстве и остаётся идентификатором персонажа на всю игру.",
            color = MB10Colors.inkTertiary, fontFamily = IBMPlexSans, fontSize = 11.sp, lineHeight = 15.sp
        )
    }
}
