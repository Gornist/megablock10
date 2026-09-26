package com.megablok10.app.ui.theme

import androidx.annotation.DrawableRes
import com.megablok10.app.R

/**
 * Иконки прототипа (24×24, штрих 1,7) — векторные ресурсы `res/drawable/ic_mb_*`, не `ImageVector` в коде: контуры
 * скопированы из `d`/`pathData` прототипа один в один (Android vector pathData — тот же синтаксис, что SVG path).
 * `Icon(painterResource(MbIcons.X), tint = …)` — тонировка через SrcIn работает и для обводки (fill прозрачный).
 */
object MbIcons {
    @DrawableRes val Chat = R.drawable.ic_mb_chat
    @DrawableRes val Phone = R.drawable.ic_mb_phone
    @DrawableRes val Hack = R.drawable.ic_mb_hack
    @DrawableRes val Wallet = R.drawable.ic_mb_wallet
    @DrawableRes val Mail = R.drawable.ic_mb_mail
    @DrawableRes val User = R.drawable.ic_mb_user
    @DrawableRes val Group = R.drawable.ic_mb_group
    @DrawableRes val In = R.drawable.ic_mb_in
    @DrawableRes val Out = R.drawable.ic_mb_out
    @DrawableRes val Miss = R.drawable.ic_mb_miss
    @DrawableRes val Bell = R.drawable.ic_mb_bell
    @DrawableRes val Shard = R.drawable.ic_mb_shard
    @DrawableRes val Chip = R.drawable.ic_mb_chip
    @DrawableRes val Plus = R.drawable.ic_mb_plus
    @DrawableRes val Close = R.drawable.ic_mb_close
    @DrawableRes val Check = R.drawable.ic_mb_check
    @DrawableRes val Swap = R.drawable.ic_mb_swap
    @DrawableRes val Scan = R.drawable.ic_mb_scan
    @DrawableRes val Pen = R.drawable.ic_mb_pen
    @DrawableRes val Upload = R.drawable.ic_mb_upload
    @DrawableRes val Reset = R.drawable.ic_mb_reset
    @DrawableRes val Send = R.drawable.ic_mb_send
    @DrawableRes val Target = R.drawable.ic_mb_target
    @DrawableRes val Alert = R.drawable.ic_mb_alert
    @DrawableRes val Clock = R.drawable.ic_mb_clock
    @DrawableRes val Sync = R.drawable.ic_mb_sync
    @DrawableRes val NoSignal = R.drawable.ic_mb_nosig
}
