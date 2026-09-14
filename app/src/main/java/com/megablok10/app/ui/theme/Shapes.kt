package com.megablok10.app.ui.theme

import androidx.compose.foundation.shape.GenericShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp

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
