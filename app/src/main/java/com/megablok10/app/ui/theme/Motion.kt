package com.megablok10.app.ui.theme

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.slideInHorizontally
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

/**
 * Приёмы разбора cyberpunk.net («Cyberpunk.net → Мегаблок №10»): не копия их вёрстки/арта (лицензионные активы CD
 * Projekt RED), а пересчитанные тайминги, геометрия и цветовые роли под наши токены — см. правило у Shapes.notchedChamferShape
 * и Color.accentSystem. Три вещи из их шапки и меню, которых раньше не было в стайлгайде: анимированный переключатель
 * "гамбургер → крестик", каскадное появление пунктов списка, мягкая виньетка вместо жёсткого обреза фона.
 */

/**
 * Три полосы → крестик: верхняя и нижняя разворачиваются на ±45° с небольшим диагональным сдвигом, средняя гаснет,
 * цвет закрыто/открыто отличается (у них жёлтый → циан; здесь accentSystem → inkPrimary, тот же смысл "закрыто/открыто",
 * что уже несёт inkPrimary у HexBullet в AppHeader). 0.3с — тот же тайминг, что в оригинале.
 */
@Composable
fun HamburgerToggle(open: Boolean, onToggle: (Boolean) -> Unit, modifier: Modifier = Modifier, barWidth: Dp = 20.dp) {
    val color by animateColorAsState(if (open) MB10Colors.inkPrimary else MB10Colors.accentSystem, tween(300), label = "hamburgerColor")
    val topRotation by animateFloatAsState(if (open) 45f else 0f, tween(300), label = "hamburgerTop")
    val bottomRotation by animateFloatAsState(if (open) -45f else 0f, tween(300), label = "hamburgerBottom")
    val topOffset by animateFloatAsState(if (open) 5f else 0f, tween(300), label = "hamburgerTopOffset")
    val middleAlpha by animateFloatAsState(if (open) 0f else 1f, tween(200), label = "hamburgerMiddle")

    Box(
        modifier = modifier.clickable { onToggle(!open) }.size(width = barWidth, height = 14.dp),
    ) {
        Box(
            Modifier
                .fillMaxWidth().height(2.dp)
                .graphicsLayer { rotationZ = topRotation; translationX = topOffset * density; translationY = topOffset * density }
                .background(color)
        )
        Box(
            Modifier
                .fillMaxWidth().height(2.dp)
                .graphicsLayer { alpha = middleAlpha; translationY = 6f * density }
                .background(color)
        )
        Box(
            Modifier
                .fillMaxWidth().height(2.dp)
                .graphicsLayer { rotationZ = bottomRotation; translationX = topOffset * density; translationY = (12f - topOffset) * density }
                .background(color)
        )
    }
}

/**
 * Пункт списка появляется с задержкой index * staggerMs — тот же приём, что у пунктов их десктоп-меню (там 0.1с на
 * каждый следующий; здесь чуть быстрее, списки в приложении обычно длиннее четырёх строк). Только вход: список,
 * который уже показан, не переигрывает анимацию при рекомпозиции — remember по индексу играет один раз.
 */
@Composable
fun StaggeredReveal(index: Int, modifier: Modifier = Modifier, staggerMs: Long = 60L, content: @Composable () -> Unit) {
    var visible by remember(index) { mutableStateOf(false) }
    LaunchedEffect(index) {
        delay(index * staggerMs)
        visible = true
    }
    AnimatedVisibility(
        visible = visible,
        modifier = modifier,
        enter = fadeIn(tween(250, easing = LinearOutSlowInEasing)) + slideInHorizontally(tween(250, easing = LinearOutSlowInEasing)) { -it / 6 }
    ) {
        content()
    }
}

/**
 * Мягкий переход в фон снизу элемента — вместо жёсткого обреза декоративного фона/арта (у них так фоновое видео шапки
 * растворяется в чёрном подвале страницы, linear-gradient(transparent → фон), высота ~40% блока).
 */
fun Modifier.vignetteBottom(color: Color = MB10Colors.surfaceBase, heightFraction: Float = 0.4f): Modifier = this.background(
    Brush.verticalGradient(0f to Color.Transparent, (1f - heightFraction) to Color.Transparent, 1f to color)
)

/**
 * Полоса точек-делений вдоль края — как HUD-линейка на шапке cyberpunk.net (repeating dot-паттерн вдоль верха/низа).
 * Рисуется, не тянет PNG — дешевле и не зависит от плотности экрана.
 */
@Composable
fun DotTickRow(modifier: Modifier = Modifier, color: Color = MB10Colors.borderMuted, dotSpacing: Dp = 10.dp, dotRadius: Dp = 1.dp) {
    Canvas(modifier.fillMaxWidth().height(dotRadius * 2)) {
        val spacingPx = dotSpacing.toPx()
        val radiusPx = dotRadius.toPx()
        var x = radiusPx
        while (x < size.width) {
            drawCircle(color, radius = radiusPx, center = androidx.compose.ui.geometry.Offset(x, size.height / 2f))
            x += spacingPx
        }
    }
}
