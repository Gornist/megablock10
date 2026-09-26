package com.megablok10.app.ui.theme

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Поле суммы: дисплей + собственная цифровая клавиатура (не системная IME) — гайдлайн просит оформить по общим правилам,
 * отдельного прототипа для него нет (открытый вопрос плана миграции, ответ владельца). Поведение — как было (AmountField/
 * NumericKeypad в DesignSystem.kt), здесь только новые токены и фаски.
 */
@Composable
fun MbAmountField(value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier, maxLength: Int = 9) {
    val c = LocalMbColors.current
    Column(modifier) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .mbFrame(fill = c.plate, edge = c.plateEdge, form = MbChamferForm.Tab, cut = 6.dp)
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                value.ifEmpty { "0" },
                style = MbTypography.balance.copy(fontSize = 26.sp),
                color = if (value.isEmpty()) c.ink3 else c.ink,
                modifier = Modifier.weight(1f)
            )
            Text("€$", style = MbTypography.meta.copy(fontSize = 13.sp), color = c.ink2)
        }
        Spacer(Modifier.height(MbDimens.blockGap))
        MbNumericKeypad(value = value, onValueChange = onValueChange, maxLength = maxLength)
    }
}

@Composable
private fun MbNumericKeypad(value: String, onValueChange: (String) -> Unit, maxLength: Int) {
    val c = LocalMbColors.current
    val rows = listOf(listOf("1", "2", "3"), listOf("4", "5", "6"), listOf("7", "8", "9"), listOf("", "0", "⌫"))
    Column(verticalArrangement = Arrangement.spacedBy(MbDimens.rowGap)) {
        rows.forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(MbDimens.rowGap)) {
                row.forEach { key ->
                    if (key.isEmpty()) {
                        Spacer(Modifier.weight(1f))
                    } else {
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .aspectRatio(1.7f)
                                .mbFrame(fill = c.plate, edge = c.plateEdge, form = MbChamferForm.Tab, cut = 6.dp)
                                .clickable {
                                    when (key) {
                                        "⌫" -> onValueChange(value.dropLast(1))
                                        else -> if (value.length < maxLength) onValueChange(value + key)
                                    }
                                },
                            contentAlignment = Alignment.Center
                        ) {
                            Text(key, style = MbTypography.demonCode.copy(fontSize = 18.sp), color = c.ink)
                        }
                    }
                }
            }
        }
    }
}
