package com.megablok10.app.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * Три акцента — это три разных СМЫСЛА, не взаимозаменяемые варианты одного.
 * lime используется ТОЛЬКО на экране взлома (Кибердека) и во всём, что
 * семантически "хак" (зашифрованные шарды, кнопка "Расшифровать") — если
 * он появляется где-то ещё, значит разделение смысла сломано, это баг,
 * а не стилистическая вольность.
 */
object MB10Colors {
    val bg0 = Color(0xFF0C0C0D)
    val bg1 = Color(0xFF151515)
    val bg2 = Color(0xFF1E1E1E)

    val ink0 = Color(0xFFF5F5F0)
    val inkMuted = Color(0xFF8F8F8F)
    val inkFaint = Color(0xFF3A3A3A)

    val yellow = Color(0xFFFCEE0A)
    val lime = Color(0xFFD9FF3F)
    val red = Color(0xFFFF2E63)
}
