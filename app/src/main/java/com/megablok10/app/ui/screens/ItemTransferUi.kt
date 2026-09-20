package com.megablok10.app.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.platform.LocalContext
import com.megablok10.app.identity.ContactStore
import com.megablok10.app.presence.PresenceService
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.ui.theme.AppButton
import com.megablok10.app.ui.theme.ButtonVariant
import com.megablok10.app.ui.theme.ChamferedSurface
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.Jura
import com.megablok10.app.ui.theme.ListRow
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.MB10Spacing
import com.megablok10.app.ui.theme.OnlineDot
import androidx.compose.ui.text.font.FontWeight

/** Выбор получателя передачи из контактов (онлайн — с точкой). Один диалог и для шарда, и для демона. */
@Composable
fun ContactPickerDialog(title: String, onPick: (Mb10Qr.Contact) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val contacts by ContactStore.observeAll(context).collectAsState(initial = emptyList())
    val online by PresenceService.peers.collectAsState()
    val onlineKeys = online.map { it.pubKeyB64 }.toSet()
    Dialog(onDismissRequest = onDismiss) {
        ChamferedSurface(borderColor = MB10Colors.borderMuted, fillColor = MB10Colors.surfaceRaised, contentPadding = MB10Spacing.lg) {
            Column {
                Text(title, color = MB10Colors.inkPrimary, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                Spacer(Modifier.height(10.dp))
                if (contacts.isEmpty()) {
                    Text("Нет контактов: отсканируйте QR-контакт игрока.", color = MB10Colors.inkSecondary, fontFamily = IBMPlexSans, fontSize = 13.sp)
                } else {
                    Column(Modifier.verticalScroll(rememberScrollState())) {
                        contacts.forEach { contact ->
                            ListRow(onClick = { onPick(contact) }, leading = { OnlineDot(contact.publicKeyB64 in onlineKeys) }) {
                                Text(contact.callsign, color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.5.sp)
                                Text(contact.faction, color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp)
                            }
                        }
                    }
                }
                Spacer(Modifier.height(14.dp))
                AppButton("Отмена", modifier = Modifier.fillMaxWidth(), variant = ButtonVariant.Secondary, onClick = onDismiss)
            }
        }
    }
}
