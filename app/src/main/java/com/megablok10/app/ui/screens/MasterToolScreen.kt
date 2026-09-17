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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.megablok10.app.breach.BreachSymbols
import com.megablok10.app.breach.CodePill
import com.megablok10.app.breach.Container
import com.megablok10.app.breach.DaemonEffect
import com.megablok10.app.breach.LootCodec
import com.megablok10.app.breach.LootCrypto
import com.megablok10.app.breach.LootSlot
import com.megablok10.app.breach.LootType
import com.megablok10.app.breach.Tier
import com.megablok10.app.breach.label
import com.megablok10.app.data.ContainerEntity
import com.megablok10.app.data.Mb10Database
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
import com.megablok10.app.ui.theme.ListRow
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.SectionLabel
import com.megablok10.app.ui.theme.SegmentedTabs
import com.megablok10.app.ui.theme.StatusChip
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * Только для мастеров — генерирует QR для контейнеров и шардов, которые
 * больше нигде в приложении не создаются (игроки их только сканируют).
 * Отдельных QR-демонов больше нет (ревизия v9) — демон выдаётся только
 * как лут-слот контейнера. Печатать/показывать заранее, до игры; в самом
 * приложении не участвует.
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
            "Генерирует QR для контейнеров, шардов и RAM-апгрейдов — их печатают или показывают заранее, до игры. Игроки эти коды только сканируют, этот экран им не нужен.",
            color = MB10Colors.inkSecondary, fontFamily = IBMPlexSans, fontSize = 12.sp, lineHeight = 16.sp
        )
        Spacer(Modifier.height(18.dp))

        SegmentedTabs(listOf("Контейнер", "Шард", "RAM", "Дашборд"), selected = activeSegment, onSelect = { activeSegment = it })
        Spacer(Modifier.height(16.dp))

        when (activeSegment) {
            0 -> ContainerForm()
            1 -> ShardForm()
            2 -> RamForm()
            else -> DashboardSegment()
        }
    }
}

@Composable
private fun TierPicker(tier: Tier, onChange: (Tier) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Tier.entries.forEach { t ->
            StatusChip(t.label, tone = if (t == tier) ChipTone.Action else ChipTone.Neutral, modifier = Modifier.clickable { onChange(t) })
        }
    }
}

/**
 * Контейнер — заменяет старую "точку доступа" (ревизия v9). Лут собирается
 * слотами прямо в форме (LootSlotBuilder) — каждый слот шифруется
 * (LootCrypto) и упаковывается в QR контейнера целиком, отдельного QR под
 * демона/шард из контейнера нет: игрок получает их автоматически, извлекая
 * слот демоном нужного эффекта (см. DaemonRewards).
 */
@Composable
private fun ContainerForm() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var id by remember { mutableStateOf(newId("container")) }
    var name by remember { mutableStateOf("") }
    var tier by remember { mutableStateOf(Tier.BASE) }
    var ownerFaction by remember { mutableStateOf("") }
    var slots by remember { mutableStateOf(listOf<LootSlot>()) }
    var generated by remember { mutableStateOf<String?>(null) }

    Column {
        LabeledField("id контейнера (менять не обязательно)", id) { id = it }
        Spacer(Modifier.height(8.dp))
        LabeledField("Название", name, placeholder = "Панель вентиляции, техэтаж") { name = it }
        Spacer(Modifier.height(12.dp))
        SectionLabel("Тир (сложность взлома)")
        TierPicker(tier) { tier = it }
        Spacer(Modifier.height(12.dp))
        LabeledField("Фракция-владелец (получает сигнал СБ при взломе)", ownerFaction, placeholder = "Otryad_SB") { ownerFaction = it }
        Spacer(Modifier.height(16.dp))

        SectionLabel("Лут — ${slots.size} слот(ов)")
        slots.forEachIndexed { index, slot ->
            SlotSummaryRow(slot) { slots = slots.filterIndexed { i, _ -> i != index } }
        }
        Spacer(Modifier.height(8.dp))
        LootSlotBuilder(onAdd = { slot -> slots = slots + slot })
        Spacer(Modifier.height(16.dp))

        AppButton(
            "Показать QR",
            modifier = Modifier.fillMaxWidth(),
            variant = ButtonVariant.Primary,
            enabled = name.isNotBlank() && ownerFaction.isNotBlank(),
            onClick = {
                val container = Container(id, name, tier, ownerFaction, slots)
                generated = Mb10QrCodec.encodeContainer(container)
                scope.launch {
                    val lootJson = slots.joinToString(";") { "${it.type.name},${it.tier.level},${it.copies},${it.payload}" }
                    Mb10Database.get(context).containerDao().upsert(
                        ContainerEntity(id = id, name = name, tier = tier.level, ownerFaction = ownerFaction, lootJson = lootJson)
                    )
                }
            }
        )

        generated?.let { raw ->
            Spacer(Modifier.height(16.dp))
            GeneratedQrPanel(raw = raw, caption = name, accent = MB10Colors.accentAction)
        }
    }
}

@Composable
private fun SlotSummaryRow(slot: LootSlot, onRemove: () -> Unit) {
    val loot = remember(slot) { LootCrypto.decrypt(slot.payload)?.let(LootCodec::decode) }
    val label = when (loot) {
        is LootCodec.Loot.ShardLoot -> "Шард: ${loot.title}"
        is LootCodec.Loot.DaemonLoot -> "Демон: ${loot.name}"
        null -> "?"
    }
    val copiesLabel = if (slot.copies == 0) "∞" else slot.copies.toString()
    ListRow(
        trailing = {
            Text("✕", color = MB10Colors.accentDanger, fontFamily = JetBrainsMono, fontSize = 13.sp, modifier = Modifier.clickable(onClick = onRemove))
        }
    ) {
        Text(label, color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 12.5.sp)
        Text("${slot.tier.label} · $copiesLabel", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.sp)
    }
}

private val slotTypeOptions = listOf(LootType.SHARD, LootType.DAEMON)

@Composable
private fun LootSlotBuilder(onAdd: (LootSlot) -> Unit) {
    var type by remember { mutableStateOf(LootType.SHARD) }
    var slotTier by remember { mutableStateOf(Tier.BASE) }
    var copiesText by remember { mutableStateOf("") }

    var shardTitle by remember { mutableStateOf("") }
    var shardMeta by remember { mutableStateOf("") }
    var shardBody by remember { mutableStateOf("") }
    var shardValueHint by remember { mutableStateOf("") }
    var shardDecryptAction by remember { mutableStateOf(false) }
    var shardMoneyText by remember { mutableStateOf("") }

    var daemonName by remember { mutableStateOf("") }
    var daemonSequence by remember { mutableStateOf(listOf<String>()) }
    var daemonEffect by remember { mutableStateOf(DaemonEffect.EXTRACT_SHARD) }

    ChamferedSurface(borderColor = MB10Colors.borderMuted, fillColor = MB10Colors.surfaceSunken, cut = 6.dp, contentPadding = 12.dp, modifier = Modifier.fillMaxWidth()) {
        Column {
            SectionLabel("Новый слот")
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                slotTypeOptions.forEach { option ->
                    StatusChip(
                        if (option == LootType.SHARD) "Шард" else "Демон",
                        tone = if (option == type) ChipTone.Action else ChipTone.Neutral,
                        modifier = Modifier.clickable { type = option }
                    )
                }
            }
            Spacer(Modifier.height(10.dp))
            TierPicker(slotTier) { slotTier = it }
            Spacer(Modifier.height(8.dp))
            LabeledField("Тираж (0 — без ограничения)", copiesText, placeholder = "0") { copiesText = it.filter(Char::isDigit) }
            Spacer(Modifier.height(10.dp))

            if (type == LootType.SHARD) {
                LabeledField("Заголовок шарда", shardTitle, placeholder = "Служебный лог клиники") { shardTitle = it }
                Spacer(Modifier.height(8.dp))
                LabeledField("Мета-строка", shardMeta, placeholder = "получен 21:02 · клиника") { shardMeta = it }
                Spacer(Modifier.height(8.dp))
                LabeledField("Текст шарда", shardBody, placeholder = "Полный текст, который увидит игрок", minLines = 4) { shardBody = it }
                Spacer(Modifier.height(8.dp))
                LabeledField("Подсказка ценности (для отыгрыша торга)", shardValueHint, placeholder = "ценный технический документ") { shardValueHint = it }
                Spacer(Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.clickable { shardDecryptAction = !shardDecryptAction }) {
                    StatusChip(
                        if (shardDecryptAction) "требует взлома: да" else "требует взлома: нет",
                        tone = if (shardDecryptAction) ChipTone.Netrun else ChipTone.Neutral
                    )
                }
                Spacer(Modifier.height(8.dp))
                LabeledField("Деньги в шарде, €$ (0 — без денег)", shardMoneyText, placeholder = "0") { shardMoneyText = it.filter(Char::isDigit) }
            } else {
                LabeledField("Название демона", daemonName, placeholder = "Backdoor.exe") { daemonName = it }
                Spacer(Modifier.height(8.dp))
                SectionLabel("Код-последовательность (тапайте по порядку)")
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    BreachSymbols.ALPHABET.forEach { code ->
                        StatusChip(code, tone = ChipTone.Netrun, modifier = Modifier.clickable { daemonSequence = daemonSequence + code })
                    }
                }
                Spacer(Modifier.height(6.dp))
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                    if (daemonSequence.isEmpty()) {
                        Text("Пока пусто — нажмите код(ы) выше", color = MB10Colors.inkTertiary, fontFamily = JetBrainsMono, fontSize = 10.5.sp)
                    } else {
                        daemonSequence.forEach { code -> CodePill(code) }
                    }
                    Spacer(Modifier.weight(1f))
                    if (daemonSequence.isNotEmpty()) {
                        Text("Очистить", color = MB10Colors.accentDanger, fontFamily = JetBrainsMono, fontSize = 10.sp, modifier = Modifier.clickable { daemonSequence = emptyList() })
                    }
                }
                Spacer(Modifier.height(10.dp))
                SectionLabel("Эффект при совпадении")
                Column {
                    DaemonEffect.entries.chunked(3).forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(bottom = 6.dp)) {
                            row.forEach { effect ->
                                StatusChip(
                                    effect.label(),
                                    tone = if (effect == daemonEffect) ChipTone.Action else ChipTone.Neutral,
                                    modifier = Modifier.clickable { daemonEffect = effect }
                                )
                            }
                        }
                    }
                }
            }

            Spacer(Modifier.height(12.dp))
            val canAdd = if (type == LootType.SHARD) shardTitle.isNotBlank() && shardBody.isNotBlank() else daemonName.isNotBlank() && daemonSequence.isNotEmpty()
            AppButton(
                "Добавить слот в контейнер",
                modifier = Modifier.fillMaxWidth(),
                variant = ButtonVariant.Secondary,
                enabled = canAdd,
                onClick = {
                    val plain = if (type == LootType.SHARD) {
                        LootCodec.encodeShard(shardTitle, shardMeta, shardBody, shardValueHint, shardDecryptAction, shardMoneyText.toLongOrNull() ?: 0)
                    } else {
                        LootCodec.encodeDaemon(daemonName, daemonSequence, slotTier, daemonEffect)
                    }
                    onAdd(LootSlot(type = type, tier = slotTier, copies = copiesText.toIntOrNull() ?: 0, payload = LootCrypto.encrypt(plain)))
                    shardTitle = ""; shardMeta = ""; shardBody = ""; shardValueHint = ""; shardDecryptAction = false; shardMoneyText = ""
                    daemonName = ""; daemonSequence = emptyList()
                    copiesText = ""
                }
            )
        }
    }
}

@Composable
private fun ShardForm() {
    var id by remember { mutableStateOf(newId("shard")) }
    var decryptAction by remember { mutableStateOf(false) }
    var tier by remember { mutableStateOf(Tier.BASE) }
    var valueHint by remember { mutableStateOf("") }
    var title by remember { mutableStateOf("") }
    var meta by remember { mutableStateOf("") }
    var body by remember { mutableStateOf("") }
    var moneyText by remember { mutableStateOf("") }
    var generated by remember { mutableStateOf<String?>(null) }

    Column {
        LabeledField("id шарда (менять не обязательно)", id) { id = it }
        Spacer(Modifier.height(8.dp))
        SectionLabel("Тир (длина цели расшифровки)")
        TierPicker(tier) { tier = it }
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
        LabeledField("Подсказка ценности (для отыгрыша торга)", valueHint, placeholder = "ценный технический документ") { valueHint = it }
        Spacer(Modifier.height(8.dp))
        LabeledField("Деньги в шарде, €$ (0 — без денег)", moneyText, placeholder = "0") { moneyText = it.filter(Char::isDigit) }
        Spacer(Modifier.height(12.dp))
        AppButton(
            "Показать QR",
            modifier = Modifier.fillMaxWidth(),
            variant = ButtonVariant.Netrun,
            enabled = title.isNotBlank() && body.isNotBlank(),
            onClick = {
                generated = Mb10QrCodec.encodeShard(id, decryptAction, tier.level, valueHint, title, meta, body, moneyText.toLongOrNull() ?: 0)
            }
        )

        generated?.let { raw ->
            Spacer(Modifier.height(16.dp))
            GeneratedQrPanel(raw = raw, caption = title, accent = MB10Colors.accentNetrun)
        }
    }
}

/** RAM-апгрейд деки — токен одноразовый на устройство (см. RamUpgradeStore), delta прибавляется к Identity.ramCapacity с потолком 13. */
@Composable
private fun RamForm() {
    var delta by remember { mutableStateOf("1") }
    var generated by remember { mutableStateOf<String?>(null) }

    Column {
        Text(
            "Каждый QR одноразовый на устройство игрока — генерируйте новый для каждой выдачи, не показывайте один и тот же токен дважды.",
            color = MB10Colors.inkSecondary, fontFamily = IBMPlexSans, fontSize = 12.sp, lineHeight = 16.sp
        )
        Spacer(Modifier.height(12.dp))
        LabeledField("Прибавка к RAM, ячеек", delta, placeholder = "1") { delta = it.filter(Char::isDigit) }
        Spacer(Modifier.height(12.dp))
        AppButton(
            "Показать QR",
            modifier = Modifier.fillMaxWidth(),
            variant = ButtonVariant.Primary,
            enabled = (delta.toIntOrNull() ?: 0) > 0,
            onClick = { generated = Mb10QrCodec.encodeRamUpgrade(newId("ram"), delta.toIntOrNull() ?: 1) }
        )
        generated?.let { raw ->
            Spacer(Modifier.height(16.dp))
            GeneratedQrPanel(raw = raw, caption = "+$delta RAM", accent = MB10Colors.accentAction)
        }
    }
}

/** Реестр контейнеров, выпущенных этим устройством — свериться с тем, что уже роздано, без пересбора состава лута по памяти. */
@Composable
private fun DashboardSegment() {
    val context = LocalContext.current
    val containers by Mb10Database.get(context).containerDao().observeAll().collectAsState(initial = emptyList())

    if (containers.isEmpty()) {
        Text(
            "Пока нет ни одного выпущенного контейнера — появится здесь после первого «Показать QR» на вкладке «Контейнер».",
            color = MB10Colors.inkSecondary, fontFamily = IBMPlexSans, fontSize = 12.5.sp, lineHeight = 17.sp
        )
        return
    }

    Column {
        containers.forEach { entity ->
            ChamferedSurface(
                borderColor = MB10Colors.borderMuted, fillColor = MB10Colors.surfaceRaised, cut = 6.dp, contentPadding = 11.dp,
                modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp)
            ) {
                Column {
                    Text("${entity.name} · ${Tier.fromLevel(entity.tier).label}", color = MB10Colors.inkPrimary, fontFamily = IBMPlexSans, fontSize = 13.sp)
                    Text("владелец: ${entity.ownerFaction} · id: ${entity.id}", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.sp)
                    Spacer(Modifier.height(6.dp))
                    ContainerClaimStatus(entity)
                }
            }
        }
    }
}

private data class LootSummary(val type: LootType, val tier: Tier, val copies: Int)

/** Тот же формат, что LootSlotBuilder пишет в ContainerEntity.lootJson при сохранении — здесь только читаем обратно тип/тир/тираж, payload дашборду не нужен. */
private fun parseLootSummary(lootJson: String): List<LootSummary> {
    if (lootJson.isBlank()) return emptyList()
    return lootJson.split(";").mapNotNull { entry ->
        val parts = entry.split(",")
        if (parts.size < 3) return@mapNotNull null
        val type = runCatching { LootType.valueOf(parts[0]) }.getOrNull() ?: return@mapNotNull null
        val tierLevel = parts[1].toIntOrNull() ?: return@mapNotNull null
        val copies = parts[2].toIntOrNull() ?: return@mapNotNull null
        LootSummary(type, Tier.fromLevel(tierLevel), copies)
    }
}

/** Сверяет напечатанный состав контейнера с уже принятыми заявками (SlotClaimDao) — что из тиража игроки уже разобрали, живьём, по мере поступления сигналов от взломов. */
@Composable
private fun ContainerClaimStatus(entity: ContainerEntity) {
    val context = LocalContext.current
    val slots = remember(entity.lootJson) { parseLootSummary(entity.lootJson) }
    if (slots.isEmpty()) return

    val claims by Mb10Database.get(context).slotClaimDao().observeForContainer(entity.id).collectAsState(initial = emptyList())
    val claimedCounts = remember(claims) { claims.groupingBy { it.slotRef }.eachCount() }

    Column {
        slots.forEachIndexed { index, slot ->
            val claimed = claimedCounts["${entity.id}#$index"] ?: 0
            val typeLabel = if (slot.type == LootType.SHARD) "шард" else "демон"
            val quota = if (slot.copies > 0) "$claimed/${slot.copies}" else "$claimed (тираж не ограничен)"
            val exhausted = slot.copies > 0 && claimed >= slot.copies
            Text(
                "· $typeLabel · ${slot.tier.label} · разобрано $quota",
                color = if (exhausted) MB10Colors.accentDanger else MB10Colors.inkSecondary,
                fontFamily = JetBrainsMono, fontSize = 10.sp
            )
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
                "Сфотографируйте или напечатайте до игры — появится у игрока сразу после скана.",
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
