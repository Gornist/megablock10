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
import com.megablok10.app.breach.BreachAccessPointFlow
import com.megablok10.app.breach.CodePill
import com.megablok10.app.breach.Daemon
import com.megablok10.app.breach.DaemonStore
import com.megablok10.app.breach.ShardDecryptFlow
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
import kotlinx.coroutines.launch

/**
 * Демоны и Шарды — два составных одной Кибердеки, не отдельные экраны:
 * оба населяются через один и тот же объект-сканер на площадке (QR точки
 * доступа или QR шарда — визуально не отличить издалека, игрок не должен
 * заранее знать, что перед ним, чтобы выбрать "правильную" кнопку скана).
 * Единая кнопка "Сканировать объект" наверху разруливает по фактическому
 * типу декодированного QR, а не по вкладке, которая открыта в моменте.
 */
@Composable
fun CyberdeckScreen(onNestedChange: (Boolean) -> Unit = {}) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { DaemonStore.ensureSeeded(context) }
    val daemons by DaemonStore.observeAll(context).collectAsState(initial = emptyList())
    val shards by ShardStore.observeAll(context).collectAsState(initial = emptyList())

    var segment by remember { mutableStateOf(0) } // 0 = Демоны, 1 = Шарды
    var point by remember { mutableStateOf<Mb10Qr.AccessPoint?>(null) }
    var openedShard by remember { mutableStateOf<Mb10Qr.Shard?>(null) }
    var decryptingShard by remember { mutableStateOf<Mb10Qr.Shard?>(null) }

    // Деталь шарда и мини-взлом — полноэкранные, со своим back-заголовком; шапка приложения над ними была бы дублем.
    LaunchedEffect(openedShard, decryptingShard) { onNestedChange(openedShard != null || decryptingShard != null) }

    val scanObject = rememberMb10QrScanner { qr ->
        when (qr) {
            is Mb10Qr.AccessPoint -> { point = qr; segment = 0 }
            is Mb10Qr.Shard -> { scope.launch { ShardStore.add(context, qr) }; segment = 1 }
            else -> Toast.makeText(context, "Это не точка доступа и не шард", Toast.LENGTH_SHORT).show()
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

        ChamferedSurface(
            borderColor = MB10Colors.borderMuted,
            fillColor = MB10Colors.surfaceRaised,
            cut = 6.dp,
            contentPadding = 0.dp,
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(Modifier.fillMaxWidth()) {
                listOf("Демоны", "Шарды").forEachIndexed { i, label ->
                    val active = i == segment
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .background(if (active) MB10Colors.surfaceSunken else MB10Colors.surfaceRaised)
                            .clickable { segment = i }
                            .padding(vertical = 8.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(label, color = if (active) MB10Colors.inkPrimary else MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 12.sp)
                    }
                }
            }
        }
        Spacer(Modifier.height(14.dp))

        Box(Modifier.weight(1f)) {
            if (segment == 0) {
                DemonsSegment(daemons = daemons, point = point, onRescan = { point = null })
            } else {
                ShardsSegment(shards = shards, onOpen = { openedShard = it })
            }
        }
    }
}

@Composable
private fun DemonsSegment(daemons: List<Daemon>, point: Mb10Qr.AccessPoint?, onRescan: () -> Unit) {
    if (point != null) {
        BreachAccessPointFlow(point = point, daemons = daemons, onRescan = onRescan)
        return
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Text(
            "Чтобы начать взлом, отсканируйте QR-метку точки доступа кнопкой выше. Демонов можно просматривать и без этого — коллекция пополняется по ходу игры.",
            color = MB10Colors.inkSecondary, fontFamily = IBMPlexSans, fontSize = 13.sp, lineHeight = 18.sp
        )
        Spacer(Modifier.height(16.dp))
        daemons.forEach { daemon -> DaemonCard(daemon) }
    }
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
                    daemon.name,
                    color = MB10Colors.inkPrimary,
                    fontFamily = IBMPlexSans,
                    fontSize = 13.5.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                Row { daemon.sequence.forEach { code -> CodePill(code) } }
            }
            if (daemon.reward.isNotEmpty()) {
                Spacer(Modifier.height(4.dp))
                Text(daemon.reward, color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.sp)
            }
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
