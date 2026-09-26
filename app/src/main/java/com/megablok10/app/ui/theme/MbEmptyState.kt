package com.megablok10.app.ui.theme

import android.provider.Settings
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

/** Пустой список всегда объясняет, что сделать дальше, и даёт действие (кнопку). */
@Composable
fun MbEmptyState(
    icon: Int,
    title: String,
    text: String,
    modifier: Modifier = Modifier,
    action: (@Composable () -> Unit)? = null
) {
    val c = LocalMbColors.current
    Column(
        modifier = modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Icon(painterResource(icon), contentDescription = null, tint = c.chrome, modifier = Modifier.size(40.dp))
        Text(
            title.uppercase(),
            style = MbTypography.cardTitle.copy(fontSize = 16.sp, letterSpacing = 0.03f.em),
            color = c.inkStrong,
            textAlign = TextAlign.Center
        )
        Text(
            text,
            style = MbTypography.rowSub.copy(fontSize = 13.sp, lineHeight = 18.sp),
            color = c.ink2,
            textAlign = TextAlign.Center,
            modifier = Modifier.widthIn(max = 220.dp)
        )
        if (action != null) {
            Spacer(Modifier.height(4.dp))
            action()
        }
    }
}

/** Android не даёт `prefers-reduced-motion`; ближайший системный аналог — шкала длительности анимаций специальных возможностей. */
@Composable
private fun isReducedMotion(): Boolean {
    if (LocalInspectionMode.current) return false
    val context = LocalContext.current
    return try {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    } catch (e: Settings.SettingNotFoundException) {
        false
    }
}

/** Заглушка строки списка на время загрузки — мерцание отключается при «уменьшить движение». [rows] — сколько строк показать. */
@Composable
fun MbSkeleton(rows: Int, modifier: Modifier = Modifier) {
    val reduced = isReducedMotion()
    val transition = rememberInfiniteTransition(label = "skeletonShimmer")
    val shimmer by transition.animateFloat(
        initialValue = -1f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1400, easing = LinearEasing), RepeatMode.Restart),
        label = "shimmerOffset"
    )
    Column(modifier.fillMaxWidth()) {
        repeat(rows) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = MbDimens.rowHeight)
                    .drawBehind {
                        drawLine(Color(0xFFC65A52).copy(alpha = 0.3f), Offset(0f, size.height), Offset(size.width, size.height), strokeWidth = 1.dp.toPx())
                    }
                    .padding(8.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                SkeletonBar(Modifier.size(18.dp), reduced, shimmer)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    SkeletonBar(Modifier.fillMaxWidth(0.6f).height(10.dp), reduced, shimmer)
                    SkeletonBar(Modifier.fillMaxWidth(0.85f).height(8.dp), reduced, shimmer)
                }
                SkeletonBar(Modifier.width(36.dp).height(10.dp), reduced, shimmer)
            }
        }
    }
}

@Composable
private fun SkeletonBar(modifier: Modifier, reduced: Boolean, shimmer: Float) {
    val base = Color(0xFF241518)
    val highlight = Color(0xFF3A2226)
    val brush = if (reduced) {
        Brush.linearGradient(listOf(base, base))
    } else {
        Brush.linearGradient(
            colors = listOf(base, highlight, base),
            start = Offset(shimmer * 400f - 200f, 0f),
            end = Offset(shimmer * 400f + 200f, 0f)
        )
    }
    Box(modifier.background(brush))
}
