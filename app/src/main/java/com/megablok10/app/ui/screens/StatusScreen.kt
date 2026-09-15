package com.megablok10.app.ui.screens

import android.widget.Toast
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
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
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.breach.MockBreach
import com.megablok10.app.identity.ContactStore
import com.megablok10.app.identity.Identity
import com.megablok10.app.presence.PeerInfo
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.qr.generateQrBitmap
import com.megablok10.app.qr.rememberMb10QrScanner
import com.megablok10.app.ui.theme.ChamferedPanel
import com.megablok10.app.ui.theme.Chip
import com.megablok10.app.ui.theme.DemoNotice
import com.megablok10.app.ui.theme.DottedDivider
import com.megablok10.app.ui.theme.HexBullet
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.Jura
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.MB10Toggle
import com.megablok10.app.ui.theme.SectionLabel
import com.megablok10.app.ui.theme.chamferShape
import kotlinx.coroutines.launch

@Composable
fun StatusScreen(identity: Identity, onMessageContact: (String) -> Unit = {}, onCallContact: (PeerInfo) -> Unit = {}) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val contacts by ContactStore.observeAll(context).collectAsState(initial = emptyList())
    val onlinePeers by PresenceService.peers.collectAsState()

    val startScan = rememberMb10QrScanner { qr ->
        when (qr) {
            is Mb10Qr.Contact -> scope.launch { ContactStore.add(context, qr) }
            else -> Toast.makeText(context, "Это не QR-код контакта", Toast.LENGTH_SHORT).show()
        }
    }

    LazyColumn(Modifier.fillMaxSize().padding(16.dp)) {
        item {
            ChamferedPanel(
                borderColor = MB10Colors.inkFaint,
                fillColor = MB10Colors.bg2,
                cut = 10.dp,
                doubleCorner = true,
                contentPadding = 16.dp,
                modifier = Modifier.fillMaxWidth()
            ) {
                Column {
                    Text(identity.callsign, color = MB10Colors.ink0, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 18.sp)
                    Spacer(Modifier.height(2.dp))
                    Text(identity.faction, color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.sp)
                }
            }
            Spacer(Modifier.height(18.dp))

            // Ни системы репутации фракций, ни cyberpsychosis-механики, ни
            // реального Character.ramCapacity в MVP пока нет (последняя
            // осознанно выведена из скоупа) — все метры ниже статичны, поэтому
            // явно помечены как демо, а не молча выдаются за реальные данные.
            DemoNotice("показатели ниже не привязаны к персонажу — визуальный макет", modifier = Modifier.padding(bottom = 10.dp))
            StatMeter("RAM нетраннера", "${MockBreach.ramCapacity - 6} / ${MockBreach.ramCapacity}", 0.4f, MB10Colors.ink0)
            StatMeter("Репутация — Отряд самообороны", "высокая", 0.78f, MB10Colors.ink0)
            StatMeter("Репутация — Клемты", "низкая", 0.18f, MB10Colors.ink0)
            StatMeter("Сбой импланта", "62%", 0.62f, MB10Colors.danger)

            SectionLabel("Медицинский статус")
            var hideSymptoms by remember { mutableStateOf(true) }
            ChamferedPanel(
                borderColor = MB10Colors.inkFaint,
                fillColor = MB10Colors.bg1,
                cut = 6.dp,
                contentPadding = 0.dp,
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("Скрывать симптомы от других", color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 13.sp)
                    MB10Toggle(hideSymptoms, { hideSymptoms = it })
                }
            }

            Spacer(Modifier.height(18.dp))
            SectionLabel("Контакты (${contacts.size})")

            val qrBitmap = remember(identity.publicKeyB64) {
                generateQrBitmap(Mb10QrCodec.encodeContact(identity.publicKeyB64, identity.callsign, identity.faction))
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                Image(
                    bitmap = qrBitmap.asImageBitmap(),
                    contentDescription = "QR-код контакта",
                    modifier = Modifier.size(160.dp)
                )
            }
            Spacer(Modifier.height(12.dp))
            Button(onClick = startScan, modifier = Modifier.fillMaxWidth()) {
                Text("Сканировать контакт")
            }
            Spacer(Modifier.height(8.dp))
        }

        if (contacts.isEmpty()) {
            item {
                Text(
                    "Пока нет контактов. Отсканируйте QR-код другого игрока, чтобы добавить его.",
                    color = MB10Colors.inkMuted, fontFamily = IBMPlexSans, fontSize = 13.sp, lineHeight = 18.sp
                )
            }
        }
        items(contacts, key = { it.publicKeyB64 }) { c ->
            Column(Modifier.fillMaxWidth().padding(vertical = 10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    HexBullet(MB10Colors.accentPrimary, size = 8.dp)
                    Spacer(Modifier.width(8.dp))
                    Text(c.callsign, color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 13.sp, modifier = Modifier.weight(1f))
                    Chip(c.faction, color = MB10Colors.inkMuted)
                }
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ContactActionButton(
                        "Сообщение",
                        modifier = Modifier.weight(1f),
                        onClick = {
                            Toast.makeText(context, "Открываю чат с ${c.callsign}", Toast.LENGTH_SHORT).show()
                            onMessageContact(c.publicKeyB64)
                        }
                    )
                    ContactActionButton(
                        "Звонок",
                        modifier = Modifier.weight(1f),
                        onClick = {
                            val peer = onlinePeers.find { it.pubKeyB64 == c.publicKeyB64 }
                            if (peer == null) {
                                Toast.makeText(context, "${c.callsign} сейчас не в сети", Toast.LENGTH_SHORT).show()
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

/** Компактная кнопка под строкой контакта — OutlineButton из темы великоват (padding под полноразмерную CTA). */
@Composable
private fun ContactActionButton(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        modifier = modifier
            .border(1.dp, MB10Colors.inkFaint, chamferShape(4.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 6.dp)
    ) {
        Text(
            text, color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.5.sp,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.fillMaxWidth()
        )
    }
}

@Composable
private fun StatMeter(name: String, value: String, fraction: Float, fillColor: Color) {
    Column(Modifier.fillMaxWidth().padding(bottom = 12.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Bottom) {
            Text(name, color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 13.sp)
            Text(value, color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 11.sp)
        }
        Spacer(Modifier.height(6.dp))
        Box(Modifier.fillMaxWidth().height(5.dp).background(MB10Colors.bg2)) {
            Box(Modifier.fillMaxWidth(fraction).height(5.dp).background(fillColor))
        }
    }
}
