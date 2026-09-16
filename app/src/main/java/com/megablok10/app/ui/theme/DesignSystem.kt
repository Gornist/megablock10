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
 * (ChamferedPanel, Chip, OutlineButton): геометрия и так была верной,
 * здесь фиксируется единый набор входных параметров и семантика.
 */

/** Направление среза для ChamferedSurface — фиксированные варианты вместо произвольного Dp по месту. */
enum class SurfaceCorner { Single, Double }

@Composable
fun ChamferedSurface(
    modifier: Modifier = Modifier,
    corner: SurfaceCorner = SurfaceCorner.Single,
    borderColor: Color = MB10Colors.borderMuted,
    fillColor: Color = MB10Colors.surfaceRaised,
    borderWidth: Dp = 1.dp,
    contentPadding: Dp = MB10Spacing.md,
    content: @Composable BoxScope.() -> Unit
) {
    ChamferedPanel(
        modifier = modifier,
        borderColor = borderColor,
        fillColor = fillColor,
        cut = 10.dp,
        borderWidth = borderWidth,
        doubleCorner = corner == SurfaceCorner.Double,
        contentPadding = contentPadding,
        content = content
    )
}

/** Смысловой тон чипа/статуса — цвет выбирается по смыслу, а не подбирается вручную на каждом экране. */
enum class ChipTone { Neutral, Info, Action, Danger, Netrun }

@Composable
fun StatusChip(text: String, tone: ChipTone = ChipTone.Neutral, modifier: Modifier = Modifier) {
    val color = when (tone) {
        ChipTone.Neutral -> MB10Colors.inkSecondary
        ChipTone.Info -> MB10Colors.inkPrimary
        ChipTone.Action -> MB10Colors.accentAction
        ChipTone.Danger -> MB10Colors.accentDanger
        ChipTone.Netrun -> MB10Colors.accentNetrun
    }
    Chip(text, color = color, modifier = modifier)
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
 * Единая строка списка: опциональные leading/trailing слоты + произвольный
 * контент по центру. Заменяет собой вручную собранные Row-паттерны в
 * контактах/чатах/звонках/шардах — те либо мигрируют на это, либо остаются
 * содержательно другими (например ShardCard — отдельная крупная карточка,
 * не строка списка).
 */
@Composable
fun ListRow(
    modifier: Modifier = Modifier,
    selected: Boolean = false,
    onClick: (() -> Unit)? = null,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .then(
                if (selected) Modifier.background(MB10Colors.accentAction, chamferShape(6.dp))
                else Modifier
            )
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 12.dp, vertical = 10.dp),
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
