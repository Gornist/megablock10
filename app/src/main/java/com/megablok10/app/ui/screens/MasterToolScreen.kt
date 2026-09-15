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
import androidx.compose.material3.TextField
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
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.qr.generateQrBitmap
import com.megablok10.app.ui.theme.ChamferedPanel
import com.megablok10.app.ui.theme.Chip
import com.megablok10.app.ui.theme.IBMPlexSans
import com.megablok10.app.ui.theme.JetBrainsMono
import com.megablok10.app.ui.theme.Jura
import com.megablok10.app.ui.theme.MB10Colors
import com.megablok10.app.ui.theme.OutlineButton
import com.megablok10.app.ui.theme.SectionLabel
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

    Column(Modifier.fillMaxSize().background(MB10Colors.bg0).verticalScroll(rememberScrollState()).padding(16.dp)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().clickable(onClick = onClose).padding(vertical = 6.dp)
        ) {
            Text("←", color = MB10Colors.ink0, fontFamily = JetBrainsMono, fontSize = 16.sp)
            Spacer(Modifier.width(8.dp))
            Text("Назад в настройки", color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 11.sp)
        }
        Spacer(Modifier.height(12.dp))
        Text("Мастерская", color = MB10Colors.ink0, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 20.sp)
        Spacer(Modifier.height(4.dp))
        Text(
            "Генерирует QR для точек доступа и шардов — их печатают или показывают заранее, до игры. Игроки эти коды только сканируют, этот экран им не нужен.",
            color = MB10Colors.inkMuted, fontFamily = IBMPlexSans, fontSize = 12.sp, lineHeight = 16.sp
        )
        Spacer(Modifier.height(18.dp))

        ChamferedPanel(
            borderColor = MB10Colors.inkFaint, fillColor = MB10Colors.bg1, cut = 6.dp, contentPadding = 0.dp,
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(Modifier.fillMaxWidth()) {
                listOf("Точка доступа", "Шард").forEachIndexed { i, label ->
                    val active = i == activeSegment
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .background(if (active) MB10Colors.bg2 else MB10Colors.bg1)
                            .clickable { activeSegment = i }
                            .padding(vertical = 8.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(label, color = if (active) MB10Colors.ink0 else MB10Colors.inkMuted, fontFamily = IBMPlexSans, fontSize = 13.sp)
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))

        if (activeSegment == 0) AccessPointForm() else ShardForm()
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
        OutlineButton(
            "Показать QR",
            modifier = Modifier.fillMaxWidth(),
            accentColor = MB10Colors.lime,
            enabled = name.isNotBlank(),
            onClick = { generatedFor = id to name }
        )

        generatedFor?.let { (gid, gname) ->
            Spacer(Modifier.height(16.dp))
            val raw = remember(gid, gname) { Mb10QrCodec.encodeAccessPoint(gid, gname) }
            GeneratedQrPanel(raw = raw, caption = gname, accent = MB10Colors.lime)
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
    var generated by remember { mutableStateOf<String?>(null) }

    Column {
        LabeledField("id шарда (менять не обязательно)", id) { id = it }
        Spacer(Modifier.height(8.dp))
        SectionLabel("Статус")
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            shardBadgeOptions.forEach { option ->
                val selected = option == badge
                Chip(
                    option,
                    color = if (selected) MB10Colors.yellow else MB10Colors.inkMuted,
                    modifier = Modifier.clickable { badge = option }
                )
            }
        }
        Spacer(Modifier.height(12.dp))
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.clickable { decryptAction = !decryptAction }) {
            Chip(if (decryptAction) "требует взлома: да" else "требует взлома: нет", color = if (decryptAction) MB10Colors.lime else MB10Colors.inkMuted)
        }
        Spacer(Modifier.height(12.dp))
        LabeledField("Заголовок (короткое описание в списке)", title, placeholder = "Служебный лог клиники") { title = it }
        Spacer(Modifier.height(8.dp))
        LabeledField("Мета-строка", meta, placeholder = "получен 21:02 · клиника, уровень доступа 2") { meta = it }
        Spacer(Modifier.height(8.dp))
        LabeledField("Текст шарда (2-3 абзаца)", body, placeholder = "Полный текст, который увидит игрок", minLines = 5) { body = it }
        Spacer(Modifier.height(12.dp))
        OutlineButton(
            "Показать QR",
            modifier = Modifier.fillMaxWidth(),
            accentColor = MB10Colors.lime,
            enabled = title.isNotBlank() && body.isNotBlank(),
            onClick = {
                generated = Mb10QrCodec.encodeShard(id, badge, decryptAction, title, meta, body)
            }
        )

        generated?.let { raw ->
            Spacer(Modifier.height(16.dp))
            GeneratedQrPanel(raw = raw, caption = title, accent = MB10Colors.lime)
        }
    }
}

@Composable
private fun GeneratedQrPanel(raw: String, caption: String, accent: Color) {
    ChamferedPanel(borderColor = accent, fillColor = MB10Colors.bg1, cut = 6.dp, contentPadding = 14.dp, modifier = Modifier.fillMaxWidth()) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
            val bitmap = remember(raw) { generateQrBitmap(raw) }
            Image(bitmap = bitmap.asImageBitmap(), contentDescription = "QR", modifier = Modifier.size(220.dp))
            Spacer(Modifier.height(8.dp))
            Text(caption, color = MB10Colors.ink0, fontFamily = IBMPlexSans, fontSize = 12.sp, textAlign = TextAlign.Center)
            Spacer(Modifier.height(4.dp))
            Text(
                "Сфотографируйте или напечатайте до игры — точка/шард появится у игрока сразу после скана.",
                color = MB10Colors.inkMuted, fontFamily = IBMPlexSans, fontSize = 10.5.sp, lineHeight = 14.sp, textAlign = TextAlign.Center
            )
        }
    }
}

@Composable
private fun LabeledField(label: String, value: String, placeholder: String = "", minLines: Int = 1, onValueChange: (String) -> Unit) {
    Column {
        Text(label, color = MB10Colors.inkMuted, fontFamily = JetBrainsMono, fontSize = 10.sp, modifier = Modifier.padding(bottom = 4.dp))
        TextField(
            value = value,
            onValueChange = onValueChange,
            placeholder = { Text(placeholder, color = MB10Colors.inkMuted, fontFamily = IBMPlexSans, fontSize = 13.sp) },
            singleLine = minLines == 1,
            modifier = Modifier.fillMaxWidth().heightIn(min = if (minLines > 1) 100.dp else 0.dp)
        )
    }
}

private fun newId(prefix: String): String = "$prefix-" + UUID.randomUUID().toString().take(8)
