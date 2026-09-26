package com.megablok10.app.ui.theme

import androidx.compose.ui.unit.dp

/** Размеры и отступы гайдлайна (docs/ux/ui-style-guide.md, раздел 4). Экран не хардкодит dp по месту — берёт отсюда. */
object MbDimens {
    val screenPadding = 10.dp
    val blockGap = 8.dp
    val rowGap = 4.dp

    /** Любая нажимаемая область — Modifier.minimumInteractiveComponentSize() уже даёт это значение, здесь для явных Box/Row. */
    val minTouch = 48.dp
    val rowHeight = 48.dp
    val buttonHeight = 48.dp
    val iconButtonArt = 40.dp
    val toggleArt = 32.dp
    val tabHeight = 46.dp
    val bottomMenuHeight = 52.dp
    val breachCell = 48.dp

    val portraitHeader = 34.dp
    val portraitBanner = 30.dp
    val portraitProfile = 58.dp
    val portraitCall = 96.dp
}
