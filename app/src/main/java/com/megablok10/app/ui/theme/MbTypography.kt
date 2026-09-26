package com.megablok10.app.ui.theme

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.megablok10.app.R

/**
 * Два шрифта гайдлайна (docs/ux/ui-style-guide.md, раздел 3) — статичные TTF в res/font, лицензия SIL OFL
 * (docs/ux/font-licenses/). Не Downloadable Fonts: на площадке нет интернета (см. CLAUDE.md).
 */
val FiraSansCondensed = FontFamily(
    Font(R.font.fira_sans_condensed_regular, FontWeight.Normal),
    Font(R.font.fira_sans_condensed_medium, FontWeight.Medium),
    Font(R.font.fira_sans_condensed_semibold, FontWeight.SemiBold)
)

val IBMPlexMono = FontFamily(
    Font(R.font.ibm_plex_mono_regular, FontWeight.Normal),
    Font(R.font.ibm_plex_mono_medium, FontWeight.Medium),
    Font(R.font.ibm_plex_mono_semibold, FontWeight.SemiBold)
)

/** Роли типографики — таблица гайдлайна, раздел 3. Имя поля — по назначению, не по экрану: одна роль может стоять на нескольких экранах. */
object MbTypography {
    val tab = TextStyle(fontFamily = FiraSansCondensed, fontWeight = FontWeight.Medium, fontSize = 14.sp, letterSpacing = 0.02f.em)
    val listItemTitle = TextStyle(fontFamily = FiraSansCondensed, fontWeight = FontWeight.Medium, fontSize = 15.sp, letterSpacing = 0.02f.em)
    val headerCallsign = TextStyle(fontFamily = FiraSansCondensed, fontWeight = FontWeight.Medium, fontSize = 15.sp)
    val cardTitle = TextStyle(fontFamily = FiraSansCondensed, fontWeight = FontWeight.Medium, fontSize = 21.sp, letterSpacing = 0.03f.em)
    val balance = TextStyle(fontFamily = FiraSansCondensed, fontWeight = FontWeight.Medium, fontSize = 38.sp)
    val tileValue = TextStyle(fontFamily = FiraSansCondensed, fontWeight = FontWeight.Medium, fontSize = 18.sp)
    val sectionTitle = TextStyle(fontFamily = FiraSansCondensed, fontWeight = FontWeight.Medium, fontSize = 13.sp)
    val messageText = TextStyle(fontFamily = FiraSansCondensed, fontWeight = FontWeight.Normal, fontSize = 14.sp)
    val dialogText = TextStyle(fontFamily = FiraSansCondensed, fontWeight = FontWeight.Normal, fontSize = 13.5.sp)
    val rowSub = TextStyle(fontFamily = FiraSansCondensed, fontWeight = FontWeight.Normal, fontSize = 12.sp)
    val settingLabel = TextStyle(fontFamily = FiraSansCondensed, fontWeight = FontWeight.Normal, fontSize = 13.sp)
    val button = TextStyle(fontFamily = FiraSansCondensed, fontWeight = FontWeight.Medium, fontSize = 13.sp, letterSpacing = 0.1f.em)
    val footerLabel = TextStyle(fontFamily = FiraSansCondensed, fontWeight = FontWeight.Medium, fontSize = 12.sp)
    val menuLabel = TextStyle(fontFamily = FiraSansCondensed, fontWeight = FontWeight.Medium, fontSize = 11.sp)
    val meta = TextStyle(fontFamily = IBMPlexMono, fontWeight = FontWeight.Normal, fontSize = 11.sp)
    val metaStatus = TextStyle(fontFamily = IBMPlexMono, fontWeight = FontWeight.Medium, fontSize = 11.sp, letterSpacing = 0.08f.em)
    val demonCode = TextStyle(fontFamily = IBMPlexMono, fontWeight = FontWeight.Medium, fontSize = 12.5.sp, letterSpacing = 0.08f.em)
    val breachCell = TextStyle(fontFamily = IBMPlexMono, fontWeight = FontWeight.Medium, fontSize = 15.sp)
    val listAmount = TextStyle(fontFamily = IBMPlexMono, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
}
