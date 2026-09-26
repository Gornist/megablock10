package com.megablok10.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.android.resources.Density
import com.megablok10.app.breach.HackCell
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbBuffer
import com.megablok10.app.ui.theme.MbButton
import com.megablok10.app.ui.theme.MbColorsBreach
import com.megablok10.app.ui.theme.MbDimens
import com.megablok10.app.ui.theme.MbListItem
import com.megablok10.app.ui.theme.MbPanel
import com.megablok10.app.ui.theme.MbProgress
import com.megablok10.app.ui.theme.MbTimer
import org.junit.Rule
import org.junit.Test

/**
 * M6 плана миграции UI: экран взлома обязан помещаться без прокрутки на пороге 360×640 dp (открытый вопрос плана,
 * ответ владельца), не только на PIXEL_5 (~393×855 dp), который использует BreachScreenTest. На реальном устройстве
 * (Android App, Т13) это уже подтверждено через `adb wm size/density` на живом рендере — здесь только регрессия:
 * если после правки экрана эта колонка (без verticalScroll, как настоящая BreachSession) перестанет помещаться
 * в 640dp высоты, кнопка «Сдать буфер» уйдёт за нижний край снимка, и это будет видно на скриншоте.
 *
 * Сетка и содержимое буфера — фейковые, повторяют форму реальных (не generateGrid: он приватный в BreachScreen.kt),
 * размер ячейки — как в BreachSession для этой ширины (BoxWithConstraints + coerceIn(28.dp, MbDimens.breachCell)).
 */
class SmallScreenBreachTest {
    @get:Rule
    val paparazzi = Paparazzi(
        deviceConfig = DeviceConfig.NEXUS_4.copy(screenWidth = 360, screenHeight = 640, density = Density.MEDIUM, xdpi = 160, ydpi = 160, softButtons = false),
        maxPercentDifference = 0.5
    )

    @Test
    fun breachSessionNightmareGrid() = paparazzi.snapshot("smallscreen_breach_nightmare_grid") {
        CompositionLocalProvider(LocalMbColors provides MbColorsBreach) {
            val c = MbColorsBreach
            Box(Modifier.fillMaxSize().background(c.bg)) {
                Column(Modifier.fillMaxSize().padding(horizontal = MbDimens.screenPadding)) {
                    MbTimer(label = "Сейф 37-Б · Кошмар", time = "01:15")
                    Spacer(Modifier.height(MbDimens.rowGap))
                    MbProgress(70)
                    Spacer(Modifier.height(MbDimens.blockGap))
                    MbPanel("Буфер", meta = "3 / 9") { MbBuffer(codes = listOf("1C", "BD", "55"), size = 9) }
                    Spacer(Modifier.height(MbDimens.blockGap))
                    // NIGHTMARE — самая тесная сетка (7×7, BreachTierParams.forTier); ячейка — нижняя граница coerceIn.
                    MbPanel("Матрица кодов", meta = "7×7") {
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            repeat(7) { r ->
                                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                    repeat(7) { col ->
                                        HackCell(size = 28.dp, code = "${r}${col}", isSelected = false, orderLabel = null, isSelectable = true, onClick = {})
                                    }
                                }
                            }
                        }
                    }
                    Spacer(Modifier.height(MbDimens.blockGap))
                    MbPanel("Последовательности", meta = "3") {
                        MbListItem(title = "Чёрный занавес", sub = "сигнал СБ не отправляется", subWrap = true)
                        MbListItem(title = "Экстрактор", sub = "извлекает шард из контейнера", subWrap = true)
                        MbListItem(title = "Перекос", sub = "+10 мин к задержке сигнала СБ", subWrap = true)
                    }
                    Spacer(Modifier.height(MbDimens.blockGap))
                    MbButton("Сдать буфер", onClick = {})
                }
            }
        }
    }
}
