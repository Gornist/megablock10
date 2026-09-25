package com.megablok10.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
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
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.megablok10.app.call.CallPhase
import com.megablok10.app.di.appGraph
import com.megablok10.app.di.callsViewModel
import com.megablok10.app.di.sessionViewModel
import com.megablok10.app.qr.ItemKind
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.rememberMb10QrScanner
import com.megablok10.app.ui.theme.AppSnack
import com.megablok10.app.ui.LocalAppGraph
import com.megablok10.app.ui.appViewModel
import com.megablok10.kit.mesh.OnlinePlayer
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
import com.megablok10.app.ui.theme.AppSnackHost
import com.megablok10.app.ui.theme.AppTextField
import com.megablok10.app.ui.theme.ButtonVariant
import com.megablok10.app.ui.theme.HexBullet
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.Jura
import com.megablok10.app.ui.theme.MB10Colors

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val graph = appGraph
        setContent {
            // Экраны берут зависимости из корня композиции приложения (di.AppGraph), а не из глобальных объектов.
            CompositionLocalProvider(LocalAppGraph provides graph) {
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
}

@Composable
fun AppRoot() {
    val context = LocalContext.current
    // Персонаж, выдача, сброс и сетевая сессия — SessionViewModel; звонки (плашка поверх любого экрана) — CallsViewModel.
    val session = appViewModel { sessionViewModel() }
    val calls = appViewModel { callsViewModel() }
    // Личность реактивна (IdentityStore.state): создание, сброс и правки мастера (позывной, фракция, RAM) видны сразу.
    val identity by session.identity.collectAsStateWithLifecycle()
    val onlinePeers by session.peers.collectAsStateWithLifecycle()
    var tab by remember { mutableStateOf(AppTab.Chat) }
    var chatContact by remember { mutableStateOf<String?>(null) }
    var showProfile by remember { mutableStateOf(false) }
    var chatThreadOpen by remember { mutableStateOf(false) }
    var walletPreset by remember { mutableStateOf<String?>(null) }
    // Пришли из чата кнопкой-скрепкой ("Передать шард/демона") — какую вкладку Кибердеки открыть и кому уже готова передача.
    var cyberdeckPeerPreset by remember { mutableStateOf<String?>(null) }
    var cyberdeckSegmentPreset by remember { mutableStateOf<Int?>(null) }
    var shardDetailOpen by remember { mutableStateOf(false) }
    BackHandler(enabled = showProfile) { showProfile = false }

    // После сброса сессии (личность исчезла) приложение начинается с чистого листа: вкладка «Чат», профиль закрыт.
    LaunchedEffect(identity == null) {
        if (identity == null) { tab = AppTab.Chat; showProfile = false }
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

    // Уведомления о сообщениях и постоянная плашка «на связи» (MeshForegroundService) не должны ждать первого звонка — раньше
    // POST_NOTIFICATIONS просили только там, и до первого звонка игрок не видел вообще никаких уведомлений о чате.
    val notificationPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    val currentIdentity = identity
    if (currentIdentity == null) {
        // Сетевая сессия поднимается сама, как только персонаж появился (SessionViewModel).
        SetupScreen(onProvision = session::provision, onCreated = session::createCharacter)
    } else if (showProfile) {
        ProfileScreen(
            identity = currentIdentity,
            onMessageContact = { pubKeyB64 ->
                chatContact = pubKeyB64
                tab = AppTab.Chat
                showProfile = false
            },
            onCallContact = { peer: OnlinePlayer -> withMicPermission { calls.start(peer) } },
            // Полный сброс сессии на устройстве (записи о сбросе мастеру → стирание игровых данных → ключи): identity/SessionReset.
            // Записи о сбросе — зеркало CHARACTER_CREATED: иначе мастер видел бы появление позывного и фракции, но не их исчезновение.
            onResetIdentity = session::resetSession,
            onBack = { showProfile = false }
        )
    } else {
        val callState by calls.call.collectAsStateWithLifecycle()
        val callContacts by calls.contacts.collectAsStateWithLifecycle()
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
                onlineNodes = onlinePeers.size,
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
                        onNestedChange = { chatThreadOpen = it },
                        onQuickTransfer = { key -> walletPreset = key; tab = AppTab.Wallet },
                        onQuickItem = { kind, peerKey ->
                            cyberdeckPeerPreset = peerKey
                            cyberdeckSegmentPreset = if (kind == ItemKind.DAEMON) 0 else 1
                            tab = AppTab.Hack
                        }
                    )
                    AppTab.Calls -> CallsScreen(onCallPeer = { peer: OnlinePlayer -> withMicPermission { calls.start(peer) } })
                    AppTab.Hack -> CyberdeckScreen(
                        identity = currentIdentity,
                        onNestedChange = { shardDetailOpen = it },
                        presetPeerKey = cyberdeckPeerPreset,
                        initialSegment = cyberdeckSegmentPreset,
                        onPresetConsumed = { cyberdeckPeerPreset = null; cyberdeckSegmentPreset = null }
                    )
                    AppTab.Wallet -> WalletScreen(presetContactKey = walletPreset, onPresetConsumed = { walletPreset = null })
                }
            }
            AnnouncementDialogHost()
            AppSnackHost(Modifier.align(Alignment.BottomCenter).padding(bottom = 64.dp))
            if (callState.phase != CallPhase.IDLE) {
                CallOverlay(
                    state = callState,
                    peerFaction = callContacts.contact(callState.peerPubKeyB64)?.faction,
                    onAccept = { withMicPermission { calls.accept() } },
                    onEnd = calls::end
                )
            }
        }
    }
}

@Composable
fun SetupScreen(onProvision: (Mb10Qr.Provision) -> Unit, onCreated: (String, String) -> Unit) {
    var callsign by remember { mutableStateOf("") }
    var faction by remember { mutableStateOf("") }
    val startScan = rememberMb10QrScanner { qr ->
        if (qr is Mb10Qr.Provision) onProvision(qr) else AppSnack.show("Это не код персонажа. Нужен QR от мастера")
    }

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
        Text(if (BuildConfig.ALLOW_MANUAL_SETUP) "Создание личности" else "Выдача персонажа", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp)
        Spacer(Modifier.height(28.dp))

        Text(
            "Подойдите к мастеру: он покажет QR с вашим персонажем. Один код настроит приложение и создаст персонажа.",
            color = MB10Colors.inkSecondary, fontFamily = IBMPlexSans, fontSize = 13.sp, lineHeight = 18.sp
        )
        Spacer(Modifier.height(16.dp))
        // Код от мастера, не игровое действие игрока — служебный жёлтый (см. правило accentSystem в Color.kt).
        AppButton("Сканировать QR персонажа", variant = ButtonVariant.System, modifier = Modifier.fillMaxWidth(), onClick = startScan)
        Spacer(Modifier.height(10.dp))
        Text(
            "Код действует один раз. Повторно — только после сброса сессии и с новым кодом от мастера.",
            color = MB10Colors.inkTertiary, fontFamily = IBMPlexSans, fontSize = 11.sp, lineHeight = 15.sp
        )
        if (!BuildConfig.ALLOW_MANUAL_SETUP) return@Column
        Spacer(Modifier.height(28.dp))
        Text("Ручное создание (сборка для разработки)", color = MB10Colors.inkTertiary, fontFamily = JetBrainsMono, fontSize = 10.sp)
        Spacer(Modifier.height(12.dp))

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
