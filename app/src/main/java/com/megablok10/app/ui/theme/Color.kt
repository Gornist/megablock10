package com.megablok10.app.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * Три акцента — это три разных СМЫСЛА, не взаимозаменяемые варианты одного.
 * accentHack используется ТОЛЬКО на экране взлома (Кибердека) и во всём, что
 * семантически "хак" (зашифрованные шарды, кнопка "Расшифровать") — если
 * он появляется где-то ещё, значит разделение смысла сломано, это баг,
 * а не стилистическая вольность.
 */
object MB10Colors {
    val bg0 = Color(0xFF0B0B14)
    val bg1 = Color(0xFF141420)
    val bg2 = Color(0xFF1c1c2a)

    val ink0 = Color(0xFF8FE8F0)
    val inkMuted = Color(0xFF6b6470)
    val inkFaint = Color(0xFF241a1a)

    val accentPrimary = Color(0xFFE8615A)
    /** Сознательно не в тон новой циановой палитре — ink0 сам циановый, второй циан для хака сливался бы с обычным текстом. Лайм остаётся собственным цветом Кибердеки, как и был. */
    val accentHack = Color(0xFFD9FF3F)
    val danger = Color(0xFFC23B3B)

    /** Приглушённая рамка панелей — там, где inkFaint слишком тёмный/нейтральный и нужен лёгкий цветовой подтон. */
    val accentBorder = Color(0xFF7A3B35)

    /** Текст поверх заливки акцентом (accentPrimary/accentHack) — оба достаточно светлые, чтобы требовать один и тот же тёмный текст. */
    val onAccent = Color(0xFF1a0a08)
}
