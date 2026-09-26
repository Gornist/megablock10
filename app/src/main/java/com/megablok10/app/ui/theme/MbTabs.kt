package com.megablok10.app.ui.theme

import androidx.annotation.DrawableRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em

/** Одна вкладка `MbTabs` — иконка необязательна, подпись всегда заглавными (раздел 5 гайдлайна). */
class MbTabItem(@DrawableRes val icon: Int? = null, val label: String)

private val TabLineIdle = Color(0xFFF1C7C2)

/** Вкладки с толстым подчёркиванием (3 dp): активная — `acc`, неактивная — светло-розовая; линия `chrome` тянется до края. */
@Composable
fun MbTabs(items: List<MbTabItem>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    val c = LocalMbColors.current
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
        items.forEachIndexed { i, item ->
            val on = i == selected
            val lineColor = if (on) c.acc else TabLineIdle
            val textColor = if (on) c.acc else c.chrome
            Row(
                modifier = Modifier
                    .heightIn(min = MbDimens.tabHeight)
                    .clickable { onSelect(i) }
                    .drawBehind { drawLine(lineColor, Offset(0f, size.height), Offset(size.width, size.height), strokeWidth = 3.dp.toPx()) }
                    .padding(start = 2.dp, end = 16.dp, bottom = 10.dp),
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                if (item.icon != null) Icon(painterResource(item.icon), contentDescription = null, tint = textColor, modifier = Modifier.size(15.dp))
                Text(item.label.uppercase(), style = MbTypography.tab, color = textColor)
            }
        }
        Box(
            Modifier
                .weight(1f)
                .heightIn(min = MbDimens.tabHeight)
                .drawBehind { drawLine(c.chrome, Offset(0f, size.height - 1.dp.toPx()), Offset(size.width, size.height - 1.dp.toPx()), strokeWidth = 1.dp.toPx()) }
        )
    }
}

/**
 * Заголовок вложенного экрана: те же отрезки, что у вкладок, разделены «›», без переключения активности.
 * [actions] — кнопки-иконки действий экрана справа (позвонить, перевод).
 */
@Composable
fun MbBreadcrumb(
    parts: List<String>,
    modifier: Modifier = Modifier,
    @DrawableRes icon: Int? = null,
    actions: (@Composable RowScope.() -> Unit)? = null
) {
    val c = LocalMbColors.current
    val ink = Color(0xFFEAF6F3)
    val line = Color(0xFFE9E0DE)
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
        parts.forEachIndexed { i, part ->
            if (i > 0) {
                Text("›", style = MbTypography.tab, color = line, modifier = Modifier.padding(bottom = 10.dp, end = 4.dp))
            }
            Row(
                modifier = Modifier
                    .heightIn(min = MbDimens.tabHeight)
                    .drawBehind { drawLine(line, Offset(0f, size.height), Offset(size.width, size.height), strokeWidth = 3.dp.toPx()) }
                    .padding(start = 2.dp, end = 10.dp, bottom = 10.dp),
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                if (i == 0 && icon != null) Icon(painterResource(icon), contentDescription = null, tint = ink, modifier = Modifier.size(15.dp))
                Text(part.uppercase(), style = MbTypography.tab, color = ink)
            }
        }
        Box(
            Modifier
                .weight(1f)
                .heightIn(min = MbDimens.tabHeight)
                .drawBehind { drawLine(c.chrome, Offset(0f, size.height - 1.dp.toPx()), Offset(size.width, size.height - 1.dp.toPx()), strokeWidth = 1.dp.toPx()) }
        )
        if (actions != null) {
            Row(
                modifier = Modifier.padding(start = 6.dp, bottom = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                content = actions
            )
        }
    }
}

enum class MbMetaTone { Neutral, Ok }

/** Строка состояния моношрифтом под Breadcrumb («● в сети · Вольные · ключ 9C1E…04B»). */
@Composable
fun MbMetaLine(text: String, modifier: Modifier = Modifier, tone: MbMetaTone = MbMetaTone.Neutral) {
    val color = if (tone == MbMetaTone.Ok) LocalMbColors.current.ok else LocalMbColors.current.ink2
    Text(text, style = MbTypography.meta.copy(letterSpacing = 0.04f.em), color = color, modifier = modifier)
}

/** Заголовок группы: текст `inkStrong`, линия `acc`, справа мета (счётчик, ▽, «поиск»). Один на все списки. */
@Composable
fun MbSectionTitle(text: String, modifier: Modifier = Modifier, meta: String? = null) {
    val c = LocalMbColors.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .drawBehind { drawLine(c.acc, Offset(0f, size.height), Offset(size.width, size.height), strokeWidth = 1.dp.toPx()) }
            .padding(top = 8.dp, bottom = 5.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.Bottom
    ) {
        Text(text, style = MbTypography.sectionTitle, color = c.inkStrong)
        if (meta != null) Text(meta, style = MbTypography.tagLabel, color = c.chrome)
    }
}
