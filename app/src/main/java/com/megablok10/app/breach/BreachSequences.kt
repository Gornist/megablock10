package com.megablok10.app.breach

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.style.TextDecoration
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbListItem
import com.megablok10.app.ui.theme.MbTypography

/**
 * Содержимое панели «Последовательности»: не только коды цели, но и что даст их совпадение — иначе на экране взлома нет ответа на
 * «зачем я выбрал этих демонов». Совпавший демон зачёркнут.
 */
@Composable
internal fun BreachSequences(attempt: BreachAttemptState) {
    val c = LocalMbColors.current
    attempt.daemons.forEach { daemon ->
        val matched = daemon.id in attempt.matchedDaemonIds
        MbListItem(
            title = daemon.name,
            sub = daemon.effect.label(),
            subWrap = true,
            trail = listOf({
                Text(
                    daemon.sequence.joinToString(" "),
                    style = MbTypography.demonCode,
                    color = if (matched) c.acc else c.ink2,
                    textDecoration = if (matched) TextDecoration.LineThrough else null
                )
            })
        )
    }
}
