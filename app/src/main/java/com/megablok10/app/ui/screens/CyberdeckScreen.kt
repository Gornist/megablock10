package com.megablok10.app.ui.screens

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.breach.BreachContainerFlow
import com.megablok10.app.breach.CodePill
import com.megablok10.app.breach.Container
import com.megablok10.app.breach.ContainerCooldownStore
import com.megablok10.app.breach.Daemon
import com.megablok10.app.breach.DaemonRewards
import com.megablok10.app.breach.DaemonStore
import com.megablok10.app.breach.LootType
import com.megablok10.app.breach.ShardDecryptFlow
import com.megablok10.app.breach.label
import com.megablok10.app.identity.Identity
import com.megablok10.app.identity.RamUpgradeStore
import com.megablok10.app.presence.MeshLink
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.rememberMb10QrScanner
import com.megablok10.app.shards.ShardStore
import com.megablok10.app.ui.theme.AppButton
import com.megablok10.app.ui.theme.ButtonVariant
import com.megablok10.app.ui.theme.ChamferedSurface
import com.megablok10.app.ui.theme.EmptyState
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.SegmentedTabs
import kotlinx.coroutines.launch

/**
 * Демоны и Шарды — два составных одной Кибердеки, не отдельные экраны:
 * оба населяются через один и тот же объект-сканер на площадке (QR
 * контейнера или QR шарда — визуально не отличить издалека, игрок не
 * должен заранее знать, что перед ним, чтобы выбрать "правильную" кнопку
 * скана). Единая кнопка "Сканировать объект" наверху разруливает по
 * фактическому типу декодированного QR, а не по вкладке, которая открыта
 * в моменте.
 */
@Composable
fun CyberdeckScreen(identity: Identity, onNestedChange: (Boolean) -> Unit = {}) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { DaemonStore.ensureSeeded(context) }
    val daemons by DaemonStore.observeAll(context).collectAsState(initial = emptyList())
    val shards by ShardStore.observeAll(context).collectAsState(initial = emptyList())

    var segment by remember { mutableStateOf(0) } // 0 = Демоны, 1 = Шарды
    var container by remember { mutableStateOf<Container?>(null) }
    var openedShard by remember { mutableStateOf<Mb10Qr.Shard?>(null) }
    var decryptingShard by remember { mutableStateOf<Mb10Qr.Shard?>(null) }

    // Деталь шарда и мини-взлом — полноэкранные, со своим back-заголовком; шапка приложения над ними была бы дублем.
    LaunchedEffect(openedShard, decryptingShard) { onNestedChange(openedShard != null || decryptingShard != null) }

    val scanObject = rememberMb10QrScanner { qr ->
        when (qr) {
            is Mb10Qr.ContainerQr -> {
                // Связь нужна ДО открытия выбора демонов, не только чтобы разослать
                // заявку на слот — без неё можно было бы обойти сигнал СБ авиарежимом
                // (см. ревизию v9 §5).
                if (!MeshLink.isOnline(context)) {
                    Toast.makeText(context, "Нет связи с сетью Мегаблока", Toast.LENGTH_SHORT).show()
                    return@rememberMb10QrScanner
                }
                scope.launch {
                    val remainingMs = ContainerCooldownStore.remainingCooldownMs(context, qr.container.id)
                    if (remainingMs > 0) {
                        val minutes = (remainingMs / 60_000L + 1).coerceAtLeast(1)
                        Toast.makeText(context, "Контейнер недоступен ещё $minutes мин", Toast.LENGTH_LONG).show()
                    } else {
                        container = qr.container
                        segment = 0
                    }
                }
            }
            is Mb10Qr.Shard -> { scope.launch { ShardStore.add(context, qr) }; segment = 1 }
            is Mb10Qr.RamUpgrade -> {
                scope.launch {
                    val newCapacity = RamUpgradeStore.apply(context, qr)
                    val message = if (newCapacity != null) "RAM деки увеличена до $newCapacity" else "Этот RAM-токен уже был применён"
                    Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
                }
            }
            is Mb10Qr.LootGrant -> {
                scope.launch {
                    val granted = DaemonRewards.applyGrant(context, qr)
                    val message = granted ?: "Фрагмент повреждён — обратитесь к мастеру"
                    Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
                    segment = if (qr.type == LootType.DAEMON) 0 else 1
                }
            }
            else -> Toast.makeText(context, "Этот QR не распознан Кибердекой", Toast.LENGTH_SHORT).show()
        }
    }

    val decrypting = decryptingShard
    if (decrypting != null) {
        ShardDecryptFlow(
            shard = decrypting,
            onDecrypted = {
                scope.launch { ShardStore.markDecrypted(context, decrypting.id) }
                decryptingShard = null
                openedShard = decrypting.copy(decrypted = true)
            },
            onCancel = { decryptingShard = null; openedShard = decrypting }
        )
        return
    }

    val opened = openedShard
    if (opened != null) {
        ShardDetailOverlay(
            shard = opened,
            onClose = { openedShard = null },
            // "Расшифровать" — открывает мини-взлом этого конкретного шарда
            // (ShardDecryptFlow), а не общий сегмент "Демоны".
            onOpenHack = { openedShard = null; decryptingShard = opened }
        )
        return
    }

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        AppButton("Сканировать объект", variant = ButtonVariant.Netrun, modifier = Modifier.fillMaxWidth(), onClick = scanObject)
        Spacer(Modifier.height(14.dp))

        SegmentedTabs(listOf("Демоны", "Шарды"), selected = segment, onSelect = { segment = it })
        Spacer(Modifier.height(14.dp))

        Box(Modifier.weight(1f)) {
            if (segment == 0) {
                DemonsSegment(daemons = daemons, identity = identity, container = container, onRescan = { container = null })
            } else {
                ShardsSegment(shards = shards, onOpen = { openedShard = it })
            }
        }
    }
}

@Composable
private fun DemonsSegment(daemons: List<Daemon>, identity: Identity, container: Container?, onRescan: () -> Unit) {
    if (container != null) {
        BreachContainerFlow(container = container, daemons = daemons, identity = identity, onRescan = onRescan)
        return
    }

    // Вступительный текст нужен только пока коллекция пуста — дальше это
    // уже не подсказка, а шум над списком, который игрок видит каждый раз.
    if (daemons.isEmpty()) {
        EmptyState("Демонов пока нет. Взломайте первый контейнер кнопкой выше, чтобы начать коллекцию.")
        return
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        daemons.forEach { daemon -> DaemonCard(daemon) }
    }
}

/** "N ячеек/ячейка/ячейки" с русским склонением — используется как цена демона в буфере взлома. */
private fun cellsLabel(count: Int): String {
    val mod100 = count % 100
    val mod10 = count % 10
    val word = when {
        mod100 in 11..14 -> "ячеек"
        mod10 == 1 -> "ячейка"
        mod10 in 2..4 -> "ячейки"
        else -> "ячеек"
    }
    return "$count $word"
}

/** Тот же визуальный паттерн строки, что у ShardCard — единый вид для обоих составных Кибердеки. */
@Composable
private fun DaemonCard(daemon: Daemon) {
    ChamferedSurface(
        borderColor = MB10Colors.borderMuted,
        fillColor = MB10Colors.surfaceRaised,
        cut = 6.dp,
        contentPadding = 11.dp,
        modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp)
    ) {
        Column {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "${daemon.name} · ${daemon.tier.label}",
                    color = MB10Colors.inkPrimary,
                    fontFamily = IBMPlexSans,
                    fontSize = 13.5.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                Row { daemon.sequence.forEach { code -> CodePill(code) } }
            }
            Spacer(Modifier.height(4.dp))
            // Стоимость видна и вне активного взлома — иначе бюджет буфера
            // (RAM) узнаётся только внутри уже начатой попытки.
            Text(
                "${daemon.effect.label()} · ${cellsLabel(daemon.sequence.size)}",
                color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.sp
            )
        }
    }
}

@Composable
private fun ShardsSegment(shards: List<Mb10Qr.Shard>, onOpen: (Mb10Qr.Shard) -> Unit) {
    if (shards.isEmpty()) {
        EmptyState("Пока нет отсканированных шардов. Отсканируйте QR-метку кнопкой выше.")
        return
    }
    LazyColumn(Modifier.fillMaxSize()) {
        items(shards, key = { it.id }) { shard -> ShardCard(shard, onClick = { onOpen(shard) }) }
    }
}
