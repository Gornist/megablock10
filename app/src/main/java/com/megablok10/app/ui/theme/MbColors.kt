package com.megablok10.app.ui.theme

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * Токены цвета из гайдлайна (docs/ux/ui-style-guide.md, раздел 2). Один [MbColorScheme] на тему: Default (основная),
 * Breach (взлом) и Success (итог взлома поверх Breach) — экран собирается из одних и тех же компонентов, меняется
 * только набор значений через [LocalMbColors]. Код обращается только к ролям (полям этого класса), не к hex-кодам —
 * см. «Нельзя» гайдлайна, п. 10.
 */
data class MbColorScheme(
    val bg: Color,
    val plate: Color,
    val plate2: Color,
    val plateEdge: Color,
    val chrome: Color,
    val chromeDim: Color,
    val chromeSoft: Color,
    val chromeDeep: Color,
    val label: Color,
    val ink: Color,
    val ink2: Color,
    val ink3: Color,
    val inkStrong: Color,
    val offTitle: Color,
    val offSub: Color,
    val acc: Color,
    val accInk: Color,
    val selFill: Color,
    val money: Color,
    val onMoney: Color,
    val ok: Color,
    val warn: Color,
    val bad: Color,
    val plateSel: Color,
    val plateSelEdge: Color,
    val mark: Color,
    val markEdge: Color,
    val dlgFill: Color,
    val dlgEdge: Color,
    val dlgBar: Color,
    val bubbleInFill: Color,
    val bubbleInEdge: Color,
    val bubbleInText: Color,
    val bubbleOwnFill: Color,
    val bubbleOwnEdge: Color,
    val bubbleOwnText: Color,
    /** Использованная ячейка матрицы взлома — осмыслена только в теме Breach. */
    val used: Color
)

val MbColorsDefault = MbColorScheme(
    bg = Color(0xFF110A0C),
    plate = Color(0xFF150D10),
    plate2 = Color(0xFF0F0A0C),
    plateEdge = Color(0xFF4A2124),
    chrome = Color(0xFFC65A52),
    chromeDim = Color(0xFF5A2629),
    chromeSoft = Color(0xFFC65A52).copy(alpha = 0.30f),
    chromeDeep = Color(0xFFC96A62),
    label = Color(0xFFF08A80),
    ink = Color(0xFFE2F4F0),
    ink2 = Color(0xFF9DB3AF),
    ink3 = Color(0xFF947A7E),
    inkStrong = Color(0xFFF1F1EF),
    offTitle = Color(0xFF8A9B98),
    offSub = Color(0xFF7C8A88),
    acc = Color(0xFF5EF6FF),
    accInk = Color(0xFF02181B),
    selFill = Color(0xFF2D6563),
    money = Color(0xFFF5D547),
    onMoney = Color(0xFF1C1600),
    ok = Color(0xFF43F08F),
    warn = Color(0xFFFF9F43),
    bad = Color(0xFFFF5A50),
    plateSel = Color(0xFFC8433A),
    plateSelEdge = Color(0xFFFF6B5E),
    mark = Color(0xFF2A1416),
    markEdge = Color(0xFF7A3632),
    dlgFill = Color(0xFF0A1320),
    dlgEdge = Color(0xFF4FB6C4),
    dlgBar = Color(0xFF2C6F7A),
    bubbleInFill = Color(0xFF0D1819),
    bubbleInEdge = Color(0xFF8FE3D6),
    bubbleInText = Color(0xFFDFF5F0),
    bubbleOwnFill = Color(0xFF17663D),
    bubbleOwnEdge = Color(0xFF43F08F),
    bubbleOwnText = Color(0xFFEFFFF4),
    used = Color(0xFF5A2629)
)

/**
 * Тема взлома: тот же набор компонентов, гайдлайн (раздел 2) переопределяет только фон, плашки и акцент
 * (лайм вместо бирюзы/красного) — остальное (деньги, статусы, окна, пузыри) наследуется от [MbColorsDefault]:
 * взлом не меняет смысл денег или ошибки, только собственную «рабочую» палитру.
 */
val MbColorsBreach = MbColorsDefault.copy(
    bg = Color(0xFF0E100A),
    plate = Color(0xFF151809),
    plate2 = Color(0xFF151809),
    plateEdge = Color(0xFF4B5626),
    chrome = Color(0xFFD0ED57),
    chromeDim = Color(0xFF3B4320),
    chromeSoft = Color(0xFFD0ED57).copy(alpha = 0.30f),
    acc = Color(0xFFD0ED57),
    ink = Color(0xFFE6F2B0),
    ink2 = Color(0xFFA2AE70),
    ink3 = Color(0xFF86934F),
    used = Color(0xFF5F6A3C)
)

/** Итог взлома — поверх темы Breach: гайдлайн переопределяет только плашки, акцент и первые два тона текста. */
val MbColorsSuccess = MbColorsBreach.copy(
    plate = Color(0xFF12291C),
    plate2 = Color(0xFF12291C),
    plateEdge = Color(0xFF1F4A33),
    chrome = Color(0xFF5EF2A0),
    chromeDim = Color(0xFF1F4A33),
    chromeSoft = Color(0xFF5EF2A0).copy(alpha = 0.30f),
    acc = Color(0xFF5EF2A0),
    ink = Color(0xFFD8FBE8),
    ink2 = Color(0xFF86C4A2)
)

val LocalMbColors = staticCompositionLocalOf { MbColorsDefault }
