package com.megablok10.app.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.megablok10.app.identity.ContactsView
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.ui.theme.MbButtonKind
import com.megablok10.app.ui.theme.MbContactItem
import com.megablok10.app.ui.theme.MbDialog
import com.megablok10.app.ui.theme.MbDialogAction
import com.megablok10.app.ui.theme.MbEmptyState
import com.megablok10.app.ui.theme.MbIcons

/** Выбор получателя передачи из контактов (не в сети — приглушённой строкой). Одно окно и для шарда, и для демона. */
@Composable
fun ContactPickerDialog(title: String, directory: ContactsView, onPick: (Mb10Qr.Contact) -> Unit, onDismiss: () -> Unit) {
    val contacts = directory.contacts
    val onlineKeys = directory.onlineKeys
    MbDialog(
        onDismissRequest = onDismiss,
        icon = MbIcons.Shard,
        title = title,
        actions = listOf(MbDialogAction("Отмена", MbButtonKind.Quiet, onClick = onDismiss))
    ) {
        if (contacts.isEmpty()) {
            MbEmptyState(MbIcons.User, "Нет контактов", "Отсканируйте QR-код игрока в Профиле.")
        } else {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                contacts.forEach { contact ->
                    val online = contact.publicKeyB64 in onlineKeys
                    MbContactItem(callsign = contact.callsign, faction = contact.faction, online = online, onClick = { onPick(contact) })
                }
            }
        }
    }
}
