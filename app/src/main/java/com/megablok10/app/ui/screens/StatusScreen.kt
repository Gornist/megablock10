package com.megablok10.app.ui.screens

import com.megablok10.app.ui.theme.AppSnack
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.identity.Identity
import com.megablok10.kit.mesh.PeerInfo
import com.megablok10.app.di.contactsViewModel
import com.megablok10.app.ui.appViewModel
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.qr.generateQrBitmap
import com.megablok10.app.qr.rememberMb10QrScanner
import com.megablok10.app.ui.theme.AppButton
import com.megablok10.app.ui.theme.ButtonVariant
import com.megablok10.app.ui.theme.ChamferedSurface
import com.megablok10.app.ui.theme.SurfaceCorner
import com.megablok10.app.ui.theme.ChipTone
import com.megablok10.app.ui.theme.DimmableQr
import com.megablok10.app.ui.theme.DottedDivider
import com.megablok10.app.ui.theme.EmptyState
import com.megablok10.app.ui.theme.HexBullet
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.Jura
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.StatusChip
import com.megablok10.app.ui.theme.chamferShape

@Composable
fun StatusScreen(identity: Identity, onMessageContact: (String) -> Unit = {}, onCallContact: (PeerInfo) -> Unit = {}) {
    val vm = appViewModel { contactsViewModel() }
    val directory by vm.contacts.collectAsStateWithLifecycle()
    val contacts = directory.contacts
    var contactsExpanded by remember { mutableStateOf(false) }

    val startScan = rememberMb10QrScanner { qr ->
        when (qr) {
            is Mb10Qr.Contact -> vm.add(qr)
            else -> AppSnack.show("Это не QR-код контакта")
        }
    }

    LazyColumn(Modifier.fillMaxSize().padding(16.dp)) {
        item {
            ChamferedSurface(
                borderColor = MB10Colors.borderMuted,
                fillColor = MB10Colors.surfaceSunken,
                cut = 10.dp,
                corner = SurfaceCorner.Double,
                contentPadding = 16.dp,
                augmented = true,
                // borderMuted слишком тёмный для уголков-прицела (см. правило в Color.kt) — акцент отдельным живым цветом.
                bracketColor = MB10Colors.accentAction,
                modifier = Modifier.fillMaxWidth()
            ) {
                Column {
                    Text(identity.callsign, color = MB10Colors.inkPrimary, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 18.sp)
                    Spacer(Modifier.height(2.dp))
                    Text(identity.faction, color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp)
                }
            }
            Spacer(Modifier.height(18.dp))

            val qrBitmap = remember(identity.publicKeyB64) {
                generateQrBitmap(Mb10QrCodec.encodeContact(identity.publicKeyB64, identity.callsign, identity.faction))
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                DimmableQr(bitmap = qrBitmap, contentDescription = "QR-код контакта", size = 160.dp)
            }
            Spacer(Modifier.height(12.dp))
            AppButton("Сканировать контакт", variant = ButtonVariant.Primary, modifier = Modifier.fillMaxWidth(), onClick = startScan)

            Spacer(Modifier.height(14.dp))
            // Тот же паттерн, что "Отправить" в Финансах: кнопка раскрывает скроллируемый
            // список под собой, а не занимает экран списком контактов постоянно.
            AppButton(
                if (contactsExpanded) "Скрыть контакты (${contacts.size})" else "Контакты (${contacts.size})",
                variant = ButtonVariant.Secondary,
                modifier = Modifier.fillMaxWidth(),
                onClick = { contactsExpanded = !contactsExpanded }
            )
            Spacer(Modifier.height(8.dp))
        }

        if (contactsExpanded) {
            if (contacts.isEmpty()) {
                item {
                    EmptyState("Пока нет контактов. Отсканируйте QR-код другого игрока, чтобы добавить его.")
                }
            }
            items(contacts, key = { it.publicKeyB64 }) { c ->
                Column(Modifier.fillMaxWidth().padding(vertical = 10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        HexBullet(MB10Colors.accentAction, size = 8.dp)
                        Spacer(Modifier.width(8.dp))
                        Text(c.callsign, color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.sp, modifier = Modifier.weight(1f))
                        StatusChip(c.faction, tone = ChipTone.Neutral)
                    }
                    Spacer(Modifier.height(8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ContactActionButton(
                            "Сообщение",
                            modifier = Modifier.weight(1f),
                            onClick = {
                                AppSnack.show("Открываю чат с ${c.callsign}")
                                onMessageContact(c.publicKeyB64)
                            }
                        )
                        ContactActionButton(
                            "Звонок",
                            modifier = Modifier.weight(1f),
                            onClick = {
                                val peer = directory.peer(c.publicKeyB64)
                                if (peer == null) {
                                    AppSnack.show("${c.callsign} сейчас не в сети")
                                } else {
                                    onCallContact(peer)
                                }
                            }
                        )
                    }
                }
                DottedDivider()
            }
        }
    }
}

/** Компактная кнопка под строкой контакта — OutlineButton из темы великоват (padding под полноразмерную CTA). */
@Composable
private fun ContactActionButton(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        modifier = modifier
            .border(1.dp, MB10Colors.borderMuted, chamferShape(4.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 6.dp)
    ) {
        Text(
            text, color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.fillMaxWidth()
        )
    }
}
