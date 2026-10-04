package com.megablok10.app.ui.theme

import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.painterResource

/** Контакт в списках выбора (новый чат, получатель передачи): значок игрока, позывной, фракция; не в сети — приглушённая строка. */
@Composable
fun MbContactItem(callsign: String, faction: String, onClick: () -> Unit, online: Boolean = true) {
    MbListItem(
        title = callsign,
        sub = faction,
        lead = { Icon(painterResource(MbIcons.User), contentDescription = null) },
        state = if (online) MbListItemState.Normal else MbListItemState.Off,
        onClick = onClick
    )
}
