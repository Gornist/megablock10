package com.megablok10.app.ui.screens

import androidx.compose.foundation.Image
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.breach.BreachSymbols
import com.megablok10.app.breach.CodePill
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.qr.generateQrBitmap
import com.megablok10.app.ui.theme.AppButton
import com.megablok10.app.ui.theme.AppTextField
import com.megablok10.app.ui.theme.ButtonVariant
import com.megablok10.app.ui.theme.ChamferedSurface
import com.megablok10.app.ui.theme.ChipTone
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.Jura
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.SectionLabel
import com.megablok10.app.ui.theme.StatusChip
import java.util.UUID

private val shardBadgeOptions = listOf("PUBLIC", "LOCKED", "FRAGMENT", "COMPROMISED")

/**
 * Только для мастеров — генерирует QR для точки доступа и шарда, которые
 * больше нигде в приложении не создаются (игроки их только сканируют).
 * Печатать/показывать заранее, до игры; в самом приложении не участвует.
 */
@Composable
fun MasterToolScreen(onClose: () -> Unit) {
    var activeSegment by remember { mutableStateOf(0) }

    Column(Modifier.fillMaxSize().background(MB10Colors.surfaceBase).verticalScroll(rememberScrollState()).padding(16.dp)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().clickable(onClick = onClose).padding(vertical = 6.dp)
        ) {
            Text("←", color = MB10Colors.inkPrimary, fontFamily = JetBrainsMono, fontSize = 16.sp)
            Spacer(Modifier.width(8.dp))
            Text("Назад в настройки", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 11.sp)
        }
        Spacer(Modifier.height(12.dp))
        Text("Мастерская", color = MB10Colors.inkPrimary, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 20.sp)
        Spacer(Modifier.height(4.dp))
        Text(
            "Генерирует QR для точек доступа, шардов и демонов — их печатают или показывают заранее, до игры. Игроки эти коды только сканируют, этот экран им не нужен.",
            color = MB10Colors.inkSecondary, fontFamily = IBMPlexSans, fontSize = 12.sp, lineHeight = 16.sp
        )
        Spacer(Modifier.height(18.dp))

        ChamferedSurface(
            borderColor = MB10Colors.borderMuted, fillColor = MB10Colors.surfaceRaised, cut = 6.dp, contentPadding = 0.dp,
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(Modifier.fillMaxWidth()) {
                listOf("Точка доступа", "Шард", "Демон").forEachIndexed { i, label ->
                    val active = i == activeSegment
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .background(if (active) MB10Colors.surfaceSunken else MB10Colors.surfaceRaised)
                            .clickable { activeSegment = i }
                            .padding(vertical = 8.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(label, color = if (active) MB10Colors.inkPrimary else MB10Colors.inkSecondary, fontFamily = IBMPlexSans, fontSize = 13.sp)
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))

        when (activeSegment) {
            0 -> AccessPointForm()
            1 -> ShardForm()
            else -> DaemonForm()
        }
    }
}

@Composable
private fun AccessPointForm() {
    var id by remember { mutableStateOf(newId("ap")) }
    var name by remember { mutableStateOf("") }
    var generatedFor by remember { mutableStateOf<Pair<String, String>?>(null) }

    Column {
        LabeledField("id точки (менять не обязательно)", id) { id = it }
        Spacer(Modifier.height(8.dp))
        LabeledField("Название точки", name, placeholder = "Панель вентиляции, техэтаж") { name = it }
        Spacer(Modifier.height(12.dp))
        AppButton(
            "Показать QR",
            modifier = Modifier.fillMaxWidth(),
            variant = ButtonVariant.Primary,
            enabled = name.isNotBlank(),
            onClick = { generatedFor = id to name }
        )

        generatedFor?.let { (gid, gname) ->
            Spacer(Modifier.height(16.dp))
            val raw = remember(gid, gname) { Mb10QrCodec.encodeAccessPoint(gid, gname) }
            GeneratedQrPanel(raw = raw, caption = gname, accent = MB10Colors.accentAction)
        }
    }
}

@Composable
private fun ShardForm() {
    var id by remember { mutableStateOf(newId("shard")) }
    var badge by remember { mutableStateOf(shardBadgeOptions[0]) }
    var decryptAction by remember { mutableStateOf(false) }
    var title by remember { mutableStateOf("") }
    var meta by remember { mutableStateOf("") }
    var body by remember { mutableStateOf("") }
    var moneyText by remember { mutableStateOf("") }
    var generated by remember { mutableStateOf<String?>(null) }

    Column {
        LabeledField("id шарда (менять не обязательно)", id) { id = it }
        Spacer(Modifier.height(8.dp))
        SectionLabel("Статус")
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            shardBadgeOptions.forEach { option ->
                val selected = option == badge
                StatusChip(
                    option,
                    tone = if (selected) ChipTone.Action else ChipTone.Neutral,
                    modifier = Modifier.clickable { badge = option }
                )
            }
        }
        Spacer(Modifier.height(12.dp))
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.clickable { decryptAction = !decryptAction }) {
            StatusChip(
                if (decryptAction) "требует взлома: да" else "требует взлома: нет",
                tone = if (decryptAction) ChipTone.Netrun else ChipTone.Neutral
            )
        }
        Spacer(Modifier.height(12.dp))
        LabeledField("Заголовок (короткое описание в списке)", title, placeholder = "Служебный лог клиники") { title = it }
        Spacer(Modifier.height(8.dp))
        LabeledField("Мета-строка", meta, placeholder = "получен 21:02 · клиника, уровень доступа 2") { meta = it }
        Spacer(Modifier.height(8.dp))
        LabeledField("Текст шарда (2-3 абзаца)", body, placeholder = "Полный текст, который увидит игрок", minLines = 5) { body = it }
        Spacer(Modifier.height(8.dp))
        LabeledField("Деньги в шарде, €$ (0 — без денег)", moneyText, placeholder = "0") { moneyText = it.filter(Char::isDigit) }
        Spacer(Modifier.height(12.dp))
        AppButton(
            "Показать QR",
            modifier = Modifier.fillMaxWidth(),
            variant = ButtonVariant.Netrun,
            enabled = title.isNotBlank() && body.isNotBlank(),
            onClick = {
                generated = Mb10QrCodec.encodeShard(id, badge, decryptAction, title, meta, body, moneyText.toLongOrNull() ?: 0)
            }
        )

        generated?.let { raw ->
            Spacer(Modifier.height(16.dp))
            GeneratedQrPanel(raw = raw, caption = title, accent = MB10Colors.accentNetrun)
        }
    }
}

private val daemonRewardTypeOptions = listOf("Без награды", "Деньги", "Шард")

/**
 * Демон — предмет, который игрок сканирует к себе в кибердеку и потом
 * может выбрать на любом взломе (см. DaemonStore.add). Код-последовательность
 * собирается тапом по алфавиту взлома (BreachSymbols.ALPHABET), а не вводом
 * произвольного текста — коды вне этого алфавита никогда не появятся в
 * сетке взлома как "случайные соседи", только как сама цель, что сделало бы
 * такую клетку подозрительно уникальной и выдавало бы решение на глаз.
 */
@Composable
private fun DaemonForm() {
    var id by remember { mutableStateOf(newId("daemon")) }
    var name by remember { mutableStateOf("") }
    var sequence by remember { mutableStateOf(listOf<String>()) }
    var reward by remember { mutableStateOf("") }
    var rewardType by remember { mutableStateOf(daemonRewardTypeOptions[0]) }
    var moneyText by remember { mutableStateOf("") }
    var shardTitle by remember { mutableStateOf("") }
    var shardMeta by remember { mutableStateOf("") }
    var shardBody by remember { mutableStateOf("") }
    var generated by remember { mutableStateOf<String?>(null) }

    Column {
        LabeledField("id демона (менять не обязательно)", id) { id = it }
        Spacer(Modifier.height(8.dp))
        LabeledField("Название демона", name, placeholder = "Backdoor.exe") { name = it }
        Spacer(Modifier.height(12.dp))

        SectionLabel("Код-последовательность (тапайте по порядку)")
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            BreachSymbols.ALPHABET.forEach { code ->
                StatusChip(code, tone = ChipTone.Netrun, modifier = Modifier.clickable { sequence = sequence + code })
            }
        }
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            if (sequence.isEmpty()) {
                Text("Пока пусто — нажмите код(ы) выше", color = MB10Colors.inkTertiary, fontFamily = JetBrainsMono, fontSize = 10.5.sp)
            } else {
                sequence.forEach { code -> CodePill(code) }
            }
            Spacer(Modifier.weight(1f))
            if (sequence.isNotEmpty()) {
                Text(
                    "Очистить",
                    color = MB10Colors.accentDanger, fontFamily = JetBrainsMono, fontSize = 10.sp,
                    modifier = Modifier.clickable { sequence = emptyList() }
                )
            }
        }
        Spacer(Modifier.height(12.dp))

        LabeledField("Описание эффекта (текст для игрока)", reward, placeholder = "Снимает физическую блокировку двери") { reward = it }
        Spacer(Modifier.height(12.dp))

        SectionLabel("Награда за совпадение на взломе")
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            daemonRewardTypeOptions.forEach { option ->
                val selected = option == rewardType
                StatusChip(
                    option,
                    tone = if (selected) ChipTone.Action else ChipTone.Neutral,
                    modifier = Modifier.clickable { rewardType = option }
                )
            }
        }
        Spacer(Modifier.height(12.dp))
        when (rewardType) {
            "Деньги" -> LabeledField("Сумма, €$", moneyText, placeholder = "50") { moneyText = it.filter(Char::isDigit) }
            "Шард" -> Column {
                LabeledField("Заголовок шарда-награды", shardTitle, placeholder = "Пропуск уровня 3") { shardTitle = it }
                Spacer(Modifier.height(8.dp))
                LabeledField("Мета-строка", shardMeta, placeholder = "получен через взлом") { shardMeta = it }
                Spacer(Modifier.height(8.dp))
                LabeledField("Текст шарда", shardBody, placeholder = "Полный текст, который увидит игрок", minLines = 4) { shardBody = it }
            }
        }
        Spacer(Modifier.height(12.dp))

        AppButton(
            "Показать QR",
            modifier = Modifier.fillMaxWidth(),
            variant = ButtonVariant.Netrun,
            enabled = name.isNotBlank() && sequence.isNotEmpty(),
            onClick = {
                generated = Mb10QrCodec.encodeDaemon(
                    id = id,
                    name = name,
                    sequence = sequence,
                    reward = reward,
                    rewardMoney = if (rewardType == "Деньги") moneyText.toLongOrNull() ?: 0 else 0,
                    rewardShardTitle = if (rewardType == "Шард" && shardTitle.isNotBlank()) shardTitle else null,
                    rewardShardMeta = if (rewardType == "Шард") shardMeta else null,
                    rewardShardBody = if (rewardType == "Шард") shardBody else null
                )
            }
        )

        generated?.let { raw ->
            Spacer(Modifier.height(16.dp))
            GeneratedQrPanel(raw = raw, caption = name, accent = MB10Colors.accentNetrun)
        }
    }
}

@Composable
private fun GeneratedQrPanel(raw: String, caption: String, accent: Color) {
    ChamferedSurface(borderColor = accent, fillColor = MB10Colors.surfaceRaised, cut = 6.dp, contentPadding = 14.dp, modifier = Modifier.fillMaxWidth()) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
            val bitmap = remember(raw) { generateQrBitmap(raw) }
            Image(bitmap = bitmap.asImageBitmap(), contentDescription = "QR", modifier = Modifier.size(220.dp))
            Spacer(Modifier.height(8.dp))
            Text(caption, color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 12.sp, textAlign = TextAlign.Center)
            Spacer(Modifier.height(4.dp))
            Text(
                "Сфотографируйте или напечатайте до игры — точка/шард появится у игрока сразу после скана.",
                color = MB10Colors.inkSecondary, fontFamily = IBMPlexSans, fontSize = 10.5.sp, lineHeight = 14.sp, textAlign = TextAlign.Center
            )
        }
    }
}

@Composable
private fun LabeledField(label: String, value: String, placeholder: String = "", minLines: Int = 1, onValueChange: (String) -> Unit) {
    Column {
        Text(label, color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.sp, modifier = Modifier.padding(bottom = 4.dp))
        AppTextField(
            value = value,
            onValueChange = onValueChange,
            placeholder = placeholder,
            singleLine = minLines == 1,
            modifier = Modifier.fillMaxWidth().heightIn(min = if (minLines > 1) 100.dp else 0.dp)
        )
    }
}

private fun newId(prefix: String): String = "$prefix-" + UUID.randomUUID().toString().take(8)
