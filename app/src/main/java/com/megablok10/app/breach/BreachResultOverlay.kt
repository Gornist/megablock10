package com.megablok10.app.breach

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbButton
import com.megablok10.app.ui.theme.MbColorsSuccess
import com.megablok10.app.ui.theme.MbDimens
import com.megablok10.app.ui.theme.MbDone
import com.megablok10.app.ui.theme.MbListItem
import com.megablok10.app.ui.theme.MbLog
import com.megablok10.app.ui.theme.MbPanel
import com.megablok10.app.ui.theme.MbTag
import com.megablok10.app.ui.theme.MbTagTone
import com.megablok10.app.ui.theme.MbTypography
import com.megablok10.app.ui.theme.formatMoney

/**
 * Итог взлома поверх экрана, а не под сеткой: сетка и буфер остаются под затемнением в финальном виде; выход — кнопка
 * внутри панели. Помещается без прокрутки (раздел M4.5 плана миграции) — короткий журнал + плашка итога + список
 * демонов, без обёрток вроде ChamferedSurface/DottedDivider. Успех — тема Success поверх Breach (раздел 5 гайдлайна).
 */
@Composable
internal fun ResultOverlay(
    result: BreachResult,
    failMessage: String,
    rewardOutcome: RewardOutcome?,
    secAlertStatus: String?,
    actionLabel: String,
    onAction: () -> Unit
) {
    val colors = if (result.outcome == BreachOutcome.SUCCESS) MbColorsSuccess else LocalMbColors.current
    CompositionLocalProvider(LocalMbColors provides colors) {
        val c = colors
        Box(
            Modifier.fillMaxSize().background(c.bg.copy(alpha = 0.92f))
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {},
            contentAlignment = Alignment.BottomCenter
        ) {
            Column(Modifier.fillMaxWidth().padding(MbDimens.screenPadding)) {
                // Заголовок исхода — тексты, по которым стенд e2e (scripts/e2e/lib.sh, breach()) проверяет результат
                // взлома, не переименовывать без правки стенда в том же коммите (CLAUDE.md). «Демоны загружены · X из Y» —
                // формулировка гайдлайна для MbDone (раздел 5) — вторая строка, деталь поверх защищённого заголовка.
                MbPanel(
                    title = "Журнал",
                    meta = "${result.matchedIds.size} из ${result.allDaemons.size}"
                ) {
                    MbLog(
                        listOf("//КОРЕНЬ", "//ЗАПРОС_ДОСТУПА") + when (result.outcome) {
                            BreachOutcome.SUCCESS -> listOf("//ЗАГРУЗКА_ЗАВЕРШЕНА")
                            BreachOutcome.PARTIAL -> listOf("//ЗАГРУЗКА_ЧАСТИЧНАЯ")
                            BreachOutcome.FAIL -> listOf("//ДОСТУП_ОТКЛОНЁН")
                        }
                    )
                    MbDone(
                        when (result.outcome) {
                            BreachOutcome.SUCCESS -> "Взлом завершён"
                            BreachOutcome.PARTIAL -> "Взлом частично успешен"
                            BreachOutcome.FAIL -> "Взлом провален"
                        }
                    )
                    if (result.outcome == BreachOutcome.SUCCESS) {
                        Text(
                            "Демоны загружены · ${result.matchedIds.size} из ${result.allDaemons.size}",
                            style = MbTypography.meta, color = c.ink2, modifier = Modifier.padding(top = MbDimens.rowGap)
                        )
                    }
                }
                Spacer(Modifier.height(MbDimens.blockGap))
                Column(Modifier.fillMaxWidth()) {
                    result.allDaemons.forEach { daemon ->
                        val done = daemon.id in result.matchedIds
                        MbListItem(
                            title = daemon.name,
                            lead = { MbTag(if (done) "установлен" else "не вошёл", tone = if (done) MbTagTone.Ok else MbTagTone.Bad) },
                            plate = true,
                            end = true
                        )
                    }
                }
                if (result.outcome == BreachOutcome.FAIL) {
                    Spacer(Modifier.height(MbDimens.rowGap))
                    Text(failMessage, style = MbTypography.meta, color = c.ink2)
                }
                if (rewardOutcome != null || secAlertStatus != null) {
                    Spacer(Modifier.height(MbDimens.blockGap))
                    rewardOutcome?.let { outcome ->
                        outcome.extractedShardTitles.forEach { t -> RewardRow("Шард извлечён", "«$t»") }
                        outcome.extractedDaemonNames.forEach { name -> RewardRow("Демон извлечён", "«$name»") }
                        if (outcome.eddies > 0) RewardRow("Эдди начислены", "+${formatMoney(outcome.eddies)}", valueColor = c.money)
                        if (outcome.cacheExhausted) RewardRow("Тираж узла", "исчерпан", valueColor = c.bad)
                    }
                    secAlertStatus?.let { RewardRow("Сигнал СБ", it, valueColor = c.bad) }
                }
                Spacer(Modifier.height(MbDimens.blockGap))
                MbButton(actionLabel, onClick = onAction, inline = true, modifier = Modifier.align(Alignment.End))
            }
        }
    }
}

/** Одна строка разбора результата — тип награды/события слева, значение справа. */
@Composable
private fun RewardRow(label: String, value: String, valueColor: Color = LocalMbColors.current.acc) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), horizontalArrangement = Arrangement.spacedBy(MbDimens.rowGap)) {
        Text(label, style = MbTypography.rowSub, color = LocalMbColors.current.ink2)
        // weight+End, не SpaceBetween: длинное значение (награда, статус сигнала СБ) при крупном шрифте системы
        // должно переноситься в оставшемся месте, а не наезжать на подпись слева (найдено FontScaleTest, M6 плана миграции).
        Text(value, style = MbTypography.demonCode, color = valueColor, textAlign = TextAlign.End, modifier = Modifier.weight(1f))
    }
}
