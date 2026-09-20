package com.megablok10.app.ui.theme

import androidx.compose.foundation.border
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
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
 * Единственный способ обвести элемент рамкой: контур повторяет срез [chamferShape], а не прямоугольник.
 * Голый `Modifier.border(w, color)` без формы даёт квадратную рамку — это считается ошибкой (следит `NoRectangularBordersTest`).
 */
@Composable
fun Modifier.chamferBorder(color: Color, cut: Dp = 5.dp, width: Dp = 1.dp): Modifier =
    this.border(width, color, chamferShape(cut))
