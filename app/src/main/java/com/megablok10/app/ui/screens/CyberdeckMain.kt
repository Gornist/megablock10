package com.megablok10.app.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import com.megablok10.app.breach.BreachAccess
import com.megablok10.app.breach.BreachBlock
import com.megablok10.app.breach.Daemon
import com.megablok10.app.breach.cellsLabel
import com.megablok10.app.breach.label
import com.megablok10.app.items.ItemTransferStore
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbBanner
import com.megablok10.app.ui.theme.MbBannerTone
import com.megablok10.app.ui.theme.MbButton
import com.megablok10.app.ui.theme.MbButtonKind
import com.megablok10.app.ui.theme.MbDimens
import com.megablok10.app.ui.theme.MbEmptyState
import com.megablok10.app.ui.theme.MbIconButton
import com.megablok10.app.ui.theme.MbIcons
import com.megablok10.app.ui.theme.MbListItem
import com.megablok10.app.ui.theme.MbTabItem
import com.megablok10.app.ui.theme.MbTabs
import com.megablok10.app.ui.theme.MbTag
import com.megablok10.app.ui.theme.MbTagTone
import com.megablok10.app.ui.theme.MbTypography

/**
 * Обычный вид Кибердеки (не взлом, не дешифровка, не вход в Сеть): карточка «почему взлом не начался», вкладки «Демоны»/«Шарды»
 * и две кнопки скана. Диалоги поверх него и маршрутизацию режимов держит [CyberdeckScreen].
 */
@Composable
internal fun CyberdeckMain(
    scanIssue: BreachAccess.Blocked?,
    onDismissIssue: () -> Unit,
    segment: Int,
    onSelectSegment: (Int) -> Unit,
    daemons: List<Daemon>,
    shards: List<Mb10Qr.Shard>,
    onTransferDaemon: (Daemon) -> Unit,
    onOpenShard: (Mb10Qr.Shard) -> Unit,
    onEnterNetrun: () -> Unit,
    onScan: () -> Unit,
) {
    Column(Modifier.fillMaxSize().padding(horizontal = MbDimens.screenPadding)) {
        scanIssue?.let { blocked ->
            val issue = scanIssueOf(blocked)
            MbBanner(
                lead = { Icon(painterResource(MbIcons.Alert), contentDescription = null, tint = LocalMbColors.current.bad) },
                title = issue.title,
                sub = issue.message,
                tone = MbBannerTone.Danger,
                action = { MbIconButton(MbIcons.Close, "Закрыть", onDismissIssue) }
            )
            Spacer(Modifier.height(MbDimens.blockGap))
        }
        MbTabs(
            items = listOf(MbTabItem(MbIcons.Hack, "Демоны"), MbTabItem(MbIcons.Shard, "Шарды")),
            selected = segment,
            onSelect = onSelectSegment
        )
        Box(Modifier.weight(1f)) {
            if (segment == CyberdeckViewModel.SEGMENT_DAEMONS) {
                DemonsSegment(daemons = daemons, onTransfer = onTransferDaemon)
            } else {
                ShardsSegment(shards = shards, onOpen = onOpenShard)
            }
        }
        MbButton("Войти в Сеть", onClick = onEnterNetrun, kind = MbButtonKind.Ghost, keyIcon = MbIcons.Hack, modifier = Modifier.padding(top = MbDimens.blockGap))
        MbButton("Сканер", onClick = onScan, keyIcon = MbIcons.Scan, modifier = Modifier.padding(vertical = MbDimens.blockGap))
    }
}

@Composable
private fun DemonsSegment(daemons: List<Daemon>, onTransfer: (Daemon) -> Unit) {
    if (daemons.isEmpty()) {
        MbEmptyState(MbIcons.Hack, "Демонов пока нет", "Отсканируйте контейнер кнопкой «Сканер» — так начнётся коллекция.")
        return
    }
    // Раскрыта одна строка за раз: тап — детали и действие «Передать»; в свёрнутом виде строка ≈ 48 dp.
    var expandedId by remember { mutableStateOf<String?>(null) }
    LazyColumn(Modifier.fillMaxSize()) {
        items(daemons, key = { it.id }) { daemon ->
            DaemonRow(
                daemon = daemon,
                expanded = expandedId == daemon.id,
                onToggle = { expandedId = if (expandedId == daemon.id) null else daemon.id },
                onTransfer = if (ItemTransferStore.isTransferable(daemon)) { { onTransfer(daemon) } } else null
            )
        }
    }
}

/** Почему взлом отсканированного контейнера не начался — карточка над списком (запись мастеру делает сценарий CheckBreachAccess). */
private fun scanIssueOf(blocked: BreachAccess.Blocked): ScanIssue = when (blocked.reason) {
    BreachBlock.NO_LINK -> ScanIssue("Нет связи", "Дека вне зоны сети Мегаблока. Взлом недоступен без подключения к узлу связи.")
    BreachBlock.COOLDOWN -> ScanIssue("Узел остывает", "Повторное подключение к этому узлу возможно через ${blocked.cooldownMinutes} мин.")
    BreachBlock.EXHAUSTED -> ScanIssue("Кэш очищен", "Все слоты узла исчерпаны — здесь больше нечего извлекать.")
}

/** Строка демона (плашка): имя+тир, коды моношрифтом справа, эффект+цена во второй строке; «Передать» появляется по тапу. */
@Composable
private fun DaemonRow(daemon: Daemon, expanded: Boolean, onToggle: () -> Unit, onTransfer: (() -> Unit)?) {
    Column(Modifier.fillMaxWidth().padding(bottom = MbDimens.rowGap)) {
        MbListItem(
            title = "${daemon.name} · ${daemon.tier.label}",
            sub = "${daemon.effect.label()} · ${cellsLabel(daemon.sequence.size)}",
            subWrap = true,
            trail = listOf({ Text(daemon.sequence.joinToString(" "), style = MbTypography.demonCode, color = LocalMbColors.current.acc) }),
            plate = true,
            onClick = onTransfer?.let { onToggle }
        )
        if (expanded && onTransfer != null) {
            MbButton("Передать другому игроку", onClick = onTransfer, inline = true, kind = MbButtonKind.Ghost, modifier = Modifier.padding(top = MbDimens.rowGap))
        }
    }
}

@Composable
private fun ShardsSegment(shards: List<Mb10Qr.Shard>, onOpen: (Mb10Qr.Shard) -> Unit) {
    if (shards.isEmpty()) {
        MbEmptyState(MbIcons.Shard, "Шардов пока нет", "Отсканируйте QR-метку контейнера — найденные шарды появятся здесь.")
        return
    }
    val (locked, open) = shards.partition { resolveBadge(it) == ShardBadge.Locked }
    LazyColumn(Modifier.fillMaxSize()) {
        if (open.isNotEmpty()) {
            items(open, key = { it.id }) { shard -> ShardRow(shard, onClick = { onOpen(shard) }) }
        }
        if (locked.isNotEmpty()) {
            items(locked, key = { it.id }) { shard -> ShardRow(shard, onClick = { onOpen(shard) }) }
        }
    }
}

/** Строка шарда: плашка с «язычком», длинное название — до двух строк; тег справа только для не-обычных состояний. */
@Composable
private fun ShardRow(shard: Mb10Qr.Shard, onClick: () -> Unit) {
    val badge = remember(shard) { resolveBadge(shard) }
    MbListItem(
        title = shard.title,
        sub = shard.meta,
        titleWrap = true,
        trail = when (badge) {
            ShardBadge.Locked -> listOf({ MbTag("нужен дешифратор", tone = MbTagTone.Warn) })
            ShardBadge.Compromised -> listOf({ MbTag(badge.text, tone = MbTagTone.Bad) })
            ShardBadge.Fragment -> listOf({ MbTag(badge.text) })
            ShardBadge.Public -> emptyList()
        },
        plate = true,
        mark = true,
        onClick = onClick
    )
}

private data class ScanIssue(val title: String, val message: String)
