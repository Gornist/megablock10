package com.megablok10.app.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Три формы среза гайдлайна (раздел 4) — единственный способ нарисовать рамку в новой дизайн-системе. Ни
 * [Modifier.background] со скруглением, ни голый `Modifier.border` без формы не используются напрямую — только
 * [mbChamferShape] / [Modifier.mbFrame].
 */
enum class MbChamferForm {
    /** Правый верхний + левый нижний — кнопки, пузыри-плашки, баннер, портрет, QR, карточка. */
    Std,

    /** Правый нижний — строки-плашки, метки, «клавиши», поля, плитки, переключатель, ползунок, кнопка-иконка, таймер. */
    Tab,

    /** Правый верхний — окна (Dialog), панели взлома (Panel). */
    Dlg
}

@Composable
fun mbChamferShape(form: MbChamferForm, cut: Dp): Shape {
    val cutPx = with(LocalDensity.current) { cut.toPx() }
    return GenericShape { size, _ ->
        val c = cutPx.coerceIn(0f, minOf(size.width, size.height))
        when (form) {
            MbChamferForm.Std -> {
                moveTo(0f, 0f)
                lineTo(size.width - c, 0f)
                lineTo(size.width, c)
                lineTo(size.width, size.height)
                lineTo(c, size.height)
                lineTo(0f, size.height - c)
                close()
            }
            MbChamferForm.Tab -> {
                moveTo(0f, 0f)
                lineTo(size.width, 0f)
                lineTo(size.width, size.height - c)
                lineTo(size.width - c, size.height)
                lineTo(0f, size.height)
                close()
            }
            MbChamferForm.Dlg -> {
                moveTo(0f, 0f)
                lineTo(size.width - c, 0f)
                lineTo(size.width, c)
                lineTo(size.width, size.height)
                lineTo(0f, size.height)
                close()
            }
        }
    }
}

/**
 * Рамка + заливка одной из трёх форм среза — двухслойный фон (рамка под отступом [width] от заливки), как раньше
 * ChamferedPanelImpl: `border` не комбинируется с clip-path на одном элементе. cut по умолчанию 8 dp — «по умолчанию»
 * из таблицы размеров гайдлайна (раздел 4); конкретные компоненты передают свой размер среза.
 */
@Composable
fun Modifier.mbFrame(fill: Color, edge: Color, form: MbChamferForm, cut: Dp = 8.dp, width: Dp = 1.dp): Modifier {
    val outer = mbChamferShape(form, cut)
    val inner = mbChamferShape(form, (cut - width).coerceAtLeast(0.dp))
    return this
        .background(edge, outer)
        .padding(width)
        .background(fill, inner)
}
