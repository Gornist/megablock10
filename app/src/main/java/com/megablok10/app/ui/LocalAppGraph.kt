package com.megablok10.app.ui

import androidx.compose.runtime.staticCompositionLocalOf
import com.megablok10.app.di.AppGraph

/**
 * Корень композиции для экранов: MainActivity кладёт сюда граф приложения (di.AppGraph) один раз. Компоненты дизайн-системы и
 * всё, что рисуют скриншот-тесты, граф не трогают — им данные передаются параметрами.
 */
val LocalAppGraph = staticCompositionLocalOf<AppGraph> { error("AppGraph не предоставлен: экран вне MainActivity") }
