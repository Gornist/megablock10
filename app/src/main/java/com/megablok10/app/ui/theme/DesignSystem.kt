package com.megablok10.app.ui.theme

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog

/**
 * Слой 0 дизайн-системы. Каждый компонент здесь — единственный способ
 * получить свой тип элемента (панель, чип, кнопка, поле, диалог, тумблер,
 * строка списка) во всём приложении. Экраны не должны собирать эти же
 * визуальные паттерны заново через голые Box/border/background — если
 * нужного варианта нет, он добавляется сюда, а не копируется по месту.
 *
 * Часть компонентов — тонкие обёртки над уже существующими примитивами
 * (Chip, OutlineButton): геометрия и так была верной, здесь фиксируется
 * единый набор входных параметров и семантика.
 */

/** Направление среза для ChamferedSurface — фиксированные варианты вместо произвольного Dp по месту. */
enum class SurfaceCorner { Single, Double }

/**
 * Единственная панель со срезанными углами во всём приложении — экраны
 * больше не собирают её сами через двухслойный border+background (см.
 * приватный chamferedPanelImpl ниже, который делает эту работу один раз).
 */
@Composable
fun ChamferedSurface(
    modifier: Modifier = Modifier,
    corner: SurfaceCorner = SurfaceCorner.Single,
    borderColor: Color = MB10Colors.borderMuted,
    fillColor: Color = MB10Colors.surfaceRaised,
    cut: Dp = 10.dp,
    borderWidth: Dp = 1.dp,
    contentPadding: Dp = MB10Spacing.md,
    content: @Composable BoxScope.() -> Unit
) {
    chamferedPanelImpl(
        modifier = modifier,
        borderColor = borderColor,
        fillColor = fillColor,
        cut = cut,
        borderWidth = borderWidth,
        doubleCorner = corner == SurfaceCorner.Double,
        contentPadding = contentPadding,
        content = content
    )
}

/**
 * Двухслойная рамка со срезом: border не комбинируется с clip-path на одном
 * элементе, поэтому "рамка" рисуется отдельным фоном под отступом borderWidth
 * от заливки. Это ОДИН Box с цепочкой модификаторов (фон рамки → отступ →
 * фон заливки → отступ → контент), а не два вложенных Box — важно: вложенный
 * Box с fillMaxSize()/fillMaxWidth() внутри Box без своего размера даёт
 * циклическую зависимость размеров (родитель хочет обернуть ребёнка, ребёнок
 * хочет заполнить родителя) и панель раздувается на весь доступный экран.
 * Модификаторы в цепочке такой проблемы не создают: Box просто оборачивает
 * content, а фоны/паддинги — это концентрические отступы вокруг него.
 * innerCut уменьшен на borderWidth, чтобы диагональ среза оставалась
 * параллельна внешней независимо от толщины рамки.
 *
 * Приватная реализация ChamferedSurface — единственный вызывающий код за
 * пределами этого файла не существует, раньше это было публичным
 * ChamferedPanel в Components.kt, на который экраны ссылались напрямую в
 * обход ChamferedSurface.
 */
@Composable
private fun chamferedPanelImpl(
    modifier: Modifier = Modifier,
    borderColor: Color,
    fillColor: Color,
    cut: Dp,
    borderWidth: Dp,
    doubleCorner: Boolean,
    contentPadding: Dp,
    content: @Composable BoxScope.() -> Unit
) {
    val innerCut = cut - borderWidth
    val outerShape = if (doubleCorner) doubleChamferShape(cut) else chamferShape(cut)
    val innerShape = if (doubleCorner) doubleChamferShape(innerCut) else chamferShape(innerCut)
    Box(
        modifier = modifier
            .background(borderColor, outerShape)
            .padding(borderWidth)
            .background(fillColor, innerShape)
            .padding(contentPadding),
        content = content
    )
}

/** Смысловой тон чипа/статуса — цвет выбирается по смыслу, а не подбирается вручную на каждом экране. */
enum class ChipTone { Neutral, Info, Action, Danger, Netrun }

/** Единственное место, где ChipTone превращается в конкретный цвет — и StatusChip, и SystemNoticeLine берут его отсюда, а не дублируют один и тот же when. */
fun toneColor(tone: ChipTone): Color = when (tone) {
    ChipTone.Neutral -> MB10Colors.inkSecondary
    ChipTone.Info -> MB10Colors.inkPrimary
    ChipTone.Action -> MB10Colors.accentAction
    ChipTone.Danger -> MB10Colors.accentDanger
    ChipTone.Netrun -> MB10Colors.accentNetrun
}

@Composable
fun StatusChip(text: String, tone: ChipTone = ChipTone.Neutral, modifier: Modifier = Modifier) {
    Chip(text, color = toneColor(tone), modifier = modifier)
}

/**
 * Единственная обёртка для системных строк-уведомлений в чате (не переписка
 * между людьми, а автоматическое сообщение — сигнал СБ, чек) — по центру
 * ленты, в одну строку (обрезается многоточием только в совсем крайнем
 * случае, ширина не ограничена искусственно, как у пузыря между двумя
 * собеседниками), цвет по смыслу через ChipTone. Один компонент на все
 * системные уведомления, а не отдельная почти такая же обёртка под каждый
 * новый тип.
 */
@Composable
fun SystemNoticeLine(text: String, tone: ChipTone = ChipTone.Neutral, modifier: Modifier = Modifier) {
    val color = toneColor(tone)
    Row(modifier.fillMaxWidth().padding(bottom = 10.dp), horizontalArrangement = Arrangement.Center) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .background(color.copy(alpha = 0.1f), chamferShape(6.dp))
                .border(1.dp, color.copy(alpha = 0.4f), chamferShape(6.dp))
                .padding(vertical = 9.dp, horizontal = 11.dp)
        ) {
            HexBullet(color, size = 6.dp)
            Spacer(Modifier.width(6.dp))
            Text(text, color = color, fontFamily = JetBrainsMono, fontSize = 10.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/**
 * Единственная сегментированная плашка вкладок во всём приложении — Мастерская,
 * Кибердека и Профиль писали один и тот же Row+Box+forEachIndexed заново,
 * расходясь по мелочи (шрифт, наличие рамки). wrapInSurface рисует
 * ChamferedSurface-рамку вокруг (как у Мастерской и Кибердеки); false — голый
 * ряд без рамки (как у Профиля, у него уже есть обрамление экрана снаружи).
 */
@Composable
fun SegmentedTabs(labels: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier, wrapInSurface: Boolean = true) {
    val row: @Composable () -> Unit = {
        Row(Modifier.fillMaxWidth()) {
            labels.forEachIndexed { i, label ->
                val active = i == selected
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .background(if (active) MB10Colors.surfaceSunken else MB10Colors.surfaceRaised)
                        .clickable { onSelect(i) }
                        .padding(vertical = 8.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(label, color = if (active) MB10Colors.inkPrimary else MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 12.sp)
                }
            }
        }
    }
    if (wrapInSurface) {
        ChamferedSurface(borderColor = MB10Colors.borderMuted, fillColor = MB10Colors.surfaceRaised, cut = 6.dp, contentPadding = 0.dp, modifier = modifier.fillMaxWidth()) {
            row()
        }
    } else {
        Box(modifier.fillMaxWidth()) { row() }
    }
}

/** Единственное текстовое поле в стайлгайде — заменяет голые Material3 TextField/OutlinedTextField по экранам. */
@Composable
fun AppTextField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "",
    singleLine: Boolean = true,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default
) {
    Box(
        modifier = modifier
            .background(MB10Colors.surfaceSunken, chamferShape(6.dp))
            .border(1.dp, MB10Colors.borderMuted, chamferShape(6.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp)
    ) {
        Box {
            if (value.isEmpty()) {
                Text(placeholder, color = MB10Colors.inkTertiary, fontFamily = JetBrainsMono, fontSize = 13.sp)
            }
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                singleLine = singleLine,
                keyboardOptions = keyboardOptions,
                textStyle = TextStyle(color = MB10Colors.inkPrimary, fontFamily = JetBrainsMono, fontSize = 13.sp),
                cursorBrush = SolidColor(MB10Colors.accentAction),
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

/**
 * Три варианта кнопки — не три случайных стиля, а три смысла: Primary — то
 * единственное действие, ради которого пользователь на экране (принять
 * звонок, подтвердить); Secondary — второстепенное/навигационное действие;
 * Danger — необратимое/разрушительное. Disabled у Primary виден отдельной
 * заливкой, а не просто прозрачностью — это единственный вариант, где
 * "выключено" и "включено, но тускло" легко перепутать на взгляд.
 */
/** Netrun — filled-акцент лаймом, СТРОГО для действий взлома (сканировать объект, расшифровать) — см. правило accentNetrun в Color.kt. */
enum class ButtonVariant { Primary, Secondary, Danger, Netrun }

@Composable
fun AppButton(
    text: String,
    modifier: Modifier = Modifier,
    variant: ButtonVariant = ButtonVariant.Secondary,
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    when (variant) {
        ButtonVariant.Primary, ButtonVariant.Netrun -> {
            val accent = if (variant == ButtonVariant.Primary) MB10Colors.accentAction else MB10Colors.accentNetrun
            val fill = if (enabled) accent else MB10Colors.surfaceSunken
            val border = if (enabled) accent else MB10Colors.borderMuted
            val textColor = if (enabled) MB10Colors.onAccent else MB10Colors.inkTertiary
            Box(
                modifier = modifier
                    .background(fill, chamferShape(6.dp))
                    .border(1.dp, border, chamferShape(6.dp))
                    .clickable(enabled = enabled, onClick = onClick)
                    .padding(vertical = 12.dp)
            ) {
                Text(
                    text, color = textColor, fontFamily = JetBrainsMono, fontWeight = FontWeight.Medium,
                    fontSize = 12.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()
                )
            }
        }
        ButtonVariant.Secondary -> OutlineButton(text, modifier, accentColor = MB10Colors.inkPrimary, enabled = enabled, onClick = onClick)
        ButtonVariant.Danger -> OutlineButton(text, modifier, accentColor = MB10Colors.accentDanger, enabled = enabled, onClick = onClick)
    }
}

/**
 * Компактная кнопка-пилюля по ширине текста, а не на всю ширину контейнера,
 * как AppButton — для действий в шапке экрана ("+ Новый чат", "+ Новый
 * звонок"), где кнопка на всю ширину строки выглядела бы нелепо рядом с
 * заголовком.
 */
@Composable
fun CompactActionButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .background(MB10Colors.accentAction, chamferShape(5.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp)
    ) {
        Text(text, color = MB10Colors.onAccent, fontFamily = JetBrainsMono, fontSize = 10.5.sp, fontWeight = FontWeight.Medium)
    }
}

/**
 * Единая строка списка: опциональные leading/trailing слоты + произвольный
 * контент по центру. Заменяет собой вручную собранные Row-паттерны в
 * контактах/чатах/звонках — те либо мигрируют на это, либо остаются
 * содержательно другими (например ShardCard — отдельная крупная карточка,
 * не строка списка). Горизонтального паддинга внутри намеренно нет — он
 * уже есть на экране (Column/LazyColumn с padding(16.dp)), дублировать
 * его тут значило бы визуально сдвинуть все существующие списки.
 *
 * selected — сплошная заливка акцентом на всю строку, единственный сигнал
 * состояния сам по себе (без отдельной галочки). selectedColor по умолчанию
 * accentAction, но в хак-контексте (взлом, шифрование) должен быть явно
 * передан accentNetrun — см. правило разделения акцентов в Color.kt. Текст/
 * иконки внутри content должны сами переключаться на onAccent при selected.
 *
 * horizontalInset — внутренний горизонтальный отступ ВНУТРИ заливки. По умолчанию 0 (см. выше), но у списков с selected он нужен: иначе текст
 * прижат к самому краю скошенной заливки и она выглядит обрезанной слева. Отступ действует и у невыбранных строк, чтобы текст не прыгал при выборе.
 */
@Composable
fun ListRow(
    modifier: Modifier = Modifier,
    selected: Boolean = false,
    selectedColor: Color = MB10Colors.accentAction,
    horizontalInset: Dp = 0.dp,
    onClick: (() -> Unit)? = null,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .then(
                if (selected) Modifier.background(selectedColor, chamferShape(6.dp))
                else Modifier
            )
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = horizontalInset, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (leading != null) {
            leading()
            Spacer(Modifier.width(10.dp))
        }
        Column(Modifier.weight(1f), content = content)
        if (trailing != null) {
            Spacer(Modifier.width(10.dp))
            trailing()
        }
    }
}

/**
 * QR, который показывают другому игроку с экрана телефона — по умолчанию
 * притушен и не читается издалека/на случайном фото через плечо, по тапу
 * раскрывается на полную яркость. Не для QR, которые печатают на пропсы
 * (МастерТул) — только для тех, что игрок показывает с руки другому игроку.
 */
@Composable
fun DimmableQr(bitmap: Bitmap, contentDescription: String, size: Dp = 200.dp, modifier: Modifier = Modifier) {
    var revealed by remember { mutableStateOf(false) }
    Box(
        modifier = modifier.size(size).clickable { revealed = !revealed },
        contentAlignment = Alignment.Center
    ) {
        Image(bitmap = bitmap.asImageBitmap(), contentDescription = contentDescription, modifier = Modifier.size(size))
        if (!revealed) {
            Box(Modifier.size(size).background(MB10Colors.surfaceBase.copy(alpha = 0.88f)))
            Text(
                "Нажмите, чтобы показать",
                color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 10.5.sp,
                textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 20.dp)
            )
        }
    }
}

/**
 * Единственный диалог в стайлгайде — заменяет стоковый Material3 AlertDialog
 * (тот рендерится в системной светлой теме поверх тёмного приложения и
 * выглядит как визуальный сбой). confirmVariant по умолчанию Danger —
 * большинство диалогов подтверждения в приложении необратимы.
 */
@Composable
fun AppDialog(
    onDismissRequest: () -> Unit,
    title: String,
    body: String,
    confirmText: String,
    onConfirm: () -> Unit,
    dismissText: String = "Отмена",
    confirmVariant: ButtonVariant = ButtonVariant.Danger
) {
    Dialog(onDismissRequest = onDismissRequest) {
        ChamferedSurface(
            borderColor = MB10Colors.borderMuted,
            fillColor = MB10Colors.surfaceRaised,
            contentPadding = MB10Spacing.lg
        ) {
            Column {
                Text(title, color = MB10Colors.inkPrimary, fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                Spacer(Modifier.height(10.dp))
                Text(body, color = MB10Colors.inkSecondary, fontFamily = IBMPlexSans, fontSize = 13.sp, lineHeight = 18.sp)
                Spacer(Modifier.height(18.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    AppButton(dismissText, modifier = Modifier.weight(1f), variant = ButtonVariant.Secondary, onClick = onDismissRequest)
                    AppButton(confirmText, modifier = Modifier.weight(1f), variant = confirmVariant, onClick = onConfirm)
                }
            }
        }
    }
}

/** Точка статуса "в сети" — единственный вид этого индикатора в приложении, вместо текста "в сети"/"не в сети" на одних экранах и точки на других. */
@Composable
fun OnlineDot(online: Boolean, modifier: Modifier = Modifier) {
    Box(modifier.size(7.dp).background(if (online) MB10Colors.inkPrimary else MB10Colors.inkTertiary, CircleShape))
}

/**
 * Единый вид пустого списка — контурный шестиугольник + пояснительный текст
 * по центру, вместо серой строки текста без акцента, как было раньше на
 * каждом экране по-своему. Не более того: сам текст ("что сделать, чтобы
 * список не был пустым") остаётся за экраном, компонент только задаёт форму.
 */
@Composable
fun EmptyState(text: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxWidth().padding(vertical = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(Modifier.size(40.dp).border(1.5.dp, MB10Colors.borderMuted, hexShape()))
        Spacer(Modifier.height(14.dp))
        Text(
            text,
            color = MB10Colors.inkTertiary, fontFamily = IBMPlexSans, fontSize = 13.sp, lineHeight = 18.sp,
            textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 28.dp)
        )
    }
}

/**
 * Поле суммы для денег: не текстовое поле с системной клавиатурой, а
 * дисплей текущего значения + своя цифровая клавиатура снизу, в тех же
 * токенах, что весь остальной интерфейс — единственное место в приложении,
 * где вместо IME телефона используется собственная раскладка.
 */
@Composable
fun AmountField(value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier, maxLength: Int = 9) {
    Column(modifier) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(MB10Colors.surfaceSunken, chamferShape(6.dp))
                .border(1.dp, MB10Colors.borderMuted, chamferShape(6.dp))
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                value.ifEmpty { "0" },
                color = if (value.isEmpty()) MB10Colors.inkTertiary else MB10Colors.inkPrimary,
                fontFamily = Jura, fontWeight = FontWeight.Bold, fontSize = 22.sp,
                modifier = Modifier.weight(1f)
            )
            Text("€$", color = MB10Colors.inkSecondary, fontFamily = JetBrainsMono, fontSize = 13.sp, fontWeight = FontWeight.Medium)
        }
        Spacer(Modifier.height(10.dp))
        NumericKeypad(value = value, onValueChange = onValueChange, maxLength = maxLength)
    }
}

@Composable
private fun NumericKeypad(value: String, onValueChange: (String) -> Unit, maxLength: Int) {
    val rows = listOf(
        listOf("1", "2", "3"),
        listOf("4", "5", "6"),
        listOf("7", "8", "9"),
        listOf("", "0", "⌫")
    )
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rows.forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { key ->
                    if (key.isEmpty()) {
                        Spacer(Modifier.weight(1f))
                    } else {
                        KeypadKey(
                            key,
                            modifier = Modifier.weight(1f),
                            onClick = {
                                when (key) {
                                    "⌫" -> onValueChange(value.dropLast(1))
                                    else -> if (value.length < maxLength) onValueChange(value + key)
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun KeypadKey(label: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        modifier = modifier
            .aspectRatio(1.7f)
            .background(MB10Colors.surfaceRaised, chamferShape(6.dp))
            .border(1.dp, MB10Colors.borderMuted, chamferShape(6.dp))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Text(label, color = MB10Colors.inkPrimary, fontFamily = JetBrainsMono, fontSize = 18.sp, fontWeight = FontWeight.Medium)
    }
}
