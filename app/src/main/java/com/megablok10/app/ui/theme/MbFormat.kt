package com.megablok10.app.ui.theme

/** Только группировка разрядов тысяч узким неразрывным пробелом, без знака и без «€$» — для MbTile (число и юнит разными стилями). */
fun groupThousands(amount: Long): String = kotlin.math.abs(amount).toString().reversed().chunked(3).joinToString(" ").reversed()

/** Деньги в формате гайдлайна (раздел 7): `1 240 €$`, узкий неразрывный пробел между разрядами тысяч, минус — знаком «−». */
fun formatMoney(amount: Long): String = (if (amount < 0) "−" else "") + groupThousands(amount) + " €$"
