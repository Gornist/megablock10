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

    // --- Слой 0: семантические имена ---
    // Существующие поля выше не переименованы и не удалены (слишком много мест
    // на них ссылается), но весь новый/переработанный код должен брать цвет
    // здесь, а не по "физическому" имени (bg1, ink0...) — так со временем
    // единственным местом, где смысл привязан к конкретному оттенку,
    // остаётся этот блок.
    val surfaceBase = bg0
    val surfaceRaised = bg1
    val surfaceSunken = bg2

    /** Рамки/разделители — то, для чего inkFaint фактически всегда использовался (это не читаемый текстовый тон). */
    val borderMuted = inkFaint
    val borderAccent = accentBorder

    val inkPrimary = ink0
    val inkSecondary = inkMuted
    /** Приглушённее inkSecondary — плейсхолдеры, disabled-текст. Отдельный тон, не inkFaint (тот слишком тёмный, чтобы читаться). */
    val inkTertiary = inkMuted.copy(alpha = 0.5f)

    val accentAction = accentPrimary
    val accentDanger = danger
    /** Кибердека/хак-контекст ТОЛЬКО — см. правило в шапке файла. */
    val accentNetrun = accentHack
}

/** Единственная горизонтальная сетка экрана — новый код берёт отступ отсюда, а не хардкодит 16.dp/12.dp по месту. */
object MB10Spacing {
    val screenPadding = androidx.compose.ui.unit.Dp(16f)
    val sm = androidx.compose.ui.unit.Dp(8f)
    val md = androidx.compose.ui.unit.Dp(12f)
    val lg = androidx.compose.ui.unit.Dp(18f)
}
