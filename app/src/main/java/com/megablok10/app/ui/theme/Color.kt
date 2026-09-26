package com.megablok10.app.ui.theme

/**
 * Псевдонимы старых имён на новые токены гайдлайна (docs/ux/ui-style-guide.md, раздел 2) — M1 плана миграции
 * (docs/ux/ui-migration-plan.md). Существующие экраны и компоненты пока читают эти поля как раньше, но получают
 * уже новую палитру; сами поля и это объявление уйдут в M5 вместе со старыми компонентами.
 *
 * accentSystem/onAccentSystem — временный псевдоним на `money`: гайдлайн отдельного «служебного жёлтого» больше не
 * определяет (жёлтый теперь только «деньги и новое» — открытый вопрос плана, ответ владельца «да, согласен»),
 * объявление мастера в новой системе узнаётся по окну (MbDialog, тёмно-синее, иконка колокола), не по цвету —
 * это меняется в M4.7 вместе с AnnouncementDialogHost, здесь только временная заглушка для компиляции.
 */
object MB10Colors {
    val onAccent = MbColorsDefault.accInk

    val surfaceBase = MbColorsDefault.bg
    val surfaceRaised = MbColorsDefault.plate
    val surfaceSunken = MbColorsDefault.plate2

    val borderMuted = MbColorsDefault.chromeDim
    val borderAccent = MbColorsDefault.chrome

    val inkPrimary = MbColorsDefault.ink
    val inkSecondary = MbColorsDefault.ink2
    val inkTertiary = MbColorsDefault.ink3

    val accentAction = MbColorsDefault.acc
    val accentDanger = MbColorsDefault.bad
    /** Кибердека/хак-контекст ТОЛЬКО — лайм темы Breach, независимо от темы экрана вокруг (см. правило в шапке файла). */
    val accentNetrun = MbColorsBreach.acc
    val accentSystem = MbColorsDefault.money
    val onAccentSystem = MbColorsDefault.onMoney
}

/** Единственная горизонтальная сетка экрана — новый код берёт отступ отсюда, а не хардкодит 16.dp/12.dp по месту. */
object MB10Spacing {
    val screenPadding = androidx.compose.ui.unit.Dp(16f)
    val sm = androidx.compose.ui.unit.Dp(8f)
    val md = androidx.compose.ui.unit.Dp(12f)
    val lg = androidx.compose.ui.unit.Dp(18f)
}
