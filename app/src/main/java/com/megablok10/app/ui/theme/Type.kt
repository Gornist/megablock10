package com.megablok10.app.ui.theme

import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import com.megablok10.app.R

/**
 * Все три семейства — variable fonts (один .ttf, ось wght), бандлятся как
 * обычные res/font-ресурсы, а НЕ через Downloadable Fonts / GoogleFont
 * provider в Compose: тот тянет файл из сети при первом использовании,
 * а на площадке интернета не будет. Конкретный вес выбирается через
 * FontVariation.Settings, а не отдельным файлом на каждый вес.
 */
@OptIn(ExperimentalTextApi::class)
val Jura = FontFamily(
    Font(R.font.jura, FontWeight.Medium, variationSettings = FontVariation.Settings(FontVariation.weight(500))),
    Font(R.font.jura, FontWeight.Bold, variationSettings = FontVariation.Settings(FontVariation.weight(700)))
)

@OptIn(ExperimentalTextApi::class)
val JetBrainsMono = FontFamily(
    Font(R.font.jetbrains_mono, FontWeight.Normal, variationSettings = FontVariation.Settings(FontVariation.weight(400))),
    Font(R.font.jetbrains_mono, FontWeight.Medium, variationSettings = FontVariation.Settings(FontVariation.weight(500)))
)

@OptIn(ExperimentalTextApi::class)
val IBMPlexSans = FontFamily(
    Font(R.font.ibm_plex_sans, FontWeight.Normal, variationSettings = FontVariation.Settings(FontVariation.weight(400))),
    Font(R.font.ibm_plex_sans, FontWeight.Medium, variationSettings = FontVariation.Settings(FontVariation.weight(500)))
)
