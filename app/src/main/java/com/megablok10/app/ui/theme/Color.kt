package com.megablok10.app.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * Три акцента — это три разных СМЫСЛА, не взаимозаменяемые варианты одного.
 * accentNetrun используется ТОЛЬКО на экране взлома (Кибердека) и во всём, что
 * семантически "хак" (зашифрованные шарды, кнопка "Расшифровать") — если
 * он появляется где-то ещё, значит разделение смысла сломано, это баг,
 * а не стилистическая вольность.
 *
 * Физические оттенки ниже приватны: весь код за пределами этого файла
 * обращается только к семантическим именам (surfaceBase, inkPrimary,
 * accentAction...) — единственное место, где смысл привязан к конкретному
 * оттенку, это блок ниже.
 */
object MB10Colors {
    private val bg0 = Color(0xFF0B0B14)
    private val bg1 = Color(0xFF141420)
    private val bg2 = Color(0xFF1c1c2a)

    private val ink0 = Color(0xFF8FE8F0)
    private val inkMuted = Color(0xFF6b6470)
    private val inkFaint = Color(0xFF241a1a)

    private val accentPrimary = Color(0xFFE8615A)
    /** Сознательно не в тон новой циановой палитре — ink0 сам циановый, второй циан для хака сливался бы с обычным текстом. Лайм остаётся собственным цветом Кибердеки, как и был. */
    private val accentHack = Color(0xFFD9FF3F)
    private val danger = Color(0xFFC23B3B)

    /** Приглушённая рамка панелей — там, где inkFaint слишком тёмный/нейтральный и нужен лёгкий цветовой подтон. */
    private val accentBorder = Color(0xFF7A3B35)

    /**
     * Служебный жёлтый — «это от мастера/приложения, не от игрока»: диалог с объявлением мастера, код/QR провижининга,
     * системное уведомление. Разбор cyberpunk.net — там тем же приёмом фирменный жёлтый отделяет CTA/статусы уровня
     * бренда от обычного игрового текста. НЕ смешивать с accentAction (действие игрока) и accentDanger (необратимое/
     * тревога) — если жёлтый начинает появляться в игровых действиях, разделение смысла сломано, это баг.
     */
    private val system = Color(0xFFFCEE0A)

    /** Текст поверх заливки акцентом (accentAction/accentNetrun) — оба достаточно светлые, чтобы требовать один и тот же тёмный текст. */
    val onAccent = Color(0xFF1a0a08)

    val surfaceBase = bg0
    val surfaceRaised = bg1
    val surfaceSunken = bg2

    /** Рамки/разделители — то, для чего inkFaint фактически всегда использовался (это не читаемый текстовый тон). */
    val borderMuted = inkFaint
    val borderAccent = accentBorder

    val inkPrimary = ink0
    val inkSecondary = inkMuted
    /** Приглушённее inkSecondary — плейсхолдеры, disabled-текст. Отдельный тон, не borderMuted (тот слишком тёмный, чтобы читаться). */
    val inkTertiary = inkMuted.copy(alpha = 0.5f)

    val accentAction = accentPrimary
    val accentDanger = danger
    /** Кибердека/хак-контекст ТОЛЬКО — см. правило в шапке файла. */
    val accentNetrun = accentHack
    /** Служебный жёлтый — см. правило у объявления [system] выше. */
    val accentSystem = system
    /** Тёмный текст поверх accentSystem — жёлтый слишком светлый для onAccent (тот расчитан на action/netrun). */
    val onAccentSystem = Color(0xFF1a1600)
}

/** Единственная горизонтальная сетка экрана — новый код берёт отступ отсюда, а не хардкодит 16.dp/12.dp по месту. */
object MB10Spacing {
    val screenPadding = androidx.compose.ui.unit.Dp(16f)
    val sm = androidx.compose.ui.unit.Dp(8f)
    val md = androidx.compose.ui.unit.Dp(12f)
    val lg = androidx.compose.ui.unit.Dp(18f)
}
