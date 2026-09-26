package com.megablok10.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.megablok10.app.di.contactsViewModel
import com.megablok10.app.identity.Identity
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.qr.generateQrBitmap
import com.megablok10.app.qr.rememberMb10QrScanner
import com.megablok10.app.ui.appViewModel
import com.megablok10.app.ui.theme.AppSnack
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbButton
import com.megablok10.app.ui.theme.MbButtonKind
import com.megablok10.app.ui.theme.MbCard
import com.megablok10.app.ui.theme.MbDimens
import com.megablok10.app.ui.theme.MbEmptyState
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbListItem
import com.megablok10.app.ui.theme.MbListItemState
import com.megablok10.app.ui.theme.MbPortrait
import com.megablok10.app.ui.theme.MbQr
import com.megablok10.app.ui.theme.MbSectionTitle
import com.megablok10.app.ui.theme.MbTag
import com.megablok10.app.ui.theme.MbTagTone
import com.megablok10.app.ui.theme.MbTypography
import com.megablok10.kit.mesh.OnlinePlayer

@Composable
fun StatusScreen(identity: Identity, onMessageContact: (String) -> Unit = {}, onCallContact: (OnlinePlayer) -> Unit = {}) {
    val vm = appViewModel { contactsViewModel() }
    val directory by vm.contacts.collectAsStateWithLifecycle()
    val contacts = directory.contacts
    var expandedKey by remember { mutableStateOf<String?>(null) }

    val startScan = rememberMb10QrScanner { qr ->
        when (qr) {
            is Mb10Qr.Contact -> vm.add(qr)
            else -> AppSnack.show("Это не QR-код контакта")
        }
    }

    LazyColumn(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(MbDimens.blockGap)) {
        item {
            MbCard(lead = { MbPortrait(identity.callsign.take(1), size = MbDimens.portraitProfile) }) {
                Text(identity.callsign, style = MbTypography.cardTitle, color = LocalMbColors.current.inkStrong)
                Text(identity.faction, style = MbTypography.rowSub, color = LocalMbColors.current.ink2)
                Text("КЛЮЧ ${shortKey(identity.publicKeyB64)}", style = MbTypography.demonCode, color = LocalMbColors.current.acc)
            }
        }
        item {
            val qrBitmap = remember(identity.publicKeyB64) {
                generateQrBitmap(Mb10QrCodec.encodeContact(identity.publicKeyB64, identity.callsign, identity.faction))
            }
            MbCard(lead = { RevealableQr(bitmap = qrBitmap, contentDescription = "QR-код контакта") }) {
                Text("Мой QR-код.", style = MbTypography.cardTitle.copy(fontSize = 13.sp), color = LocalMbColors.current.inkStrong)
                Text(
                    "Покажите игроку — он отсканирует и добавит вас в контакты.",
                    style = MbTypography.rowSub, color = LocalMbColors.current.ink2
                )
            }
        }
        item { MbSectionTitle("Контакты", meta = contacts.size.toString()) }
        if (contacts.isEmpty()) {
            item { MbEmptyState(MbIcons.User, "Контактов пока нет", "Отсканируйте QR-код другого игрока, чтобы добавить его.") }
        } else {
            items(contacts, key = { it.publicKeyB64 }) { c ->
                ContactRow(
                    contact = c,
                    online = c.publicKeyB64 in directory.onlineKeys,
                    expanded = expandedKey == c.publicKeyB64,
                    onToggle = { expandedKey = if (expandedKey == c.publicKeyB64) null else c.publicKeyB64 },
                    onMessage = { onMessageContact(c.publicKeyB64) },
                    onCall = {
                        val peer = directory.peer(c.publicKeyB64)
                        if (peer == null) AppSnack.show("${c.callsign} сейчас не в сети") else onCallContact(peer)
                    }
                )
            }
        }
        item {
            Spacer(Modifier.height(MbDimens.rowGap))
            MbButton("Сканер", onClick = startScan, keyIcon = MbIcons.Scan, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(MbDimens.blockGap))
        }
    }
}

/** Строка контакта: тап разворачивает «Сообщение»/«Звонок» — тот же паттерн, что у демонов в Кибердеке (DaemonRow). */
@Composable
private fun ContactRow(contact: Mb10Qr.Contact, online: Boolean, expanded: Boolean, onToggle: () -> Unit, onMessage: () -> Unit, onCall: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(bottom = MbDimens.rowGap)) {
        MbListItem(
            title = contact.callsign,
            sub = contact.faction,
            trail = if (online) listOf({ MbTag("в сети", tone = MbTagTone.Ok) }) else emptyList(),
            plate = true,
            state = if (online) MbListItemState.Normal else MbListItemState.Off,
            onClick = onToggle
        )
        if (expanded) {
            Row(Modifier.padding(top = MbDimens.rowGap), horizontalArrangement = Arrangement.spacedBy(MbDimens.rowGap * 2)) {
                MbButton("Сообщение", onClick = onMessage, kind = MbButtonKind.Ghost, modifier = Modifier.weight(1f))
                MbButton("Звонок", onClick = onCall, kind = MbButtonKind.Ghost, modifier = Modifier.weight(1f))
            }
        }
    }
}

/** Один тап показывает и скрывает QR — ключ не должен маячить открытым на столе (было DimmableQr). */
@Composable
private fun RevealableQr(bitmap: android.graphics.Bitmap, contentDescription: String) {
    var revealed by remember { mutableStateOf(false) }
    val size = 96.dp
    Box(Modifier.size(size).clickable { revealed = !revealed }, contentAlignment = Alignment.Center) {
        MbQr(bitmap = bitmap, contentDescription = contentDescription, size = size)
        if (!revealed) {
            Box(Modifier.size(size).background(LocalMbColors.current.bg.copy(alpha = 0.9f)))
            Text(
                "Нажмите, чтобы показать",
                style = MbTypography.meta, color = LocalMbColors.current.ink2,
                textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 10.dp)
            )
        }
    }
}

/** «7F3A…C21» — первые 4 и последние 3 символа ключа, как в прототипе. */
private fun shortKey(keyB64: String): String = if (keyB64.length <= 9) keyB64 else "${keyB64.take(4)}…${keyB64.takeLast(3)}"
