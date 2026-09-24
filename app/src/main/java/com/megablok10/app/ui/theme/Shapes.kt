package com.megablok10.app.ui.theme

import androidx.compose.foundation.border
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Срез — только в верхнем левом углу. Так решено во всех предыдущих
 * итерациях макета — не менять на все четыре угла без явного запроса.
 *
 * GenericShape отдаёт в билдер LayoutDirection, а не Density, поэтому
 * Dp -> px переводим заранее через LocalDensity.current и просто
 * захватываем готовое значение в замыкании форм-билдера.
 */
@Composable
fun chamferShape(cut: Dp): Shape {
    val cutPx = with(LocalDensity.current) { cut.toPx() }
    return GenericShape { size, _ ->
        val c = cutPx.coerceIn(0f, minOf(size.width, size.height))
        moveTo(c, 0f)
        lineTo(size.width, 0f)
        lineTo(size.width, size.height)
        lineTo(0f, size.height)
        lineTo(0f, c)
        close()
    }
}

/**
 * Двойной срез (верх-лево + низ-право) — для более крупных панелей в
 * макете (баланс, профиль), а не как замена одиночному чамферу.
 */
@Composable
fun doubleChamferShape(cut: Dp): Shape {
    val cutPx = with(LocalDensity.current) { cut.toPx() }
    return GenericShape { size, _ ->
        val c = cutPx.coerceIn(0f, minOf(size.width, size.height) / 2)
        moveTo(c, 0f)
        lineTo(size.width, 0f)
        lineTo(size.width, size.height - c)
        lineTo(size.width - c, size.height)
        lineTo(0f, size.height)
        lineTo(0f, c)
        close()
    }
}

@Composable
fun hexShape(): Shape = GenericShape { size, _ ->
    moveTo(size.width * 0.5f, 0f)
    lineTo(size.width, size.height * 0.25f)
    lineTo(size.width, size.height * 0.75f)
    lineTo(size.width * 0.5f, size.height)
    lineTo(0f, size.height * 0.75f)
    lineTo(0f, size.height * 0.25f)
    close()
}

/** Флажок-нашивка — заголовок панели (используется на экране Кибердеки). */
@Composable
fun flagTabShape(): Shape = GenericShape { size, _ ->
    moveTo(0f, 0f)
    lineTo(size.width, 0f)
    lineTo(size.width - size.height * 0.4f, size.height)
    lineTo(0f, size.height)
    close()
}

/**
 * Зубчатый чамфер — как chamferShape (срез только в верхнем левом углу), но
 * с дополнительным уступом-ступенькой на правом крае посередине высоты:
 * верхний сегмент уже нижнего на stepInset. Источник паттерна — фан-карточка
 * персонажа CP2077 (боковые акцентные полосы), не панель общего назначения —
 * не путать с обычным chamferShape для карточек/кнопок.
 */
@Composable
fun jaggedChamferShape(cut: Dp, stepInset: Dp = cut): Shape {
    val cutPx = with(LocalDensity.current) { cut.toPx() }
    val stepPx = with(LocalDensity.current) { stepInset.toPx() }
    return GenericShape { size, _ ->
        val c = cutPx.coerceIn(0f, minOf(size.width, size.height))
        val step = stepPx.coerceIn(0f, size.width * 0.6f)
        val midY = size.height / 2f
        moveTo(c, 0f)
        lineTo(size.width - step, 0f)
        lineTo(size.width - step, midY)
        lineTo(size.width, midY)
        lineTo(size.width, size.height)
        lineTo(0f, size.height)
        lineTo(0f, c)
        close()
    }
}

/**
 * Срез в правом нижнем углу плюс маленький прямоугольный вырез-паз на левом крае, у середины высоты — форма кнопки с
 * cyberpunk.net (докладка «Cyberpunk.net → Мегаблок №10»): их SVG — лицензионный актив CD Projekt RED, не копируется,
 * но геометрию (единственный, а не оба среза chamferShape/doubleChamferShape; плюс сам приём паза) переснял с реального
 * контура (viewBox 232×48) и пересчитал в доли — cut ≈ 37.5% высоты, notch ≈ 4.2% высоты у 52% от верха. Для
 * ButtonVariant.System — не замена chamferShape для остальных кнопок.
 */
@Composable
fun notchedChamferShape(cut: Dp, notchWidth: Dp = 10.dp, notchHeight: Dp = 2.dp): Shape {
    val cutPx = with(LocalDensity.current) { cut.toPx() }
    val notchWPx = with(LocalDensity.current) { notchWidth.toPx() }
    val notchHPx = with(LocalDensity.current) { notchHeight.toPx() }
    return GenericShape { size, _ ->
        val c = cutPx.coerceIn(0f, minOf(size.width, size.height))
        val notchBottom = size.height * 0.52f
        val notchTop = (notchBottom - notchHPx).coerceAtLeast(0f)
        val nw = notchWPx.coerceIn(0f, size.width * 0.4f)
        moveTo(0f, 0f)
        lineTo(size.width, 0f)
        lineTo(size.width, size.height - c)
        lineTo(size.width - c, size.height)
        lineTo(0f, size.height)
        lineTo(0f, notchBottom)
        lineTo(nw, notchBottom)
        lineTo(nw, notchTop)
        lineTo(0f, notchTop)
        close()
    }
}

/**
 * Единственный способ обвести элемент рамкой: контур повторяет срез [chamferShape], а не прямоугольник.
 * Голый `Modifier.border(w, color)` без формы даёт квадратную рамку — это считается ошибкой (следит `NoRectangularBordersTest`).
 */
@Composable
fun Modifier.chamferBorder(color: Color, cut: Dp = 5.dp, width: Dp = 1.dp): Modifier =
    this.border(width, color, chamferShape(cut))

/**
 * Тип обработки угла в [augmentedShape] — словарь augmented-ui
 * (propjockey/augmented-ui, см. докладку «Редизайн под augmented-ui» в
 * коммитах этого файла): угол можно срезать по прямой (Clip — то же, что
 * даёт chamferShape), скруглить наружу (Round) или вогнуть дугой внутрь
 * (Scoop). Именно смешение разных типов по углам ОДНОЙ панели — а не просто
 * скруглённые углы — и даёт узнаваемый вид игрового HUD вместо карточки
 * Material. Не замена chamferShape/doubleChamferShape и остальных срезов
 * выше — те зафиксированы по месту в десятках мелких элементов (бейджи,
 * тумблер, ячейки взлома), их геометрию отдельно не меняем. augmentedShape —
 * инструмент для новых "героических" поверхностей (диалоги, акцентные
 * карточки, кнопки).
 */
enum class AugCorner { None, Clip, Round, Scoop }

/**
 * Общий движок формы: все четыре угла настраиваются независимо — тип +
 * размер. При size=0 или типе None угол вырождается в обычный прямой угол
 * независимо от типа (не нужно отдельно обрабатывать None в вызывающем коде).
 */
@Composable
fun augmentedShape(
    topLeft: AugCorner = AugCorner.None, topLeftSize: Dp = 0.dp,
    topRight: AugCorner = AugCorner.None, topRightSize: Dp = 0.dp,
    bottomRight: AugCorner = AugCorner.None, bottomRightSize: Dp = 0.dp,
    bottomLeft: AugCorner = AugCorner.None, bottomLeftSize: Dp = 0.dp
): Shape {
    val density = LocalDensity.current
    val tlPx = if (topLeft == AugCorner.None) 0f else with(density) { topLeftSize.toPx() }
    val trPx = if (topRight == AugCorner.None) 0f else with(density) { topRightSize.toPx() }
    val brPx = if (bottomRight == AugCorner.None) 0f else with(density) { bottomRightSize.toPx() }
    val blPx = if (bottomLeft == AugCorner.None) 0f else with(density) { bottomLeftSize.toPx() }
    return GenericShape { size, _ ->
        val maxCorner = minOf(size.width, size.height)
        val tl = tlPx.coerceIn(0f, maxCorner)
        val tr = trPx.coerceIn(0f, maxCorner)
        val br = brPx.coerceIn(0f, maxCorner)
        val bl = blPx.coerceIn(0f, maxCorner)
        val w = size.width
        val h = size.height

        moveTo(tl, 0f)

        lineTo(w - tr, 0f)
        when (topRight) {
            AugCorner.None, AugCorner.Clip -> lineTo(w, tr)
            AugCorner.Round -> arcTo(Rect(w - 2 * tr, 0f, w, 2 * tr), -90f, 90f, false)
            AugCorner.Scoop -> arcTo(Rect(w - tr, -tr, w + tr, tr), 180f, -90f, false)
        }

        lineTo(w, h - br)
        when (bottomRight) {
            AugCorner.None, AugCorner.Clip -> lineTo(w - br, h)
            AugCorner.Round -> arcTo(Rect(w - 2 * br, h - 2 * br, w, h), 0f, 90f, false)
            AugCorner.Scoop -> arcTo(Rect(w - br, h - br, w + br, h + br), -90f, -90f, false)
        }

        lineTo(bl, h)
        when (bottomLeft) {
            AugCorner.None, AugCorner.Clip -> lineTo(0f, h - bl)
            AugCorner.Round -> arcTo(Rect(0f, h - 2 * bl, 2 * bl, h), 90f, 90f, false)
            AugCorner.Scoop -> arcTo(Rect(-bl, h - bl, bl, h + bl), 0f, -90f, false)
        }

        lineTo(0f, tl)
        when (topLeft) {
            AugCorner.None, AugCorner.Clip -> lineTo(tl, 0f)
            AugCorner.Round -> arcTo(Rect(0f, 0f, 2 * tl, 2 * tl), 180f, 90f, false)
            AugCorner.Scoop -> arcTo(Rect(-tl, -tl, tl, tl), 90f, -90f, false)
        }

        close()
    }
}

/**
 * Уголки-прицел поверх готовой панели — не форма, а декоративный слой:
 * четыре короткие скобки по углам, поверх уже нарисованного (drawWithContent),
 * не занимает место в layout и не мешает кликам. Классический приём игрового
 * HUD (см. докладку по augmented-ui/cyberpunk.net), самостоятельно применяется
 * к "героическим" поверхностям — не встроен в chamferShape/ChamferedSurface
 * по умолчанию, чтобы не перегружать мелкие элементы.
 */
fun Modifier.augCornerBrackets(
    color: Color,
    armLength: Dp = 9.dp,
    thickness: Dp = 1.5.dp,
    inset: Dp = 3.dp
): Modifier = this.drawWithContent {
    drawContent()
    val arm = armLength.toPx()
    val t = thickness.toPx()
    val i = inset.toPx()
    val w = size.width
    val h = size.height
    drawLine(color, Offset(i, i), Offset(i + arm, i), t, StrokeCap.Square)
    drawLine(color, Offset(i, i), Offset(i, i + arm), t, StrokeCap.Square)
    drawLine(color, Offset(w - i, i), Offset(w - i - arm, i), t, StrokeCap.Square)
    drawLine(color, Offset(w - i, i), Offset(w - i, i + arm), t, StrokeCap.Square)
    drawLine(color, Offset(w - i, h - i), Offset(w - i - arm, h - i), t, StrokeCap.Square)
    drawLine(color, Offset(w - i, h - i), Offset(w - i, h - i - arm), t, StrokeCap.Square)
    drawLine(color, Offset(i, h - i), Offset(i + arm, h - i), t, StrokeCap.Square)
    drawLine(color, Offset(i, h - i), Offset(i, h - i - arm), t, StrokeCap.Square)
}

/** Тот же приём, что chamferBorder — но контуром [notchedChamferShape], для ButtonVariant.System. */
@Composable
fun Modifier.notchedChamferBorder(color: Color, cut: Dp = 8.dp, width: Dp = 1.dp): Modifier =
    this.border(width, color, notchedChamferShape(cut))
