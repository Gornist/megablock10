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

/** Тот же приём, что chamferBorder — но контуром [notchedChamferShape], для ButtonVariant.System. */
@Composable
fun Modifier.notchedChamferBorder(color: Color, cut: Dp = 8.dp, width: Dp = 1.dp): Modifier =
    this.border(width, color, notchedChamferShape(cut))
