package com.megablok10.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import com.megablok10.app.di.AppGraph

/**
 * Корень композиции для экранов: MainActivity кладёт сюда граф приложения (di.AppGraph) один раз. Экраны берут из него только
 * свои ViewModel ([appViewModel]); компоненты дизайн-системы и всё, что рисуют скриншот-тесты, граф не трогают — им данные
 * передаются параметрами.
 */
val LocalAppGraph = staticCompositionLocalOf<AppGraph> { error("AppGraph не предоставлен: экран вне MainActivity") }

/**
 * ViewModel экрана, собранная из графа (фабрики — di/ViewModels.kt): `val vm = appViewModel { walletViewModel() }`. Живёт, пока жива
 * Activity, — переживает поворот и переключение вкладок. [key] — если экземпляров несколько (тред на каждого собеседника).
 */
@Composable
inline fun <reified VM : ViewModel> appViewModel(key: String? = null, crossinline create: AppGraph.() -> VM): VM {
    val graph = LocalAppGraph.current
    return viewModel(key = key) { graph.create() }
}
